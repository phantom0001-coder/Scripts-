--[[ TinyDEX No_pulsar (v1) — PRIMEz Studios Dex Explorer. All v22 features except the PULSAR AI and all its integrations. ]]

local plr = game:GetService("Players").LocalPlayer
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local TweenService = game:GetService("TweenService")

local gui = Instance.new("ScreenGui")
gui.Name = "TinyDex"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
gui.Enabled = true
local playerGui = plr:FindFirstChildOfClass("PlayerGui") or plr:WaitForChild("PlayerGui", 10)
assert(playerGui, "TinyDex must run from a LocalScript with access to PlayerGui")
gui.Parent = playerGui

local C = {
  bg = Color3.fromRGB(12, 12, 20), row = Color3.fromRGB(17, 17, 29), panel = Color3.fromRGB(20, 19, 34),
  txt = Color3.fromRGB(235, 232, 248), dim = Color3.fromRGB(151, 145, 177),
  hot = Color3.fromRGB(160, 83, 255), hot2 = Color3.fromRGB(105, 48, 210),
  good = Color3.fromRGB(77, 224, 143), bad = Color3.fromRGB(255, 103, 128),
  line = Color3.fromRGB(72, 48, 125),
}
local FULL = UDim2.new(0, 900, 0, 540)
local MINI = UDim2.new(0, 900, 0, 58)

local win = Instance.new("Frame")
win.Name = "PRIMEzTinyDexWindow"
win.Size = FULL
win.AnchorPoint = Vector2.new(0.5, 0.5)
win.Position = UDim2.fromScale(0.5, 0.5)
win.BackgroundColor3 = C.bg
win.BorderSizePixel = 0
win.ClipsDescendants = true
win.Parent = gui
Instance.new("UICorner", win).CornerRadius = UDim.new(0, 13)
local outerStroke = Instance.new("UIStroke", win)
outerStroke.Color = C.line
outerStroke.Thickness = 1.5
outerStroke.Transparency = 0.08
local winGradient = Instance.new("UIGradient", win)
winGradient.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 17, 36)), ColorSequenceKeypoint.new(0.55, C.bg), ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 13, 27))})
winGradient.Rotation = 25
local winScale = Instance.new("UIScale")
winScale.Name = "ResponsiveScale"
winScale.Parent = win
local function updateScale()
  local camera = workspace.CurrentCamera
  if not camera then return end
  local v = camera.ViewportSize
  winScale.Scale = math.clamp(math.min((v.X * 0.96) / 900, (v.Y * 0.92) / 540), 0.42, 1.12)
end
updateScale()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale) end

local bar = Instance.new("Frame")
bar.Name = "TopBar"
bar.Size = UDim2.new(1,0,0,36)
bar.BackgroundColor3 = Color3.fromRGB(16, 13, 29)
bar.BorderSizePixel = 0
bar.Parent = win
local barGrad = Instance.new("UIGradient", bar)
barGrad.Color = ColorSequence.new(Color3.fromRGB(36, 20, 65), Color3.fromRGB(15, 14, 27))
barGrad.Rotation = 0
local barLine = Instance.new("Frame")
barLine.Size = UDim2.new(1, -24, 0, 1)
barLine.Position = UDim2.new(0, 12, 1, -1)
barLine.BackgroundColor3 = C.line
barLine.BackgroundTransparency = 0.25
barLine.BorderSizePixel = 0
barLine.Parent = bar
local brand = Instance.new("TextLabel")
brand.Name = "Brand"
brand.Size = UDim2.new(0, 270, 1, 0)
brand.Position = UDim2.fromOffset(15, 0)
brand.BackgroundTransparency = 1
brand.Font = Enum.Font.GothamBold
brand.TextSize = 17
brand.TextXAlignment = Enum.TextXAlignment.Left
brand.TextColor3 = C.txt
brand.Text = "◆  TinyDex  "
brand.Parent = bar
local brandSub = Instance.new("TextLabel")
brandSub.Size = UDim2.new(0, 180, 0, 14)
brandSub.Position = UDim2.fromOffset(111, 18)
brandSub.BackgroundTransparency = 1
brandSub.Font = Enum.Font.Gotham
brandSub.TextSize = 9
brandSub.TextXAlignment = Enum.TextXAlignment.Left
brandSub.TextColor3 = Color3.fromRGB(177, 145, 235)
brandSub.Text = "by PRIMEz Studios  •  No PULSAR"
brandSub.Parent = bar

-- manual drag on the title bar only
do
  local dragging, ds, ws
  bar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
      dragging, ds, ws = true, i.Position, win.Position
    end
  end)
  UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
      local d = i.Position - ds
      win.Position = UDim2.new(ws.X.Scale, ws.X.Offset + d.X, ws.Y.Scale, ws.Y.Offset + d.Y)
    end
  end)
  UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
  end)
end

local function tbtn(text, w, xo, col)
  local b = Instance.new("TextButton")
  b.Size = UDim2.new(0, w, 0, 25)
  b.Position = UDim2.new(1, xo, 0, 5)
  b.BackgroundColor3 = Color3.fromRGB(39, 27, 65)
  b.BorderSizePixel = 0
  b.Font = Enum.Font.GothamSemibold
  b.TextSize = 10
  b.Text = text
  b.TextColor3 = col or Color3.fromRGB(210,210,220)
  b.Parent = bar
  Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
  local st = Instance.new("UIStroke", b)
  st.Color = C.line
  st.Transparency = 0.25
  b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.14), {BackgroundColor3 = Color3.fromRGB(72, 43, 112)}):Play() end)
  b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.18), {BackgroundColor3 = Color3.fromRGB(39, 27, 65)}):Play() end)
  return b
end
local diagBtn = tbtn("HELP", 48, -166, C.dim)
local pickBtn = tbtn("✦  PICK", 74, -112, C.hot)
local copyShown = tbtn("▣  COPY SHOWN", 116, -236)
local xb = Instance.new("TextButton")
xb.Size = UDim2.new(0, 30, 0, 28)
xb.Position = UDim2.new(1, -36, 0, 4)
xb.BackgroundColor3 = Color3.fromRGB(72, 27, 52)
xb.BackgroundTransparency = 0.1
xb.BorderSizePixel = 0
xb.Font = Enum.Font.GothamBold
xb.TextSize = 15
xb.TextColor3 = C.bad
xb.Text = "x"
xb.Parent = bar
Instance.new("UICorner", xb).CornerRadius = UDim.new(0, 7)
xb.MouseButton1Click:Connect(function() gui:Destroy() end)

local readout = Instance.new("TextLabel")
readout.Size = UDim2.new(1, -26, 0, 14)
readout.Position = UDim2.new(0, 13, 0, 39)
readout.BackgroundTransparency = 1
readout.Font = Enum.Font.Code
readout.TextSize = 11
readout.TextXAlignment = Enum.TextXAlignment.Left
readout.TextTruncate = Enum.TextTruncate.AtEnd
readout.TextColor3 = C.hot
readout.Text = ""
readout.Parent = win

local status = Instance.new("TextLabel")
status.Size = UDim2.new(0.52, -10, 0, 14)
status.Position = UDim2.new(0, 13, 1, -19)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Code
status.TextSize = 11
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextColor3 = C.good
status.Parent = win

local footer = Instance.new("TextLabel")
footer.Name = "PRIMEzFooter"
footer.Size = UDim2.new(1, -22, 0, 14)
footer.Position = UDim2.new(0, 11, 1, -17)
footer.BackgroundTransparency = 1
footer.Font = Enum.Font.Gotham
footer.TextSize = 9
footer.TextXAlignment = Enum.TextXAlignment.Right
footer.TextColor3 = Color3.fromRGB(133, 112, 170)
footer.Text = "PRIMEz Studios   •   Dex Explorer   •   v1.0 (No PULSAR)"
footer.Parent = win
local function flash(t, c)
  status.Text = tostring(t)
  status.TextColor3 = c or C.good
  task.delay(3, function() if status.Text == tostring(t) then status.Text = "" end end)
