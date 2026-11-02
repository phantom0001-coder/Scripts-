-- TinyDex AI server bridge
-- Place this Script in ServerScriptService in an experience you own or are authorized to develop.
-- Configure these StringValues in ServerStorage/TinyDexAIConfig:
--   Endpoint = full HTTPS URL for an OpenAI-compatible /chat/completions endpoint
--   Model    = provider model ID
--   ApiKey   = secret API key (server-only; never place this in a LocalScript)
-- Enable Game Settings > Security > Allow HTTP Requests.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local function getOrCreateRemote()
	local existing = ReplicatedStorage:FindFirstChild("TinyDexAI")
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = "TinyDexAI"
	remote.Parent = ReplicatedStorage
	return remote
end

local remote = getOrCreateRemote()
local requestHistory = {}
local REQUESTS_PER_MINUTE = 5

local function readConfigValue(name)
	local folder = ServerStorage:FindFirstChild("TinyDexAIConfig")
	if not folder then
		return nil
	end
	local value = folder:FindFirstChild(name)
	if value and value:IsA("StringValue") then
		return value.Value
	end
	return nil
end

local function allowRequest(userId)
	local now = os.clock()
	local history = requestHistory[userId] or {}
	local recent = {}
	for _, stamp in ipairs(history) do
		if now - stamp < 60 then
			recent[#recent + 1] = stamp
		end
	end
	if #recent >= REQUESTS_PER_MINUTE then
		requestHistory[userId] = recent
		return false
	end
	recent[#recent + 1] = now
	requestHistory[userId] = recent
	return true
end

remote.OnServerInvoke = function(player, prompt, context)
	if typeof(prompt) ~= "string" or typeof(context) ~= "string" then
		return false, "Invalid request format."
	end
	if #prompt > 1200 or #context > 16000 then
		return false, "Request is too large. Shorten the question or selected object tree."
	end
	if not allowRequest(player.UserId) then
		return false, "Rate limit reached. Please wait a minute before asking again."
	end

	local endpoint = readConfigValue("Endpoint")
	local model = readConfigValue("Model")
	local apiKey = readConfigValue("ApiKey")
	if not endpoint or not model or not apiKey or endpoint == "" or model == "" or apiKey == "" then
		return false, "AI is not configured. Add Endpoint, Model, and ApiKey StringValues inside ServerStorage/TinyDexAIConfig."
	end
	if not endpoint:match("^https://") then
		return false, "The AI endpoint must use HTTPS."
	end

	local systemPrompt = table.concat({
		"You are TinyDex AI, a Roblox development assistant.",
		"Explain only the client-visible Instance metadata supplied by the user.",
		"Help with legitimate debugging, hierarchy understanding, UI, properties, attributes, and performance in experiences the user is authorized to develop.",
		"Do not claim to see server-only data or script source when it is not provided.",
		"Do not provide executor injection, exploit, anti-cheat bypass, hidden-instance access, or unauthorized game inspection instructions.",
		"Be clear when the provided metadata is insufficient. Give concise, practical explanations.",
	}, " ")

	local body = {
		model = model,
		temperature = 0.2,
		max_tokens = 800,
		messages = {
			{ role = "system", content = systemPrompt },
			{
				role = "user",
				content = "Question:\n" .. string.sub(prompt, 1, 1200)
					.. "\n\nSelected Instance metadata:\n"
					.. string.sub(context, 1, 16000),
			},
		},
	}

	local okEncode, requestBody = pcall(function()
		return HttpService:JSONEncode(body)
	end)
	if not okEncode then
		return false, "Could not encode the AI request."
	end

	local okRequest, response = pcall(function()
		return HttpService:RequestAsync({
			Url = endpoint,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["Authorization"] = "Bearer " .. apiKey,
			},
			Body = requestBody,
		})
	end)
	if not okRequest then
		return false, "AI network request failed: " .. tostring(response)
	end
	if not response.Success then
		return false, "AI provider returned HTTP " .. tostring(response.StatusCode) .. ". Check the endpoint, model, and server-side API key."
	end

	local okDecode, decoded = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	if not okDecode or typeof(decoded) ~= "table" then
		return false, "AI provider returned invalid JSON."
	end

	local choices = decoded.choices
	local first = typeof(choices) == "table" and choices[1]
	local message = first and first.message
	local answer = message and message.content
	if typeof(answer) ~= "string" or answer == "" then
		return false, "AI provider response did not contain choices[1].message.content."
	end
	return true, string.sub(answer, 1, 12000)
end
