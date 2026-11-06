--[[ ══════════════════════════════════════════════════════════════════════════
  TinyDex v23 — PRIMEz Studios FULL SCRIPTS CLIENT
  PULSAR AGENT edition: real tool-calling agent loop + executing Luau terminal.

  WHAT'S NEW IN v23 (vs v22)
  • AGENT LOOP: the server may return tool_calls; TinyDex executes them live
    (analyze_game, inspect, search_game, list_children, read_property,
    get_selection, get_logs, run_luau, save_draft, set_property,
    create_instance, destroy_instance) and posts results back — up to 8
    steps per turn. PULSAR can now ACT, not just chat.
  • TERMINAL: the CONSOLE tab executes Luau (`run`, `run <code>`) when the
    runtime provides loadstring (executor clients). Studio stays read-only.
  • FULL GAME ANALYSIS: the analyze_game tool produces a structured report of
    the whole DataModel — services, players, characters, remotes, replicated
    content, camera, lighting, workspace.
  • SCRIPT CARDS + AUTO-RUN: PULSAR replies with ```lua blocks that become
    RUN / COPY cards. With AUTO-RUN ON, generated scripts execute through the
    terminal automatically; execution output and errors are fed back to the
    agent so it can fix its own code.
  • FIXES v22 BUG: raw tool_calls JSON leaking into the chat is now parsed
    and executed (or cleanly reported) instead of being displayed as text.

  WHAT'S NEW IN v23.1 (PERF PATCH)
  • No boot-time full-game index build — it froze big games (laggy movement,
    crashes). The index now builds lazily via SYNC DATA or deep analyze_game.
  • Index builder is capped (4000 instances / 2s CPU budget), yields every 10
    instances, and caps per-instance child lists — labeled CAPPED when partial.
  • MAX_STEPS 40 → 8 (the documented limit). A turn can no longer spiral into
    dozens of chained model requests.
  • Tool results are clipped to 6k chars in agent history — requests stay
    small and fast instead of dragging megabytes through every step.
  • search_game and the analyze_game remote scan cap their work per service
    and yield mid-scan.

  WHAT'S NEW IN v23.2 (FLOATING TOGGLE)
  • A round PRIMEz "P" button (black bg, white P, purple stroke) is pinned
    at the BOTTOM-LEFT of the screen and always stays there.
  • Tap it to hide the TinyDex window, tap again to show it. PULSAR, the
    agent loop, tools and the terminal keep working while hidden.
  • Showing the window snaps it fully back on screen — it can never be
    stuck outside the viewport or impossible to grab.
  • The X button still removes TinyDex completely, including the P button.

  WHAT'S NEW IN v23.3 (DRAGGABLE P BUTTON)
  • The P button can now be DRAGGED anywhere on screen — any side, any
    corner — so it never has to sit on top of the game's mobile controls.
  • Drag = move the button; quick tap = toggle the window (same as before).
  • The button is live-clamped while dragging: it always stays fully
    visible on screen and can never get lost off-screen.
  • v23.3.1 FIX: tapping P to show the window no longer drifts it into a
    corner. The window re-centers ONLY if part of it is off-screen; a
    valid position is never rewritten.
  • v23.3.2 FIX: P taps now use the Activated event. On mobile, InputEnded
    could miss the button when the finger lifted slightly off it — P then
    looked dead and the drag state could stick, making the button follow
    the next touch. Drag state is now cleaned up globally and a finished
    drag suppresses the tap for 0.35s, so drags never toggle the window.

  WHAT'S NEW IN v23.4 (AUTO-FINISH + WEB RESEARCH)
  • NO MORE "SAY CONTINUE": the agent budget is 8 → 24 steps per turn, so
    PULSAR keeps working until the task is actually DONE (research →
    analyze → build → execute → verify), not stopped mid-task.
  • WEB RESEARCH: new web_search tool — PULSAR searches the internet
    (DuckDuckGo, client-side via executor HTTP, no backend change) for
    the game's current scripts, features, updates and meta.
  • v23.4.1 FIX: failed AI requests no longer kill the whole turn — each
    step retries up to 3 times (waits in between), and the HTTP timeout
    is 90s instead of 45s so Render cold starts stop eating requests.
    Invented tool names now get told the real tool list so the agent
    self-corrects on the next step.
  • v23.4.2 SPEED: the goal is a delivered script in under 5 minutes.
    New SPEED RULES in the agent brain — finish in 8 steps or fewer, at
    most ONE web search, summary analysis only, no narration between
    steps. Status bar shows a live step + elapsed-time counter, and
    history is trimmed tighter (28 messages) so requests stay fast.
  • v23.4.3 FIX: status bar now has a live heartbeat (refreshes every
    second, even mid-request — before, it froze at "STEP 1/24 · 0:00"
    during long model waits and PULSAR looked dead). Messages typed
    while PULSAR is working are QUEUED and auto-sent when the task
    finishes instead of being silently swallowed. The agent brain is
    forbidden from announcing a script without including the full code
    in the same reply. AGENT DONE shows the total turn time.
  • v23.4.4 FOCUS: PULSAR is a SCRIPT BUILDER, judged only by whether
    the delivered script actually RUNS. New WORKING SCRIPT STANDARD in
    the brain (a script "works" only after run_luau returns EXEC OK,
    fix up to 3 attempts, final report states SCRIPT RUNNING ✓/✗ plus
    how to stop it) and anti-random rules (no tutorials, no "here are
    ideas", no off-topic chatter when a script was requested).
    Mechanical guarantee: after the final reply, the delivered script's
    largest lua block is auto-executed and reported EXEC OK / FAILED —
    a broken script can never be passed off as working.
  • GAME DETECTION: the game's real name is auto-detected (place info)
    and sent to PULSAR with EVERY request; new get_game_info tool.
  • SCRIPT WORKFLOW: for game-script requests PULSAR now follows:
    identify the game → web_search its known features/scripts → analyze
    the live game → build → execute. It knows the common script types
    (auto-steal, autofarm/auto-collect, auto-buy, ESP, movement,
    teleport, anti-AFK, GUI hubs, remote tools, lag tools).


  ── BACKEND CONTRACT — POST {PRIMEZ}/api/ai/chat ─────────────────────────
  request body:
    {
      agent   = true,
      step    = <int>,
      tools   = { { name, description, parameters }, ... },  -- from TOOL_SCHEMAS
      context = "<product knowledge + live client context>",
      messages = {
        { role = "user",      content = "..." },
        { role = "assistant", content = "..." },
        { role = "tool", tool_call_id = "...", name = "...", arguments = <args table>, content = "<result>" },
      },
    }
  response body, one of:
    { success = true, done = false, tool_calls = { { id, name, args } } }
    { success = true, done = true,  reply = "final answer text" }
    { success = false, error = "..." }
  • Legacy { success = true, reply = "..." } responses are treated as done.
  • Server must NEVER place raw tool_calls JSON inside `reply`.
  • role="tool" entries in `messages` are tool results from the previous step.
═════════════════════════════════════════════════════════════════════════════ ]]

-- DELTA-style boot: executors inject before the client finishes loading.
if not game:IsLoaded() then game.Loaded:Wait() end
local PlayersService = game:GetService("Players")
local plr = PlayersService.LocalPlayer
while not plr do
  task.wait(0.1)
  plr = PlayersService.LocalPlayer
end
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local TweenService = game:GetService("TweenService")
local luaSelect = select
local PRIMEZ = "https://primez-studios.onrender.com/"

local gui = Instance.new("ScreenGui")
gui.Name = "TinyDex"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
gui.Enabled = true
local playerGui = plr:FindFirstChildOfClass("PlayerGui") or plr:WaitForChild("PlayerGui", 10)
-- Prefer the executor's hidden UI container so the Dex survives respawns,
-- with PlayerGui as the Studio fallback.
local hiddenUi
pcall(function()
  if type(gethui) == "function" then hiddenUi = gethui() end
end)
pcall(function()
  for _, existing in ipairs(playerGui and playerGui:GetChildren() or {}) do
    if existing.Name == "TinyDex" then existing:Destroy() end
  end
  for _, existing in ipairs(hiddenUi and hiddenUi:GetChildren() or {}) do
    if existing.Name == "TinyDex" then existing:Destroy() end
  end
end)
if hiddenUi then
  gui.Parent = hiddenUi
elseif playerGui then
  gui.Parent = playerGui
else
  error("TinyDex v23: no UI container available (PlayerGui missing, gethui unavailable)")
end

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
brandSub.Text = "by PRIMEz Studios  •  v23.4"
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

-- v23.2: floating PRIMEz toggle button, pinned bottom-left. Tap to hide the
-- TinyDex window, tap again to show it. PULSAR, the agent loop, tools and
-- the terminal keep running while the window is hidden. The X button is
-- still the only way to remove TinyDex completely (it takes the P button
-- with it).
-- v23.3: the P button is also DRAGGABLE — press and slide it anywhere on
-- screen (any side, any corner) so it never has to sit on top of the game's
-- mobile controls. Drag = move, quick tap = toggle.
local pBtn = Instance.new("TextButton")
pBtn.Name = "PRIMEzToggle"
pBtn.Size = UDim2.new(0, 40, 0, 40)
pBtn.AnchorPoint = Vector2.new(0, 0)
pBtn.Position = UDim2.new(0, 10, 1, -52)
pBtn.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
pBtn.BorderSizePixel = 0
pBtn.Font = Enum.Font.GothamBold
pBtn.TextSize = 21
pBtn.Text = "P"
pBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
pBtn.AutoButtonColor = false
pBtn.Parent = gui
Instance.new("UICorner", pBtn).CornerRadius = UDim.new(1, 0)
local pStroke = Instance.new("UIStroke", pBtn)
pStroke.Color = C.hot
pStroke.Thickness = 1.5
pStroke.Transparency = 0.12

-- v23.3: drag the P button anywhere on screen; a quick tap toggles the
-- window. The button is live-clamped so it always stays fully visible.
local pDragging, pDragStart, pBtnStart, pMoved = false, nil, nil, false
pBtn.InputBegan:Connect(function(i)
  if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
    pDragging, pMoved = true, false
    pDragStart, pBtnStart = i.Position, pBtn.Position
  end
end)
UIS.InputChanged:Connect(function(i)
  if pDragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
    local d = i.Position - pDragStart
    if not pMoved and (math.abs(d.X) > 8 or math.abs(d.Y) > 8) then pMoved = true end
    if pMoved then
      pBtn.Position = UDim2.new(pBtnStart.X.Scale, pBtnStart.X.Offset + d.X, pBtnStart.Y.Scale, pBtnStart.Y.Offset + d.Y)
      -- live clamp: keep the button fully on screen while dragging
      local cam = workspace.CurrentCamera
      local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
      local pos, size = pBtn.AbsolutePosition, pBtn.AbsoluteSize
      local nx = math.clamp(pos.X, 2, math.max(2, vp.X - size.X - 2))
      local ny = math.clamp(pos.Y, 2, math.max(2, vp.Y - size.Y - 2))
      if nx ~= pos.X or ny ~= pos.Y then
        pBtn.Position = UDim2.new(0, nx, 0, ny)
        pBtnStart, pDragStart = pBtn.Position, i.Position
      end
    end
  end
end)
-- v23.3.2 FIX: InputEnded on a small button is unreliable on mobile — if the
-- finger lifts slightly off the button it never fires, so P looked dead and
-- pDragging stayed stuck (the button then followed the next touch). Taps
-- now use the Activated event (fires reliably on release over the button,
-- never fires on a drag-away), and a GLOBAL InputEnded clears drag state and
-- suppresses the tap for 0.35s after any drag so a drag that ends on the
-- button can't accidentally toggle the window.
local pSuppressTapUntil = 0
UIS.InputEnded:Connect(function(i)
  if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
    if pDragging then
      pDragging = false
      if pMoved then
        pMoved = false
        pSuppressTapUntil = time() + 0.35
      end
    end
  end
end)
pBtn.Activated:Connect(function()
  if time() < pSuppressTapUntil then return end
  win.Visible = not win.Visible
  if win.Visible then
    -- v23.3.1 FIX: the old snap code read the window position before the
    -- layout refreshed and wrote offsets that ignored the window's center
    -- anchor — every show drifted the window until it landed in a corner
    -- where its title bar (the only drag handle) was unreachable. Now:
    -- wait one frame for fresh layout, and re-center the window ONLY if
    -- any part of it is off-screen. On-screen positions are untouched.
    task.wait()
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    local pos, size = win.AbsolutePosition, win.AbsoluteSize
    local offScreen = pos.X < -12 or pos.Y < -12
      or (pos.X + size.X) > (vp.X + 12) or (pos.Y + size.Y) > (vp.Y + 12)
    if offScreen then
      win.Position = UDim2.fromScale(0.5, 0.5)
    end
  end
end)

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
footer.Text = "PRIMEz Studios   •   Shared Inspection Index   •   v22.0 (No Limits)"
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
for _, n in ipairs({ "Props", "3D", "Code", "Term", "PrimeZ" }) do
  local b = Instance.new("TextButton")
  b.Size = UDim2.new(0, 92, 0, 26)
  b.BackgroundColor3 = Color3.fromRGB(28, 24, 43)
  b.BorderSizePixel = 0
  b.Font = Enum.Font.GothamSemibold
  b.TextSize = 10
  b.Text = ({Props = "INSPECT", ["3D"] = "PREVIEW", Code = "WORKSPACE", Term = "CONSOLE", PrimeZ = "PULSAR AI"})[n]
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
editorNote.Text = "DRAFT MODE  •  Run with CONSOLE `run` or let PULSAR auto-run it"
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


local inspectionIndexDirty, inspectionIndexEpoch = true, 0
local inspectionIndexCache = "Inspection index has not been built yet."
local inspectionIndexRevision, inspectionIndexCount = 0, 0
local inspectionIndexTruncated = false
local indexInfo

local function markInspectionIndexDirty()
  inspectionIndexEpoch += 1
  inspectionIndexDirty = true
  if indexInfo then indexInfo.Text = "INDEX OUTDATED · refresh pending" end
end

local KNOWN_SERVICES = {
  "Workspace", "Players", "Lighting", "ReplicatedFirst", "ReplicatedStorage",
  "StarterGui", "StarterPack", "StarterPlayer", "SoundService", "Chat",
  "TextChatService", "LocalizationService", "JointsService", "MaterialService",
  "ServerScriptService", "ServerStorage", "HttpService",
}

local function resolveTarget(name)
  if not name or name == "" then return nil end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  local ok, s = pcall(function() return game:GetService(name) end)
  if ok and s then return s end
  for _, sName in ipairs(KNOWN_SERVICES) do
    if sName:lower() == name:lower() then
      local sOk, res = pcall(function() return game:GetService(sName) end)
      if sOk and res then return res end
    end
  end
  local found
  pcall(function()
    found = game:FindFirstChild(name, true)
  end)
  return found
end

local PULSAR_INDEX_PROPERTIES = {
  "Value", "Text", "Visible", "Enabled", "Active", "Anchored", "CanCollide",
  "Transparency", "Position", "Size", "WalkSpeed", "JumpPower", "JumpHeight",
  "Health", "MaxHealth", "DisplayName", "Team", "Material", "Color",
  "BackgroundColor3", "Image", "SoundId", "AnimationId", "PlaybackSpeed",
}
local function indexValue(inst, propertyName)
  local ok, value = pcall(function() return inst[propertyName] end)
  if not ok then return nil end
  local kind = typeof(value)
  if kind ~= "string" and kind ~= "number" and kind ~= "boolean"
    and kind ~= "EnumItem" and kind ~= "Vector2" and kind ~= "Vector3"
    and kind ~= "CFrame" and kind ~= "Color3" and kind ~= "UDim"
    and kind ~= "UDim2" and kind ~= "BrickColor" and kind ~= "Instance" then
    return nil
  end
  local rendered = valueToText(value)
  if #rendered > 120 then rendered = rendered:sub(1, 117) .. "..." end
  return propertyName .. "=" .. rendered
end

local function rebuildInspectionIndex()
  if not inspectionIndexDirty then return inspectionIndexCache end
  local buildEpoch = inspectionIndexEpoch
  local lines = {
    "SCOPE: Full client-accessible Roblox DataModel descendants (NO LIMITS).",
    "STATUS: Complete, unconstrained live hierarchy snapshot.",
  }
  local stack, seen, seenRoots = {}, {}, {}

  -- Discover all accessible root services (StarterPlayer, ServerStorage, Workspace, etc.)
  for _, sName in ipairs(KNOWN_SERVICES) do
    pcall(function()
      local s = game:GetService(sName)
      if s and s ~= gui and not seenRoots[s] then
        seenRoots[s] = true
        stack[#stack + 1] = s
      end
    end)
  end

  local roots = {}
  pcall(function() roots = game:GetChildren() end)
  for i = #roots, 1, -1 do
    local r = roots[i]
    if r and r ~= gui and not seenRoots[r] then
      seenRoots[r] = true
      stack[#stack + 1] = r
    end
  end

  -- PERF: hard caps + CPU budget so big games can't freeze the client or
  -- balloon memory (v23.1). Index is built lazily, never at boot.
  local INDEX_MAX_INSTANCES = 4000
  local INDEX_CPU_BUDGET = 2.0
  local buildStartClock = os.clock()
  local count = 0
  local stoppedWhy = nil
  while #stack > 0 do
    local inst = table.remove(stack)
    if inst and inst ~= gui and not seen[inst] then
      seen[inst] = true
      local childOk, children = pcall(function() return inst:GetChildren() end)
      if not childOk or type(children) ~= "table" then children = {} end

      local entry = {
        ("ITEM %d | %s | %s | children=%d"):format(
          count + 1, tostring(inst.ClassName), tostring(inst.Name), #children
        ),
        "PATH: " .. tostring(pathOf(inst)),
      }

      local propParts = {}
      for _, propertyName in ipairs(PULSAR_INDEX_PROPERTIES) do
        local rendered = indexValue(inst, propertyName)
        if rendered then
          propParts[#propParts + 1] = rendered
        end
      end
      if #propParts > 0 then entry[#entry + 1] = "PROPERTIES: " .. table.concat(propParts, " | ") end

      local attrOk, attrs = pcall(function() return inst:GetAttributes() end)
      if attrOk and type(attrs) == "table" then
        local keys = {}
        for key in pairs(attrs) do keys[#keys + 1] = tostring(key) end
        table.sort(keys)
        local attrParts = {}
        for i = 1, #keys do
          local key = keys[i]
          local valueOk, value = pcall(function() return inst:GetAttribute(key) end)
          if valueOk then
            local rendered = valueToText(value)
            attrParts[#attrParts + 1] = key .. "=" .. rendered
          end
        end
        if #attrParts > 0 then entry[#entry + 1] = "ATTRIBUTES: " .. table.concat(attrParts, " | ") end
      end

      local childParts = {}
      for i = 1, math.min(#children, 12) do
        local child = children[i]
        childParts[#childParts + 1] = tostring(child.Name) .. "<" .. tostring(child.ClassName) .. ">"
      end
      if #children > 12 then childParts[#childParts + 1] = ("…(+%d more)"):format(#children - 12) end
      if #childParts > 0 then entry[#entry + 1] = "DIRECT CHILDREN: " .. table.concat(childParts, ", ") end

      lines[#lines + 1] = table.concat(entry, "\n")
      count += 1

      for i = #children, 1, -1 do
        if children[i] ~= gui and not seen[children[i]] then
          stack[#stack + 1] = children[i]
        end
      end

      if count % 10 == 0 then task.wait() end
      if count >= INDEX_MAX_INSTANCES then stoppedWhy = "instance cap reached" break end
      if os.clock() - buildStartClock > INDEX_CPU_BUDGET then stoppedWhy = "cpu budget reached" break end
    end
  end

  inspectionIndexCount = count
  inspectionIndexTruncated = stoppedWhy ~= nil
  inspectionIndexRevision += 1
  inspectionIndexCache = table.concat(lines, "\n")
    .. ("\nINDEX SUMMARY: %d instances indexed; revision %d; %s"):format(
      count, inspectionIndexRevision,
      stoppedWhy and ("PARTIAL — stopped: " .. stoppedWhy .. ". Use search_game/inspect for anything not listed.") or "complete index."
    )
  inspectionIndexDirty = inspectionIndexEpoch ~= buildEpoch
  if indexInfo then
    indexInfo.Text = ("INDEX %d · REV %d · %s"):format(
      inspectionIndexCount, inspectionIndexRevision, stoppedWhy and "CAPPED" or "FULL"
    )
    indexInfo.TextColor3 = inspectionIndexDirty and C.dim or C.good
  end
  return inspectionIndexCache
end

game.DescendantAdded:Connect(function(inst)
  if inst ~= gui and not inst:IsDescendantOf(gui) then markInspectionIndexDirty() end
end)
game.DescendantRemoving:Connect(function(inst)
  if inst ~= gui and not inst:IsDescendantOf(gui) then markInspectionIndexDirty() end
end)
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
  markInspectionIndexDirty()
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


-- ══════════════════════════════════════════════════════════════════════
-- TERMINAL EXECUTION CORE (v23)
-- Shared by the CONSOLE tab (`run` command) and the PULSAR agent
-- (run_luau tool / auto-run). Execution requires loadstring, which only
-- executor runtimes provide. Studio stays read-only and reports that.
-- ══════════════════════════════════════════════════════════════════════
local EXEC_AVAILABLE = (function()
  if type(loadstring) == "function" then return true end
  local g = (type(getgenv) == "function") and getgenv() or nil
  return g ~= nil and type(g.loadstring) == "function"
end)()

local Terminal = {}
Terminal.runs = 0

function Terminal.exec(code, label)
  local result = { ok = false, output = "", duration = 0 }
  if type(code) ~= "string" or code:match("^%s*$") then
    result.output = "nothing to run: empty code"
    return result
  end
  if not EXEC_AVAILABLE then
    result.output = "Luau execution unavailable: this runtime has no loadstring. "
      .. "Run TinyDex from an executor client, or copy the script into Roblox Studio."
    out(result.output, C.bad)
    return result
  end

  -- Capture print/warn output so tool results can be returned to the agent.
  local captured = {}
  local oldPrint, oldWarn = print, warn
  local shimOk = pcall(function()
    print = function(...)
      local parts = {}
      for i = 1, luaSelect("#", ...) do parts[#parts + 1] = tostring(luaSelect(i, ...)) end
      captured[#captured + 1] = table.concat(parts, "  ")
    end
    warn = function(...)
      local parts = { "[warn]" }
      for i = 1, luaSelect("#", ...) do parts[#parts + 1] = tostring(luaSelect(i, ...)) end
      captured[#captured + 1] = table.concat(parts, "  ")
    end
  end)
  local function restore()
    if shimOk then
      pcall(function() print = oldPrint end)
      pcall(function() warn = oldWarn end)
    end
  end

  Terminal.runs += 1
  local tag = tostring(label or "run") .. " #" .. Terminal.runs
  out("▶ EXEC " .. tag .. " (" .. #code .. " chars)", Color3.fromRGB(190, 145, 255))
  local startedAt = os.clock()
  local chunk, compileErr
  local compileOk = pcall(function()
    chunk, compileErr = loadstring(code, "=PRIMEz_" .. tag:gsub("%W+", "_"))
  end)
  if not compileOk or type(chunk) ~= "function" then
    restore()
    result.output = "compile error: " .. tostring(compileErr)
    out("✖ " .. result.output, C.bad)
    return result
  end
  local runOk, runErr = pcall(chunk)
  restore()
  result.duration = math.floor((os.clock() - startedAt) * 1000 + 0.5)
  local tail = table.concat(captured, "\n")
  if #tail > 6000 then tail = tail:sub(1, 6000) .. "\n... output truncated" end
  if runOk then
    result.ok = true
    result.output = (tail ~= "" and tail or "(no output)")
    out("✔ done in " .. result.duration .. " ms", C.good)
    for _, line in ipairs(captured) do out("   " .. line) end
  else
    result.output = "runtime error: " .. tostring(runErr) .. (tail ~= "" and ("\n" .. tail) or "")
    out("✖ " .. tostring(runErr), C.bad)
    for _, line in ipairs(captured) do out("   " .. line) end
  end
  return result
end

function Terminal.execDraft(label)
  local source = editor.Text or ""
  if source:match("^%s*$") then
    out("Draft is empty. Write code in the WORKSPACE tab first.", C.bad)
    return { ok = false, output = "draft empty", duration = 0 }
  end
  return Terminal.exec(source, label or "draft")
end

Terminal.available = EXEC_AVAILABLE
termIn.PlaceholderText = "help | run | refresh | selected | children | count | clear | agent"
termIn.FocusLost:Connect(function(enter)
  local txt = termIn.Text
  if not enter or txt == "" then return end
  termIn.Text = ""
  local raw = txt:match("^%s*(.-)%s*$")
  local command = raw:lower()
  out("> " .. raw, Color3.fromRGB(120,120,135))
  if command == "help" then
    out("Commands: help, run, exec, refresh, selected, path, children, count, clear, status, agent")
    out("run            — execute the WORKSPACE draft in this terminal")
    out("run <luau>     — execute one line of Luau code, e.g.  run print(workspace.Name)")
    out("status         — runtime capabilities (executor / execution / PRIMEz route)")
    out("agent          — open the PULSAR AI tab")
    if not Terminal.available then
      out("Execution is OFF in this runtime (no loadstring): Studio-safe diagnostics only.", C.dim)
    end
  elseif command == "run" or command == "exec" then
    Terminal.execDraft("console")
  elseif command:sub(1, 4) == "run " or command:sub(1, 5) == "exec " then
    local code = raw:sub(command:sub(1, 4) == "run " and 5 or 6)
    Terminal.exec(code, "console-line")
  elseif command == "status" then
    out("TinyDex v23 runtime status")
    out("  execution (loadstring): " .. (Terminal.available and "AVAILABLE" or "unavailable (read-only mode)"), Terminal.available and C.good or C.bad)
    local hasHttp = (type(request) == "function") or (type(http_request) == "function") or (syn and type(syn.request) == "function")
    out("  executor HTTP: " .. (hasHttp and "AVAILABLE" or "unavailable"), hasHttp and C.good or C.bad)
    out("  PRIMEz route: " .. PRIMEZ)
    out("  terminal runs this session: " .. Terminal.runs)
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
  elseif command == "agent" then
    gotoTab("PrimeZ")
  elseif command == "clear" then
    for _, child in ipairs(termOut:GetChildren()) do
      if child:IsA("TextLabel") then child:Destroy() end
    end
  else
    out("Unknown command. Type help.", C.bad)
  end
end)

-- ══════════════════════════════════════════════════════════════════════
-- PRIMEz PULSAR AGENT v23 — FULL SCRIPTS CLIENT
-- Real tool-calling agent loop + auto-executing Luau terminal.
-- Backend contract: see the file header.
-- ══════════════════════════════════════════════════════════════════════

local pz = pages["PrimeZ"]

local pzTitle = Instance.new("TextLabel")
pzTitle.Size = UDim2.new(1, -8, 0, 22)
pzTitle.BackgroundTransparency = 1
pzTitle.Font = Enum.Font.GothamBold
pzTitle.TextSize = 16
pzTitle.TextXAlignment = Enum.TextXAlignment.Left
pzTitle.TextColor3 = Color3.fromRGB(176,130,255)
pzTitle.Text = "✦  PULSAR AGENT  ·  PRIMEz Full Scripts Client (v23)"
pzTitle.Parent = pz

local pzStatus = Instance.new("TextLabel")
pzStatus.Size = UDim2.new(1, -8, 0, 16)
pzStatus.Position = UDim2.fromOffset(0, 23)
pzStatus.BackgroundTransparency = 1
pzStatus.Font = Enum.Font.Code
pzStatus.TextSize = 10
pzStatus.TextXAlignment = Enum.TextXAlignment.Left
pzStatus.TextColor3 = C.dim
pzStatus.Text = "Connecting to PRIMEz Cloud..."
pzStatus.Parent = pz

local chatFeed = Instance.new("ScrollingFrame")
chatFeed.Name = "PulsarConversation"
chatFeed.Size = UDim2.new(1, -4, 1, -120)
chatFeed.Position = UDim2.fromOffset(0, 43)
chatFeed.BackgroundColor3 = C.row
chatFeed.BorderSizePixel = 0
chatFeed.ScrollBarThickness = 3
chatFeed.AutomaticCanvasSize = Enum.AutomaticSize.Y
chatFeed.CanvasSize = UDim2.new(0,0,0,0)
chatFeed.Parent = pz
Instance.new("UICorner", chatFeed).CornerRadius = UDim.new(0, 9)
local chatStroke = Instance.new("UIStroke", chatFeed)
chatStroke.Color = C.line
chatStroke.Transparency = 0.5
local feedLayout = Instance.new("UIListLayout")
feedLayout.Padding = UDim.new(0, 6)
feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
feedLayout.Parent = chatFeed
local feedPad = Instance.new("UIPadding")
feedPad.PaddingTop = UDim.new(0, 7)
feedPad.PaddingBottom = UDim.new(0, 7)
feedPad.PaddingLeft = UDim.new(0, 7)
feedPad.PaddingRight = UDim.new(0, 7)
feedPad.Parent = chatFeed

local composer = Instance.new("Frame")
composer.Size = UDim2.new(1, -4, 0, 54)
composer.Position = UDim2.new(0, 0, 1, -74)
composer.BackgroundColor3 = Color3.fromRGB(27, 22, 43)
composer.BorderSizePixel = 0
composer.Parent = pz
Instance.new("UICorner", composer).CornerRadius = UDim.new(0, 9)
local composerStroke = Instance.new("UIStroke", composer)
composerStroke.Color = C.line
composerStroke.Transparency = 0.25

local promptBox = Instance.new("TextBox")
promptBox.Size = UDim2.new(1, -72, 1, -8)
promptBox.Position = UDim2.fromOffset(7, 4)
promptBox.BackgroundTransparency = 1
promptBox.Font = Enum.Font.Gotham
promptBox.TextSize = 12
promptBox.TextColor3 = C.txt
promptBox.PlaceholderColor3 = C.dim
promptBox.PlaceholderText = "Describe the script you want — PULSAR analyzes the game, builds it, and runs it in the terminal..."
promptBox.Text = ""
promptBox.ClearTextOnFocus = false
promptBox.MultiLine = true
promptBox.TextWrapped = true
promptBox.TextXAlignment = Enum.TextXAlignment.Left
promptBox.TextYAlignment = Enum.TextYAlignment.Center
promptBox.Parent = composer

local sendBtn = Instance.new("TextButton")
sendBtn.Size = UDim2.new(0, 56, 0, 36)
sendBtn.Position = UDim2.new(1, -62, 0, 9)
sendBtn.BackgroundColor3 = C.hot2
sendBtn.BorderSizePixel = 0
sendBtn.Font = Enum.Font.GothamBold
sendBtn.TextSize = 11
sendBtn.Text = "SEND"
sendBtn.TextColor3 = Color3.new(1,1,1)
sendBtn.Parent = composer
Instance.new("UICorner", sendBtn).CornerRadius = UDim.new(0, 8)
local sendStroke = Instance.new("UIStroke", sendBtn)
sendStroke.Color = Color3.fromRGB(191, 142, 255)
sendStroke.Transparency = 0.45
sendBtn.MouseEnter:Connect(function() TweenService:Create(sendBtn, TweenInfo.new(0.14), {BackgroundColor3 = C.hot}):Play() end)
sendBtn.MouseLeave:Connect(function() TweenService:Create(sendBtn, TweenInfo.new(0.18), {BackgroundColor3 = C.hot2}):Play() end)

-- ── Agent permissions ──────────────────────────────────────────────────
local AGENT_PERMISSIONS = {
  execution = true,  -- allow run_luau (terminal execution)
  autoRun = true,    -- automatically execute agent-generated scripts
  mutate = true,     -- allow set_property / create_instance / destroy_instance
}

local utilityRow = Instance.new("Frame")
utilityRow.Size = UDim2.new(1, -4, 0, 18)
utilityRow.Position = UDim2.new(0, 0, 1, -18)
utilityRow.BackgroundTransparency = 1
utilityRow.Parent = pz

local contextBtn = Instance.new("TextButton")
contextBtn.Size = UDim2.new(0, 150, 1, 0)
contextBtn.BackgroundTransparency = 1
contextBtn.Font = Enum.Font.Code
contextBtn.TextSize = 10
contextBtn.TextXAlignment = Enum.TextXAlignment.Left
contextBtn.TextColor3 = C.hot
contextBtn.Text = "● Selection: ON"
contextBtn.Parent = utilityRow

local autoRunBtn = Instance.new("TextButton")
autoRunBtn.Size = UDim2.new(0, 100, 1, 0)
autoRunBtn.Position = UDim2.new(0, 152, 0, 0)
autoRunBtn.BackgroundColor3 = Color3.fromRGB(48, 29, 79)
autoRunBtn.BorderSizePixel = 0
autoRunBtn.Font = Enum.Font.GothamSemibold
autoRunBtn.TextSize = 9
autoRunBtn.Text = "⚡ AUTO-RUN: ON"
autoRunBtn.TextColor3 = C.txt
autoRunBtn.Parent = utilityRow
Instance.new("UICorner", autoRunBtn).CornerRadius = UDim.new(0, 5)

local execBtn = Instance.new("TextButton")
execBtn.Size = UDim2.new(0, 80, 1, 0)
execBtn.Position = UDim2.new(0, 254, 0, 0)
execBtn.BackgroundColor3 = Color3.fromRGB(48, 29, 79)
execBtn.BorderSizePixel = 0
execBtn.Font = Enum.Font.GothamSemibold
execBtn.TextSize = 9
execBtn.Text = "▶ EXEC: ON"
execBtn.TextColor3 = C.txt
execBtn.Parent = utilityRow
Instance.new("UICorner", execBtn).CornerRadius = UDim.new(0, 5)

indexInfo = Instance.new("TextLabel")
indexInfo.Size = UDim2.new(1, -496, 1, 0)
indexInfo.Position = UDim2.fromOffset(336, 0)
indexInfo.BackgroundTransparency = 1
indexInfo.Font = Enum.Font.Code
indexInfo.TextSize = 9
indexInfo.TextXAlignment = Enum.TextXAlignment.Left
indexInfo.TextColor3 = C.dim
indexInfo.Text = "INDEX NOT BUILT"
indexInfo.Parent = utilityRow

local syncBtn = Instance.new("TextButton")
syncBtn.Size = UDim2.new(0, 88, 1, 0)
syncBtn.Position = UDim2.new(1, -154, 0, 0)
syncBtn.BackgroundColor3 = Color3.fromRGB(48, 29, 79)
syncBtn.BorderSizePixel = 0
syncBtn.Font = Enum.Font.GothamSemibold
syncBtn.TextSize = 9
syncBtn.Text = "SYNC DATA"
syncBtn.TextColor3 = C.txt
syncBtn.Parent = utilityRow
Instance.new("UICorner", syncBtn).CornerRadius = UDim.new(0, 5)

local clearBtn = Instance.new("TextButton")
clearBtn.Size = UDim2.new(0, 60, 1, 0)
clearBtn.Position = UDim2.new(1, -60, 0, 0)
clearBtn.BackgroundTransparency = 1
clearBtn.Font = Enum.Font.Code
clearBtn.TextSize = 10
clearBtn.Text = "CLEAR"
clearBtn.TextColor3 = C.dim
clearBtn.Parent = utilityRow

-- ── Cloud bridge (executor HTTP; provider keys stay on PRIMEz servers) ──
local function pulsarRequest(method, url, body)
  local req = request or http_request
  if not req and syn and type(syn.request) == "function" then req = syn.request end
  if type(req) ~= "function" then
    error("Executor HTTP is unavailable in this runtime.")
  end
  local options = {
    Url = url,
    Method = method,
    Headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" },
  }
  -- v23.4.1: 45 → 90 seconds. Render free-tier cold starts (~30-50s) plus a
  -- slow model request regularly exceeded 45s and the turn died with
  -- "Request failed" mid-task.
  pcall(function() options.TimeOut = 90 end)
  if body ~= nil then options.Body = HttpService:JSONEncode(body) end
  local response = req(options)
  if type(response) ~= "table" then error("Unexpected HTTP response.") end
  local code = tonumber(response.StatusCode or response.Status or 0) or 0
  local raw = response.Body or response.body or ""
  if code < 200 or code >= 300 then
    local detail = tostring(raw):sub(1, 220)
    error("PRIMEz returned HTTP " .. tostring(code) .. (detail ~= "" and (": " .. detail) or ""))
  end
  return raw
end

-- ── Path resolution ─────────────────────────────────────────────────────
local function resolvePath(input)
  if type(input) ~= "string" or input:match("^%s*$") then
    return nil, "path must be a non-empty string like 'Workspace.Baseplate'"
  end
  local raw = input:match("^%s*(.-)%s*$")
  raw = raw:gsub("^game%.", "")
  raw = raw:gsub("^%[", ""):gsub("%]$", "")
  local segments = {}
  for seg in raw:gmatch("[^.]+") do segments[#segments + 1] = seg end
  if #segments == 0 then return nil, "empty path" end
  local current
  local okService, service = pcall(function() return game:GetService(segments[1]) end)
  if okService and service then
    current = service
  else
    current = game:FindFirstChild(segments[1])
    if not current then return nil, ("unknown service or top-level '%s'"):format(segments[1]) end
  end
  for i = 2, #segments do
    local seg = segments[i]
    local okChild, child = pcall(function() return current:FindFirstChild(seg) end)
    if not okChild or not child then
      local okWait, waited = pcall(function() return current:WaitForChild(seg, 0.5) end)
      if not okWait or not waited then
        return nil, ("'%s' not found under %s"):format(seg, pathOf(current))
      end
      current = waited
    else
      current = child
    end
  end
  return current
end

-- ── Value coercion for set_property ────────────────────────────────────
local function coerceValue(raw)
  if type(raw) ~= "string" then return raw, true end
  local s = raw:match("^%s*(.-)%s*$")
  if s == "true" then return true, true end
  if s == "false" then return false, true end
  if s == "nil" then return nil, true end
  if s:match("^-?%d+%.?%d*$") then return tonumber(s), true end
  local vx, vy, vz = s:match("^Vector3%.new%(%s*(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)%s*%)$")
  if vx then return Vector3.new(tonumber(vx), tonumber(vy), tonumber(vz)), true end
  local r, g, b = s:match("^Color3%.fromRGB%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)$")
  if r then return Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b)), true end
  local inst = resolvePath(s)
  if inst then return inst, true end
  return s, true -- fall back to the raw string
end

-- ── Whole-game analysis (the agent's primary research tool) ────────────
local function buildGameAnalysis(scope)
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  add("PRIMEz TINYDEX v23 — FULL GAME ANALYSIS")
  add(("Place: %s  |  PlaceId: %s  |  JobId: %s"):format(tostring(game.Name), tostring(game.PlaceId), tostring(game.JobId)))
  add(("Runtime: %s / %s  |  WorkspaceStreaming: %s"):format(
    RunService:IsRunning() and "running" or "edit",
    RunService:IsClient() and "client" or "server",
    tostring(workspace.StreamingEnabled)))
  add("")
  add("== SERVICES ==")
  for _, service in ipairs(game:GetChildren()) do
    local ok, count = pcall(function()
      local n = 0
      for _ in ipairs(service:GetChildren()) do n += 1 end
      return n
    end)
    add(("- %s <%s> — %d direct children"):format(service.Name, service.ClassName, ok and count or -1))
  end
  add("")
  add("== PLAYERS ==")
  for _, player in ipairs(PlayersService:GetPlayers()) do
    add(("- %s (UserId %d)%s"):format(player.Name, player.UserId, player == plr and "  << LOCAL PLAYER" or ""))
    local character = player.Character
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    if character then
      local partCount = 0
      for _ in ipairs(character:GetChildren()) do partCount += 1 end
      add(("  Character '%s': Health=%s WalkSpeed=%s JumpPower=%s State=%s parts=%d"):format(
        character.Name,
        hum and tostring(hum.Health) or "?",
        hum and tostring(hum.WalkSpeed) or "?",
        hum and tostring(hum.JumpPower) or "?",
        hum and tostring(hum:GetState()) or "?",
        partCount))
    else
      add("  Character: none (not spawned)")
    end
  end
  add("")
  add("== REMOTES (client-visible, first 150) ==")
  local remoteCount = 0
  for _, service in ipairs(game:GetChildren()) do
    local ok, descendants = pcall(function() return service:GetDescendants() end)
    if ok and type(descendants) == "table" then
      local scannedHere = 0
      for _, inst in ipairs(descendants) do
        scannedHere += 1
        if scannedHere % 2000 == 0 then task.wait() end
        if scannedHere > 20000 then break end -- PERF: per-service scan cap
        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent") then
          remoteCount += 1
          if remoteCount <= 150 then
            add(("- %s <%s> @ %s"):format(inst.Name, inst.ClassName, pathOf(inst)))
          end
        end
      end
    end
    if remoteCount > 150 then break end
    task.wait()
  end
  add(("Total remotes found: %d%s"):format(remoteCount, remoteCount > 150 and " (list capped at 150)" or ""))
  for _, serviceName in ipairs({ "ReplicatedStorage", "ReplicatedFirst", "StarterPlayer", "StarterGui", "StarterPack", "Lighting", "Teams", "SoundService" }) do
    local ok, service = pcall(function() return game:GetService(serviceName) end)
    if ok and service then
      local kids = service:GetChildren()
      add("")
      add(("== %s (%d direct children) =="):format(service.Name, #kids))
      for i = 1, math.min(#kids, 60) do
        local k = kids[i]
        add(("- %s <%s>"):format(k.Name, k.ClassName))
      end
      if #kids > 60 then add(("... %d more"):format(#kids - 60)) end
    end
  end
  local cam = workspace.CurrentCamera
  if cam then
    add("")
    add(("== CAMERA == CFrame=%s FOV=%s Type=%s"):format(tostring(cam.CFrame), tostring(cam.FieldOfView), tostring(cam.CameraType)))
  end
  local wsKids = workspace:GetChildren()
  add("")
  add(("== WORKSPACE (%d direct children) =="):format(#wsKids))
  for i = 1, math.min(#wsKids, 60) do
    local k = wsKids[i]
    add(("- %s <%s>"):format(k.Name, k.ClassName))
  end
  if #wsKids > 60 then add(("... %d more"):format(#wsKids - 60)) end
  if scope == "deep" then
    add("")
    add("== FULL INSPECTION INDEX (deep mode) ==")
    add(rebuildInspectionIndex())
  end
  return table.concat(lines, "\n")
end

-- ── Tool registry ───────────────────────────────────────────────────────
local AGENT_TOOLS = {}
local function toolResult(ok, text) return { ok = ok, output = text } end

AGENT_TOOLS.analyze_game = {
  description = "Build a structured report of the whole game: services, players, characters, remotes, replicated content, camera, lighting, workspace. Use this FIRST when you need broad understanding. scope='deep' also appends the full instance index.",
  parameters = {
    type = "object",
    properties = { scope = { type = "string", description = "'summary' (default) or 'deep'" } },
  },
  run = function(args)
    return toolResult(true, buildGameAnalysis(args and args.scope))
  end,
}

-- ── v23.4: game identification + live web research ──────────────────────
local cachedGameInfo = nil
local function getGameInfo()
  if cachedGameInfo then return cachedGameInfo end
  local gameName = game.Name
  local creator = "?"
  local okP, info = pcall(function()
    return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
  end)
  if okP and type(info) == "table" then
    if type(info.Name) == "string" and info.Name ~= "" then gameName = info.Name end
    if type(info.Creator) == "table" then
      creator = tostring(info.Creator.Name or info.Creator.Id or "?")
    elseif info.Creator then
      creator = tostring(info.Creator)
    end
  end
  cachedGameInfo = { name = gameName, creator = creator, placeId = game.PlaceId }
  return cachedGameInfo
end

local function urlEncode(s)
  s = tostring(s or "")
  return (s:gsub("[^%w%-_%.%~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function urlDecode(s)
  s = tostring(s or ""):gsub("+", " ")
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function stripHtmlTags(s)
  s = tostring(s or "")
  s = s:gsub("<[^>]->", "")
  s = s:gsub("&amp;", "&"):gsub("&quot;", '"'):gsub("&#x27;", "'")
  s = s:gsub("&#39;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&nbsp;", " ")
  return s
end

AGENT_TOOLS.get_game_info = {
  description = "Identify the current game: real game name, place id, creator. The game name is also in the context. Call this when unsure which game you are in.",
  parameters = {
    type = "object",
    properties = {},
  },
  run = function()
    local g = getGameInfo()
    return toolResult(true, ("GAME: %s\nPLACE ID: %d\nJOB ID: %s\nCREATOR: %s"):format(
      g.name, g.placeId, tostring(game.JobId), g.creator))
  end,
}

AGENT_TOOLS.web_search = {
  description = "Search the internet (DuckDuckGo) for current information: this game's known scripts and features, recent updates, how a feature works. USE THIS FIRST for game-specific script requests — research what features exist for THIS game (e.g. '<game name> auto steal script roblox') before building.",
  parameters = {
    type = "object",
    properties = {
      query = { type = "string", description = "search keywords, e.g. 'Steal a Brainrot auto steal script roblox'" },
      count = { type = "number", description = "max results (default 6, max 10)" },
    },
    required = { "query" },
  },
  run = function(args)
    local query = tostring(args and args.query or "")
    if query:match("^%s*$") then return toolResult(false, "query is empty") end
    local maxResults = math.clamp(tonumber(args and args.count) or 6, 1, 10)
    local req = request or http_request
    if not req and syn and type(syn.request) == "function" then req = syn.request end
    if type(req) ~= "function" then
      return toolResult(false, "Executor HTTP unavailable — web_search needs an executor runtime.")
    end
    local function fetch(url)
      local body = ""
      local ok = pcall(function()
        local resp = req({
          Url = url,
          Method = "GET",
          Headers = {
            ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            ["Accept"] = "text/html",
          },
        })
        local code = tonumber(resp.StatusCode or resp.Status or 0) or 0
        if code < 200 or code >= 300 then error("HTTP " .. tostring(code)) end
        body = tostring(resp.Body or resp.body or "")
      end)
      return ok and body or ""
    end
    -- DuckDuckGo lite first (simple HTML), then the html endpoint as fallback.
    local html = fetch("https://lite.duckduckgo.com/lite/?q=" .. urlEncode(query))
    if html == "" then html = fetch("https://html.duckduckgo.com/html/?q=" .. urlEncode(query)) end
    if html == "" then
      return toolResult(false, "search request failed (blocked, offline, or no usable response)")
    end
    local results = {}
    for href, title in html:gmatch('<a[^>]-href="([^"]-uddg=[^"]-)"[^>]->(.-)</a>') do
      local link = href:match('uddg=([^&"]+)')
      results[#results + 1] = { title = stripHtmlTags(title), url = link and urlDecode(link) or "" }
    end
    local snippets = {}
    for snip in html:gmatch('class="result__snippet"[^>]->(.-)</a>') do snippets[#snippets + 1] = stripHtmlTags(snip) end
    for snip in html:gmatch('class="result%-snippet"[^>]->(.-)</[at][td]>') do snippets[#snippets + 1] = stripHtmlTags(snip) end
    if #results == 0 then
      return toolResult(false, "no results parsed (search page layout may have changed) — proceed with analyze_game + your own knowledge instead")
    end
    local out = { ("WEB SEARCH '%s' — top results:"):format(query) }
    for i = 1, math.min(maxResults, #results) do
      local r = results[i]
      local snip = (snippets[i] and snippets[i] ~= "") and snippets[i] or "(no snippet)"
      if #snip > 300 then snip = snip:sub(1, 300) .. "…" end
      out[#out + 1] = ("%d. %s\n   %s\n   %s"):format(i, r.title ~= "" and r.title or "(untitled)", snip, r.url)
    end
    return toolResult(true, table.concat(out, "\n"))
  end,
}

AGENT_TOOLS.inspect = {
  description = "Inspect one instance in depth: full readable properties, attributes, direct children. path like 'Workspace.Baseplate' or 'Players.LocalPlayer.Character.Humanoid'.",
  parameters = {
    type = "object",
    properties = { path = { type = "string" } },
    required = { "path" },
  },
  run = function(args)
    local inst, err = resolvePath(args and args.path)
    if not inst then return toolResult(false, "resolve failed: " .. tostring(err)) end
    local outLines = { ("INSTANCE: %s <%s>"):format(inst.Name, inst.ClassName), "PATH: " .. pathOf(inst), "PROPERTIES:" }
    for _, propertyName in ipairs(readableProperties(inst)) do
      local valueOk, value = pcall(function() return inst[propertyName] end)
      if valueOk then outLines[#outLines + 1] = "  " .. propertyName .. " = " .. valueToText(value) end
    end
    local okAttrs, attrs = pcall(function() return inst:GetAttributes() end)
    outLines[#outLines + 1] = "ATTRIBUTES:"
    if okAttrs and type(attrs) == "table" then
      local keys = {}
      for key in pairs(attrs) do keys[#keys + 1] = tostring(key) end
      table.sort(keys)
      for _, key in ipairs(keys) do
        local valueOk, value = pcall(function() return inst:GetAttribute(key) end)
        if valueOk then outLines[#outLines + 1] = "  " .. key .. " = " .. tostring(value) end
      end
      if #keys == 0 then outLines[#outLines + 1] = "  (none)" end
    else
      outLines[#outLines + 1] = "  (unavailable)"
    end
    local okKids, kids = pcall(function() return inst:GetChildren() end)
    outLines[#outLines + 1] = "DIRECT CHILDREN:"
    if okKids and type(kids) == "table" then
      outLines[#outLines + 1] = "  count: " .. #kids
      for i = 1, math.min(#kids, 50) do
        outLines[#outLines + 1] = ("  %d. %s <%s>"):format(i, kids[i].Name, kids[i].ClassName)
      end
      if #kids > 50 then outLines[#outLines + 1] = ("  ... %d more"):format(#kids - 50) end
    else
      outLines[#outLines + 1] = "  (unavailable)"
    end
    return toolResult(true, table.concat(outLines, "\n"))
  end,
}

AGENT_TOOLS.list_children = {
  description = "List the direct children of an instance (name, class, path). Bounded to 80.",
  parameters = {
    type = "object",
    properties = { path = { type = "string" }, includeDescendants = { type = "boolean" } },
    required = { "path" },
  },
  run = function(args)
    local inst, err = resolvePath(args and args.path)
    if not inst then return toolResult(false, "resolve failed: " .. tostring(err)) end
    if args and args.includeDescendants then
      local ok, descendants = pcall(function() return inst:GetDescendants() end)
      if not ok then return toolResult(false, "descendants unavailable") end
      local outLines = { ("DESCENDANTS OF %s (%d)"):format(pathOf(inst), #descendants) }
      for i = 1, math.min(#descendants, 120) do
        outLines[#outLines + 1] = ("  %s <%s>"):format(pathOf(descendants[i]), descendants[i].ClassName)
      end
      if #descendants > 120 then outLines[#outLines + 1] = ("  ... %d more"):format(#descendants - 120) end
      return toolResult(true, table.concat(outLines, "\n"))
    end
    local ok, kids = pcall(function() return inst:GetChildren() end)
    if not ok then return toolResult(false, "children unavailable") end
    local outLines = { ("CHILDREN OF %s (%d)"):format(pathOf(inst), #kids) }
    for i = 1, math.min(#kids, 80) do
      outLines[#outLines + 1] = ("  %d. %s <%s>"):format(i, kids[i].Name, kids[i].ClassName)
    end
    if #kids > 80 then outLines[#outLines + 1] = ("  ... %d more"):format(#kids - 80) end
    return toolResult(true, table.concat(outLines, "\n"))
  end,
}

AGENT_TOOLS.search_game = {
  description = "Search client-visible instances by name substring with an optional class filter. Bounded to 120 results.",
  parameters = {
    type = "object",
    properties = { query = { type = "string" }, class = { type = "string" } },
    required = { "query" },
  },
  run = function(args)
    local query = tostring(args and args.query or ""):lower()
    if query == "" then return toolResult(false, "query required") end
    local classFilter = args and args.class and tostring(args.class):lower() or nil
    local results, scanned = {}, 0
    for _, service in ipairs(game:GetChildren()) do
      local ok, descendants = pcall(function() return service:GetDescendants() end)
      if ok and type(descendants) == "table" then
        for _, inst in ipairs(descendants) do
          scanned += 1
          if scanned % 2000 == 0 then task.wait() end
          if scanned >= 20000 then break end -- PERF: per-service scan cap
          if #results < 120 then
            local name = tostring(inst.Name):lower()
            local className = tostring(inst.ClassName):lower()
            if name:find(query, 1, true) and (not classFilter or className:find(classFilter, 1, true)) then
              results[#results + 1] = pathOf(inst) .. "  <" .. inst.ClassName .. ">"
            end
          end
        end
      end
      if #results >= 120 then break end
      task.wait()
    end
    local text = ("SEARCH '%s' — %d matches (scanned %d instances):\n%s"):format(
      query, #results, scanned, table.concat(results, "\n"))
    if #results >= 120 then text = text .. "\n(result cap reached; refine the query)" end
    return toolResult(true, text)
  end,
}

AGENT_TOOLS.read_property = {
  description = "Read a single property of one instance. Returns the raw value as text.",
  parameters = {
    type = "object",
    properties = { path = { type = "string" }, property = { type = "string" } },
    required = { "path", "property" },
  },
  run = function(args)
    local inst, err = resolvePath(args and args.path)
    if not inst then return toolResult(false, "resolve failed: " .. tostring(err)) end
    local prop = args and args.property
    if type(prop) ~= "string" or prop == "" then return toolResult(false, "property required") end
    local ok, value = pcall(function() return inst[prop] end)
    if not ok then return toolResult(false, ("cannot read property '%s': %s"):format(prop, tostring(value))) end
    return toolResult(true, ("%s.%s = %s"):format(pathOf(inst), prop, valueToText(value)))
  end,
}

AGENT_TOOLS.get_selection = {
  description = "Get the instance currently selected in the TinyDex Explorer (full detail). No arguments.",
  parameters = { type = "object", properties = {} },
  run = function()
    if not selected then return toolResult(false, "nothing selected in the Explorer") end
    local outLines = { ("SELECTION: %s <%s>"):format(selected.Name, selected.ClassName), "PATH: " .. pathOf(selected) }
    for _, propertyName in ipairs(readableProperties(selected)) do
      local valueOk, value = pcall(function() return selected[propertyName] end)
      if valueOk then outLines[#outLines + 1] = "  " .. propertyName .. " = " .. valueToText(value) end
    end
    return toolResult(true, table.concat(outLines, "\n"))
  end,
}

AGENT_TOOLS.get_logs = {
  description = "Read recent client log messages (print/warn/error) from the game. count defaults to 25, max 200.",
  parameters = {
    type = "object",
    properties = { count = { type = "number" } },
  },
  run = function(args)
    local count = math.clamp(tonumber(args and args.count) or 25, 1, 200)
    local ok, history = pcall(function() return LogService:GetLogHistory() end)
    if not ok or type(history) ~= "table" then return toolResult(false, "log history unavailable") end
    local lines = {}
    local start = math.max(1, #history - count + 1)
    for i = start, #history do
      local entry = history[i]
      lines[#lines + 1] = ("[%s] %s"):format(tostring(entry and entry.MessageType), tostring(entry and entry.Message))
    end
    return toolResult(true, "RECENT LOGS:\n" .. table.concat(lines, "\n"))
  end,
}

AGENT_TOOLS.run_luau = {
  description = "Execute Luau code on the client through the TinyDex terminal and return captured output/errors. THIS IS THE PRIMARY ACTION TOOL: after analyzing the game and writing a script, run it here. If execution errors, read the output, fix the code, and run again.",
  parameters = {
    type = "object",
    properties = {
      code = { type = "string", description = "Complete, runnable Luau source code" },
      label = { type = "string", description = "Short name shown in the terminal, e.g. 'esp'" },
    },
    required = { "code" },
  },
  run = function(args)
    if not AGENT_PERMISSIONS.execution then
      return toolResult(false, "EXEC permission is OFF — enable the ▶ EXEC toggle in the PULSAR bar to allow code execution.")
    end
    local result = Terminal.exec(args and args.code, args and args.label or "PULSAR")
    local status = result.ok and "EXEC OK" or "EXEC FAILED"
    return toolResult(result.ok, ("%s in %d ms\n%s"):format(status, result.duration or 0, result.output))
  end,
}

AGENT_TOOLS.save_draft = {
  description = "Save Luau code into the WORKSPACE draft editor (does NOT execute it). Use when the user asked to review code before running, or alongside run_luau for later reuse.",
  parameters = {
    type = "object",
    properties = { code = { type = "string" } },
    required = { "code" },
  },
  run = function(args)
    if type(args and args.code) ~= "string" or args.code:match("^%s*$") then
      return toolResult(false, "code required")
    end
    editor.Text = args.code
    editorNote.Text = "Draft loaded by PULSAR. Run it from CONSOLE with `run`."
    editorNote.TextColor3 = C.good
    return toolResult(true, "draft saved to the WORKSPACE tab (" .. #args.code .. " chars)")
  end,
}

local PROTECTED_INSTANCES = {
  Workspace = true, Players = true, Lighting = true, ReplicatedStorage = true,
  ReplicatedFirst = true, StarterPlayer = true, StarterGui = true, StarterPack = true,
  Teams = true, SoundService = true, TeleportService = true, HttpService = true,
  ScriptContext = true, WorkspaceFluidForcesServiceInternal = true,
}

AGENT_TOOLS.set_property = {
  description = "Set a property on a client-visible instance. Values accept booleans, numbers, strings, Vector3.new(x,y,z), Color3.fromRGB(r,g,b), or an instance path. Requires MUTATE permission.",
  parameters = {
    type = "object",
    properties = { path = { type = "string" }, property = { type = "string" }, value = {} },
    required = { "path", "property" },
  },
  run = function(args)
    if not AGENT_PERMISSIONS.mutate then
      return toolResult(false, "MUTATE permission is OFF — cannot modify instances.")
    end
    local inst, err = resolvePath(args and args.path)
    if not inst then return toolResult(false, "resolve failed: " .. tostring(err)) end
    local prop = args and args.property
    if type(prop) ~= "string" or prop == "" then return toolResult(false, "property required") end
    if prop == "Parent" then return toolResult(false, "use create_instance/destroy_instance for reparenting") end
    local value, okCoerce = coerceValue(args and args.value)
    local ok, setErr = pcall(function() inst[prop] = value end)
    if not ok then return toolResult(false, ("set failed: %s"):format(tostring(setErr))) end
    local okRead, readBack = pcall(function() return inst[prop] end)
    return toolResult(true, ("set %s.%s = %s"):format(pathOf(inst), prop, okRead and valueToText(readBack) or "?"))
  end,
}

AGENT_TOOLS.create_instance = {
  description = "Create a new instance under a parent (client-side). Example: create a Highlight named 'PRIMEz_ESP' under Workspace. Requires MUTATE permission.",
  parameters = {
    type = "object",
    properties = {
      class = { type = "string" },
      name = { type = "string" },
      parentPath = { type = "string" },
      properties = { type = "object", description = "optional {property: value} map applied after creation" },
    },
    required = { "class", "parentPath" },
  },
  run = function(args)
    if not AGENT_PERMISSIONS.mutate then
      return toolResult(false, "MUTATE permission is OFF — cannot create instances.")
    end
    local parent, err = resolvePath(args and args.parentPath)
    if not parent then return toolResult(false, "resolve failed: " .. tostring(err)) end
    local class = args and args.class
    if type(class) ~= "string" or class == "" then return toolResult(false, "class required") end
    local okInst, inst = pcall(function() return Instance.new(class) end)
    if not okInst or not inst then return toolResult(false, ("cannot create class '%s'"):format(tostring(class))) end
    inst.Name = (args and args.name ~= "" and args.name) or class
    local okParent, parentErr = pcall(function() inst.Parent = parent end)
    if not okParent then
      pcall(function() inst:Destroy() end)
      return toolResult(false, ("parent failed: %s"):format(tostring(parentErr)))
    end
    local applied, failed = {}, {}
    if args and type(args.properties) == "table" then
      for prop, rawValue in pairs(args.properties) do
        local value = coerceValue(rawValue)
        local okSet, setErr = pcall(function() inst[prop] = value end)
        if okSet then applied[#applied + 1] = prop else failed[#failed + 1] = prop .. " (" .. tostring(setErr) .. ")" end
      end
    end
    local text = ("CREATED %s <%s> under %s"):format(inst.Name, inst.ClassName, pathOf(parent))
    if #applied > 0 then text = text .. " | set: " .. table.concat(applied, ", ") end
    if #failed > 0 then text = text .. " | failed: " .. table.concat(failed, ", ") end
    return toolResult(true, text)
  end,
}

AGENT_TOOLS.destroy_instance = {
  description = "Destroy a client-side instance by path. Core DataModel services are protected. Use responsibly; effects are client-side only. Requires MUTATE permission.",
  parameters = {
    type = "object",
    properties = { path = { type = "string" } },
    required = { "path" },
  },
  run = function(args)
    if not AGENT_PERMISSIONS.mutate then
      return toolResult(false, "MUTATE permission is OFF — cannot destroy instances.")
    end
    local inst, err = resolvePath(args and args.path)
    if not inst then return toolResult(false, "resolve failed: " .. tostring(err)) end
    if inst.Parent == game and PROTECTED_INSTANCES[inst.Name] then
      return toolResult(false, ("refusing to destroy protected service '%s'"):format(inst.Name))
    end
    if inst == gui or inst:IsDescendantOf(gui) then
      return toolResult(false, "refusing to destroy TinyDex's own UI")
    end
    local where = pathOf(inst)
    local ok, destroyErr = pcall(function() inst:Destroy() end)
    if not ok then return toolResult(false, ("destroy failed: %s"):format(tostring(destroyErr))) end
    return toolResult(true, "DESTROYED " .. where)
  end,
}

-- Schemas sent to the server with every request.
local TOOL_SCHEMAS = {}
for name, def in pairs(AGENT_TOOLS) do
  TOOL_SCHEMAS[#TOOL_SCHEMAS + 1] = {
    name = name,
    description = def.description,
    parameters = def.parameters,
  }
end
table.sort(TOOL_SCHEMAS, function(a, b) return a.name < b.name end)

local function dispatchTool(name, args)
  local def = AGENT_TOOLS[name]
  if not def then
    -- v23.4.1: weak models sometimes invent tool names (e.g. pul_search_info).
    -- Tell them exactly which tools are real so the next step corrects itself.
    local names = {}
    for realName in pairs(AGENT_TOOLS) do names[#names + 1] = realName end
    table.sort(names)
    return { ok = false, output = ("unknown tool '%s'. These are the ONLY real tools: %s. Re-issue the task using one of these."):format(tostring(name), table.concat(names, ", ")) }
  end
  if type(args) == "string" then
    local okDecode, decoded = pcall(function() return HttpService:JSONDecode(args) end)
    args = (okDecode and type(decoded) == "table") and decoded or { raw = args }
  end
  local ok, result = pcall(def.run, args)
  if not ok then
    return { ok = false, output = ("tool '%s' crashed: %s"):format(tostring(name), tostring(result)) }
  end
  if type(result) ~= "table" then
    return { ok = true, output = tostring(result) }
  end
  return result
end

-- ── Chat UI helpers ────────────────────────────────────────────────────
local conversation = {}
local includeSelection = true
local busy = false
-- v23.4: 8 → 24. The user wants the agent to keep going until the task is
-- actually DONE (research → analyze → build → execute → verify), not stop
-- mid-task. The v23.1 protections still apply (clipped history, capped
-- index, capped scans), so long turns can't drag huge payloads anymore.
local MAX_STEPS = 24

local function scrollFeed()
  task.defer(function()
    chatFeed.CanvasPosition = Vector2.new(0, math.max(0, feedLayout.AbsoluteContentSize.Y + 30))
  end)
end

local function addChatMessage(who, message, isError)
  local card = Instance.new("Frame")
  card.BackgroundColor3 = (who == "YOU") and Color3.fromRGB(31,35,47) or Color3.fromRGB(34,29,43)
  card.BorderSizePixel = 0
  card.Size = UDim2.new(1, -2, 0, 40)
  card.AutomaticSize = Enum.AutomaticSize.Y
  card.Parent = chatFeed
  Instance.new("UICorner", card).CornerRadius = UDim.new(0, 4)
  local name = Instance.new("TextLabel")
  name.Size = UDim2.new(1, -14, 0, 15)
  name.Position = UDim2.fromOffset(7, 4)
  name.BackgroundTransparency = 1
  name.Font = Enum.Font.GothamBold
  name.TextSize = 10
  name.TextXAlignment = Enum.TextXAlignment.Left
  name.TextColor3 = isError and C.bad or (who == "YOU" and C.hot or Color3.fromRGB(190,145,255))
  name.Text = who
  name.Parent = card
  local body = Instance.new("TextLabel")
  body.Size = UDim2.new(1, -14, 0, 0)
  body.Position = UDim2.fromOffset(7, 21)
  body.AutomaticSize = Enum.AutomaticSize.Y
  body.BackgroundTransparency = 1
  body.Font = Enum.Font.Gotham
  body.TextSize = 11
  body.TextWrapped = true
  body.TextXAlignment = Enum.TextXAlignment.Left
  body.TextYAlignment = Enum.TextYAlignment.Top
  body.TextColor3 = isError and C.bad or C.txt
  body.Text = tostring(message)
  body.Parent = card
  scrollFeed()
end

local function addToolChip(name, detail, ok)
  local chip = Instance.new("Frame")
  chip.BackgroundColor3 = Color3.fromRGB(24, 20, 38)
  chip.BorderSizePixel = 0
  chip.Size = UDim2.new(1, -2, 0, 24)
  chip.AutomaticSize = Enum.AutomaticSize.Y
  chip.Parent = chatFeed
  Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 4)
  local chipStroke = Instance.new("UIStroke", chip)
  chipStroke.Color = ok and C.line or C.bad
  chipStroke.Transparency = 0.4
  local icon = Instance.new("TextLabel")
  icon.Size = UDim2.new(0, 22, 0, 24)
  icon.Position = UDim2.fromOffset(6, 0)
  icon.BackgroundTransparency = 1
  icon.Font = Enum.Font.GothamBold
  icon.TextSize = 11
  icon.TextXAlignment = Enum.TextXAlignment.Left
  icon.TextYAlignment = Enum.TextYAlignment.Top
  icon.TextColor3 = ok and C.good or C.bad
  icon.Text = ok and "🔧" or "✖"
  icon.Parent = chip
  local label = Instance.new("TextLabel")
  label.Size = UDim2.new(1, -36, 0, 24)
  label.Position = UDim2.fromOffset(28, 0)
  label.BackgroundTransparency = 1
  label.Font = Enum.Font.Code
  label.TextSize = 10
  label.TextWrapped = true
  label.TextXAlignment = Enum.TextXAlignment.Left
  label.TextYAlignment = Enum.TextYAlignment.Top
  label.TextColor3 = ok and C.dim or C.bad
  label.Text = "TOOL " .. tostring(name) .. (detail and (" · " .. tostring(detail)) or "")
  label.Parent = chip
  scrollFeed()
end

local function copyToClipboard(text)
  local ok = pcall(function()
    if type(setclipboard) == "function" then setclipboard(text) return end
    if type(toclipboard) == "function" then toclipboard(text) return end
    local g = (type(getgenv) == "function") and getgenv() or nil
    if g and type(g.setclipboard) == "function" then g.setclipboard(text) return end
    error("no clipboard API in this runtime")
  end)
  if ok then flash("copied to clipboard", C.good) else showTextExport("Copy script manually", text) end
end

local function addScriptCard(title, code)
  local card = Instance.new("Frame")
  card.BackgroundColor3 = Color3.fromRGB(16, 14, 28)
  card.BorderSizePixel = 0
  card.Size = UDim2.new(1, -2, 0, 0)
  card.AutomaticSize = Enum.AutomaticSize.Y
  card.Parent = chatFeed
  Instance.new("UICorner", card).CornerRadius = UDim.new(0, 4)
  local cardStroke = Instance.new("UIStroke", card)
  cardStroke.Color = C.hot2
  cardStroke.Transparency = 0.3
  local header = Instance.new("Frame")
  header.Size = UDim2.new(1, -8, 0, 24)
  header.Position = UDim2.fromOffset(4, 4)
  header.BackgroundTransparency = 1
  header.Parent = card
  local titleText = Instance.new("TextLabel")
  titleText.Size = UDim2.new(1, -150, 1, 0)
  titleText.BackgroundTransparency = 1
  titleText.Font = Enum.Font.GothamBold
  titleText.TextSize = 10
  titleText.TextXAlignment = Enum.TextXAlignment.Left
  titleText.TextColor3 = Color3.fromRGB(190,145,255)
  titleText.Text = "📜 " .. tostring(title) .. "  (" .. #code .. " chars)"
  titleText.Parent = header
  local runBtn = Instance.new("TextButton")
  runBtn.Size = UDim2.new(0, 66, 0, 22)
  runBtn.Position = UDim2.new(1, -146, 0, 1)
  runBtn.BackgroundColor3 = C.hot2
  runBtn.BorderSizePixel = 0
  runBtn.Font = Enum.Font.GothamBold
  runBtn.TextSize = 9
  runBtn.Text = "▶ RUN"
  runBtn.TextColor3 = Color3.new(1, 1, 1)
  runBtn.Parent = header
  Instance.new("UICorner", runBtn).CornerRadius = UDim.new(0, 5)
  local copyBtn = Instance.new("TextButton")
  copyBtn.Size = UDim2.new(0, 66, 0, 22)
  copyBtn.Position = UDim2.new(1, -74, 0, 1)
  copyBtn.BackgroundColor3 = Color3.fromRGB(48, 29, 79)
  copyBtn.BorderSizePixel = 0
  copyBtn.Font = Enum.Font.GothamBold
  copyBtn.TextSize = 9
  copyBtn.Text = "⧉ COPY"
  copyBtn.TextColor3 = C.txt
  copyBtn.Parent = header
  Instance.new("UICorner", copyBtn).CornerRadius = UDim.new(0, 5)
  local codeBox = Instance.new("TextBox")
  codeBox.Size = UDim2.new(1, -12, 0, 0)
  codeBox.Position = UDim2.fromOffset(6, 30)
  codeBox.AutomaticSize = Enum.AutomaticSize.Y
  codeBox.BackgroundColor3 = Color3.fromRGB(10, 9, 18)
  codeBox.BorderSizePixel = 0
  codeBox.Font = Enum.Font.Code
  codeBox.TextSize = 10
  codeBox.TextEditable = false
  codeBox.MultiLine = true
  codeBox.TextWrapped = true
  codeBox.TextXAlignment = Enum.TextXAlignment.Left
  codeBox.TextYAlignment = Enum.TextYAlignment.Top
  codeBox.TextColor3 = C.txt
  codeBox.Text = code
  codeBox.Parent = card
  Instance.new("UICorner", codeBox).CornerRadius = UDim.new(0, 5)
  local codePad = Instance.new("UIPadding", codeBox)
  codePad.PaddingTop = UDim.new(0, 6)
  codePad.PaddingBottom = UDim.new(0, 6)
  codePad.PaddingLeft = UDim.new(0, 8)
  codePad.PaddingRight = UDim.new(0, 8)
  runBtn.MouseButton1Click:Connect(function()
    local result = Terminal.exec(code, title)
    if result.ok then flash(("ran '%s' · %d ms"):format(title, result.duration), C.good)
    else flash(("run failed: %s"):format(tostring(result.output):sub(1, 120)), C.bad) end
  end)
  copyBtn.MouseButton1Click:Connect(function() copyToClipboard(code) end)
  scrollFeed()
end

-- Extract fenced ```lua blocks from a reply so they render as script cards.
local function renderReply(reply)
  if type(reply) ~= "string" or reply == "" then return end
  local chunks = {}
  local start = 1
  while true do
    local a = reply:find("```", start, true)
    if not a then
      chunks[#chunks + 1] = { text = reply:sub(start) }
      break
    end
    chunks[#chunks + 1] = { text = reply:sub(start, a - 1) }
    local b = reply:find("```", a + 3, true)
    if not b then
      chunks[#chunks + 1] = { code = reply:sub(a + 3) }
      break
    end
    chunks[#chunks + 1] = { code = reply:sub(a + 3, b - 1) }
    start = b + 3
  end
  local cardIndex = 1
  for _, chunk in ipairs(chunks) do
    if chunk.code then
      local code = chunk.code
      local firstLineEnd = code:find("\n", 1, true)
      local firstLine = firstLineEnd and code:sub(1, firstLineEnd - 1) or ""
      local lang = firstLine:match("^%s*(%a+)")
      local title = nil
      if lang and (lang:lower() == "lua" or lang:lower() == "luau") then
        code = code:sub(firstLineEnd + 1)
      else
        title = firstLine:match("^@?(%S[%w _%-]*)")
      end
      code = code:gsub("^%s*\n", ""):gsub("\n%s*$", "")
      if code:match("%S") then
        addScriptCard(title or ("script " .. cardIndex), code)
        cardIndex += 1
      end
    elseif chunk.text and chunk.text:match("%S") then
      addChatMessage("PULSAR", chunk.text)
    end
  end
end

-- ── v22 bug fix: detect leaked raw tool_calls JSON inside a reply ──────
local function extractLeakedToolCalls(reply)
  if type(reply) ~= "string" then return nil end
  local probe = reply:match("%b{}")
  if not probe or not probe:find("tool_calls", 1, true) then return nil end
  local okDecode, decoded = pcall(function() return HttpService:JSONDecode(probe) end)
  if not okDecode or type(decoded) ~= "table" or type(decoded.tool_calls) ~= "table" then return nil end
  return decoded.tool_calls
end

-- ── Text tool protocol (works with any backend, including the current ──
-- PRIMEz passthrough): the model asks for tools with plain lines like
-- TOOL_CALL {"id":"c1","tool":"run_luau","args":{"code":"print('hi')"}}
-- and the client executes them locally and returns TOOL_RESULT blocks.
local function parseTextToolCalls(reply)
  if type(reply) ~= "string" then return nil end
  local calls = {}
  for line in reply:gmatch("[^\r\n]+") do
    local payload = line:match("^%s*TOOL_CALL%s+(%b{})%s*$")
    if payload then
      local okDecode, decoded = pcall(function() return HttpService:JSONDecode(payload) end)
      if okDecode and type(decoded) == "table" and type(decoded.tool or decoded.name) == "string" then
        calls[#calls + 1] = {
          id = tostring(decoded.id or ("t" .. #calls + 1)),
          name = tostring(decoded.tool or decoded.name),
          args = decoded.args or decoded.arguments or {},
        }
      end
    end
  end
  if #calls == 0 then return nil end
  return calls
end

-- ── System context (agentic product knowledge) ─────────────────────────
local PULSAR_SYSTEM = [[
IDENTITY
You are PULSAR AGENT, the built-in AI SCRIPT BUILDER of PRIMEz Studios TinyDex v23 (Full Scripts Client). You are not a chatbot and not a tutor: you are a script BUILDER, judged ONLY by whether the scripts you deliver actually RUN in the live game. Analysis and research are only means to that end — the finished product is a working, EXECUTED script.

OFFICIAL PRIMEz REFERENCE
PRIMEz Studios: https://primez-studios.onrender.com/
You may give the user this link. Do not claim you browsed the live site.

YOUR TOOLS (real, executed by the TinyDex client)
- analyze_game (scope: summary|deep): structured whole-game report — services, players, characters, remotes, replicated content, camera, lighting, workspace. Call this FIRST for any broad request or when you have not analyzed the game yet in this conversation.
- inspect(path), list_children(path), search_game(query, class?), read_property(path, property), get_selection()
- run_luau(code, label?): EXECUTES Luau in the TinyDex terminal and returns real output/errors. PRIMARY ACTION TOOL.
- save_draft(code): places code in the WORKSPACE draft editor for the user to review/run later.
- set_property(path, property, value), create_instance(class, name?, parentPath, properties?), destroy_instance(path)
- get_game_info(): real game name, place id, creator — identifies the game you are in.
- web_search(query, count?): searches the internet (DuckDuckGo) for current info about this game's scripts, features and updates.
- get_logs(count?): recent client logs — use it after run_luau to verify behavior.

AGENT WORKFLOW (follow strictly)
1. UNDERSTAND the request. If the request involves the game's structure, characters, remotes, UI, or anything you have not verified yet, call analyze_game first.
2. RESEARCH with targeted tools (inspect / search_game / list_children) until you have concrete evidence — names, classes, paths.
3. BUILD a COMPLETE, runnable Luau script. No placeholders, no TODOs, no pseudo-code. Client-side effects only.
4. EXECUTE it with run_luau. AUTO-RUN is enabled by default: the user wants scripts executed automatically in the terminal. Always run what you build unless the user explicitly asked to only review code (then use save_draft).
5. VERIFY: read the run_luau output and get_logs. If execution failed, FIX the code and run again — up to 3 fix attempts per script.
6. REPORT: finish with a short summary — what you analyzed, what you built, whether it ran, output highlights, and how to stop or tweak it (e.g. a toggle the script exposes).

GAME SCRIPT WORKFLOW (when the user asks for a script for THIS game)
1. IDENTIFY the game: the CURRENT GAME name is already in the context — do NOT call get_game_info for this, it is free information.
2. RESEARCH (OPTIONAL, at most ONE web_search): a single "<game name> script features" search is enough. If it fails or looks slow, SKIP research entirely.
3. ANALYZE the live game with analyze_game scope='summary' (go deep ONLY if the summary is clearly insufficient to build the script).
4. BUILD and EXECUTE immediately after the analysis.
SCRIPT TYPES users ask for: auto-steal (steal-style games), autofarm / auto-collect, auto-buy / shop, movement (speed, fly, infinite jump), teleport, ESP / visuals (players, items, bases), anti-AFK, GUI hub menus, remote tools, lag tools, and game-specific mixes. Pick the feature set that matches the request.

SPEED RULES (the user's #1 requirement — a delivered script in under 5 minutes)
- Every step is a model round trip and costs real time. FINISH IN 8 STEPS OR FEWER whenever possible.
- LEAN PATH: (game name is free in context) → at most 1 web_search → 1 summary analyze → build → run_luau once → fix max 2 times → short report.
- Do NOT narrate, restate plans, or summarize progress between steps. Tool calls only while working.
- Do NOT verify with extra steps unless run_luau errored. A delivered working script beats a fully researched one — when in doubt, BUILD.
- NEVER announce a script without delivering it: if you write "here is the script", the COMPLETE ```lua code MUST be in that SAME reply. Once you give your final answer the turn ENDS — you cannot add anything after it, so finish the whole task first.

WORKING SCRIPT STANDARD (how you are judged)
- You are judged ONLY by whether the delivered script RUNS. Not by research quality, not by explanation length.
- A script "works" ONLY after run_luau returns EXEC OK. Before that it is UNVERIFIED — never call it working.
- If run_luau fails, FIX the code and run again — up to 3 attempts. Only give up after 3 real failures, and then say exactly what error you could not fix.
- Your FINAL reply must state: SCRIPT RUNNING ✓ or ✗, and how to toggle/stop the script (e.g. a keybind or button it creates).
- NO RANDOM OUTPUT: when a script was requested, do NOT reply with tutorials, "here are some ideas", safety lectures, general game info, or multi-topic answers. Either build and deliver the script, or state precisely what evidence you still need to build it.
- Stay ON-TARGET: if the user asked for auto-steal, deliver auto-steal. Do not add unrelated features the user never asked for.

SCRIPT RULES
- Complete runnable Luau; correct service usage (game:GetService); wrap risky operations in pcall.
- Scripts that create loops, connections, or GUIs must be re-runnable: destroy/clean up anything they previously created (name your objects, keep a state table), and expose a simple stop mechanism.
- Never hard-crash the client: avoid infinite tight loops without task.wait().
- Target the LOCAL client only. Do not attempt to touch server-only instances or other players' clients.
- Respect tool results as ground truth: never claim something ran unless run_luau returned success.

RESPONSE FORMAT
- While working: request tools through the tool_calls mechanism. Do not narrate more than one short sentence per step.
- TOOL LINE FALLBACK (use this when the tool_calls mechanism is not active on this connection): request tools by emitting plain lines, one per line, as your ENTIRE reply — the TinyDex client executes them locally and returns TOOL_RESULT blocks:
TOOL_CALL {"id":"c1","tool":"analyze_game","args":{"scope":"summary"}}
TOOL_CALL {"id":"c2","tool":"run_luau","args":{"code":"print('hi')"}}
Tool names: analyze_game, inspect, list_children, search_game, read_property, get_selection, get_logs, get_game_info, web_search, run_luau, save_draft, set_property, create_instance, destroy_instance. While tool results are pending, emit nothing except TOOL_CALL lines. After TOOL_RESULT blocks arrive, continue with more TOOL_CALL lines or give the final answer as plain text with NO TOOL_CALL lines.
- Final answer: plain text with ```lua fenced blocks for any script code (they render as RUN/COPY cards). Keep it concise and practical.
- Never mention model vendors, provider names, routing vendors, or infrastructure labels.
- Never fabricate tool results or capabilities. If a tool fails, say what failed and adapt.
]]

local function buildContext(userPrompt)
  local parts = {
    "CURRENT PRODUCT: PRIMEz Studios TinyDex v23 (Full Scripts Client, agent mode)",
    "OFFICIAL SITE: https://primez-studios.onrender.com/",
    ("CURRENT GAME: %s (PlaceId %d) — use this game name when researching or building game scripts"):format(getGameInfo().name, game.PlaceId),
    "AGENT SYSTEM PROMPT:",
    PULSAR_SYSTEM,
    "",
    "TOOL EXECUTION RULES",
    "- Tools execute on the live client; role='tool' messages in the history are their real results.",
    "- exec permission: " .. (AGENT_PERMISSIONS.execution and "ON (run_luau allowed)" or "OFF (run_luau will be refused)"),
    "- auto-run expectation: " .. (AGENT_PERMISSIONS.autoRun and "user wants generated scripts executed automatically" or "user reviews scripts before running"),
    "- mutate permission: " .. (AGENT_PERMISSIONS.mutate and "ON" or "OFF"),
    "- luau execution runtime: " .. (Terminal.available and "executor with loadstring (execution supported)" or "no loadstring (execution unavailable; save_draft only)"),
  }

  local explicitTarget = nil
  if type(userPrompt) == "string" and userPrompt ~= "" then
    local matchTarget = userPrompt:match("[Ii]nspect%s+([%w_%.]+)")
      or userPrompt:match("[Cc]heck%s+([%w_%.]+)")
      or userPrompt:match("[Ss]how%s+([%w_%.]+)")
    if matchTarget then explicitTarget = resolveTarget(matchTarget) end
    if not explicitTarget then
      for _, sName in ipairs(KNOWN_SERVICES) do
        if userPrompt:lower():find(sName:lower(), 1, true) then
          explicitTarget = resolveTarget(sName)
          if explicitTarget then break end
        end
      end
    end
  end

  local targetInst = explicitTarget or (includeSelection and selected or nil)
  if targetInst then
    table.insert(parts, "CURRENT TARGET / SELECTED INSTANCE:")
    table.insert(parts, ("Name: %s | Class: %s | Path: %s"):format(
      tostring(targetInst.Name), tostring(targetInst.ClassName), tostring(pathOf(targetInst))))
    local okKids, kids = pcall(function() return targetInst:GetChildren() end)
    if okKids and type(kids) == "table" then
      local childNames = {}
      for i = 1, math.min(#kids, 20) do
        childNames[#childNames + 1] = kids[i].Name .. " <" .. kids[i].ClassName .. ">"
      end
      table.insert(parts, "First children: " .. (#childNames > 0 and table.concat(childNames, ", ") or "(none)"))
    end
  elseif includeSelection then
    table.insert(parts, "LIVE SELECTION: none. Tip: select an instance in Explorer, or use the inspect/analyze_game tools.")
  else
    table.insert(parts, "LIVE SELECTION: disabled by user.")
  end

  return table.concat(parts, "\n\n")
end

local function refreshPulsarStatus()
  task.spawn(function()
    local ok, raw = pcall(pulsarRequest, "GET", PRIMEZ .. "api/ai/status")
    if ok then
      local decodedOk, data = pcall(function() return HttpService:JSONDecode(raw) end)
      if decodedOk and data and data.available then
        pzStatus.Text = "● PULSAR ONLINE — agent tools armed"
        pzStatus.TextColor3 = C.good
      else
        pzStatus.Text = "● PRIMEz replied, but AI status was unexpected"
        pzStatus.TextColor3 = C.bad
      end
    else
      pzStatus.Text = "● Offline / HTTP unavailable: " .. tostring(raw):sub(1, 80)
      pzStatus.TextColor3 = C.bad
    end
  end)
end

local function trimConversation()
  -- v23.4.2: 40 → 28 messages — smaller payloads get faster model responses.
  while #conversation > 28 do table.remove(conversation, 1) end
end

-- PERF: tool outputs can be huge (deep analyze_game / long terminal logs).
-- Cap what goes into history so every later agent request stays small and
-- fast (free providers choke on megabyte payloads; also respects the 2mb limit).
local HISTORY_TOOL_RESULT_LIMIT = 6000
local function clipForHistory(text)
  text = tostring(text or "")
  if #text <= HISTORY_TOOL_RESULT_LIMIT then return text end
  return text:sub(1, HISTORY_TOOL_RESULT_LIMIT)
    .. ("\n…[TRUNCATED for history: first %d of %d chars kept]"):format(HISTORY_TOOL_RESULT_LIMIT, #text)
end

-- ── The agent loop ──────────────────────────────────────────────────────
-- v23.4.3: live heartbeat. The status line only refreshed BETWEEN steps, so
-- during a long model request (up to 90s x 3 attempts) it froze at
-- "STEP 1/24 - 0:00" and PULSAR looked dead while still working. This loop
-- refreshes the status every second while a turn is active.
local agentRuntime = { active = false, step = 0, stepT0 = 0, turnT0 = 0, tools = 0, note = "working…" }
task.spawn(function()
  while true do
    if agentRuntime.active then
      local el = os.clock() - agentRuntime.stepT0
      pzStatus.Text = ("● STEP %d/%d · this step %d:%02d · tools: %d · %s"):format(
        agentRuntime.step, MAX_STEPS, math.floor(el / 60), math.floor(el % 60), agentRuntime.tools, agentRuntime.note)
      pzStatus.TextColor3 = C.dim
    end
    task.wait(1)
  end
end)

local function runAgentTurn(userPrompt)
  local toolUses = 0
  for step = 1, MAX_STEPS do
    agentRuntime.active = true
    agentRuntime.step = step
    agentRuntime.stepT0 = os.clock()
    if step == 1 then agentRuntime.turnT0 = agentRuntime.stepT0 end
    agentRuntime.tools = toolUses
    agentRuntime.note = "working…"
    -- v23.4.1: retry failed requests. The free-tier provider fails
    -- intermittently (rate limits / generic "Something went wrong" errors)
    -- and the Render server cold-starts after idle — one bad request used
    -- to kill the whole turn. Now: 3 attempts with waits between them.
    local ok, raw = false, nil
    for attempt = 1, 3 do
      if attempt > 1 then
        agentRuntime.note = ("retrying after request error (attempt %d/3)…"):format(attempt)
        task.wait(attempt == 2 and 3 or 6)
      end
      ok, raw = pcall(pulsarRequest, "POST", PRIMEZ .. "api/ai/chat", {
        agent = true,
        step = step,
        tools = TOOL_SCHEMAS,
        context = buildContext(userPrompt),
        messages = conversation,
      })
      if ok then break end
    end
    if not ok then
      addChatMessage("CONNECTION ERROR", tostring(raw) .. "\n\n3 attempts failed. If the PRIMEz server was idle (free-tier cold start), wait ~1 minute, then say 'continue' — I'll resume exactly where I stopped.", true)
      agentRuntime.active = false
      pzStatus.Text = "● Request failed (3 attempts)"
      pzStatus.TextColor3 = C.bad
      return false
    end
    local decodedOk, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not decodedOk or type(data) ~= "table" then
      addChatMessage("CONNECTION ERROR", "Invalid response from PRIMEz AI (not JSON).", true)
      return false
    end
    if data.success == false then
      addChatMessage("PRIMEz ERROR", tostring(data.error or "unknown error"), true)
      return false
    end

    -- New contract: explicit tool_calls round.
    if type(data.tool_calls) == "table" and #data.tool_calls > 0 then
      if type(data.reply) == "string" and data.reply:match("%S") then
        addChatMessage("PULSAR", data.reply)
      end
      for _, call in ipairs(data.tool_calls) do
        local callId = tostring(call and call.id or ("call_" .. step .. "_" .. toolUses))
        local name = tostring(call and call.name or "?")
        local args = call and call.args or call and call.arguments or {}
        local result = dispatchTool(name, args)
        toolUses += 1
        local summary = tostring(result.output or "")
        if #summary > 90 then summary = summary:sub(1, 90) .. "…" end
        summary = summary:gsub("[\r\n]+", " ")
        addToolChip(name, summary, result.ok)
        conversation[#conversation + 1] = {
          role = "tool",
          tool_call_id = callId,
          name = name,
          arguments = args,
          content = clipForHistory(result.output),
        }
        -- Auto-run companion: if the agent wrote a script but only saved it as
        -- a draft while AUTO-RUN is ON, run it through the terminal as well.
        if name == "save_draft" and AGENT_PERMISSIONS.autoRun and AGENT_PERMISSIONS.execution and result.ok then
          local draft = editor.Text or ""
          if not draft:match("^%s*$") then
            addToolChip("auto_run", "AUTO-RUN executing saved draft (" .. #draft .. " chars)", true)
            local runResult = Terminal.exec(draft, "PULSAR auto-run")
            conversation[#conversation + 1] = {
              role = "tool",
              tool_call_id = callId .. "_autorun",
              name = "run_luau",
              arguments = { code = (#draft > 6000) and (draft:sub(1, 6000) .. "\n--[[ code truncated for history ]]") or draft },
              content = clipForHistory(("AUTO-RUN of saved draft — EXEC %s in %d ms\n%s"):format(
                runResult.ok and "OK" or "FAILED", runResult.duration or 0, runResult.output)),
            }
          end
        end
      end
      trimConversation()
      task.wait(0.1)
    else
      -- Final reply (done=true) or legacy response.
      local reply = (type(data.reply) == "string") and data.reply or nil
      if not reply then
        addChatMessage("CONNECTION ERROR", "PRIMEz AI returned no reply and no tool calls.", true)
        return false
      end
      -- Text tool protocol (current PRIMEz backend): the model asks for
      -- tools via TOOL_CALL lines; execute them and feed results back.
      local textCalls = parseTextToolCalls(reply)
      -- v22 bug fix: a backend that leaks raw tool_calls JSON inside `reply`.
      local leaked = extractLeakedToolCalls(reply)
      if textCalls then
        local parts = {}
        for _, call in ipairs(textCalls) do
          local result = dispatchTool(call.name, call.args)
          toolUses += 1
          local summary = tostring(result.output or ""):gsub("[\r\n]+", " ")
          if #summary > 90 then summary = summary:sub(1, 90) .. "…" end
          addToolChip(call.name, summary, result.ok)
          parts[#parts + 1] = ("TOOL_RESULT %s (%s)\n%s"):format(call.id, call.name, clipForHistory(result.output))
        end
        parts[#parts + 1] = "Tool results above are live facts from the client. Continue: emit more TOOL_CALL lines if needed, otherwise give the final answer as plain text with NO TOOL_CALL lines."
        conversation[#conversation + 1] = { role = "assistant", content = reply }
        conversation[#conversation + 1] = { role = "user", content = table.concat(parts, "\n\n") }
        trimConversation()
        task.wait(0.1)
      elseif leaked then
        addChatMessage("PULSAR", "The PRIMEz backend sent raw tool calls inside the reply text (v22 bug detected). Executing them anyway…", true)
        for _, call in ipairs(leaked) do
          local callId = tostring(call and call.id or ("leaked_" .. toolUses))
          local name = tostring(call and call.name or "?")
          local args = call and call.args or call and call.arguments or {}
          local result = dispatchTool(name, args)
          toolUses += 1
          local summary = tostring(result.output or ""):gsub("[\r\n]+", " ")
          if #summary > 90 then summary = summary:sub(1, 90) .. "…" end
          addToolChip(name, summary, result.ok)
          conversation[#conversation + 1] = {
            role = "tool",
            tool_call_id = callId,
            name = name,
            arguments = args,
            content = clipForHistory(result.output),
          }
        end
        trimConversation()
        task.wait(0.1)
      else
        conversation[#conversation + 1] = { role = "assistant", content = reply }
        trimConversation()
        renderReply(reply)
        -- v23.4.4: mechanical guarantee — if the final reply delivered lua
        -- code and auto-run + exec are ON, execute the largest block and
        -- report EXEC OK/FAILED, so the user always knows if it really runs.
        if AGENT_PERMISSIONS.autoRun and AGENT_PERMISSIONS.execution then
          local blocks, pos = {}, 1
          while true do
            local a = reply:find("```", pos, true)
            if not a then break end
            local b = reply:find("```", a + 3, true)
            if not b then break end
            local code = reply:sub(a + 3, b - 1)
            local nl = code:find("\n", 1, true)
            local first = nl and code:sub(1, nl - 1) or ""
            local lang = first:match("^%s*(%a+)")
            if lang and (lang:lower() == "lua" or lang:lower() == "luau") then
              code = nl and code:sub(nl + 1) or code
            end
            code = code:gsub("^%s*\n", ""):gsub("\n%s*$", "")
            if code:match("%S") then blocks[#blocks + 1] = code end
            pos = b + 3
          end
          if #blocks > 0 then
            local best = blocks[1]
            for i = 2, #blocks do
              if #blocks[i] > #best then best = blocks[i] end
            end
            local result = Terminal.exec(best, "PULSAR delivery check")
            if result.ok then
              addChatMessage("PULSAR", "✅ DELIVERED SCRIPT RUNNING — auto-executed the final script (" .. #best .. " chars, " .. result.duration .. " ms). Use the script's own toggle/keybind to stop it, or re-run it to clean up.")
            else
              addChatMessage("PULSAR", "❌ DELIVERED SCRIPT FAILED — " .. tostring(result.output):sub(1, 200))
            end
          end
        end
        agentRuntime.active = false
        local turnSecs = math.floor(os.clock() - agentRuntime.turnT0)
        pzStatus.Text = ("● AGENT DONE · %d tool uses · %d:%02d · ready"):format(toolUses, math.floor(turnSecs / 60), turnSecs % 60)
        pzStatus.TextColor3 = C.good
        return true
      end
    end
  end
  addChatMessage("PULSAR", ("I used all %d automatic agent steps this turn and the task is still not finished. Say 'continue' and I will pick up exactly where I stopped and finish it."):format(MAX_STEPS))
  agentRuntime.active = false
  pzStatus.Text = "● Step budget used — say continue"
  pzStatus.TextColor3 = C.dim
  return true
end

local pendingPrompt = nil
local function sendPulsar()
  if busy then
    -- v23.4.3: messages typed while PULSAR is working were silently
    -- swallowed (looked dead). Queue them instead and auto-send when the
    -- current task finishes.
    local queued = promptBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
    if queued ~= "" then
      pendingPrompt = queued
      promptBox.Text = ""
      flash("queued — PULSAR will run it when the current task finishes", C.dim)
    end
    return
  end
  local prompt = promptBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
  if prompt == "" then return end
  promptBox.Text = ""
  busy = true
  sendBtn.Text = "..."
  sendBtn.AutoButtonColor = false
  table.insert(conversation, { role = "user", content = prompt })
  addChatMessage("YOU", prompt)
  task.spawn(function()
    local ok = pcall(runAgentTurn, prompt)
    if not ok then addChatMessage("AGENT ERROR", "The agent loop crashed unexpectedly.", true) end
    agentRuntime.active = false
    busy = false
    sendBtn.Text = "SEND"
    sendBtn.AutoButtonColor = true
    -- v23.4.3: auto-send the queued message (if any) now that we're free.
    if pendingPrompt then
      local nextPrompt = pendingPrompt
      pendingPrompt = nil
      task.wait(0.5)
      promptBox.Text = nextPrompt
      sendPulsar()
    end
  end)
end

sendBtn.MouseButton1Click:Connect(sendPulsar)
promptBox.FocusLost:Connect(function(enterPressed)
  if enterPressed then sendPulsar() end
end)

contextBtn.MouseButton1Click:Connect(function()
  includeSelection = not includeSelection
  contextBtn.Text = includeSelection and "● Selection: ON" or "○ Selection: OFF"
  contextBtn.TextColor3 = includeSelection and C.hot or C.dim
end)

execBtn.MouseButton1Click:Connect(function()
  AGENT_PERMISSIONS.execution = not AGENT_PERMISSIONS.execution
  execBtn.Text = AGENT_PERMISSIONS.execution and "▶ EXEC: ON" or "▶ EXEC: OFF"
  execBtn.BackgroundColor3 = AGENT_PERMISSIONS.execution and Color3.fromRGB(48, 29, 79) or Color3.fromRGB(40, 40, 48)
  flash("agent execution " .. (AGENT_PERMISSIONS.execution and "enabled" or "disabled"), AGENT_PERMISSIONS.execution and C.good or C.bad)
end)

autoRunBtn.MouseButton1Click:Connect(function()
  AGENT_PERMISSIONS.autoRun = not AGENT_PERMISSIONS.autoRun
  autoRunBtn.Text = AGENT_PERMISSIONS.autoRun and "⚡ AUTO-RUN: ON" or "⚡ AUTO-RUN: OFF"
  autoRunBtn.BackgroundColor3 = AGENT_PERMISSIONS.autoRun and Color3.fromRGB(48, 29, 79) or Color3.fromRGB(40, 40, 48)
  flash("auto-run " .. (AGENT_PERMISSIONS.autoRun and "enabled" or "disabled"), AGENT_PERMISSIONS.autoRun and C.good or C.bad)
end)

syncBtn.MouseButton1Click:Connect(function()
  if syncBtn.Text == "SYNCING..." then return end
  markInspectionIndexDirty()
  syncBtn.Text = "SYNCING..."
  task.spawn(function()
    local ok, result = pcall(rebuildInspectionIndex)
    syncBtn.Text = "SYNC DATA"
    if ok then
      flash(("inspection index synced · %d objects"):format(inspectionIndexCount), C.good)
    else
      flash("inspection sync failed: " .. tostring(result), C.bad)
    end
  end)
end)

clearBtn.MouseButton1Click:Connect(function()
  conversation = {}
  for _, child in ipairs(chatFeed:GetChildren()) do
    if child:IsA("Frame") then child:Destroy() end
  end
  addChatMessage("PULSAR", "Conversation cleared. Tools stay armed. Official PRIMEz site: https://primez-studios.onrender.com/")
end)

addChatMessage("PULSAR", "I'm PULSAR AGENT — TinyDex v23 Full Scripts Client. I can research this game's current scripts ONLINE (web_search), analyze the whole game (services, characters, remotes, UI), write complete Luau scripts for what you need, and EXECUTE them in the terminal automatically. Execution: "
  .. (Terminal.available and "AVAILABLE (loadstring detected)" or "unavailable in this runtime (Studio-safe mode)") .. ". Describe what you want built and I'll get to work.")
refreshPulsarStatus()
-- v23.1 PERF: no boot-time full-game index build (it froze big games and
-- caused crashes). The index builds lazily via the SYNC DATA button or the
-- first deep analyze_game — always capped and yielding.

gotoTab("Props")
safe("props", refreshProps)
safe("render", render)
safe("view", buildView, nil)
flash("ready", C.dim)