end
local function safe(label, fn, ...)
  local ok, e = pcall(fn, ...)
  if not ok then
    flash(label .. " ERR: " .. tostring(e), C.bad)
    warn("[TinyDex] " .. label .. ": " .. tostring(e))
  end
  return ok
end

-- Standard-Luau export surface: users can select and copy text manually.
local function showTextExport(title, payload)
  local overlay = Instance.new("Frame")
  overlay.Name = "TinyDexExport"
  overlay.Size = UDim2.fromScale(1, 1)
  overlay.BackgroundColor3 = Color3.new(0, 0, 0)
  overlay.BackgroundTransparency = 0.3
  overlay.ZIndex = 100
  overlay.Parent = gui

  local panel = Instance.new("Frame")
  panel.Size = UDim2.new(0.82, 0, 0.78, 0)
  panel.Position = UDim2.fromScale(0.09, 0.11)
  panel.BackgroundColor3 = C.panel
  panel.BorderSizePixel = 0
  panel.ZIndex = 101
  panel.Parent = overlay
  Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 6)

  local heading = Instance.new("TextLabel")
  heading.Size = UDim2.new(1, -80, 0, 28)
  heading.Position = UDim2.fromOffset(8, 4)
  heading.BackgroundTransparency = 1
  heading.Font = Enum.Font.GothamBold
  heading.TextSize = 12
  heading.TextXAlignment = Enum.TextXAlignment.Left
  heading.TextColor3 = C.txt
  heading.Text = title .. " — select text, then copy"
  heading.ZIndex = 102
  heading.Parent = panel

  local close = Instance.new("TextButton")
  close.Size = UDim2.fromOffset(28, 24)
  close.Position = UDim2.new(1, -34, 0, 5)
  close.BackgroundColor3 = C.row
  close.TextColor3 = C.bad
  close.Font = Enum.Font.Code
  close.Text = "X"
  close.ZIndex = 102
  close.Parent = panel
  close.MouseButton1Click:Connect(function() overlay:Destroy() end)

  local body = Instance.new("TextBox")
  body.Size = UDim2.new(1, -16, 1, -44)
  body.Position = UDim2.fromOffset(8, 36)
  body.BackgroundColor3 = C.row
  body.BorderSizePixel = 0
  body.ClearTextOnFocus = false
  body.MultiLine = true
  body.TextEditable = true
  body.TextWrapped = false
  body.TextXAlignment = Enum.TextXAlignment.Left
  body.TextYAlignment = Enum.TextYAlignment.Top
  body.Font = Enum.Font.Code
  body.TextSize = 11
  body.TextColor3 = C.txt
  body.Text = payload
  body.ZIndex = 102
  body.Parent = panel
  body:CaptureFocus()
  body.CursorPosition = 1
  body.SelectionStart = #body.Text + 1
end

local search = Instance.new("TextBox")
search.Size = UDim2.new(0, 340, 0, 27)
search.Position = UDim2.new(0, 10, 0, 59)
search.BackgroundColor3 = C.row
search.BorderSizePixel = 0
search.Font = Enum.Font.Gotham
search.TextSize = 11
search.Text = ""
search.PlaceholderText = "search name / class"
search.TextColor3 = C.txt
search.PlaceholderColor3 = C.dim
search.ClearTextOnFocus = false
search.TextXAlignment = Enum.TextXAlignment.Left
search.Parent = win
Instance.new("UIPadding", search).PaddingLeft = UDim.new(0, 5)
Instance.new("UICorner", search).CornerRadius = UDim.new(0, 7)
local searchStroke = Instance.new("UIStroke", search)
searchStroke.Color = C.line
searchStroke.Transparency = 0.4

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(0, 340, 1, -120)
list.Position = UDim2.new(0, 10, 0, 92)
list.BackgroundColor3 = C.row
list.BorderSizePixel = 0
list.ScrollBarThickness = 5
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new(0,0,0,0)
list.Parent = win
Instance.new("UICorner", list).CornerRadius = UDim.new(0, 9)
local listStroke = Instance.new("UIStroke", list)
listStroke.Color = C.line
listStroke.Transparency = 0.48
Instance.new("UIListLayout", list).SortOrder = Enum.SortOrder.LayoutOrder

local right = Instance.new("Frame")
right.Size = UDim2.new(1, -370, 1, -70)
right.Position = UDim2.new(0, 360, 0, 40)
right.BackgroundColor3 = C.panel
right.BorderSizePixel = 0
right.Parent = win
Instance.new("UICorner", right).CornerRadius = UDim.new(0, 10)
local rightStroke = Instance.new("UIStroke", right)
rightStroke.Color = C.line
rightStroke.Transparency = 0.42

local tabRow = Instance.new("Frame")
tabRow.Size = UDim2.new(1, -16, 0, 28)
tabRow.Position = UDim2.new(0, 8, 0, 7)
tabRow.BackgroundTransparency = 1
tabRow.Parent = right
local tl = Instance.new("UIListLayout")
tl.FillDirection = Enum.FillDirection.Horizontal
tl.Padding = UDim.new(0, 6)
tl.Parent = tabRow

local pageArea = Instance.new("Frame")
pageArea.Size = UDim2.new(1, -16, 1, -47)
pageArea.Position = UDim2.new(0, 8, 0, 43)
pageArea.BackgroundTransparency = 1
pageArea.Parent = right

local pages, tabBtns = {}, {}
local function gotoTab(n)
  for k, p in pairs(pages) do p.Visible = (k == n) end
  for k, b in pairs(tabBtns) do
    b.TextColor3 = (k == n) and Color3.fromRGB(255, 250, 255) or C.dim
    local target = (k == n) and Color3.fromRGB(83, 43, 139) or Color3.fromRGB(28, 24, 43)
    TweenService:Create(b, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = target}):Play()
  end
  if n == "3D" then safe("view", buildView, selected) end
end
for _, n in ipairs({ "Props", "3D", "Code", "Term" }) do
  local b = Instance.new("TextButton")
  b.Size = UDim2.new(0, 92, 0, 26)
  b.BackgroundColor3 = Color3.fromRGB(28, 24, 43)
  b.BorderSizePixel = 0
  b.Font = Enum.Font.GothamSemibold
  b.TextSize = 10
  b.Text = ({Props = "INSPECT", ["3D"] = "PREVIEW", Code = "WORKSPACE", Term = "CONSOLE"})[n]
  b.TextColor3 = C.dim
  b.Parent = tabRow
  Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
  local tabStroke = Instance.new("UIStroke", b)
  tabStroke.Color = C.line
  tabStroke.Transparency = 0.55
  b.MouseButton1Click:Connect(function() gotoTab(n) end)
  tabBtns[n] = b
  local p = Instance.new("Frame")
  p.Size = UDim2.new(1,0,1,0)
  p.BackgroundTransparency = 1
  p.Visible = false
  p.Parent = pageArea
  pages[n] = p
end

