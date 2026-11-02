--[[ TinyDex v17 — refined Dex++ tree renderer, portable LocalScript edition ]]

local plr = game:GetService("Players").LocalPlayer
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local luaSelect = select
local PRIMEZ = "https://primez-studios.onrender.com/"

local gui = Instance.new("ScreenGui")
gui.Name = "TinyDex"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
gui.Enabled = true
local playerGui = plr:FindFirstChildOfClass("PlayerGui") or plr:WaitForChild("PlayerGui", 10)
assert(playerGui, "TinyDex must run from a LocalScript with access to PlayerGui")
gui.Parent = playerGui

local C = {
  bg = Color3.fromRGB(22,22,26), row = Color3.fromRGB(16,16,19), panel = Color3.fromRGB(18,18,22),
  txt = Color3.fromRGB(198,198,208), dim = Color3.fromRGB(120,120,135),
  hot = Color3.fromRGB(122,162,255), good = Color3.fromRGB(110,190,120), bad = Color3.fromRGB(230,110,110),
}
local FULL = UDim2.new(0, 790, 0, 450)
local MINI = UDim2.new(0, 790, 0, 56)

local win = Instance.new("Frame")
win.Size = FULL
win.Position = UDim2.new(0, 16, 0, 16)
win.BackgroundColor3 = C.bg
win.BorderSizePixel = 0
win.Parent = gui
Instance.new("UICorner", win).CornerRadius = UDim.new(0, 6)
Instance.new("UIStroke", win).Color = Color3.fromRGB(58,58,68)

local bar = Instance.new("Frame")
bar.Size = UDim2.new(1,0,0,26)
bar.BackgroundTransparency = 1
bar.Parent = win

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
  b.Size = UDim2.new(0, w, 0, 18)
  b.Position = UDim2.new(1, xo, 0, 4)
  b.BackgroundColor3 = Color3.fromRGB(40,40,50)
  b.BorderSizePixel = 0
  b.Font = Enum.Font.Code
  b.TextSize = 11
  b.Text = text
  b.TextColor3 = col or Color3.fromRGB(210,210,220)
  b.Parent = bar
  Instance.new("UICorner", b).CornerRadius = UDim.new(0, 3)
  return b
end
local diagBtn = tbtn("?", 20, -162, C.dim)
local pickBtn = tbtn("PICK", 46, -136, C.hot)
local copyShown = tbtn("COPY SHOWN", 92, -242)
local xb = Instance.new("TextButton")
xb.Size = UDim2.new(0, 24, 0, 24)
xb.Position = UDim2.new(1, -24, 0, 1)
xb.BackgroundTransparency = 1
xb.Font = Enum.Font.Code
xb.TextSize = 14
xb.TextColor3 = C.bad
xb.Text = "x"
xb.Parent = bar
xb.MouseButton1Click:Connect(function() gui:Destroy() end)

local readout = Instance.new("TextLabel")
readout.Size = UDim2.new(1, -10, 0, 14)
readout.Position = UDim2.new(0, 5, 0, 28)
readout.BackgroundTransparency = 1
readout.Font = Enum.Font.Code
readout.TextSize = 11
readout.TextXAlignment = Enum.TextXAlignment.Left
readout.TextTruncate = Enum.TextTruncate.AtEnd
readout.TextColor3 = C.hot
readout.Text = ""
readout.Parent = win

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -10, 0, 14)
status.Position = UDim2.new(0, 5, 1, -17)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Code
status.TextSize = 11
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextColor3 = C.good
status.Parent = win
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
search.Size = UDim2.new(0, 340, 0, 18)
search.Position = UDim2.new(0, 5, 0, 46)
search.BackgroundColor3 = C.row
search.BorderSizePixel = 0
search.Font = Enum.Font.Code
search.TextSize = 11
search.Text = ""
search.PlaceholderText = "search name / class"
search.TextColor3 = C.txt
search.PlaceholderColor3 = C.dim
search.ClearTextOnFocus = false
search.TextXAlignment = Enum.TextXAlignment.Left
search.Parent = win
Instance.new("UIPadding", search).PaddingLeft = UDim.new(0, 5)
Instance.new("UICorner", search).CornerRadius = UDim.new(0, 4)

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(0, 340, 1, -92)
list.Position = UDim2.new(0, 5, 0, 68)
list.BackgroundColor3 = C.row
list.BorderSizePixel = 0
list.ScrollBarThickness = 5
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new(0,0,0,0)
list.Parent = win
Instance.new("UICorner", list).CornerRadius = UDim.new(0, 4)
Instance.new("UIListLayout", list).SortOrder = Enum.SortOrder.LayoutOrder

