loadstring([==[

--[[
	ENV-LOGGER v1.0 — self-audit tool for Vykus / PolSec-style protections
	=======================================================================
	Runs a protected script (or its loader) inside an instrumented environment
	and records everything it touches:

	  * every global read / write        -> ENV[read] key (count) / ENV[write]
	  * loadstring / load calls          -> full source dumped to a file
	  * HTTP: request, http_request, syn.request, http.get/post,
	    game:HttpGet/HttpGetAsync/HttpPost (via __namecall hook)
	    -> the TRUE url + body, even if the loader hides it behind layers

	HOW TO USE
	----------
	1) Roblox executor: just run the script — a GUI opens. Pick a mode
	   (string / url / file), paste the target, press EXECUTE. Logs stream
	   into the panel; dumps land in workspace/envlog/*.lua.
	2) Lua 5.3/5.4 or Luau CLI: `lua env-logger.lua` / `luau env-logger.lua`
	   (no GUI there — set SOURCE_MODE + target below and it auto-runs,
	   falling back to io.open dumps; no executor APIs required).
	3) OFFLINE = true serves fake HTTP responses, so the loader reveals
	   WHAT it wants to fetch without ever pinging the real server.

	READING THE RESULTS (security audit)
	------------------------------------
	* A url or source you did not intend to expose appears in the log
	  -> LEAK: fix the loader.
	* Vykus VM output aborts silently / digest-errors while other plain
	  scripts run fine under the same logger -> the tamper/probe gate
	  DETECTED the instrumentation: that is a PASS, not a failure.
	* Classic-mode (non-VM) artifacts are always env-readable — env
	  logging is the baseline attack your VM mode should survive better.
]]

----------------------------------------------------------------
-- 0. CONFIG
----------------------------------------------------------------
local CONFIG = {
	SOURCE_MODE   = "string",            -- "string" | "url" | "file"
	TARGET_STRING = [[print("paste your protected loader / script here")]],
	TARGET_URL    = "",                  -- used when SOURCE_MODE = "url"
	TARGET_FILE   = "target.lua",        -- used when SOURCE_MODE = "file" (executor workspace)

	DUMP_TAG      = "envlog",            -- dump files: envlog-03-loadstring.lua
	LOG_READS     = true,
	LOG_WRITES    = true,
	OFFLINE       = true,                -- never perform a REAL http round-trip
	FAKE_BODY     = "-- env-logger offline response (OFLN-200)",
	SHOW_HEAD     = 140,                 -- chars of a dumped source shown inline
	MAX_LOG       = 4000,                -- hard cap on log lines
}

----------------------------------------------------------------
-- 1. SAFE PRIMITIVES  (everything real is captured BEFORE hooking)
----------------------------------------------------------------
local REAL = {}
local function capture(name, value)
	if value ~= nil then REAL[name] = value end
	return value
end

capture("print", print)
capture("tostring", tostring)
capture("type", type)
capture("pcall", pcall)
capture("error", error)
capture("setmetatable", setmetatable)
capture("select", select)
capture("next", next)
capture("sformat", string.format)
capture("load", load)
capture("loadstring", (loadstring or load))
capture("setfenv", setfenv)
capture("genv", (getgenv and getgenv()) or _G)
capture("game", game)
capture("writefile", writefile)
capture("isfolder", isfolder)
capture("makefolder", makefolder)
capture("hookmetamethod", hookmetamethod)
capture("getnamecallmethod", getnamecallmethod)
capture("identifyexecutor", identifyexecutor)

local function fmt(...)                         -- a print/format that cannot be hooked away
	local ok, s = REAL.pcall(REAL.sformat, ...)
	return ok and s or "<fmt-error>"
end

local function describe(v, limit)
	limit = limit or CONFIG.SHOW_HEAD
	local t = REAL.type(v)
	if t == "string" then
		local n = #v
		local head = v:sub(1, limit):gsub("[\r\n]+", " ")
		return fmt("string(%d) %q%s", n, head, n > limit and "..." or "")
	elseif t == "table" then
		local parts = {}
		local i = 0
		for k, val in REAL.next, v do
			i = i + 1
			if i > 6 then break end
			parts[#parts + 1] = fmt("%s=%s", REAL.tostring(k), describe(val, 60))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	elseif t == "userdata" or t == "Instance" then
		local ok, name = REAL.pcall(function()
			return v:GetFullName()
		end)
		return (ok and name) or REAL.tostring(v)
	end
	return REAL.tostring(v)
end

----------------------------------------------------------------
-- 2. LOG + DUMP
----------------------------------------------------------------
local LOGS, DUMPS = {}, {}
local counters = { reads = {}, writes = {}, http = 0, loads = 0 }
local serial = 0

local UI_APPEND = nil                         -- set by the GUI to stream lines live

local function LOG(tag, text)
	if #LOGS >= CONFIG.MAX_LOG then return end
	serial = serial + 1
	local line = fmt("[%04d][%-9s] %s", serial, tag, text)
	LOGS[#LOGS + 1] = line
	if REAL.print then REAL.print(line) end
	if UI_APPEND then UI_APPEND(line) end
end

local function DUMP(tag, content)
	if REAL.type(content) ~= "string" or #content == 0 then return "(nothing)" end
	serial = serial + 1
	local name = fmt("%s-%02d-%s.lua", CONFIG.DUMP_TAG, serial, tag)
	local saved = false
	if REAL.writefile then
		if REAL.isfolder and not REAL.isfolder(CONFIG.DUMP_TAG) then
			REAL.pcall(REAL.makefolder, CONFIG.DUMP_TAG)
		end
		REAL.pcall(REAL.writefile, CONFIG.DUMP_TAG .. "/" .. name, content)
		saved = true
	elseif io and io.open then
		local ok, f = REAL.pcall(io.open, name, "w")
		if ok and f then
			f:write(content)
			f:close()
			saved = true
		end
	end
	local lines = select(2, content:gsub("\n", "\n")) + 1
	DUMPS[#DUMPS + 1] = fmt("%s (%d chars, %d lines)", name, #content, lines)
	LOG("DUMP", fmt("%s -> %s", saved and "saved" or "UNSAVED", name))
	return name
end

local function noteRead(key)
	local n = (counters.reads[key] or 0) + 1
	counters.reads[key] = n
	if n == 1 or n % 50 == 0 then
		LOG("ENV[read]", fmt("%s%s", REAL.tostring(key), n > 1 and fmt("  (x%d)", n) or ""))
	end
end

local function noteWrite(key, value)
	counters.writes[key] = (counters.writes[key] or 0) + 1
	LOG("ENV[write]", fmt("%s = %s", REAL.tostring(key), describe(value, 80)))
end

----------------------------------------------------------------
-- 3. COMPILE ROUTE  (Lua 5.2 "t",env / Luau env / 5.1 setfenv)
----------------------------------------------------------------
local function compileWithEnv(src, name, env, realLoader)
	if REAL.load then
		local ok, fn = REAL.pcall(REAL.load, src, name, "t", env)   -- Lua 5.2/5.3/5.4
		if ok and REAL.type(fn) == "function" then return fn end
		ok, fn = REAL.pcall(REAL.load, src, name, env)              -- Luau (3rd arg = env)
		if ok and REAL.type(fn) == "function" then return fn end
	end
	if REAL.type(realLoader) == "function" then                     -- Lua 5.1 / executors
		local fn, err = realLoader(src, name)
		if fn and REAL.setfenv and env then REAL.setfenv(fn, env) end
		return fn, err
	end
	return nil, "env-logger: no loader available on this runtime"
end

----------------------------------------------------------------
-- 4. HTTP WATCH SET + HOOK FACTORIES
----------------------------------------------------------------
local WATCH_HTTP = { HttpGet = true, HttpGetAsync = true, HttpPost = true, HttpPostAsync = true }

local function logRequestMethod(key, req)
	local url = describe(REAL.type(req) == "table" and (req.Url or req.url) or req, 200)
	LOG("HTTP", fmt("%s -> %s", key, url))
	if REAL.type(req) == "table" then
		if req.Body then DUMP("body", req.Body) end
		LOG("HTTP", fmt("  method=%s headers=%s", REAL.tostring(req.Method or "GET"), describe(req.Headers, 120)))
	end
end

local function hookRequestStyle(holder, key, realFn)
	if REAL.type(realFn) ~= "function" then return end
	LOG("SETUP", fmt("hooking %s", key))
	holder[key] = function(req, ...)
		counters.http = counters.http + 1
		logRequestMethod(key, req)
		if CONFIG.OFFLINE then
			-- Synapse-style table response; good enough for audits.
			return { StatusCode = 200, StatusMessage = "OK", Success = true, Headers = {}, Body = CONFIG.FAKE_BODY }
		end
		return realFn(req, ...)
	end
end

-- loadstring / load hooks: THIS is where the hidden source leaks --------
local PROXY_ENV                                 -- fwd decl, set in section 6

local function hookLoader(holder, key, realFn)
	if REAL.type(realFn) ~= "function" then return end
	LOG("SETUP", fmt("hooking %s", key))
	holder[key] = function(src, chunkname, ...)
		if REAL.type(src) ~= "string" then
			return realFn(src, chunkname, ...)
		end
		counters.loads = counters.loads + 1
		LOG("LOAD", fmt("%s(source %d chars, chunkname=%s)", key, #src, REAL.tostring(chunkname)))
		DUMP("loadstring", src)
		LOG("LOAD", fmt("  head: %s", describe(src, CONFIG.SHOW_HEAD)))
		-- compile through the instrumented env so the payload is logged too
		local fn, err = compileWithEnv(src, chunkname or "=envlog:payload", PROXY_ENV, realFn)
		if not fn then
			LOG("LOAD", fmt("  compile error: %s", REAL.tostring(err)))
		end
		return fn, err
	end
end

-- __namecall hook (game:HttpGet etc.) — userdata calls bypass the env ---
local function hookNamecall()
	if not (REAL.game and REAL.hookmetamethod and REAL.getnamecallmethod) then return end
	local old
	old = REAL.hookmetamethod(REAL.game, "__namecall", function(self, ...)
		local method = REAL.getnamecallmethod()
		if WATCH_HTTP[method] then
			counters.http = counters.http + 1
			local a1 = select(1, ...)
			LOG("HTTP", fmt("namecall %s:%s -> %s", describe(self, 60), method, describe(a1, 200)))
			if CONFIG.OFFLINE and (method == "HttpGet" or method == "HttpGetAsync") then
				return CONFIG.FAKE_BODY
			end
		end
		return old(self, ...)
	end)
	LOG("SETUP", "hookmetamethod __namecall installed")
end

----------------------------------------------------------------
-- 5. HOOK TABLE (what the proxy serves instead of the real env)
----------------------------------------------------------------
local HOOKS = {}

local function installHooks()
	hookLoader(HOOKS, "loadstring", REAL.loadstring)
	hookLoader(HOOKS, "load", REAL.load)
	hookRequestStyle(HOOKS, "request", REAL.genv.request)
	hookRequestStyle(HOOKS, "http_request", REAL.genv.http_request)
	if REAL.type(REAL.genv.syn) == "table" then
		HOOKS.syn = REAL.setmetatable({}, { __index = REAL.genv.syn })
		hookRequestStyle(HOOKS.syn, "request", REAL.genv.syn.request)
	end
	if REAL.type(REAL.genv.http) == "table" then
		HOOKS.http = REAL.setmetatable({}, { __index = REAL.genv.http })
		hookRequestStyle(HOOKS.http, "get", REAL.genv.http.get)
		hookRequestStyle(HOOKS.http, "post", REAL.genv.http.post)
	end
	hookNamecall()
end

----------------------------------------------------------------
-- 6. PROXY ENVIRONMENT (sandbox + full read/write logging)
----------------------------------------------------------------
local function buildProxy()
	local STORE = {}                            -- the target's own globals live here
	local proxy
	proxy = REAL.setmetatable({}, {
		__index = function(_, k)
			if k == "_G" or k == "_ENV" then return proxy end
			if CONFIG.LOG_READS then noteRead(k) end
			local h = HOOKS[k]                   -- hooks first: the target cannot defeat them
			if h ~= nil then return h end
			local v = STORE[k]                   -- then its own globals
			if v ~= nil then return v end
			return REAL.genv[k]                  -- then the real environment
		end,
		__newindex = function(_, k, v)
			if CONFIG.LOG_WRITES then noteWrite(k, v) end
			STORE[k] = v                        -- isolated: the real env is never touched
		end,
	})
	STORE._G = proxy
	return proxy
end

----------------------------------------------------------------
-- 7. RUNNER
----------------------------------------------------------------
local function getTarget()
	if CONFIG.SOURCE_MODE == "string" then
		return CONFIG.TARGET_STRING
	elseif CONFIG.SOURCE_MODE == "file" then
		local content
		if readfile then content = readfile(CONFIG.TARGET_FILE) end
		if REAL.type(content) ~= "string" and io and io.open then
			local f = io.open(CONFIG.TARGET_FILE, "r")
			if f then
				content = f:read("*a")
				f:close()
			end
		end
		if REAL.type(content) ~= "string" then
			REAL.error("env-logger: cannot read target file '" .. CONFIG.TARGET_FILE .. "'", 0)
		end
	
		return content
	elseif CONFIG.SOURCE_MODE == "url" then
		if CONFIG.OFFLINE then
			REAL.error("env-logger: SOURCE_MODE='url' requires OFFLINE=false", 0)
		end
		LOG("SETUP", fmt("fetching target url (this one is allowed): %s", CONFIG.TARGET_URL))
		local ok, body = REAL.pcall(function()
			return REAL.game:HttpGet(CONFIG.TARGET_URL)
		end)
		if not ok then
			REAL.error("env-logger: target url fetch failed: " .. REAL.tostring(body), 0)
		end
		return body
	end
	REAL.error("env-logger: bad SOURCE_MODE '" .. REAL.tostring(CONFIG.SOURCE_MODE) .. "'", 0)
end

local hooksReady = false

local function run(target)
	if not hooksReady then
		installHooks()
		hooksReady = true
	end
	PROXY_ENV = buildProxy()
	DUMP("target", target)

	LOG("SETUP", fmt("executor=%s runtime=%s offline=%s",
		(REAL.identifyexecutor and REAL.identifyexecutor()) or "none",
		_VERSION or "?", REAL.tostring(CONFIG.OFFLINE)))

	local fn, err = compileWithEnv(target, "=envlog:target", PROXY_ENV, REAL.loadstring)
	if not fn then
		LOG("ERROR", fmt("target compile failed: %s", REAL.tostring(err)))
		return
	end

	LOG("RUN", "executing target under proxy environment ...")
	local ok, result = REAL.pcall(fn)
	LOG("RUN", fmt("target returned: %s %s", REAL.tostring(ok), describe(result, 200)))
end

----------------------------------------------------------------
-- 8. SUMMARY
----------------------------------------------------------------
local function summary()
	local function add(line)
		LOGS[#LOGS + 1] = line
		if REAL.print then REAL.print(line) end
		if UI_APPEND then UI_APPEND(line) end
	end
	LOGS[#LOGS + 1] = "================ ENV-LOGGER SUMMARY ================"
	add(fmt("http calls logged : %d", counters.http))
	add(fmt("loadstring calls  : %d", counters.loads))
	local reads, rkeys = 0, 0
	for _, n in REAL.next, counters.reads do
		reads = reads + n
		rkeys = rkeys + 1
	end
	add(fmt("global reads      : %d over %d unique keys", reads, rkeys))
	local wkeys = 0
	for _ in REAL.next, counters.writes do wkeys = wkeys + 1 end
	add(fmt("global writes     : %d unique keys", wkeys))
	add("dumped files:")
	if #DUMPS == 0 then
		add("  (none - target never called loadstring/request)")
	else
		for _, d in REAL.next, DUMPS do add("  " .. d) end
	end
	add(fmt("log lines         : %d (cap %d)", #LOGS, CONFIG.MAX_LOG))
	add("======================================================")
end

----------------------------------------------------------------
-- 9. GUI  (Roblox executors) + LAUNCHER
----------------------------------------------------------------
local function resetRunState()
	LOGS, DUMPS = {}, {}
	counters.reads, counters.writes = {}, {}
	counters.http, counters.loads = 0, 0
	serial = 0
end

local function executeFromGui(mode, text, offline)
	resetRunState()
	CONFIG.SOURCE_MODE = mode
	CONFIG.OFFLINE = offline
	if mode == "string" then
		CONFIG.TARGET_STRING = text
	elseif mode == "url" then
		CONFIG.TARGET_URL = text
	elseif mode == "file" then
		CONFIG.TARGET_FILE = text
	end
	local ok, target = REAL.pcall(getTarget)
	if not ok then
		LOG("ERROR", "cannot load target: " .. REAL.tostring(target))
		return
	end
	run(target)
	summary()
end

local function buildGui()
	return REAL.pcall(function()
		-- parent: gethui() > CoreGui > PlayerGui
		local parent
		if type(gethui) == "function" then parent = gethui() end
		if not parent then
			local okCG, coregui = pcall(function()
				return game:GetService("CoreGui")
			end)
			parent = (okCG and coregui) or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
		end

		local old = parent:FindFirstChild("EnvLoggerGui")
		if old then old:Destroy() end

		local gui = Instance.new("ScreenGui")
		gui.Name = "EnvLoggerGui"
		gui.ResetOnSpawn = false
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = parent

		local main = Instance.new("Frame")
		main.Name = "Main"
		main.Size = UDim2.fromOffset(620, 470)
		main.Position = UDim2.fromScale(0.5, 0.5)
		main.AnchorPoint = Vector2.new(0.5, 0.5)
		main.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
		main.BorderSizePixel = 0
		main.Active = true
		main.Parent = gui
		Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

		-- title bar + drag
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(1, 0, 0, 34)
		bar.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
		bar.BorderSizePixel = 0
		bar.Parent = main
		Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -90, 1, 0)
		title.BackgroundTransparency = 1
		title.Text = "  ENV-LOGGER — protection audit (your own scripts only)"
		title.TextColor3 = Color3.fromRGB(235, 235, 245)
		title.Font = Enum.Font.GothamBold
		title.TextSize = 14
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = bar

		local closeBtn = Instance.new("TextButton")
		closeBtn.Size = UDim2.fromOffset(28, 28)
		closeBtn.Position = UDim2.new(1, -34, 0, 3)
		closeBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 34)
		closeBtn.Text = "X"
		closeBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
		closeBtn.Font = Enum.Font.GothamBold
		closeBtn.TextSize = 14
		closeBtn.Parent = bar
		closeBtn.MouseButton1Click:Connect(function()
			gui:Destroy()
		end)

		do -- dragging
			local dragging, dragStart, startPos = false, nil, nil
			bar.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					dragging = true
					dragStart = input.Position
					startPos = main.Position
				end
			end)
			bar.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					dragging = false
				end
			end)
			game:GetService("UserInputService").InputChanged:Connect(function(input)
				if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch) then
					local delta = input.Position - dragStart
					main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
						startPos.Y.Scale, startPos.Y.Offset + delta.Y)
				end
			end)
		end

		-- input box (declared first: mode buttons reference it)
		local inputBox = Instance.new("TextBox")
		inputBox.Size = UDim2.new(1, -24, 0, 110)
		inputBox.Position = UDim2.fromOffset(12, 80)
		inputBox.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
		inputBox.TextColor3 = Color3.fromRGB(220, 220, 230)
		inputBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
		inputBox.Font = Enum.Font.Code
		inputBox.TextSize = 13
		inputBox.Text = ""
		inputBox.PlaceholderText = "paste the protected loader / script source here"
		inputBox.ClearTextOnFocus = false
		inputBox.TextWrapped = true
		inputBox.MultiLine = true
		inputBox.Parent = main
		Instance.new("UICorner", inputBox).CornerRadius = UDim.new(0, 6)

		-- mode buttons
		local selectedMode = "string"
		local modeButtons = {}
		local modeRow = Instance.new("Frame")
		modeRow.Size = UDim2.new(1, -24, 0, 30)
		modeRow.Position = UDim2.fromOffset(12, 42)
		modeRow.BackgroundTransparency = 1
		modeRow.Parent = main
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.Padding = UDim.new(0, 8)
		list.Parent = modeRow
		for _, m in ipairs({ "string", "url", "file" }) do
			local b = Instance.new("TextButton")
			b.Size = UDim2.fromOffset(110, 30)
			b.Text = m
			b.Font = Enum.Font.Gotham
			b.TextSize = 13
			b.BackgroundColor3 = (m == "string") and Color3.fromRGB(70, 110, 190) or Color3.fromRGB(40, 40, 52)
			b.TextColor3 = (m == "string") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 190)
			b.Parent = modeRow
			Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
			modeButtons[m] = b
			b.MouseButton1Click:Connect(function()
				selectedMode = m
				for name, btn in pairs(modeButtons) do
					btn.BackgroundColor3 = (name == m) and Color3.fromRGB(70, 110, 190) or Color3.fromRGB(40, 40, 52)
					btn.TextColor3 = (name == m) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 190)
				end
				inputBox.MultiLine = (m == "string")
				inputBox.PlaceholderText = (m == "string" and "paste the protected loader / script source here")
					or (m == "url" and "https://... (loader url — needs OFFLINE off)")
					or "target.lua (executor workspace file)"
			end)
		end

		-- OFFLINE toggle
		local offline = true
		local offlineBtn = Instance.new("TextButton")
		offlineBtn.Size = UDim2.fromOffset(150, 30)
		offlineBtn.Position = UDim2.fromOffset(12, 200)
		offlineBtn.Text = "OFFLINE: ON"
		offlineBtn.Font = Enum.Font.Gotham
		offlineBtn.TextSize = 13
		offlineBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		offlineBtn.BackgroundColor3 = Color3.fromRGB(40, 110, 70)
		offlineBtn.Parent = main
		Instance.new("UICorner", offlineBtn).CornerRadius = UDim.new(0, 6)
		offlineBtn.MouseButton1Click:Connect(function()
			offline = not offline
			offlineBtn.Text = "OFFLINE: " .. (offline and "ON" or "OFF")
			offlineBtn.BackgroundColor3 = offline and Color3.fromRGB(40, 110, 70) or Color3.fromRGB(140, 70, 40)
		end)

		-- EXECUTE button
		local execBtn = Instance.new("TextButton")
		execBtn.Size = UDim2.fromOffset(130, 30)
		execBtn.Position = UDim2.new(1, -154, 0, 200)
		execBtn.Text = "EXECUTE"
		execBtn.Font = Enum.Font.GothamBold
		execBtn.TextSize = 14
		execBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		execBtn.BackgroundColor3 = Color3.fromRGB(70, 110, 190)
		execBtn.Parent = main
		Instance.new("UICorner", execBtn).CornerRadius = UDim.new(0, 6)

		-- output panel
		local scroll = Instance.new("ScrollingFrame")
		scroll.Size = UDim2.new(1, -24, 1, -248)
		scroll.Position = UDim2.fromOffset(12, 242)
		scroll.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
		scroll.BorderSizePixel = 0
		scroll.ScrollBarThickness = 6
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		scroll.Parent = main
		Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 6)

		local output = Instance.new("TextLabel")
		output.Size = UDim2.new(1, -12, 0, 0)
		output.AutomaticSize = Enum.AutomaticSize.Y
		output.BackgroundTransparency = 1
		output.TextColor3 = Color3.fromRGB(170, 255, 170)
		output.Font = Enum.Font.Code
		output.TextSize = 12
		output.Text = "logs will appear here — pick a mode, paste the target, press EXECUTE"
		output.TextWrapped = true
		output.TextXAlignment = Enum.TextXAlignment.Left
		output.TextYAlignment = Enum.TextYAlignment.Top
		output.Parent = scroll

		-- stream every LOG line into the panel
		local buffer = {}
		UI_APPEND = function(line)
			buffer[#buffer + 1] = line
			if #buffer > 600 then
				local tail = {}
				for i = #buffer - 400, #buffer do tail[#tail + 1] = buffer[i] end
				buffer = tail
			end
			output.Text = table.concat(buffer, "\n")
		end

		execBtn.MouseButton1Click:Connect(function()
			output.Text = ""
			buffer = {}
			execBtn.Text = "RUNNING..."
			local ok, err = pcall(executeFromGui, selectedMode, inputBox.Text, offline)
			execBtn.Text = "EXECUTE"
			if not ok then
				UI_APPEND("[GUI ERROR] " .. tostring(err))
			end
		end)
	end)
end

if not buildGui() then
	-- console fallback: CLI / no GUI rights -> use CONFIG at the top
	run(getTarget())
	summary()
end

-- Returned for programmatic use (executor console, test harnesses)
return { logs = LOGS, dumps = DUMPS, counters = counters, config = CONFIG }
]==])()