-- Lua Workspace: edit and review snippets. This client intentionally does not
-- compile/execute arbitrary text; use Roblox Studio's Script Editor for execution
-- in projects you own or are authorized to develop.
local codePage = pages["Code"]
local codeHeader = Instance.new("Frame")
codeHeader.Size = UDim2.new(1, 0, 0, 32)
codeHeader.BackgroundTransparency = 1
codeHeader.Parent = codePage
local codeTitle = Instance.new("TextLabel")
codeTitle.Size = UDim2.new(0.45, 0, 1, 0)
codeTitle.BackgroundTransparency = 1
codeTitle.Font = Enum.Font.GothamBold
codeTitle.TextSize = 12
codeTitle.TextXAlignment = Enum.TextXAlignment.Left
codeTitle.TextColor3 = C.txt
codeTitle.Text = "Lua Workspace  ·  Draft Editor"
codeTitle.Parent = codeHeader
local function editorButton(label, width, offset)
  local b = Instance.new("TextButton")
  b.Size = UDim2.fromOffset(width, 25)
  b.Position = UDim2.new(1, offset, 0, 3)
  b.BackgroundColor3 = Color3.fromRGB(48, 29, 79)
  b.BorderSizePixel = 0
  b.Font = Enum.Font.GothamSemibold
  b.TextSize = 10
  b.TextColor3 = C.txt
  b.Text = label
  b.Parent = codeHeader
  Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
  return b
