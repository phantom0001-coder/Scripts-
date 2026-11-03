-- TinyDex Studio v22
-- Official Roblox Studio plugin. Runs only inside Studio and inspects the current DataModel.
-- No executor APIs, exploit hooks, remote code loading, or hidden/server-only access.

local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local toolbar = plugin:CreateToolbar("PRIMEz TinyDex")
local toggleButton = toolbar:CreateButton("TinyDex", "Open TinyDex Studio v22", "rbxassetid://4458901886")

local widgetInfo = DockWidgetPluginGuiInfo.new(
    Enum.InitialDockState.Left,
    true,
    false,
    520,
    620,
    360,
    300
)
local widget = plugin:CreateDockWidgetPluginGui("PRIMEzTinyDexStudioV22", widgetInfo)
widget.Title = "TinyDex Studio v22"

local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(16, 18, 23)
root.BorderSizePixel = 0
root.Parent = widget

local function make(className, props, parent)
    local obj = Instance.new(className)
    for key, value in pairs(props) do obj[key] = value end
    obj.Parent = parent
    return obj
end

local top = make("Frame", {
    Size = UDim2.new(1, 0, 0, 84),
    BackgroundColor3 = Color3.fromRGB(22, 25, 32),
    BorderSizePixel = 0
}, root)

make("TextLabel", {
    Position = UDim2.fromOffset(12, 7),
    Size = UDim2.new(1, -24, 0, 24),
    BackgroundTransparency = 1,
    Text = "TinyDex  /  STUDIO EXPLORER",
    TextColor3 = Color3.fromRGB(110, 235, 160),
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left
}, top)

local search = make("TextBox", {
    Position = UDim2.fromOffset(12, 39),
    Size = UDim2.new(1, -112, 0, 32),
    BackgroundColor3 = Color3.fromRGB(33, 37, 46),
    BorderSizePixel = 0,
    PlaceholderText = "Search name, class, or full path...",
    PlaceholderColor3 = Color3.fromRGB(145, 150, 162),
    Text = "",
    TextColor3 = Color3.fromRGB(235, 238, 244),
    Font = Enum.Font.Gotham,
    TextSize = 12,
    ClearTextOnFocus = false
}, top)
make("UICorner", {CornerRadius = UDim.new(0, 6)}, search)

local refresh = make("TextButton", {
    Position = UDim2.new(1, -88, 0, 39),
    Size = UDim2.fromOffset(76, 32),
    BackgroundColor3 = Color3.fromRGB(48, 112, 78),
    BorderSizePixel = 0,
    Text = "Refresh",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 12
}, top)
make("UICorner", {CornerRadius = UDim.new(0, 6)}, refresh)

local status = make("TextLabel", {
    Position = UDim2.fromOffset(12, 91),
    Size = UDim2.new(1, -24, 0, 22),
    BackgroundTransparency = 1,
    Text = "Index not built",
    TextColor3 = Color3.fromRGB(165, 172, 185),
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left
}, root)

local list = make("ScrollingFrame", {
    Position = UDim2.fromOffset(10, 117),
    Size = UDim2.new(1, -20, 1, -194),
    BackgroundColor3 = Color3.fromRGB(20, 23, 29),
    BorderSizePixel = 0,
    ScrollBarThickness = 7,
    CanvasSize = UDim2.fromOffset(0, 0)
}, root)
make("UICorner", {CornerRadius = UDim.new(0, 6)}, list)
local layout = make("UIListLayout", {
    Padding = UDim.new(0, 3),
    SortOrder = Enum.SortOrder.LayoutOrder
}, list)
make("UIPadding", {
    PaddingTop = UDim.new(0, 6),
    PaddingBottom = UDim.new(0, 6),
    PaddingLeft = UDim.new(0, 6),
    PaddingRight = UDim.new(0, 6)
}, list)

local footer = make("Frame", {
    Position = UDim2.new(0, 10, 1, -68),
    Size = UDim2.new(1, -20, 0, 58),
    BackgroundColor3 = Color3.fromRGB(22, 25, 32),
    BorderSizePixel = 0
}, root)
make("UICorner", {CornerRadius = UDim.new(0, 6)}, footer)

