--[[ =========================================================================
 LOCUS v2.1.2 - behavior audit tool for Vykus / PolSec-style protections
============================================================================
(formerly ENV-LOGGER v1.0; dump folder renamed envlog/ -> locus/)
(v2.1: GUI launcher - enter the target in the GUI, press EXECUTE AUDIT)

Runs a protected script (or its loader) inside an instrumented environment
and records everything it touches:

  * every global read / write  ->  ENV[read] key (count) / ENV[write]
  * loadstring / load calls    ->  full source dumped to a file
  * HTTP: request, http.request, syn.request, http.get/post,
    game:HttpGet/HttpGetAsync/HttpPost/HttpPostAsync (via __namecall hook)
    ->  the TRUE url + body, even if the Loader hides it behind layers
  * remote calls: FireServer / InvokeServer logged with the remote path
    and a preview of the first argument (via __namecall hook)
  * leak scanner: every dumped source is auto-scanned for urls, discord
    webhooks and hwid/fingerprint strings, flagged in the summary
  * detection report: a target that errors with zero loadstring/http
    activity is reported as a possible anti-instrumentation detection
  * GUI: on executors a launcher window opens - enter the URL or paste
    the source, toggle OFFLINE / console printing, press EXECUTE AUDIT,
    and watch the output stream into the GUI log live

MAIN GOAL: full source recovery. Every source string the target (or any
of its stages) hands to loadstring/load is dumped verbatim to
<workspace>/locus/*.lua. A layered loader that fetches stage 2, 3, ...
over HTTP and loadstrings them hands you every stage's complete source.
A Vykus packed output that bootstraps via (loadstring or load)('...')
gets its entire program source dumped on the spot.

HOW TO USE
----------
  0) Roblox executor (Xeno etc.): run the script. The LOCUS GUI opens.
     - SOURCE MODE: URL  -> put the loader URL in the URL box
     - SOURCE MODE: TEXT -> paste the protected script in the big box
     - toggle OFFLINE (default ON: fake responses, no real requests)
     - toggle CONSOLE SOURCE PRINT if you also want sources in the console
     - press EXECUTE AUDIT. Output streams into the GUI log;
       dumps land in workspace/locus/*.lua.
  1) If the GUI cannot be built on your executor, the script falls back
     to auditing the built-in placeholder with default settings
     (edit the entry line at the bottom to pass a config table).
  2) Lua 5.3/5.4 or Luau CLI:  lua locus.lua  /  luau locus.lua
     (no GUI; falls back to io.open dumps; no executor APIs required).

READING THE RESULTS (security audit)
-----------------------------------
  * A url or source you did not intend to expose appears in the log
    -> LEAK: fix the loader.
  * A hit in the leak scan (webhook / hwid / fingerprint) in a source
    you did not write -> treat the loader as hostile until explained.
  * Vykus VM output aborts silently / digest-errors while plain scripts
    run fine under the same logger -> the tamper/probe gate DETECTED the
    instrumentation: that is a PASS for the protection, not a failure.
  * Classic-mode (non-VM) artifacts are always env-readable: env logging
    is the baseline attack your VM mode should survive better.

Honest residuals (what this harness does not catch):
  - game.HttpGet(url) dot-calls (no colon) bypass the __namecall hook.
  - Remotes are observed, never stubbed: OFFLINE blocks HTTP, not game
    interaction (a FireServer still fires for real).
  - Continuations spawned via task.delay/spawn may finish after the summary.
  - Bytecode chunks cannot be env-bound on Lua 5.3+ (they still get dumped).
  - The harness is an observer, not a prison: aliases captured before
    instrumentation can survive. It is built to audit your own Vykus /
    PolSec-style outputs, which it does exactly.
]]

-- ================================ HOST =====================================
-- The harness itself works only on captured REAL globals, so its own
-- activity is never counted in the audit.

local G = _G

local realType   = type
local rawget_    = rawget
local tinsert    = table.insert
local tconcat    = table.concat
local sfind      = string.find
local format     = string.format
local sub        = string.sub
local realPrint  = print
local pcall_     = pcall
local tostring_  = tostring
local pairs_     = pairs
local ipairs_    = ipairs

local realLoad       = load
local realLoadstring = loadstring or load
local realSetfenv    = setfenv

local EXEC     = (realType(game) ~= "nil")            -- Roblox executor / Luau host
local HAS_LFS  = (realType(writefile) == "function") -- executor file API
local HAS_IO   = (realType(io) == "table" and realType(io.open) == "function")
local CAN_HOOK = (realType(hookmetamethod) == "function")
             and (realType(getnamecallmethod) == "function")

-- Roblox/executor environments do NOT expose the standard libraries through
-- _G (desktop Lua does). The proxy env falls back to this table first, so
-- audited targets still see table/string/math/game/task/... on Roblox.
local FALLBACK = {
  table = table, string = string, math = math, os = os, io = io,
  coroutine = coroutine, bit32 = bit32, utf8 = utf8, task = task,
  game = game, workspace = workspace, script = script,
  Instance = Instance, Enum = Enum, UDim2 = UDim2, Color3 = Color3,
  Vector3 = Vector3, Vector2 = Vector2, CFrame = CFrame, Ray = Ray,
  warn = warn, typeof = typeof, tick = tick, wait = wait,
  spawn = spawn, delay = delay, require = require,
  tostring = tostring, tonumber = tonumber, pairs = pairs, ipairs = ipairs,
  next = next, select = select, unpack = unpack, pcall = pcall,
  xpcall = xpcall, setmetatable = setmetatable, getmetatable = getmetatable,
  rawget = rawget, rawset = rawset, rawequal = rawequal, rawlen = rawlen,
  assert = assert, error = error, type = type, print = print,
  loadstring = loadstring, load = load, getfenv = getfenv, setfenv = setfenv,
  getgenv = getgenv, hookmetamethod = hookmetamethod,
  getnamecallmethod = getnamecallmethod, getrawmetatable = getrawmetatable,
  setrawmetatable = setrawmetatable, newcclosure = newcclosure,
  identifyexecutor = identifyexecutor, request = request,
  http_request = http_request, writefile = writefile, readfile = readfile,
  isfile = isfile, isfolder = isfolder, makefolder = makefolder,
  delfile = delfile, delfolder = delfolder, listfiles = listfiles,
}

local PLACEHOLDER = [[
-- paste the protected script / loader here (or use SOURCE MODE: URL in the GUI)
print("hello from the audited script")
]]

-- ------------------------- target fetch (real http) ------------------------
-- fetches the target with the REAL http stack, before any hook exists,
-- so the bootstrap fetch itself is never counted in the audit

local function realHttpGet(url)
  if EXEC then
    local ok, res = pcall_(function() return game:HttpGet(url) end)
    if ok and realType(res) == "string" then return res end
    if realType(http) == "table" and realType(http.get) == "function" then
      local ok2, res2 = pcall_(http.get, url)
      if ok2 and realType(res2) == "string" then return res2 end
    end
    if realType(request) == "function" then
      local ok3, res3 = pcall_(request, { Url = url, Method = "GET" })
      if ok3 and realType(res3) == "table" and realType(res3.Body) == "string" then
        return res3.Body
      end
    end
    return nil, "no http API available in this executor"
  end
  if realType(io) == "table" and realType(io.popen) == "function" then
    local ok, res = pcall_(function()
      local fh = io.popen("curl -sL " .. url)
      if not fh then return nil end
      local out = fh:read("*a")
      fh:close()
      return out
    end)
    if ok and realType(res) == "string" and #res > 0 then return res end
    return nil, "io.popen/curl fetch failed"
  end
  return nil, "no http API on this host (use SOURCE_MODE = 'text')"
end

-- ================================ AUDIT RUN ================================
-- one complete audit = one runAudit(cfg) call:
--   cfg.OFFLINE          true  -> every HTTP call returns a fake response
--   cfg.SOURCE_MODE      "text" | "url"
--   cfg.SOURCE_TEXT      the pasted target (text mode)
--   cfg.SOURCE_URL       the fetch target (url mode)
--   cfg.LOG_DIR          dump folder (default "locus")
--   cfg.SCAN_LEAKS       scan dumped sources (default true)
--   cfg.CAPTURE_REMOTES  log FireServer/InvokeServer (default true)
--   cfg.PRINT_SOURCES    print dumped sources (default true)
--   cfg.PRINT_LIMIT      console chars per source (default 20000)
--   cfg.onLog            function(line) for GUI live output

local function runAudit(cfg)
  cfg = (realType(cfg) == "table") and cfg or {}

  local OFFLINE         = cfg.OFFLINE and true or false
  local SOURCE_MODE     = (cfg.SOURCE_MODE == "url") and "url" or "text"
  local SOURCE_TEXT     = (realType(cfg.SOURCE_TEXT) == "string") and cfg.SOURCE_TEXT or PLACEHOLDER
  local SOURCE_URL      = (realType(cfg.SOURCE_URL) == "string") and cfg.SOURCE_URL or ""
  local LOG_DIR         = (realType(cfg.LOG_DIR) == "string" and #cfg.LOG_DIR > 0) and cfg.LOG_DIR or "locus"
  local SCAN_LEAKS      = cfg.SCAN_LEAKS ~= false
  local CAPTURE_REMOTES = cfg.CAPTURE_REMOTES ~= false
  local PRINT_SOURCES   = cfg.PRINT_SOURCES ~= false
  local PRINT_LIMIT     = (realType(cfg.PRINT_LIMIT) == "number") and cfg.PRINT_LIMIT or 20000
  local onLog           = (realType(cfg.onLog) == "function") and cfg.onLog or nil

  -- print to console AND to the GUI log when one is attached
  local function P(...)
    realPrint(...)
    if onLog then
      local n = select("#", ...)
      local parts = {}
      for i = 1, n do parts[i] = tostring_((select(i, ...))) end
      onLog(tconcat(parts, "\t"))
    end
  end

  -- ------------------------------- banner ----------------------------------

  P("========================================================================")
  P(" LOCUS v2.1.2 - behavior audit tool for Vykus / PolSec-style protections")
  P("========================================================================")
  P("  * every global read / write  ->  ENV[read] key (count) / ENV[write]")
  P("  * loadstring / load calls    ->  full source dumped to a file")
  P("  * HTTP: request, http.request, syn.request, http.get/post,")
  P("    game:HttpGet/HttpGetAsync/HttpPost/HttpPostAsync (namecall hook)")
  P("  * remotes: FireServer / InvokeServer logged with args")
  P("  * leak scan on every dumped source: urls / webhooks / hwid")
  P("")
  P(" host    : " .. (EXEC and "Roblox executor" or "Lua CLI"))
  P(" files   : " .. ((HAS_LFS and ("writefile -> workspace/" .. LOG_DIR .. "/"))
    or ((HAS_IO and ("io.open -> ./" .. LOG_DIR .. "/")) or "NO FILE API (dumps disabled)")))
  P(" namecall: " .. ((EXEC and CAN_HOOK) and "hook available" or "not available"))
  P(" executor : " .. ((realType(identifyexecutor) == "function")
    and identifyexecutor() or "unknown"))
  P(" extras  : leak scan = " .. tostring_(SCAN_LEAKS)
    .. ", remote capture = " .. tostring_(CAPTURE_REMOTES))
  P(" OFFLINE : " .. tostring_(OFFLINE))
  P("========================================================================")

  -- ------------------------------ file dumps -------------------------------

  local filesWritten = {}
  local dirTried = false

  local function ensureDir()
    if dirTried then return end
    dirTried = true
    if realType(os) == "table" and realType(os.execute) == "function" then
      pcall_(os.execute, "mkdir -p " .. LOG_DIR)
      pcall_(os.execute, "mkdir " .. LOG_DIR)
    end
  end

  local function dumpFile(name, content)
    local full = LOG_DIR .. "/" .. name
    local flat = LOG_DIR .. "_" .. name
    local ok, where = false, full
    if HAS_LFS then
      if realType(isfolder) == "function" and realType(makefolder) == "function"
        and not isfolder(LOG_DIR) then
        pcall_(makefolder, LOG_DIR)
      end
      pcall_(writefile, full, content)
      if realType(isfile) == "function" then
        if isfile(full) then
          ok = true
        else
          pcall_(writefile, flat, content)
          if isfile(flat) then ok, where = true, flat end
        end
      else
        ok = true -- no isfile to verify with; assume the pcall wrote it
      end
    end
    if not ok and HAS_IO then
      ensureDir()
      ok = pcall_(function()
        local fh = io.open(full, "w")
        if not fh then fh = io.open(flat, "w") end
        if not fh then return false end
        fh:write(content)
        fh:close()
        return true
      end)
      if ok then
        local fh2 = io.open(full, "r")
        if fh2 then fh2:close() else where = flat end
      end
    end
    tinsert(filesWritten, { path = ok and where or full, ok = ok, size = #content })
    return ok
  end

  -- ------------------------------ audit state ------------------------------

  local readCounts, writeCounts = {}, {}
  local totalReads, totalWrites = 0, 0
  local loadEvents, httpEvents = {}, {}
  local remoteEvents, leakHits = {}, {}
  local writeDesc = {}   -- first-write value preview per key
  local isolationLeak = false

  -- short, safe value preview for the summary (no gsub: stays harness-safe)
  local function describe(v, limit)
    local t = realType(v)
    if t == "string" then
      local n = #v
      local m = n < limit and n or limit
      local head = ""
      for i = 1, m do
        local c = sub(v, i, i)
        if c >= " " then head = head .. c else head = head .. " " end
      end
      if n > limit then head = head .. "..." end
      return format("string(%d) '%s'", n, head)
    elseif t == "table" or t == "userdata" then
      return t
    end
    return tostring_(v)
  end

  -- --------------------------- the instrumented env ------------------------

  -- Proxy globals: backing holds writes; unknown keys fall through to the
  -- real _G. Every single read and write is counted, every time.

  local backing = {}
  local env

  env = setmetatable({}, {
    __index = function(_, k)
      totalReads = totalReads + 1
      readCounts[k] = (readCounts[k] or 0) + 1
      local v = backing[k]
      if v ~= nil then return v end
      local fb = FALLBACK[k]
      if fb ~= nil then return fb end
      return G[k]
    end,
    __newindex = function(_, k, v)
      totalWrites = totalWrites + 1
      writeCounts[k] = (writeCounts[k] or 0) + 1
      if writeDesc[k] == nil then writeDesc[k] = describe(v, 48) end
      backing[k] = v
    end,
  })

  -- --------------------------- compile into the env ------------------------

  local function compileInto(src, cname)
    -- 1) compile with loadstring (executors, Lua 5.1) or load (5.2+/Luau)
    local f, err
    if realLoadstring ~= realLoad then
      local ok, a, b = pcall_(realLoadstring, src, cname)
      if not ok then return nil, a end
      f, err = a, b
    end
    if realType(f) ~= "function" and realLoad then
      local ok, a, b = pcall_(realLoad, src, cname)
      if not ok then return nil, a end
      f, err = a, b
    end
    if realType(f) ~= "function" then return f, err end
    -- 2) bind the chunk to the sandboxed env
    if realSetfenv then
      local ok, r = pcall_(realSetfenv, f, env)
      if ok and realType(r) == "function" then return r end
    end
    local ok2, f2 = pcall_(realLoad, src, cname, env)       -- Lua 5.2 / Luau load env
    if ok2 and realType(f2) == "function" then return f2 end
    local ok3, f3 = pcall_(realLoad, src, cname, "t", env)  -- Lua 5.3 / 5.4 mode+env
    if ok3 and realType(f3) == "function" then return f3 end
    isolationLeak = true -- could not bind: this chunk runs on raw globals
    return f
  end

  -- --------------------- loadstring / load interception --------------------

  local dumpSeq = 0

  -- manual padding (avoids %-10s style width flags, which stay portable)
  local function pad(s, n)
    s = tostring_(s)
    if #s >= n then return s end
    return s .. string.rep(" ", n - #s)
  end

  -- leak scanner: plain string.find loops (no gsub; harness-safe)
  local function scanSource(source, label)
    if not SCAN_LEAKS or realType(source) ~= "string" or #source == 0 then return end
    local needles = {
      { "https://",    "url" },
      { "http://",     "url" },
      { "webhooks",    "discord-webhook" },
      { "hwid",        "hwid" },
      { "HWID",        "hwid" },
      { "fingerprint", "fingerprint" },
    }
    for _, nd in ipairs_(needles) do
      local pat, kind = nd[1], nd[2]
      local from = 1
      while #leakHits < 200 do
        local at = sfind(source, pat, from, true)
        if not at then break end
        local snippet = sub(source, at, at + 79)
        local clean = {}
        for i = 1, #snippet do
          local c = sub(snippet, i, i)
          if c >= " " then tinsert(clean, c) end
        end
        tinsert(leakHits, format("%s [%s] @%d '%s'", label, kind, at, tconcat(clean)))
        from = at + #pat
      end
    end
  end

  -- console view: print a dumped source so you can watch it pass in real time
  local function printSource(fname, source)
    if not PRINT_SOURCES then return end
    P("")
    P("======== [locus] SOURCE " .. fname .. " (" .. #source .. " bytes) ========")
    if #source <= PRINT_LIMIT then
      P(source)
    else
      P(sub(source, 1, PRINT_LIMIT))
      P("======== [locus] truncated, " .. (#source - PRINT_LIMIT)
        .. " more bytes; full copy in " .. LOG_DIR .. "/" .. fname .. " ========")
    end
  end

  local function noteLoadSource(source, label, cname)
    dumpSeq = dumpSeq + 1
    local fname = format("loadstring_%02d.lua", dumpSeq)
    dumpFile(fname, source)
    scanSource(source, fname)
    local line = format("%s -> %s/%s (%d bytes, chunk='%s')",
      pad(label, 10), LOG_DIR, fname, #source, tostring_(cname))
    tinsert(loadEvents, line)
    P("[locus] " .. line)
    printSource(fname, source)
  end

  local function makeWrappedLoader(realFn, label)
    return function(src, cname, ...)
      -- string source: dump it verbatim, compile it into the sandbox
      if realType(src) == "string" and #src > 0 then
        noteLoadSource(src, label, cname)
        return compileInto(src, cname)
      end
      -- reader-function source: drain the reader and dump what it produced
      if realType(src) == "function" then
        local acc = {}
        while true do
          local ok, piece = pcall_(src)
          if not ok or piece == nil then break end
          tinsert(acc, piece)
          if #acc >= 65536 then break end
        end
        local source = tconcat(acc)
        noteLoadSource(source, label, cname)
        return compileInto(source, cname)
      end
      return realFn(src, cname, ...)
    end
  end

  -- ------------------------------- HTTP hooks ------------------------------

  local OFFLINE_BODY = '{"status":"ok","offline":true}'

  local function noteHttp(label, url, body)
    tinsert(httpEvents, { label = label, url = tostring_(url), body = body })
    P(format("[locus] %s %s%s", label, tostring_(url),
      OFFLINE and "  (OFFLINE stub)" or ""))
  end

  local function offlineResponse(label, url)
    return {
      Success       = true,
      StatusCode    = 200,
      StatusMessage = "200 OK (offline stub)",
      Body          = OFFLINE_BODY,
      Headers       = { ["Content-Type"] = "application/json" },
      Url           = url,
      Method        = label,
    }
  end

  -- request / http_request / http.request / syn.request
  -- accepts request(url, opts), request(url, body), request({Url=..., Body=...})
  local function wrapRequest(realFn, label)
    return function(a, b, ...)
      local url, body
      if realType(a) == "table" then
        url  = a.Url or a.url or a.URL
        body = a.Body or a.body
      else
        url = a
        if realType(b) == "table" then body = b.Body or b.body
        elseif realType(b) == "string" then body = b end
      end
      noteHttp(label, url, body)
      if OFFLINE then return offlineResponse(label, url) end
      return realFn(a, b, ...)
    end
  end

  local function wrapGet(realFn, label) -- http.get / HttpGet / HttpGetAsync / GetAsync
    return function(url, ...)
      noteHttp(label, url, nil)
      if OFFLINE then return OFFLINE_BODY end
      return realFn(url, ...)
    end
  end

  local function wrapPost(realFn, label) -- http.post / HttpPost / PostAsync
    return function(url, body, ...)
      noteHttp(label, url, body)
      if OFFLINE then return OFFLINE_BODY end
      return realFn(url, body, ...)
    end
  end

  -- proxy an API table (http, syn): wrapped reads, counted writes
  local function proxyTable(realT, name, wrapMap)
    local store = {}
    return setmetatable({}, {
      __index = function(_, k)
        local v = store[k]
        if v ~= nil then return v end
        local orig = rawget_(realT, k)
        local w = wrapMap[k]
        if orig ~= nil and w and realType(orig) == "function" then
          return w(orig)
        end
        return orig
      end,
      __newindex = function(_, k, v)
        totalWrites = totalWrites + 1
        local dk = name .. "." .. tostring_(k)
        writeCounts[dk] = (writeCounts[dk] or 0) + 1
        store[k] = v
      end,
    })
  end

  -- ------------------------ instrumented env installs ----------------------

  -- close the classic escape hatches so reads keep flowing through the proxy
  backing._G = env
  if realType(getfenv) == "function" then
    backing.getfenv = function() return env end
  end
  if realType(getgenv) == "function" then
    backing.getgenv = function() return env end
  end

  -- wrapped loaders everywhere; loadstring shim on 5.3/5.4 CLI
  backing.loadstring = makeWrappedLoader(loadstring or realLoad, "loadstring")
  backing.load       = makeWrappedLoader(realLoad, "load")

  if realType(request) == "function" then
    backing.request = wrapRequest(request, "request")
  end
  if realType(http_request) == "function" then
    backing.http_request = wrapRequest(http_request, "http_request")
  end
  if realType(http) == "table" then
    backing.http = proxyTable(http, "http", {
      request = function(r) return wrapRequest(r, "http.request") end,
      get     = function(r) return wrapGet(r, "http.get") end,
      post    = function(r) return wrapPost(r, "http.post") end,
    })
  end
  if realType(syn) == "table" then
    backing.syn = proxyTable(syn, "syn", {
      request = function(r) return wrapRequest(r, "syn.request") end,
    })
  end

  -- ------------------------- __namecall hook (executor) --------------------

  local namecallHooked = false

  local function installNamecallHook()
    if not (EXEC and CAN_HOOK) then return end
    -- capture the original __namecall BEFORE hooking, so we can pass through
    local okMT, mt = pcall_(function()
      if realType(getrawmetatable) == "function" then return getrawmetatable(game) end
      return getmetatable(game)
    end)
    local oldNamecall = (okMT and realType(mt) == "table") and mt.__namecall or nil
    if realType(oldNamecall) ~= "function" then return end

    local okS, HTTP_SERVICE = pcall_(game.GetService, game, "HttpService")
    if not okS then HTTP_SERVICE = nil end

    local function hook(self, ...)
      local args = { ... }
      local method = getnamecallmethod()
      if self == game and (method == "HttpGet" or method == "HttpGetAsync") then
        noteHttp("game:" .. method, args[1], nil)
        if OFFLINE then return OFFLINE_BODY end
      elseif self == game and (method == "HttpPost" or method == "HttpPostAsync") then
        noteHttp("game:" .. method, args[1], args[2] or args[3])
        if OFFLINE then return OFFLINE_BODY end
      elseif self == HTTP_SERVICE and method == "GetAsync" then
        noteHttp("HttpService:GetAsync", args[1], nil)
        if OFFLINE then return OFFLINE_BODY end
      elseif self == HTTP_SERVICE and method == "PostAsync" then
        noteHttp("HttpService:PostAsync", args[1], args[2])
        if OFFLINE then return OFFLINE_BODY end
      elseif CAPTURE_REMOTES and realType(self) == "userdata"
        and (method == "FireServer" or method == "InvokeServer") then
        if #remoteEvents < 500 then
          local rname = "?"
          pcall_(function() rname = self:GetFullName() end)
          local entry = format("%s %s  args=%s", method, rname, describe(args[1], 40))
          tinsert(remoteEvents, entry)
          P("[locus] remote " .. entry)
        end
      end
      return oldNamecall(self, ...)
    end

    local hookFn = (realType(newcclosure) == "function") and newcclosure(hook) or hook
    namecallHooked = pcall_(hookmetamethod, game, "__namecall", hookFn)
  end

  -- ------------------------------- run target ------------------------------

  local target, terror
  if SOURCE_MODE == "url" then
    target, terror = realHttpGet(SOURCE_URL)
    if not target then
      P("[locus] FAILED to fetch SOURCE_URL: " .. tostring_(terror))
    else
      P("[locus] fetched target from url (" .. #target .. " bytes)")
    end
  else
    target = SOURCE_TEXT
  end

  local runError, runResult = nil, nil

  if realType(target) == "string" and #target > 0 then
    dumpFile("target.lua", target)
    scanSource(target, "target.lua")
    printSource("target.lua", target)
    installNamecallHook()
    local f, cerr = compileInto(target, "=locus:target")
    if not f then
      runError = "compile failed: " .. tostring_(cerr)
    else
      local ok, r = pcall_(f)
      if not ok then runError = tostring_(r) else runResult = r end
    end
  else
    if SOURCE_MODE == "text" then
      P("[locus] SOURCE_TEXT is empty - nothing to audit.")
    end
  end

  -- -------------------------------- summary --------------------------------

  local function sortedKeys()
    local keys, seen = {}, {}
    for k in pairs_(readCounts) do tinsert(keys, k) seen[k] = true end
    for k in pairs_(writeCounts) do if not seen[k] then tinsert(keys, k) end end
    table.sort(keys, function(x, y)
      local cx, cy = (readCounts[x] or 0), (readCounts[y] or 0)
      if cx ~= cy then return cx > cy end
      return tostring_(x) < tostring_(y)
    end)
    return keys
  end

  local S = {}
  local function emit(s)
    tinsert(S, s)
    P(s)
  end

  emit("")
  emit("============================== LOCUS SUMMARY ===============================")
  emit(format("host        : %s | OFFLINE = %s",
    EXEC and "Roblox executor" or "Lua CLI", tostring_(OFFLINE)))
  emit("env binding : " .. (isolationLeak
    and "PARTIAL - some chunks ran on raw globals (see residuals)"
    or "sandboxed (all stages ran through the proxy env)"))
  if EXEC then
    emit("namecall    : " .. (namecallHooked
      and "hooked (game:HttpGet/HttpGetAsync/HttpPost/HttpPostAsync, remotes, HttpService)"
      or "NOT hooked (game:* http and remote calls will NOT be seen)"))
  end
  emit("run         : " .. (runError and ("ERROR - " .. runError)
    or ((realType(target) == "string" and #target > 0) and "completed" or "no target")))
  if runResult ~= nil then emit("return      : " .. tostring_(runResult)) end
  if runError and #loadEvents == 0 and #httpEvents == 0 then
    emit("detection   : possible - target errored with zero loadstring/http activity;")
    emit("              if plain scripts run fine under LOCUS, this is the")
    emit("              protection detecting the instrumentation (a PASS for it)")
  end

  emit("")
  emit(format("-- globals: %d reads, %d writes ------------------------------------------------",
    totalReads, totalWrites))
  local keys = sortedKeys()
  if #keys == 0 then emit("  (the target touched no globals)") end
  for _, k in ipairs_(keys) do
    emit(format("  ENV[read]  %s (%d)   ENV[write] (%d)%s",
      pad(k, 34), readCounts[k] or 0, writeCounts[k] or 0,
      (writeDesc[k] and ("  = " .. writeDesc[k])) or ""))
  end

  emit("")
  emit(format("-- loadstring/load: %d call(s), full sources dumped ---------------------------",
    #loadEvents))
  for _, e in ipairs_(loadEvents) do emit("  " .. e) end
  if #loadEvents == 0 then emit("  (no loadstring/load calls observed)") end

  emit("")
  emit(format("-- http: %d call(s), TRUE url + body -----------------------------------------------",
    #httpEvents))
  for i, h in ipairs_(httpEvents) do
    emit(format("  [%d] %s %s%s", i, h.label, h.url,
      OFFLINE and "  (offline stub served)" or ""))
    if h.body ~= nil then
      if realType(h.body) == "string" then
        local preview = h.body
        if #preview > 160 then preview = sub(preview, 1, 160) .. "..." end
        emit(format("      body[%d]: %s", #h.body, preview))
      else
        emit("      body: " .. tostring_(h.body))
      end
    end
  end
  if #httpEvents == 0 then emit("  (no http activity observed)") end

  emit("")
  emit(format("-- remotes: %d call(s) (FireServer/InvokeServer) ---------------------------------",
    #remoteEvents))
  for _, e in ipairs_(remoteEvents) do emit("  " .. e) end
  if #remoteEvents == 0 then emit("  (no remote calls observed)") end

  emit("")
  emit(format("-- leak scan: %d hit(s) in dumped sources -----------------------------------------",
    #leakHits))
  for _, l in ipairs_(leakHits) do emit("  " .. l) end
  if #leakHits == 0 then
    emit("  (no urls / webhooks / hwid / fingerprint strings found in dumped sources)")
  end

  emit("")
  emit(format("-- files written to %s/ -----------------------------------------------------------", LOG_DIR))
  for _, fw in ipairs_(filesWritten) do
    emit(format("  %s  (%d bytes)%s", fw.path, fw.size, fw.ok and "" or "  [WRITE FAILED]"))
  end
  if #filesWritten == 0 then emit("  (no dumps - file API unavailable)") end

  -- full http transcript and the summary are dumped for the record too
  if #httpEvents > 0 then
    local T = {}
    for i, h in ipairs_(httpEvents) do
      tinsert(T, format("[%d] %s %s", i, h.label, h.url))
      if h.body ~= nil then
        tinsert(T, realType(h.body) == "string" and h.body or tostring_(h.body))
      end
      tinsert(T, "")
    end
    dumpFile("_http_log.txt", tconcat(T, "\n"))
  end
  dumpFile("_summary.txt", tconcat(S, "\n"))
  if #remoteEvents > 0 then
    dumpFile("_remotes.txt", tconcat(remoteEvents, "\n"))
  end

  P("")
  P("[locus] audit complete. Sources, http transcript and summary are in "
    .. LOG_DIR .. "/.")

  -- programmatic use: call runAudit(cfg) to get the full record
  return {
    logs         = S,
    files        = filesWritten,
    reads        = readCounts,
    writes       = writeCounts,
    writeDesc    = writeDesc,
    totalReads   = totalReads,
    totalWrites  = totalWrites,
    loadEvents   = loadEvents,
    httpEvents   = httpEvents,
    remoteEvents = remoteEvents,
    leakHits     = leakHits,
    offline      = OFFLINE,
    logDir       = LOG_DIR,
  }
end

-- ================================ GUI ======================================
-- Executor-only: a launcher window. Enter the target, press EXECUTE AUDIT.
-- Every buildGUI failure falls back to a default CLI-style run.

local function buildGUI(runAudit)
  local Inst  = Instance
  local EnumT = Enum
  local UDim2 = UDim2
  local Color3 = Color3
  if realType(Inst) ~= "table" or realType(EnumT) ~= "table"
    or realType(UDim2) ~= "table" or realType(Color3) ~= "table" then
    return false, "Roblox GUI datatypes not available"
  end

  local function mk(class, props, parent)
    local o = Inst.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
  end

  local C_BG    = Color3.fromRGB(8, 12, 14)
  local C_PANEL = Color3.fromRGB(15, 22, 26)
  local C_ACC   = Color3.fromRGB(112, 240, 179)
  local C_TXT   = Color3.fromRGB(226, 238, 232)
  local C_DIM   = Color3.fromRGB(130, 148, 140)
  local FONT    = EnumT.Font.Code

  local gui = mk("ScreenGui", { Name = "LOCUS_GUI", ResetOnSpawn = false, DisplayOrder = 10000 })

  -- parent: gethui() -> CoreGui -> PlayerGui
  local parented = false
  if realType(gethui) == "function" then
    local okH, hui = pcall_(gethui)
    if okH and hui then gui.Parent = hui; parented = true end
  end
  if not parented then
    parented = (pcall_(function() gui.Parent = game:GetService("CoreGui") end) == true)
  end
  if not parented then
    pcall_(function()
      local lp = game:GetService("Players").LocalPlayer
      gui.Parent = lp and (lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui"))
    end)
  end
  -- if every parent refused, say so loudly and fall back to a default run
  -- instead of building a window nobody can see (silent no-op bug, fixed v2.1.2)
  if gui.Parent == nil then
    gui:Destroy()
    return false, "could not display the GUI (gethui/CoreGui/PlayerGui all refused)"
  end

  local root = mk("Frame", {
    Name = "Root",
    Size = UDim2.new(0, 470, 0, 560),
    Position = UDim2.new(0.5, -235, 0.5, -280),
    BackgroundColor3 = C_BG,
    BorderSizePixel = 0,
    Active = true,
  }, gui)
  pcall_(function() root.Draggable = true end) -- deprecated but widely functional

  -- title bar
  local bar = mk("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C_PANEL, BorderSizePixel = 0 }, root)
  mk("TextLabel", {
    Size = UDim2.new(1, -44, 1, 0), Position = UDim2.new(0, 10, 0, 0),
    BackgroundTransparency = 1, Text = "LOCUS v2.1.2 - audit launcher",
    TextColor3 = C_ACC, Font = FONT, TextSize = 16, TextXAlignment = EnumT.TextXAlignment.Left,
  }, bar)
  mk("TextButton", {
    Size = UDim2.new(0, 34, 1, 0), Position = UDim2.new(1, -34, 0, 0),
    BackgroundColor3 = C_PANEL, Text = "X", TextColor3 = C_DIM,
    Font = FONT, TextSize = 16,
  }, bar).MouseButton1Click:Connect(function() gui:Destroy() end)

  local y = 44
  local function nextRow(h)
    local pos = UDim2.new(0, 10, 0, y)
    y = y + h + 6
    return pos, h
  end

  -- source mode toggle
  local mode = "url"
  local pos = nextRow(30)
  local modeBtn = mk("TextButton", {
    Position = pos, Size = UDim2.new(1, -20, 0, 30),
    BackgroundColor3 = C_PANEL, BorderSizePixel = 0,
    Text = "SOURCE MODE: URL", TextColor3 = C_TXT, Font = FONT, TextSize = 14,
  }, root)

  -- url box
  pos = nextRow(30)
  local urlBox = mk("TextBox", {
    Position = pos, Size = UDim2.new(1, -20, 0, 30),
    BackgroundColor3 = C_PANEL, BorderSizePixel = 0,
    Text = "", PlaceholderText = "https://raw.githubusercontent.com/.../loader",
    PlaceholderColor3 = C_DIM, TextColor3 = C_TXT, Font = FONT, TextSize = 13,
    ClearTextOnFocus = false,
  }, root)

  -- source text box (text mode)
  pos = nextRow(120)
  local srcBox = mk("TextBox", {
    Position = pos, Size = UDim2.new(1, -20, 0, 120),
    BackgroundColor3 = C_PANEL, BorderSizePixel = 0, Visible = false,
    Text = "", PlaceholderText = "paste the protected script / loader here",
    PlaceholderColor3 = C_DIM, TextColor3 = C_TXT, Font = FONT, TextSize = 13,
    TextWrapped = true, ClearTextOnFocus = false,
  }, root)

  -- toggles
  local offline = true
  pos = nextRow(28)
  local offlineBtn = mk("TextButton", {
    Position = pos, Size = UDim2.new(1, -20, 0, 28),
    BackgroundColor3 = C_PANEL, BorderSizePixel = 0,
    Text = "OFFLINE: ON  (fake responses, no real requests)",
    TextColor3 = C_ACC, Font = FONT, TextSize = 13,
  }, root)

  local printSrc = true
  pos = nextRow(28)
  local printBtn = mk("TextButton", {
    Position = pos, Size = UDim2.new(1, -20, 0, 28),
    BackgroundColor3 = C_PANEL, BorderSizePixel = 0,
    Text = "CONSOLE SOURCE PRINT: ON",
    TextColor3 = C_ACC, Font = FONT, TextSize = 13,
  }, root)

  -- execute
  pos = nextRow(34)
  local execBtn = mk("TextButton", {
    Position = pos, Size = UDim2.new(1, -20, 0, 34),
    BackgroundColor3 = C_ACC, BorderSizePixel = 0,
    Text = "EXECUTE AUDIT", TextColor3 = C_BG, Font = FONT, TextSize = 16,
  }, root)

  pos = nextRow(18)
  local status = mk("TextLabel", {
    Position = pos, Size = UDim2.new(1, -20, 0, 18),
    BackgroundTransparency = 1,
    Text = "enter the target, then press EXECUTE AUDIT",
    TextColor3 = C_DIM, Font = FONT, TextSize = 12, TextXAlignment = EnumT.TextXAlignment.Left,
  }, root)

  -- live log
  local logFrame = mk("ScrollingFrame", {
    Position = UDim2.new(0, 10, 0, y + 4), Size = UDim2.new(1, -20, 1, -(y + 18)),
    BackgroundColor3 = C_PANEL, BorderSizePixel = 0,
    ScrollBarThickness = 4, CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = EnumT.AutomaticSize.Y,
  }, root)
  local logLabel = mk("TextLabel", {
    Size = UDim2.new(1, -8, 0, 0), BackgroundTransparency = 1,
    Text = "", TextColor3 = C_TXT, Font = FONT, TextSize = 12,
    TextWrapped = true, TextXAlignment = EnumT.TextXAlignment.Left,
    TextYAlignment = EnumT.TextYAlignment.Top,
    AutomaticSize = EnumT.AutomaticSize.Y,
  }, logFrame)

  -- live log pipe: every captured line streams here as it happens
  -- (the developer console gets the same stream, uncapped)
  local buf, bufLen = {}, 0
  local function appendLog(line)
    line = tostring_(line)
    tinsert(buf, line)
    bufLen = bufLen + #line + 1
    while bufLen > 150000 and #buf > 1 do
      bufLen = bufLen - (#buf[1] + 1)
      table.remove(buf, 1)
    end
    logLabel.Text = tconcat(buf, "\n")
  end

  -- wiring
  modeBtn.MouseButton1Click:Connect(function()
    if mode == "url" then mode = "text" else mode = "url" end
    modeBtn.Text = "SOURCE MODE: " .. string.upper(mode)
    urlBox.Visible = (mode == "url")
    srcBox.Visible = (mode == "text")
  end)

  offlineBtn.MouseButton1Click:Connect(function()
    offline = not offline
    offlineBtn.Text = offline
      and "OFFLINE: ON  (fake responses, no real requests)"
      or  "OFFLINE: OFF  (REAL requests will be sent)"
    offlineBtn.TextColor3 = offline and C_ACC or Color3.fromRGB(240, 140, 120)
  end)

  printBtn.MouseButton1Click:Connect(function()
    printSrc = not printSrc
    printBtn.Text = "CONSOLE SOURCE PRINT: " .. (printSrc and "ON" or "OFF")
    printBtn.TextColor3 = printSrc and C_ACC or C_DIM
  end)

  local running = false
  execBtn.MouseButton1Click:Connect(function()
    if running then return end
    local urlText = urlBox.Text or ""
    local srcText = srcBox.Text or ""
    if mode == "url" and #urlText == 0 then
      status.Text = "enter the target URL first"
      return
    end
    if mode == "text" and #srcText == 0 then
      status.Text = "paste the target source first"
      return
    end
    running = true
    execBtn.Text = "RUNNING..."
    status.Text = "audit running - output below"
    local cfg = {
      OFFLINE       = offline,
      SOURCE_MODE   = mode,
      SOURCE_URL    = urlText,
      SOURCE_TEXT   = srcText,
      PRINT_SOURCES = printSrc,
      onLog         = appendLog,
    }
    local function job()
      local okR, rec = pcall_(runAudit, cfg)
      running = false
      execBtn.Text = "EXECUTE AUDIT"
      if okR then
        status.Text = "done - dumps in workspace/" .. ((rec and rec.logDir) or "locus") .. "/"
      else
        status.Text = "audit error: " .. tostring_(rec)
      end
    end
    local taskT = task
    if realType(taskT) == "table" and realType(taskT.spawn) == "function" then
      taskT.spawn(job)
    else
      job()
    end
  end)

  return true, "GUI up"
end

-- ================================ ENTRY ====================================

realPrint("[locus] loading LOCUS v2.1.2 ...")

if EXEC then
  local okG, gerr = pcall_(buildGUI, runAudit)
  if not okG then
    realPrint("[locus] GUI unavailable (" .. tostring_(gerr) .. ") - running a default audit instead")
    return runAudit(nil) -- GUI failed; default run
  end
  realPrint("[locus] GUI loaded - enter the target and press EXECUTE AUDIT")
  return nil -- GUI is up; the audit starts when EXECUTE AUDIT is pressed
end
return runAudit(nil) -- CLI / harness entry