end
local validateDraft = editorButton("CHECK", 62, -68)
local clearDraft = editorButton("CLEAR", 58, -132)
local editor = Instance.new("TextBox")
editor.Name = "LuaDraftEditor"
editor.Size = UDim2.new(1, 0, 1, -68)
editor.Position = UDim2.fromOffset(0, 36)
editor.BackgroundColor3 = Color3.fromRGB(12, 11, 20)
editor.BorderSizePixel = 0
editor.Font = Enum.Font.Code
editor.TextSize = 12
editor.TextColor3 = Color3.fromRGB(220, 213, 240)
editor.PlaceholderColor3 = C.dim
editor.PlaceholderText = "-- Write or paste a Luau draft here\\n-- Use CHECK for a basic delimiter review."
editor.Text = "-- PRIMEz TinyDex Lua Workspace\\n-- Draft and review Luau here.\\n-- For execution, use Roblox Studio in an experience you own.\\n"
editor.ClearTextOnFocus = false
editor.MultiLine = true
editor.TextWrapped = false
editor.TextXAlignment = Enum.TextXAlignment.Left
editor.TextYAlignment = Enum.TextYAlignment.Top
editor.Parent = codePage
Instance.new("UICorner", editor).CornerRadius = UDim.new(0, 8)
local editorStroke = Instance.new("UIStroke", editor)
editorStroke.Color = C.line
editorStroke.Transparency = 0.35
local editorPad = Instance.new("UIPadding", editor)
editorPad.PaddingTop = UDim.new(0, 9)
editorPad.PaddingLeft = UDim.new(0, 10)
editorPad.PaddingRight = UDim.new(0, 8)
local editorNote = Instance.new("TextLabel")
editorNote.Size = UDim2.new(1, 0, 0, 22)
editorNote.Position = UDim2.new(0, 0, 1, -24)
editorNote.BackgroundTransparency = 1
editorNote.Font = Enum.Font.Gotham
editorNote.TextSize = 9
editorNote.TextXAlignment = Enum.TextXAlignment.Left
editorNote.TextColor3 = C.dim
editorNote.Text = "DRAFT MODE  •  No arbitrary code execution from this client"
editorNote.Parent = codePage
local function checkDraft()
  local source = editor.Text or ""
  local stack, pairsMap = {}, { [")"] = "(", ["]"] = "[", ["}"] = "{" }
  local quote, escaped, lineComment, blockComment = nil, false, false, false
  local i = 1
  while i <= #source do
    local ch, nx = source:sub(i,i), source:sub(i+1,i+1)
    if lineComment then
      if ch == "\n" then lineComment = false end
    elseif blockComment then
      if ch == "]" and nx == "]" then blockComment = false; i = i + 1 end
    elseif quote then
      if escaped then escaped = false
      elseif ch == "\\" then escaped = true
      elseif ch == quote then quote = nil end
    elseif ch == "-" and nx == "-" then
      if source:sub(i+2,i+3) == "[[" then blockComment = true; i = i + 3 else lineComment = true; i = i + 1 end
    elseif ch == "'" or ch == '"' or ch == "`" then quote = ch
    elseif ch == "(" or ch == "[" or ch == "{" then table.insert(stack, ch)
    elseif pairsMap[ch] then
      if stack[#stack] ~= pairsMap[ch] then
        editorNote.Text = "CHECK FAILED  •  Unexpected " .. ch .. " near character " .. i
        editorNote.TextColor3 = C.bad
        return
      end
      table.remove(stack)
    end
    i = i + 1
  end
  if quote then editorNote.Text = "CHECK WARNING  •  Unclosed string literal"
  elseif blockComment then editorNote.Text = "CHECK WARNING  •  Unclosed block comment"
  elseif #stack > 0 then editorNote.Text = "CHECK WARNING  •  Unclosed delimiter " .. stack[#stack]
  else editorNote.Text = "BASIC CHECK PASSED  •  Delimiters balanced; not a full Luau compile" end
  editorNote.TextColor3 = (quote or blockComment or #stack > 0) and C.bad or C.good
end
validateDraft.MouseButton1Click:Connect(checkDraft)
clearDraft.MouseButton1Click:Connect(function()
  editor.Text = ""
  editorNote.Text = "Draft cleared."
  editorNote.TextColor3 = C.dim
end)

local selected, expanded, vis = nil, {}, {}
local propList, vp -- forward declarations used by diagnostics
local selBox = Instance.new("SelectionBox")
selBox.LineThickness = 0.03
selBox.Color3 = Color3.fromRGB(0, 170, 255)
selBox.Visible = false
selBox.Parent = workspace

local function pathOf(i)
  local ok, p = pcall(function() return i:GetFullName() end)
  return ok and p or "?"
end

-- Roblox Instances are userdata-like objects: `next(instance)` does not
-- enumerate their properties. Probe a safe, broad list and keep readable ones.
local PROPERTY_CANDIDATES = {
  "Name", "ClassName", "Parent", "Archivable", "AbsolutePosition", "AbsoluteSize",
  "AnchorPoint", "AutomaticSize", "BackgroundColor3", "BackgroundTransparency",
  "BorderColor3", "BorderSizePixel", "CanvasPosition", "CanvasSize", "ClipsDescendants",
  "Color", "CFrame", "CastShadow", "CanCollide", "CanQuery", "CanTouch", "Transparency",
  "BrickColor", "Material", "Reflectance", "Size", "Position", "Orientation", "PivotOffset",
  "Shape", "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface",
  "BackSurface", "AssemblyLinearVelocity", "AssemblyAngularVelocity", "Mass",
  "Massless", "Anchored", "Velocity", "RotVelocity", "CollisionGroup",
  "Text", "TextColor3", "TextTransparency", "TextSize", "TextScaled", "TextWrapped",
  "TextXAlignment", "TextYAlignment", "Font", "FontFace", "RichText", "PlaceholderText",
  "Image", "ImageColor3", "ImageTransparency", "ImageRectOffset", "ImageRectSize",
  "Visible", "Enabled", "Active", "Selectable", "Modal", "DisplayOrder", "ResetOnSpawn",
  "ZIndex", "LayoutOrder", "Rotation", "ScaleType", "SliceCenter", "TileSize",
  "Value", "MaxValue", "MinValue", "Disabled", "Looped", "Playing", "TimePosition",
  "PlaybackSpeed", "Volume", "SoundId", "AnimationId", "WalkSpeed", "JumpPower",
  "JumpHeight", "HipHeight", "Health", "MaxHealth", "Team", "Neutral", "UserId",
  "AccountAge", "DisplayName", "RigType", "PrimaryPart", "WorldPivot", "ModelStreamingMode",
  "CurrentCamera", "FieldOfView", "CameraType", "CameraSubject", "Focus", "Ambient",
  "LightColor", "LightDirection", "Brightness", "ClockTime", "GeographicLatitude",
  "FogColor", "FogEnd", "FogStart", "GlobalShadows", "OutdoorAmbient", "TimeOfDay",
  "PlaybackState", "SoundGroup", "EmitterSize", "RollOffMaxDistance", "RollOffMinDistance",
  "Rate", "Lifetime", "Speed", "SpreadAngle", "Enabled", "Texture", "TextureID",
  "MeshId", "TextureID", "Animation", "PrimaryAxis", "SecondaryAxis", "Target",
  "TargetFilter", "CurrentDistance", "Enabled", "Style", "Color3", "TextButton",
}
local READ_ONLY_PROPERTIES = {
  ClassName = true, Parent = true, AbsolutePosition = true, AbsoluteSize = true,
  AssemblyLinearVelocity = true, AssemblyAngularVelocity = true, Mass = true,
  PlaybackState = true, UserId = true, AccountAge = true, DisplayName = true,
  CurrentDistance = true,
}
local function readableProperties(inst)
  local names, seen = {}, {}
  local function addName(name)
    if type(name) ~= "string" or seen[name] then return end
    seen[name] = true
    local ok = pcall(function() return inst[name] end)
    if ok then names[#names + 1] = name end
  end

  -- Standard Roblox Luau does not expose universal property enumeration.
  -- Use the curated, readable property list below; no executor APIs are probed.
  -- Standard Roblox fallback: enumerate a broad, safe list of common
  -- properties. No property is assigned during copying.
  for _, name in ipairs(PROPERTY_CANDIDATES) do addName(name) end
  table.sort(names)
  return names
end

local function valueToText(value)
  local kind = typeof(value)
  if kind == "Instance" then return pathOf(value) end
  if kind == "string" then return string.format("%q", value) end
  if kind == "table" then
    local ok, encoded = pcall(function() return HttpService:JSONEncode(value) end)
    if ok then return encoded end
  end
  return tostring(value)
end


local function dump(inst, out)
  if not inst or not inst.Parent and inst ~= game then return end
  out[#out+1] = "=================================================="
  out[#out+1] = "PATH: " .. pathOf(inst)
  out[#out+1] = "CLASS: " .. inst.ClassName
  out[#out+1] = "NAME: " .. inst.Name
  out[#out+1] = "-- PROPERTIES"
  local names = readableProperties(inst)
  for _, k in ipairs(names) do
    local ok, v = pcall(function() return inst[k] end)
    if ok then out[#out+1] = k .. " = " .. valueToText(v) end
  end

  local oka, at = pcall(function() return inst:GetAttributes() end)
  if oka and at then
    out[#out+1] = "-- ATTRIBUTES"
    local keys = {}
    for k in pairs(at) do keys[#keys + 1] = k end
    table.sort(keys)
    if #keys == 0 then out[#out+1] = "(none)" end
    for _, k in ipairs(keys) do out[#out+1] = k .. " = " .. valueToText(at[k]) end
  end

  local okTags, tags = pcall(function()
    return game:GetService("CollectionService"):GetTags(inst)
  end)
  if okTags then
    table.sort(tags)
    out[#out+1] = "-- TAGS"
    out[#out+1] = #tags > 0 and table.concat(tags, ", ") or "(none)"
  end
  out[#out+1] = ""
end

local copying = false
local function copy(insts, note)
  if copying then return flash("copy already running", C.bad) end
  copying = true
  task.spawn(function()
    -- Export each supplied Explorer row AND every descendant beneath it.
    -- Keep a running size counter (rather than rescanning the output on each
    -- object) and yield periodically so large trees do not monopolize a frame.
    local MAX_CHARS = 250000
    local out = {
      "Tiny Dex — RECURSIVE TREE EXPORT",
      "Roots supplied by Explorer: " .. tostring(#insts),
      "Every reachable descendant is traversed recursively; duplicate instances are emitted once.",
      "Each object includes its path, class, name, readable properties, attributes, and CollectionService tags where available.",
      "Property limitation: standard Roblox Luau has no universal property-enumeration API; a curated built-in property list is used.",
      "Export safety limit: approximately 250,000 characters. If reached, the export reports truncation instead of freezing the client.",
      "",
    }
    local size = 0
    for _, line in ipairs(out) do size = size + #line + 1 end
    local stack, seen = {}, {}
    -- Reverse insertion preserves the Explorer's usual forward order in DFS.
    for i = #insts, 1, -1 do
      if insts[i] then stack[#stack + 1] = insts[i] end
    end
    local count, stopped, failed = 0, false, 0
    while #stack > 0 do
      local inst = table.remove(stack)
      if inst and not seen[inst] then
        seen[inst] = true
        local objectOut = {}
        local ok = pcall(dump, inst, objectOut)
        if ok then
          local chunk = table.concat(objectOut, "\n") .. "\n"
          if size + #chunk > MAX_CHARS then
            out[#out + 1] = "[TRUNCATED SAFELY] Clipboard size limit reached. Collapse/filter the Explorer and copy smaller subtrees to export the remainder."
            stopped = true
            break
          end
          for _, line in ipairs(objectOut) do out[#out + 1] = line end
          size = size + #chunk
          count = count + 1
        else
          failed = failed + 1
          out[#out + 1] = "[ERROR] Could not dump an object at " .. pathOf(inst)
        end

        -- Add every child regardless of whether its Explorer row is expanded.
        local children = {}
        pcall(function()
          for _, child in ipairs(inst:GetChildren()) do
            children[#children + 1] = child
          end
        end)
        for i = #children, 1, -1 do
          if not seen[children[i]] then stack[#stack + 1] = children[i] end
        end

        if count % 2 == 0 then task.wait() end
      end
    end
    if failed > 0 then out[#out + 1] = "Objects that could not be fully read: " .. tostring(failed) end
    local payload = table.concat(out, "\n")
    copying = false
    showTextExport(note or "Tree export", payload)
    flash("export ready · " .. count .. " objects · " .. #payload .. " chars" .. (stopped and " · safely truncated" or ""), C.good)
  end)
end

local refreshProps, buildView, render
local function selectInst(i)
  selected = i
  safe("selbox", function()
    selBox.Adornee = i
    selBox.Visible = i ~= nil and i:IsA("BasePart")
  end)
  safe("props", refreshProps)
  if pages["3D"] and pages["3D"].Visible then
    safe("view", buildView, i)
  end
end

function render()
  for _, c in ipairs(list:GetChildren()) do
    if c:IsA("TextButton") then c:Destroy() end
  end
  vis = {}
  local q = search.Text:lower()
  local matchBelowCache = {}

  local function matches(inst)
    return q == ""
      or inst.Name:lower():find(q, 1, true) ~= nil
      or inst.ClassName:lower():find(q, 1, true) ~= nil
  end

  local function getChildren(inst)
    local kids = {}
    local ok = pcall(function()
      for _, child in ipairs(inst:GetChildren()) do
        kids[#kids + 1] = child
      end
    end)
    if not ok then return {} end
    table.sort(kids, function(a, b)
      local an, bn = a.Name:lower(), b.Name:lower()
      if an == bn then return a.ClassName < b.ClassName end
      return an < bn
    end)
    return kids
  end

  local function hasMatchBelow(inst)
    if matchBelowCache[inst] ~= nil then
      return matchBelowCache[inst]
    end
    local found = false
    for _, child in ipairs(getChildren(inst)) do
      if matches(child) or hasMatchBelow(child) then
        found = true
        break
      end
    end
    matchBelowCache[inst] = found
    return found
  end

  local function makeLine(parent, x, y, h, w)
    local line = Instance.new("Frame")
    line.BorderSizePixel = 0
    line.BackgroundColor3 = C.good
    line.BackgroundTransparency = 0.08
    line.Position = UDim2.fromOffset(x, y)
    line.Size = UDim2.fromOffset(w or 1, h)
    line.Parent = parent
    return line
  end

  -- Each visible row is a node in a real tree. Ancestor guide lines are
  -- repeated down the rows while that ancestor has following siblings.
  local function walk(parentInst, depth, ancestorContinues)
    local sourceKids = getChildren(parentInst)
    local shownKids = {}
    for _, child in ipairs(sourceKids) do
      if q == "" or matches(child) or hasMatchBelow(child) then
        shownKids[#shownKids + 1] = child
      end
    end

    for index, child in ipairs(shownKids) do
      local isLast = index == #shownKids
      local childKids = getChildren(child)
      local childCount = #childKids
      local hasChildren = childCount > 0
      local isOpen = expanded[child] == true or q ~= ""
      local rowHeight = 21

      vis[#vis + 1] = child
      local row = Instance.new("TextButton")
      row.Name = "TreeRow_" .. child.Name
      row.Size = UDim2.new(1, 0, 0, rowHeight)
      row.BackgroundTransparency = (selected == child) and 0 or 1
      row.BackgroundColor3 = Color3.fromRGB(66, 39, 112)
      row.AutoButtonColor = false
      row.Text = ""
      row.Parent = list

      -- Carry vertical guides from open parent branches through this row.
      for level, continues in ipairs(ancestorContinues) do
        if continues then
          makeLine(row, (level - 1) * 14 + 6, 0, rowHeight, 1)
        end
      end

      local branchX = depth * 14 + 6
      makeLine(row, branchX, 0, 9, 1)
      makeLine(row, branchX, 8, 1, 9)
      if not isLast then
        makeLine(row, branchX, 9, 9, 1)
      end

      local arrow = Instance.new("TextButton")
      arrow.Size = UDim2.fromOffset(13, 16)
      arrow.Position = UDim2.fromOffset(depth * 14 + 14, 1)
      arrow.BackgroundTransparency = 1
      arrow.Font = Enum.Font.Code
      arrow.TextSize = 12
      arrow.TextColor3 = hasChildren and C.hot or C.dim
      arrow.Text = hasChildren and (isOpen and "v" or ">") or " "
      arrow.AutoButtonColor = false
      arrow.Parent = row
      if hasChildren then
        arrow.MouseButton1Click:Connect(function()
          expanded[child] = not expanded[child]
          render()
        end)
      end

      local icon = Instance.new("TextLabel")
      icon.Size = UDim2.fromOffset(14, 16)
      icon.Position = UDim2.fromOffset(depth * 14 + 28, 1)
      icon.BackgroundTransparency = 1
      icon.Font = Enum.Font.Code
      icon.TextSize = 11
      icon.TextColor3 = hasChildren and C.hot or C.dim
      icon.Text = hasChildren and (isOpen and "▾" or "▸") or "·"
      icon.Parent = row

      local name = Instance.new("TextLabel")
      name.Size = UDim2.new(1, -(depth * 14 + 46), 1, 0)
      name.Position = UDim2.fromOffset(depth * 14 + 44, 0)
      name.BackgroundTransparency = 1
      name.Font = Enum.Font.Code
      name.TextSize = 11
      name.TextXAlignment = Enum.TextXAlignment.Left
      name.TextTruncate = Enum.TextTruncate.AtEnd
      name.TextColor3 = (selected == child) and Color3.new(1, 1, 1) or C.txt
      local countText = hasChildren
        and ("  (" .. tostring(childCount) .. (childCount == 1 and " item)" or " items)"))
        or ""
      name.Text = child.Name .. countText .. "  [" .. child.ClassName .. "]"
      if q ~= "" and not matches(child) then
        name.TextColor3 = C.dim
      end
      name.Parent = row

      local lastClick = 0
      row.MouseButton1Click:Connect(function()
        local now = os.clock()
        if now - lastClick < 0.30 and hasChildren then
          expanded[child] = not expanded[child]
          render()
          lastClick = 0
          return
        end
        lastClick = now
        selectInst(child)
      end)
      row.MouseButton2Click:Connect(function()
        showTextExport("Instance path", pathOf(child))
      end)

      if hasChildren and isOpen then
        local nextAncestors = {}
        for level, continues in ipairs(ancestorContinues) do
          nextAncestors[level] = continues
        end
        -- Keep a green guide running down every expanded folder branch.
        nextAncestors[#nextAncestors + 1] = true
        walk(child, depth + 1, nextAncestors)
      end
    end
  end

  walk(game, 0, {})
  flash(#vis .. " shown", C.dim)
end
search:GetPropertyChangedSignal("Text"):Connect(function() safe("render", render) end)

local function revealNode(inst)
  local chain = {}
  local p = inst
  while p and p ~= game do chain[#chain+1] = p; p = p.Parent end
  for _, n in ipairs(chain) do expanded[n] = true end
  render()
  for i, c in ipairs(vis) do
    if c == inst then list.CanvasPosition = Vector2.new(0, math.max(0, i * 21 - 60)); break end
  end
end

-- World picker: supports mouse and touch through one raycast path.
local mouse = plr:GetMouse()
local GuiService = game:GetService("GuiService")
local pickOn, pickCon, pickInputCon
local function setCollapsed(v)
  win.Size = v and MINI or FULL
  search.Visible = not v
  list.Visible = not v
  right.Visible = not v
  status.Visible = not v
  footer.Visible = not v
end
local function hover(t)
  if not t then readout.Text = ""; return end
  selBox.Adornee = t:IsA("BasePart") and t or nil
  selBox.Visible = t:IsA("BasePart")
  readout.Text = t.ClassName .. " · " .. pathOf(t)
    .. (t:IsA("BasePart") and ("  @ " .. tostring(t.Position)) or "")
end
local function stopPick()
  pickOn = false
  pickBtn.BackgroundColor3 = Color3.fromRGB(39, 27, 65)
  if pickCon then pickCon:Disconnect(); pickCon = nil end
  if pickInputCon then pickInputCon:Disconnect(); pickInputCon = nil end
  setCollapsed(false)
  readout.Text = ""
  selBox.Adornee = selected and selected:IsA("BasePart") and selected or nil
  selBox.Visible = selected ~= nil and selected:IsA("BasePart")
end
local function promotePick(hit)
  -- Selecting a part inside a model previews the complete model when possible.
  local node = hit
  local parent = hit.Parent
  while parent and parent ~= workspace do
    if parent:IsA("Model") then node = parent; break end
    parent = parent.Parent
  end
  return node
end
local function pickAt(screenPos, isTouch)
  if not pickOn then return end
  local cam = workspace.CurrentCamera
  if not cam then return end
  local pos = screenPos
  local inset = GuiService:GetGuiInset()
  pos = Vector2.new(pos.X - inset.X, pos.Y - inset.Y)
  local ray = cam:ViewportPointToRay(pos.X, pos.Y)
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Exclude
  local excluded = {}
  if plr.Character then excluded[#excluded + 1] = plr.Character end
  params.FilterDescendantsInstances = excluded
  params.IgnoreWater = false
  local hit = workspace:Raycast(ray.Origin, ray.Direction * 3000, params)
  if not hit or not hit.Instance then return end
  local object = promotePick(hit.Instance)
  hover(object)
  selectInst(object)
  revealNode(object)
  -- Switch to the preview tab so the picked object's 3D view is ready on exit.
  gotoTab("3D")
  -- Keep PICK active for repeated picks; user can tap PICK again to exit.
  if isTouch then flash("picked " .. object.Name, C.good) end
end
local function startPick()
  pickOn = true
  pickBtn.BackgroundColor3 = C.hot
  setCollapsed(true)
  pickCon = UIS.InputBegan:Connect(function(input, processed)
    if not pickOn or processed then return end
    if input.UserInputType == Enum.UserInputType.Touch then
      pickAt(input.Position, true)
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
      pickAt(UIS:GetMouseLocation(), false)
    end
  end)
end
pickBtn.MouseButton1Click:Connect(function()
  if pickOn then stopPick() else startPick() end
end)

copyShown.MouseButton1Click:Connect(function()
  -- Copy every Explorer row plus every descendant beneath those rows,
  -- including children hidden by collapsed folders/tree branches.
  if #vis == 0 then return flash("nothing shown", Color3.fromRGB(230,180,110)) end
  copy(vis, "COPY TREE complete")
end)

local function runDiagnostics()
  local rows, props, vpKids, camOk = #vis, 0, 0, false
  pcall(function() for _, c in ipairs(propList:GetChildren()) do if c:IsA("TextButton") then props = props + 1 end end end)
  pcall(function() vpKids = #vp:GetChildren() end)
  pcall(function() camOk = vp.CurrentCamera ~= nil end)
  local sel = selected and (selected.ClassName .. " " .. pathOf(selected)) or "none"
  local msg = ("rows=%d props=%d sel=%s vpKids=%d cam=%s mouse=%s")
    :format(rows, props, sel, vpKids, tostring(camOk), tostring(mouse ~= nil))
  flash(msg, C.dim)
  print("[TinyDex DIAG] " .. msg)
end

-- props
local propsPage = pages["Props"]
local pSearch = Instance.new("TextBox")
pSearch.Size = UDim2.new(1, 0, 0, 18)
pSearch.BackgroundColor3 = Color3.fromRGB(28,28,34)
pSearch.BorderSizePixel = 0
pSearch.Font = Enum.Font.Code
pSearch.TextSize = 11
pSearch.Text = ""
pSearch.PlaceholderText = "filter"
pSearch.TextColor3 = C.txt
pSearch.PlaceholderColor3 = C.dim
pSearch.ClearTextOnFocus = false
pSearch.TextXAlignment = Enum.TextXAlignment.Left
pSearch.Parent = propsPage
Instance.new("UIPadding", pSearch).PaddingLeft = UDim.new(0, 5)

propList = Instance.new("ScrollingFrame")
propList.Size = UDim2.new(1, 0, 1, -22)
propList.Position = UDim2.new(0, 0, 0, 22)
propList.BackgroundColor3 = C.row
propList.BorderSizePixel = 0
propList.ScrollBarThickness = 5
propList.AutomaticCanvasSize = Enum.AutomaticSize.Y
propList.CanvasSize = UDim2.new(0,0,0,0)
propList.Parent = propsPage
Instance.new("UIListLayout", propList).SortOrder = Enum.SortOrder.LayoutOrder

local function textEditable(t)
  return t ~= "bool" and t ~= "Enum" and t ~= "BrickColor" and t ~= "Instance"
end
local propConnections = {}
local function setProp(prop, val)
  local target = prop.target
  if prop.ro or not target then return end
  local ok, err = pcall(function()
    if prop.attr then target:SetAttribute(prop.name, val) else target[prop.name] = val end
  end)
  flash(ok and ("set " .. prop.name) or ("failed " .. prop.name .. ": " .. tostring(err)), ok and C.good or C.bad)
end
local function modal(w, text, done)
  local m = Instance.new("TextBox")
  m.Size = UDim2.new(0, w, 0, 22)
  m.Position = UDim2.new(0.5, -w/2, 0.5, -11)
  m.BackgroundColor3 = Color3.fromRGB(34,34,42)
  m.BorderSizePixel = 0
  m.Font = Enum.Font.Code
  m.TextSize = 11
  m.Text = text or ""
  m.TextColor3 = Color3.fromRGB(225,225,235)
  m.ClearTextOnFocus = false
  m.ZIndex = 70
  m.Parent = gui
  Instance.new("UICorner", m).CornerRadius = UDim.new(0, 4)
  m:CaptureFocus()
  m.FocusLost:Connect(function(enter)
    if enter then pcall(done, m.Text) end
    m:Destroy()
  end)
end
local function enumPick(enum, done)
  local m = Instance.new("ScrollingFrame")
  m.Size = UDim2.new(0, 220, 0, 240)
  m.Position = UDim2.new(0.5, -110, 0.5, -120)
  m.BackgroundColor3 = Color3.fromRGB(34,34,42)
  m.BorderSizePixel = 0
  m.ScrollBarThickness = 5
  m.ZIndex = 70
  m.Parent = gui
  Instance.new("UICorner", m).CornerRadius = UDim.new(0, 5)
  Instance.new("UIListLayout", m).SortOrder = Enum.SortOrder.LayoutOrder
  for _, item in ipairs(enum:GetEnumItems()) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 17)
    b.BackgroundTransparency = 1
    b.AutoButtonColor = false
    b.Font = Enum.Font.Code
    b.TextSize = 11
    b.Text = "  " .. item.Name
    b.TextColor3 = C.txt
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Parent = m
    b.MouseButton1Click:Connect(function() pcall(done, item); m:Destroy() end)
  end
end

function refreshProps()
  for _, connection in ipairs(propConnections) do
    pcall(function() connection:Disconnect() end)
  end
  table.clear(propConnections)
  for _, c in ipairs(propList:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
  if not selected then
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, 26)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Gotham
    l.TextSize = 11
    l.Text = "select something"
    l.TextColor3 = C.dim
    l.Parent = propList
    return
  end
  local q = pSearch.Text:lower()
  local target = selected
  local names = readableProperties(target)

  local function addRow(name, value, isAttr)
    local t = typeof(value)
    if t == "RBXScriptSignal" or t == "function" then return end
    local prop = { name = name, attr = isAttr, target = target }
    -- Never probe writability by assigning the current value: setters can
    -- fire events or have side effects. Attempt the real edit only on request.
    prop.ro = (not isAttr and READ_ONLY_PROPERTIES[name] == true) or t == "Instance"

    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 17)
    row.BackgroundTransparency = 1
    row.AutoButtonColor = false
    row.Text = ""
    row.Parent = propList

    local nl = Instance.new("TextLabel")
    nl.Size = UDim2.new(0.45, 0, 1, 0)
    nl.BackgroundTransparency = 1
    nl.Font = Enum.Font.Code
    nl.TextSize = 11
    nl.Text = (isAttr and "@" or "") .. name
    nl.TextColor3 = prop.ro and C.dim or Color3.fromRGB(140,180,255)
    nl.TextXAlignment = Enum.TextXAlignment.Left
    nl.TextTruncate = Enum.TextTruncate.AtEnd
    nl.Parent = row

    local vf = Instance.new("Frame")
    vf.Size = UDim2.new(0.55, 0, 1, 0)
    vf.Position = UDim2.new(0.45, 0, 0, 0)
    vf.BackgroundTransparency = 1
    vf.Parent = row

    if t == "boolean" then
      local cb = Instance.new("TextButton")
      cb.Size = UDim2.new(0, 16, 0, 16)
      cb.BackgroundTransparency = 1
      cb.Font = Enum.Font.Code
      cb.TextSize = 13
      cb.Text = value and "☑" or "☐"
      cb.TextColor3 = prop.ro and C.dim or C.txt
      cb.Parent = vf
      cb.MouseButton1Click:Connect(function()
        if prop.ro then return end
        value = not value
        cb.Text = value and "☑" or "☐"
        setProp(prop, value)
      end)
    elseif t == "Color3" then
      local sw = Instance.new("TextButton")
      sw.Size = UDim2.new(0, 46, 0, 14)
      sw.BackgroundColor3 = value
      sw.BorderSizePixel = 0
      sw.Text = ""
      sw.Parent = vf
      Instance.new("UICorner", sw).CornerRadius = UDim.new(0, 2)
      local l = Instance.new("TextLabel")
      l.Size = UDim2.new(1, -50, 1, 0)
      l.Position = UDim2.new(0, 50, 0, 0)
      l.BackgroundTransparency = 1
      l.Font = Enum.Font.Code
      l.TextSize = 11
      l.TextColor3 = prop.ro and C.dim or C.txt
      l.TextXAlignment = Enum.TextXAlignment.Left
      l.Text = string.format("%d,%d,%d", math.floor(value.R*255 + 0.5), math.floor(value.G*255 + 0.5), math.floor(value.B*255 + 0.5))
      l.Parent = vf
      sw.MouseButton1Click:Connect(function()
        if prop.ro then return end
        modal(200, tostring(value), function(txt)
          local r, g, b = txt:match("^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
          if r and g and b then
            local v = Color3.fromRGB(
              math.clamp(tonumber(r), 0, 255),
              math.clamp(tonumber(g), 0, 255),
              math.clamp(tonumber(b), 0, 255)
            )
            sw.BackgroundColor3 = v
            setProp(prop, v)
          else
            flash("enter RGB as 120,140,255", C.bad)
          end
        end)
      end)
    elseif t == "EnumItem" then
      local b = Instance.new("TextButton")
      b.Size = UDim2.new(1, 0, 1, 0)
      b.BackgroundTransparency = 1
      b.Font = Enum.Font.Code
      b.TextSize = 11
      b.Text = value.Name
      b.TextColor3 = prop.ro and C.dim or C.txt
      b.TextXAlignment = Enum.TextXAlignment.Left
      b.Parent = vf
      b.MouseButton1Click:Connect(function()
        if prop.ro then return end
        enumPick(value.EnumType, function(item) b.Text = item.Name; setProp(prop, item) end)
      end)
    else
      local l = Instance.new("TextLabel")
      l.Size = UDim2.new(1, 0, 1, 0)
      l.BackgroundTransparency = 1
      l.Font = Enum.Font.Code
      l.TextSize = 11
      l.Text = (typeof(value) == "Instance") and pathOf(value) or tostring(value)
      l.TextColor3 = prop.ro and C.dim or C.txt
      l.TextXAlignment = Enum.TextXAlignment.Left
      l.TextTruncate = Enum.TextTruncate.AtEnd
      l.Parent = vf
      if textEditable(t) and not prop.ro then
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 1, 0)
        b.BackgroundTransparency = 1
        b.Text = ""
        b.Parent = vf
        b.MouseButton1Click:Connect(function()
          modal(240, tostring(value), function(txt)
            local ok, v = pcall(function()
              if t == "number" then
                local n = tonumber(txt)
                assert(n ~= nil, "enter a valid number")
                return n
              elseif t == "string" then
                return txt
              elseif t == "Vector3" then
                local x, y, z = txt:match("^%s*([^,]+),%s*([^,]+),%s*([^,]+)%s*$")
                assert(x and y and z, "use x,y,z")
                return Vector3.new(assert(tonumber(x)), assert(tonumber(y)), assert(tonumber(z)))
              elseif t == "Vector2" then
                local x, y = txt:match("^%s*([^,]+),%s*([^,]+)%s*$")
                assert(x and y, "use x,y")
                return Vector2.new(assert(tonumber(x)), assert(tonumber(y)))
              else
                error("editing this value type is not supported")
              end
            end)
            if ok then
              setProp(prop, v)
              l.Text = tostring(v)
            else
              flash(tostring(v), C.bad)
            end
          end)
        end)
      end
      if not isAttr then
        pcall(function()
          local connection = target:GetPropertyChangedSignal(name):Connect(function()
            local ok, nv = pcall(function() return target[name] end)
            if ok then l.Text = (typeof(nv) == "Instance") and pathOf(nv) or tostring(nv) end
          end)
          propConnections[#propConnections + 1] = connection
        end)
      end
    end
    if isAttr then
      row.MouseButton2Click:Connect(function()
        pcall(function() target:SetAttribute(name, nil) end)
        refreshProps()
      end)
    end
  end

  for _, k in ipairs(names) do
    if q == "" or k:lower():find(q, 1, true) then
      local ok, v = pcall(function() return selected[k] end)
      if ok then addRow(k, v, false) end
    end
  end
  local oka, at = pcall(function() return selected:GetAttributes() end)
  if oka and at then
    for k, v in next, at do
      if q == "" or k:lower():find(q, 1, true) then addRow(k, v, true) end
    end
  end
end
pSearch:GetPropertyChangedSignal("Text"):Connect(function() safe("props", refreshProps) end)

-- 3D preview: lightweight part-only clone, bounded model size, lazy rendering.
local viewPage = pages["3D"]
vp = Instance.new("ViewportFrame")
vp.Size = UDim2.new(1, 0, 1, -14)
vp.BackgroundColor3 = Color3.fromRGB(12, 13, 23)
vp.BorderSizePixel = 0
vp.Ambient = Color3.fromRGB(140,140,150)
vp.LightColor = Color3.new(1,1,1)
vp.LightDirection = Vector3.new(-0.5, -0.8, -0.6)
vp.Parent = viewPage
Instance.new("UICorner", vp).CornerRadius = UDim.new(0, 9)
local vpStroke = Instance.new("UIStroke", vp)
vpStroke.Color = C.line
vpStroke.Transparency = 0.45

diagBtn.MouseButton1Click:Connect(runDiagnostics)

local pathLbl = Instance.new("TextLabel")
pathLbl.Size = UDim2.new(1, 0, 0, 14)
pathLbl.Position = UDim2.new(0, 0, 1, 0)
pathLbl.BackgroundTransparency = 1
pathLbl.Font = Enum.Font.Code
pathLbl.TextSize = 10
pathLbl.TextTransparency = 0.15
pathLbl.TextXAlignment = Enum.TextXAlignment.Left
pathLbl.TextTruncate = Enum.TextTruncate.AtEnd
pathLbl.Text = "Choose a Part or Model"
pathLbl.Parent = viewPage

local rotationX, rotationY, distance = 0.25, 0.6, 10
local dragging, hovering, zoomMul = false, false, 2
local lastpos = Vector2.zero
local vcam, vmodel
local previewCenter = Vector3.zero
local previewSize = Vector3.new(4, 4, 4)
local previewPartCount = 0
local MAX_PREVIEW_PARTS = 120

local function stopView()
  vcam = nil
  vmodel = nil
  vp.CurrentCamera = nil
  for _, child in ipairs(vp:GetChildren()) do child:Destroy() end
end

local function stripUnsafeChildren(root)
  for _, child in ipairs(root:GetDescendants()) do
    if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript")
      or child:IsA("Constraint") or child:IsA("JointInstance") then
      pcall(function() child:Destroy() end)
    end
  end
end

function buildView(item)
  stopView()
  rotationX, rotationY = 0.25, 0.6
  if not item then
    pathLbl.Text = "Choose a Part or Model"
    return
  end
  if not (item:IsA("BasePart") or item:IsA("Model")) then
    pathLbl.Text = "No 3D preview for " .. item.ClassName
    return
  end

  local sourceParts = {}
  if item:IsA("BasePart") then
    sourceParts[1] = item
  else
    for _, child in ipairs(item:GetDescendants()) do
      if child:IsA("BasePart") then
        sourceParts[#sourceParts + 1] = child
        if #sourceParts >= MAX_PREVIEW_PARTS then break end
      end
    end
  end
  if #sourceParts == 0 then
    pathLbl.Text = "No BaseParts found in this object"
    return
  end

  local boundsOK, boundsCF, boundsSize = pcall(function()
    if item:IsA("Model") then return item:GetBoundingBox() end
    return item.CFrame, item.Size
  end)
  if boundsOK then
    previewCenter = boundsCF.Position
    previewSize = boundsSize
  else
    previewCenter = sourceParts[1].Position
    previewSize = sourceParts[1].Size
  end

  vmodel = Instance.new("Model")
  vmodel.Name = "TinyDexPreview"
  vmodel.Parent = vp
  local firstPart
  for _, source in ipairs(sourceParts) do
    local ok, clone = pcall(function() return source:Clone() end)
    if ok and clone and clone:IsA("BasePart") then
      stripUnsafeChildren(clone)
      clone.Anchored = true
      clone.CanCollide = false
      clone.CanTouch = false
      clone.CanQuery = false
      clone.CFrame = CFrame.new(-previewCenter) * source.CFrame
      clone.Parent = vmodel
      firstPart = firstPart or clone
      previewPartCount += 1
    end
  end
  if not firstPart then
    stopView()
    pathLbl.Text = "Preview unavailable (object cannot be cloned)"
    return
  end
  vmodel.PrimaryPart = firstPart
  local maxAxis = math.max(previewSize.X, previewSize.Y, previewSize.Z)
  distance = math.max(4, maxAxis * 1.8)
  vcam = Instance.new("Camera")
  vcam.FieldOfView = 55
  vcam.Parent = vp
  vp.CurrentCamera = vcam
  local suffix = (#sourceParts >= MAX_PREVIEW_PARTS) and (" · capped at " .. MAX_PREVIEW_PARTS .. " parts") or (" · " .. #sourceParts .. " parts")
  pathLbl.Text = "3D: " .. pathOf(item) .. suffix
end

vp.InputBegan:Connect(function(i)
  if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
    dragging = true
    lastpos = Vector2.new(i.Position.X, i.Position.Y)
  end
end)
vp.InputEnded:Connect(function(i)
  if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
    dragging = false
  end
end)
vp.MouseEnter:Connect(function() hovering = true end)
vp.MouseLeave:Connect(function() hovering = false; dragging = false end)
vp.InputChanged:Connect(function(i)
  if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
    local p = Vector2.new(i.Position.X, i.Position.Y)
    local d = p - lastpos
    lastpos = p
    rotationY = rotationY - d.X * 0.012
    rotationX = math.clamp(rotationX - d.Y * 0.012, -math.pi/2 + 0.1, math.pi/2 - 0.1)
  end
  if i.UserInputType == Enum.UserInputType.MouseWheel and hovering then
    distance = math.clamp(distance - i.Position.Z * zoomMul, 1, math.max(6, math.max(previewSize.X, previewSize.Y, previewSize.Z) * 8))
  end
end)

-- Throttle camera work and pause completely when the 3D tab is hidden.
local renderAccumulator = 0
RunService.RenderStepped:Connect(function(dt)
  if not viewPage.Visible or not vcam or not vmodel or not vmodel.Parent then return end
  renderAccumulator += dt
  if renderAccumulator < (1 / 30) then return end
  local step = renderAccumulator
  renderAccumulator = 0
  rotationY = rotationY + 0.18 * step
  local center = Vector3.zero
  local cf = CFrame.new(center) * CFrame.Angles(0, rotationY, 0)
    * CFrame.Angles(rotationX, 0, 0) * CFrame.new(0, 0, distance)
  vcam.CFrame = CFrame.lookAt(cf.Position, center)
end)

-- Local utility console: intentionally does not compile or execute user-provided code.
local termPage = pages["Term"]
local termOut = Instance.new("ScrollingFrame")
termOut.Size = UDim2.new(1, 0, 1, -26)
termOut.BackgroundColor3 = C.row
termOut.BorderSizePixel = 0
termOut.ScrollBarThickness = 5
termOut.AutomaticCanvasSize = Enum.AutomaticSize.Y
termOut.CanvasSize = UDim2.new(0,0,0,0)
termOut.Parent = termPage
Instance.new("UIListLayout", termOut).SortOrder = Enum.SortOrder.LayoutOrder
Instance.new("UIPadding", termOut).PaddingTop = UDim.new(0, 2)

local function out(msg, col)
  local l = Instance.new("TextLabel")
  l.Size = UDim2.new(1, 0, 0, 14)
  l.BackgroundTransparency = 1
  l.Font = Enum.Font.Code
  l.TextSize = 11
  l.Text = os.date("%H:%M:%S") .. "   " .. tostring(msg)
  l.TextColor3 = col or Color3.fromRGB(171,171,171)
  l.TextXAlignment = Enum.TextXAlignment.Left
  l.TextTruncate = Enum.TextTruncate.AtEnd
  l.Parent = termOut
  termOut.CanvasPosition = Vector2.new(0, 9e9)
end
LogService.MessageOut:Connect(function(msg, t)
  local col = Color3.fromRGB(204,204,204)
  if t == Enum.MessageType.MessageWarning then col = Color3.fromRGB(255,142,60)
  elseif t == Enum.MessageType.MessageError then col = Color3.fromRGB(255,68,68) end
  pcall(out, msg, col)
end)

local termLine = Instance.new("Frame")
termLine.Size = UDim2.new(1, 0, 0, 22)
termLine.Position = UDim2.new(0, 0, 1, -22)
termLine.BackgroundColor3 = Color3.fromRGB(37,37,37)
termLine.BorderSizePixel = 0
termLine.Parent = termPage
local termIn = Instance.new("TextBox")
termIn.Size = UDim2.new(1, 0, 1, 0)
termIn.BackgroundTransparency = 1
termIn.Font = Enum.Font.Code
termIn.TextSize = 11
termIn.Text = ""
termIn.PlaceholderText = "Run a command"
termIn.PlaceholderColor3 = C.dim
termIn.TextColor3 = Color3.fromRGB(211,211,211)
termIn.ClearTextOnFocus = false
termIn.TextXAlignment = Enum.TextXAlignment.Left
termIn.Parent = termLine
Instance.new("UIPadding", termIn).PaddingLeft = UDim.new(0, 6)

termIn.PlaceholderText = "help | refresh | selected | children | count | clear"
termIn.FocusLost:Connect(function(enter)
  local txt = termIn.Text
  if not enter or txt == "" then return end
  termIn.Text = ""
  local command = txt:lower():match("^%s*(.-)%s*$")
  out("> " .. command, Color3.fromRGB(120,120,135))
  if command == "help" then
    out("Commands: help, refresh, selected, children, count, path, clear")
    out("Read-only diagnostics only. Use Studio Script Editor to run project code.")
  elseif command == "refresh" then
    safe("render", render)
    safe("props", refreshProps)
    out("Explorer and properties refreshed.", C.good)
  elseif command == "selected" or command == "path" then
    out(selected and (selected.ClassName .. "  " .. pathOf(selected)) or "Nothing selected.")
  elseif command == "children" then
    if not selected then out("Select an instance first.", C.bad) else
      local kids = selected:GetChildren()
      out("Children: " .. #kids)
      for i = 1, math.min(#kids, 40) do out(kids[i].Name .. "  <" .. kids[i].ClassName .. ">") end
      if #kids > 40 then out("Output limited to first 40 children.", C.dim) end
    end
  elseif command == "count" then
    local total, stack = 0, { game }
    while #stack > 0 and total < 5000 do
      local obj = table.remove(stack)
      total += 1
      local ok, kids = pcall(function() return obj:GetChildren() end)
      if ok then for _, child in ipairs(kids) do stack[#stack+1] = child end end
    end
    out("Visible DataModel descendants counted: " .. total .. (total >= 5000 and " (limit reached)" or ""), C.good)
  elseif command == "clear" then
    for _, child in ipairs(termOut:GetChildren()) do
      if child:IsA("TextLabel") then child:Destroy() end
    end
  else
    out("Unknown command. Type help.", C.bad)
  end
end)

gotoTab("Props")
safe("props", refreshProps)
safe("render", render)
safe("view", buildView, nil)
flash("ready", C.dim)