local right = Instance.new("Frame")
right.Size = UDim2.new(1, -356, 1, -46)
right.Position = UDim2.new(0, 350, 0, 28)
right.BackgroundColor3 = C.panel
right.BorderSizePixel = 0
right.Parent = win
Instance.new("UICorner", right).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", right).Color = Color3.fromRGB(45,45,55)

local tabRow = Instance.new("Frame")
tabRow.Size = UDim2.new(1, -8, 0, 20)
tabRow.Position = UDim2.new(0, 4, 0, 4)
tabRow.BackgroundTransparency = 1
tabRow.Parent = right
local tl = Instance.new("UIListLayout")
tl.FillDirection = Enum.FillDirection.Horizontal
tl.Padding = UDim.new(0, 3)
tl.Parent = tabRow

local pageArea = Instance.new("Frame")
pageArea.Size = UDim2.new(1, -8, 1, -30)
pageArea.Position = UDim2.new(0, 4, 0, 28)
pageArea.BackgroundTransparency = 1
pageArea.Parent = right

local pages, tabBtns = {}, {}
local function gotoTab(n)
  for k, p in pairs(pages) do p.Visible = (k == n) end
  for k, b in pairs(tabBtns) do
    b.TextColor3 = (k == n) and Color3.fromRGB(235,235,245) or C.dim
    b.BackgroundColor3 = (k == n) and Color3.fromRGB(40,40,50) or Color3.fromRGB(26,26,32)
  end
  if n == "3D" then safe("view", buildView, selected) end
end
for _, n in ipairs({ "Props", "3D", "Term", "PrimeZ" }) do
  local b = Instance.new("TextButton")
  b.Size = UDim2.new(0, 66, 0, 18)
  b.BackgroundColor3 = Color3.fromRGB(26,26,32)
  b.BorderSizePixel = 0
  b.Font = Enum.Font.Gotham
  b.TextSize = 11
  b.Text = n
  b.TextColor3 = C.dim
  b.Parent = tabRow
  Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
  b.MouseButton1Click:Connect(function() gotoTab(n) end)
  tabBtns[n] = b
  local p = Instance.new("Frame")
  p.Size = UDim2.new(1,0,1,0)
  p.BackgroundTransparency = 1
  p.Visible = false
  p.Parent = pageArea
  pages[n] = p