local previous = make("TextButton", {
    Position = UDim2.fromOffset(8, 8),
    Size = UDim2.fromOffset(84, 32),
    BackgroundColor3 = Color3.fromRGB(45, 50, 62),
    BorderSizePixel = 0,
    Text = "Previous",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.Gotham,
    TextSize = 11
}, footer)
local nextPage = make("TextButton", {
    Position = UDim2.fromOffset(98, 8),
    Size = UDim2.fromOffset(84, 32),
    BackgroundColor3 = Color3.fromRGB(45, 50, 62),
    BorderSizePixel = 0,
    Text = "Next",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.Gotham,
    TextSize = 11
}, footer)
local inspect = make("TextButton", {
    Position = UDim2.new(1, -104, 0, 8),
    Size = UDim2.fromOffset(96, 32),
    BackgroundColor3 = Color3.fromRGB(48, 112, 78),
    BorderSizePixel = 0,
    Text = "Inspect selected",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 10
}, footer)
local pageLabel = make("TextLabel", {
    Position = UDim2.fromOffset(190, 8),
    Size = UDim2.new(1, -310, 0, 32),
    BackgroundTransparency = 1,
    Text = "Page 0 / 0",
    TextColor3 = Color3.fromRGB(165, 172, 185),
    Font = Enum.Font.Gotham,
    TextSize = 11
}, footer)

local PAGE_SIZE = 100
local allItems = {}
local filteredItems = {}
local page = 1
local selectedItem = nil
local dirty = false
local rebuilding = false

local function fullPath(instance)
    local parts = {}
    local current = instance
    while current and current ~= game do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end
    return "game" .. (#parts > 0 and "." .. table.concat(parts, ".") or "")
end

local function setStatus(extra)
    status.Text = string.format(
        "%d instances indexed  •  %d matching  •  %s",
        #allItems,
        #filteredItems,
        extra or "Live"
    )
end

local function applyFilter()
    local query = string.lower(search.Text)
    filteredItems = {}
    for _, item in ipairs(allItems) do
        local haystack = string.lower(item.Name .. " " .. item.ClassName .. " " .. item.Path)
        if query == "" or string.find(haystack, query, 1, true) then
            table.insert(filteredItems, item)
        end
    end
    local maxPage = math.max(1, math.ceil(#filteredItems / PAGE_SIZE))
    page = math.clamp(page, 1, maxPage)
end

local function render()
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    applyFilter()
    local startIndex = (page - 1) * PAGE_SIZE + 1
    local endIndex = math.min(startIndex + PAGE_SIZE - 1, #filteredItems)

    for index = startIndex, endIndex do
        local item = filteredItems[index]
        local button = make("TextButton", {
            Size = UDim2.new(1, -4, 0, 28),
            BackgroundColor3 = (selectedItem == item.Instance)
                and Color3.fromRGB(45, 83, 65)
                or Color3.fromRGB(29, 33, 41),
            BorderSizePixel = 0,
            Text = string.format("  %s   [%s]   %s", item.Name, item.ClassName, item.Path),
            TextColor3 = Color3.fromRGB(220, 225, 234),
            Font = Enum.Font.Code,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            LayoutOrder = index
        }, list)
        button.Activated:Connect(function()
            selectedItem = item.Instance
            Selection:Set({item.Instance})
            render()
        end)
    end

    list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 12)
    pageLabel.Text = string.format("Page %d / %d", page, math.max(1, math.ceil(#filteredItems / PAGE_SIZE)))
    setStatus(dirty and "Updating..." or "Live")
end

local function rebuild()
    if rebuilding then return end
    rebuilding = true
    dirty = false
    local newItems = {}
    for _, instance in ipairs(game:GetDescendants()) do
        table.insert(newItems, {
            Instance = instance,
            Name = instance.Name,
            ClassName = instance.ClassName,
            Path = fullPath(instance)
        })
    end
    allItems = newItems
    rebuilding = false
    render()
end

local function scheduleRebuild()
    dirty = true
    setStatus("Change detected")
    task.defer(function()
        if not rebuilding and widget.Enabled then
            rebuild()
        end
    end)
end

refresh.Activated:Connect(rebuild)
search:GetPropertyChangedSignal("Text"):Connect(function()
    page = 1
    render()
end)
previous.Activated:Connect(function()
    page = math.max(1, page - 1)
    render()
end)
nextPage.Activated:Connect(function()
    local maxPage = math.max(1, math.ceil(#filteredItems / PAGE_SIZE))
    page = math.min(maxPage, page + 1)
    render()
end)
inspect.Activated:Connect(function()
    local target = Selection:Get()[1]
    if not target then
        status.Text = "Select an instance first."
        return
    end
    local attrs = target:GetAttributes()
    local lines = {fullPath(target), "Class: " .. target.ClassName, "Attributes:"}
    for key, value in pairs(attrs) do
        table.insert(lines, tostring(key) .. " = " .. tostring(value))
    end
    if #lines == 3 then table.insert(lines, "(none)") end
    status.Text = table.concat(lines, "  |  ")
end)

game.DescendantAdded:Connect(scheduleRebuild)
game.DescendantRemoving:Connect(scheduleRebuild)
toggleButton.Click:Connect(function()
    widget.Enabled = not widget.Enabled
    if widget.Enabled and #allItems == 0 then rebuild() end
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
    if widget.Enabled and (#allItems == 0 or dirty) then rebuild() end
end)

rebuild()