end

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

  -- Cache each node's children for this render pass. Without this, the
  -- recursive filter and row builder repeatedly call GetChildren() on the
  -- same instances, which becomes expensive on large DataModels.
  local childrenCache = {}
  local function getChildren(inst)
    local cached = childrenCache[inst]
    if cached then return cached end

    local kids = {}
    local ok = pcall(function()
      for _, child in ipairs(inst:GetChildren()) do
        kids[#kids + 1] = child
      end
    end)
    if not ok then
      childrenCache[inst] = kids
      return kids
    end

    table.sort(kids, function(a, b)
      local an, bn = a.Name:lower(), b.Name:lower()
      if an == bn then return a.ClassName < b.ClassName end
      return an < bn
    end)
    childrenCache[inst] = kids
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
      local rowHeight = 18

      vis[#vis + 1] = child
      local row = Instance.new("TextButton")
      row.Name = "TreeRow_" .. child.Name
      row.LayoutOrder = #vis -- explicit ordering keeps recursive rows stable
      row.Size = UDim2.new(1, 0, 0, rowHeight)
      row.BackgroundTransparency = (selected == child) and 0 or 1
      row.BackgroundColor3 = Color3.fromRGB(40, 62, 110)
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
      arrow.TextColor3 = hasChildren and C.good or C.dim
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
      icon.TextColor3 = hasChildren and C.good or C.hot
      -- Keep the disclosure arrow separate from the class glyph, as in
      -- object explorers: the arrow controls branches; the glyph identifies
      -- the kind of Instance.
      if child:IsA("Folder") then
        icon.Text = "▰"
      elseif child:IsA("Model") then
        icon.Text = "◩"
      elseif child:IsA("BasePart") then
        icon.Text = "◧"
      elseif child:IsA("LuaSourceContainer") then
        icon.Text = "◇"
      else
        icon.Text = hasChildren and "▣" or "·"
      end
      icon.Parent = row

      local name = Instance.new("TextLabel")
      name.Size = UDim2.new(1, -(depth * 14 + 46), 1, 0)
      name.Position = UDim2.fromOffset(depth * 14 + 44, 0)
      name.BackgroundTransparency = 1
      name.Font = Enum.Font.Code
      name.TextSize = 12
      name.TextXAlignment = Enum.TextXAlignment.Left
      name.TextTruncate = Enum.TextTruncate.AtEnd
      name.TextColor3 = (selected == child) and Color3.new(1, 1, 1) or C.txt
      local countText = "  (" .. tostring(childCount)
        .. (childCount == 1 and " item)" or " items)")
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
        -- Carry this branch's guide only while this node has following
        -- siblings. This prevents green rails from continuing past the end
        -- of a parent branch while preserving each open folder's own guide.
        nextAncestors[#nextAncestors + 1] = not isLast
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
    if c == inst then list.CanvasPosition = Vector2.new(0, math.max(0, i * 18 - 60)); break end
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
  pickBtn.BackgroundColor3 = Color3.fromRGB(40,40,50)
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
vp.BackgroundColor3 = C.row
vp.BorderSizePixel = 0
vp.Ambient = Color3.fromRGB(140,140,150)
vp.LightColor = Color3.new(1,1,1)
vp.LightDirection = Vector3.new(-0.5, -0.8, -0.6)
vp.Parent = viewPage
Instance.new("UICorner", vp).CornerRadius = UDim.new(0, 4)

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

termIn.PlaceholderText = "help | refresh | selected | clear"
termIn.FocusLost:Connect(function(enter)
  local txt = termIn.Text
  if not enter or txt == "" then return end
  termIn.Text = ""
  local command = txt:lower():match("^%s*(.-)%s*$")
  out("> " .. command, Color3.fromRGB(120,120,135))
  if command == "help" then
    out("Commands: help, refresh, selected, clear")
    out("This panel is read-only; arbitrary Luau execution is disabled.")
  elseif command == "refresh" then
    safe("render", render)
    safe("props", refreshProps)
    out("Explorer and properties refreshed.", C.good)
  elseif command == "selected" then
    out(selected and (selected.ClassName .. "  " .. pathOf(selected)) or "Nothing selected.")
  elseif command == "clear" then
    for _, child in ipairs(termOut:GetChildren()) do
      if child:IsA("TextLabel") then child:Destroy() end
    end
  else
    out("Unknown command. Type help.", C.bad)
  end
end)

-- PrimeZ
local pz = pages["PrimeZ"]
local pzT = Instance.new("TextLabel")
pzT.Size = UDim2.new(1, 0, 0, 20)
pzT.BackgroundTransparency = 1
pzT.Font = Enum.Font.GothamBold
pzT.TextSize = 14
pzT.TextXAlignment = Enum.TextXAlignment.Left
pzT.TextColor3 = Color3.fromRGB(176,130,255)
pzT.Text = "PrimeZ Studios"
pzT.Parent = pz
local pzU = Instance.new("TextLabel")
pzU.Size = UDim2.new(1, 0, 0, 16)
pzU.Position = UDim2.new(0, 0, 0, 22)
pzU.BackgroundTransparency = 1
pzU.Font = Enum.Font.Code
pzU.TextSize = 11
pzU.TextXAlignment = Enum.TextXAlignment.Left
pzU.TextColor3 = C.hot
pzU.TextTruncate = Enum.TextTruncate.AtEnd
pzU.Text = PRIMEZ
pzU.Parent = pz
local pzS = Instance.new("TextLabel")
pzS.Size = UDim2.new(1, 0, 0, 16)
pzS.Position = UDim2.new(0, 0, 0, 40)
pzS.BackgroundTransparency = 1
pzS.Font = Enum.Font.Code
pzS.TextSize = 11
pzS.TextXAlignment = Enum.TextXAlignment.Left
pzS.TextColor3 = C.dim
pzS.Text = "checking..."
pzS.Parent = pz
local function pzBtn(text, y)
  local b = Instance.new("TextButton")
  b.Size = UDim2.new(0, 150, 0, 24)
  b.Position = UDim2.new(0, 0, 0, y)
  b.BackgroundColor3 = Color3.fromRGB(34,34,42)
  b.BorderSizePixel = 0
  b.Font = Enum.Font.Gotham
  b.TextSize = 11
  b.Text = text
  b.TextColor3 = C.txt
  b.Parent = pz
  Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
  return b
end
pzBtn("Show pairing URL", 64).MouseButton1Click:Connect(function()
  showTextExport("PRIMEz URL", PRIMEZ)
end)
local pairNote = Instance.new("TextLabel")
pairNote.Size = UDim2.new(1, -4, 0, 42)
pairNote.Position = UDim2.fromOffset(0, 94)
pairNote.BackgroundTransparency = 1
pairNote.Font = Enum.Font.Code
pairNote.TextSize = 11
pairNote.TextWrapped = true
pairNote.TextXAlignment = Enum.TextXAlignment.Left
pairNote.TextYAlignment = Enum.TextYAlignment.Top
pairNote.TextColor3 = C.dim
pairNote.Text = "Pairing is not connected yet. A server-authenticated PRIMEz pairing endpoint is required; client-side executor HTTP is not used."
pairNote.Parent = pz
pzS.Text = "pairing not configured"
pzS.TextColor3 = C.dim

gotoTab("Props")
safe("props", refreshProps)
safe("render", render)
safe("view", buildView, nil)
flash("ready", C.dim)