--[[
    Brainrot Egg Breaker - Zone 1 Automation (v6 - Delta Fix)
    Sửa từ v5: chạy được trên Delta (parent UI an toàn, chờ game load, báo lỗi trên màn hình)
    Tab Main     : cầm búa / bay sát đất / đập trứng + đặt vùng bay (đúng bố cục ảnh mẫu)
    Tab Hop      : Server Hop (Ít người / Server mới / Hop nhanh / Tự động hop)
    Tab Settings : Tăng tốc chạy, Fast Attack, Bay xuyên trứng, ôm pet, thông số nâng cao
    Nút 👑 nổi (kéo thả được) hoặc phím RightShift để ẩn/hiện menu.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer

----------------------------------------------------------------
-- V6 (DELTA FIX): toàn bộ script chạy trong safeMain()
--  * Chờ game load xong trước khi chạy (tránh lỗi auto-execute quá sớm)
--  * Nếu có lỗi runtime, HIỆN hộp đỏ báo lỗi trên màn hình kèm số dòng
----------------------------------------------------------------
local function safeMain()
    -- Chờ game load (tối đa 15 giây, không treo vĩnh viễn)
    if not game:IsLoaded() then
        local t0 = os.clock()
        while not game:IsLoaded() and os.clock() - t0 < 15 do
            task.wait(0.1)
        end
    end

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local CONFIG = {
    HammerKeywords = { "hammer", "mallet", "bua", "búa", "smash" },
    HammerExactName = nil,

    FlightHeight = 4,
    FlightSpeed = 35,
    RowSpacing = 14,
    Margin = 6,

    SmashDelay = 0.08,
    SmashRemote = nil,
    SmashRemoteArgs = {},

    EggKeywords = { "egg", "trung", "trứng" },        -- tên trứng để bỏ qua khi dò mặt đất
    CarryKeywords = { "pet", "brainrot", "carry" },   -- tên vật đang ôm gắn trên nhân vật (nhận biết ôm pet)

    SpeedMode = "cframe",  -- kiểu tăng tốc: "cframe" | "heartbeat" | "walkspeed" | "velocity" (đổi trong Settings nếu bị giật)
    WalkSpeed = 32,        -- tốc độ chạy mong muốn (game thường 16). Cao quá server sẽ kéo lại
    FastAttackDelay = 0.01, -- Fast Attack: số GIÂY giữa 2 lần đánh (tối thiểu 0.0001; càng nhỏ server càng dễ lag)
    MaxSwingsPerFrame = 6,  -- Fast Attack: tối đa số lần đánh mỗi khung hình (chống dồn lệnh làm lag server)
    FlySpeed = 40,          -- Fly bay trên không: tốc độ
    SpreadRadius = 30,      -- Đánh lan rộng: bán kính (studs) quanh nhân vật
    SpreadInterval = 0.1,   -- Đánh lan rộng (khi KHÔNG bật Fast Attack): số giây giữa 2 đợt. Bật Fast Attack thì quét mỗi khung hình có đánh
    SpreadFire = nil,       -- tuỳ chọn: function(eggPart) ... end để bắn remote đánh từng trứng (nếu game không dùng Touched)
    HammerScale = 3,       -- Búa to: phóng to Handle búa x lần để đánh trúng nhiều trứng hơn
    AutoHopMax = 6,        -- Tự động hop khi server có nhiều hơn N người

    LogoImage = nil,       -- tuỳ chọn: "rbxassetid://123456" để thay logo vương miện bằng ảnh của bạn

    ToggleKey = Enum.KeyCode.RightShift,
}

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local State = {
    Equip = false, Flight = false, Smash = false,
    Speed = false, FastAttack = false, Noclip = true, CarryBoost = false,
    AutoHop = false, BigHammer = false,
    Fly = false, Spread = false, PauseOnRun = true,
}
local Diag = { rb = 0, speedCap = 1, flightCap = 1, carrying = false, paused = false, gameWS = nil }
local SPEED_MODES = { "cframe", "heartbeat", "walkspeed", "velocity" }
local SPEED_MODE_LABEL = { cframe = "CFrame (Stepped)", heartbeat = "CFrame (Heartbeat)", walkspeed = "WalkSpeed", velocity = "Vận tốc" }
local carrying = false   -- đang ôm pet (cập nhật ở phần D, dùng ở phần C)

local cornerA, cornerB
local bounds
local bodyVel
local outlineParts = {}
local conns = {}

local function getChar() return player.Character end
local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function recomputeBounds()
    if not (cornerA and cornerB) then bounds = nil return end
    local m = CONFIG.Margin
    local minX = math.min(cornerA.X, cornerB.X) + m
    local maxX = math.max(cornerA.X, cornerB.X) - m
    local minZ = math.min(cornerA.Z, cornerB.Z) + m
    local maxZ = math.max(cornerA.Z, cornerB.Z) - m
    if minX >= maxX or minZ >= maxZ then bounds = nil return end
    bounds = { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

----------------------------------------------------------------
-- CLEANUP BẢN CŨ
----------------------------------------------------------------
local env = (getgenv and getgenv()) or _G
if env.__BrainrotCleanup then pcall(env.__BrainrotCleanup) end

local parentGui
-- V6: thử TỪNG ứng viên bằng cách parent thật một Folder thử (pcall),
-- ứng viên nào gán được thì dùng -> không bao giờ chết ở bước tạo UI trên Delta
do
    local candidates = {}
    local okHui, hui = pcall(function() return (gethui and gethui()) or nil end)
    if okHui and hui then table.insert(candidates, hui) end
    table.insert(candidates, game:GetService("CoreGui"))
    table.insert(candidates, player:WaitForChild("PlayerGui"))
    for _, cand in ipairs(candidates) do
        if typeof(cand) == "Instance" and cand.Parent ~= nil then
            local probe = Instance.new("Folder")
            local ok = pcall(function() probe.Parent = cand end)
            if probe.Parent == cand then
                parentGui = cand
                probe:Destroy()
                break
            end
            probe:Destroy()
        end
    end
end
if not parentGui then parentGui = player:WaitForChild("PlayerGui") end
local oldGui = parentGui:FindFirstChild("BrainrotEggBreakerUI")
if oldGui then oldGui:Destroy() end

----------------------------------------------------------------
-- UI HELPERS
----------------------------------------------------------------
local RED = Color3.fromRGB(255, 38, 38)
local RED_DARK = Color3.fromRGB(190, 12, 20)
local WHITE = Color3.new(1, 1, 1)
local GREEN = Color3.fromRGB(110, 235, 120)
local YELLOW = Color3.fromRGB(255, 205, 60)
local GRAY = Color3.fromRGB(170, 170, 180)

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local function corner(o, r)
    return new("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

local function stroke(o, col, th, tr)
    return new("UIStroke", {
        Color = col or RED, Thickness = th or 1.5, Transparency = tr or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, o)
end

local function tw(o, t, props)
    TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function text(parent, props)
    local p = {
        BackgroundTransparency = 1, TextColor3 = WHITE, Font = Enum.Font.GothamBold,
        TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0,
    }
    for k, v in pairs(props) do p[k] = v end
    return new("TextLabel", p, parent)
end

local function neonButton(parent, label, pos, size, kind)
    local base, hover, strokeCol
    if kind == "dark" then
        base, hover, strokeCol = Color3.fromRGB(20, 20, 25), Color3.fromRGB(40, 20, 24), Color3.fromRGB(130, 30, 36)
    else
        base, hover, strokeCol = Color3.fromRGB(150, 10, 18), Color3.fromRGB(215, 20, 28), RED
    end
    local b = new("TextButton", {
        Position = pos, Size = size, Text = label, Font = Enum.Font.GothamBold, TextSize = 13,
        TextColor3 = WHITE, AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = base,
    }, parent)
    corner(b, 8)
    stroke(b, strokeCol, 1.5)
    b.MouseEnter:Connect(function() tw(b, 0.12, { BackgroundColor3 = hover }) end)
    b.MouseLeave:Connect(function() tw(b, 0.12, { BackgroundColor3 = base }) end)
    local sc = new("UIScale", { Scale = 1 }, b)
    b.MouseButton1Down:Connect(function() tw(sc, 0.08, { Scale = 0.96 }) end)
    b.MouseButton1Up:Connect(function() tw(sc, 0.12, { Scale = 1 }) end)
    b.MouseLeave:Connect(function() tw(sc, 0.12, { Scale = 1 }) end)
    return b
end

local function panel(parent, pos, size, title)
    local f = new("Frame", {
        Position = pos, Size = size, BackgroundColor3 = Color3.fromRGB(8, 8, 10),
        BackgroundTransparency = 0.25, BorderSizePixel = 0,
    }, parent)
    corner(f, 10)
    stroke(f, Color3.fromRGB(95, 20, 26), 1.2, 0.15)
    if title then
        new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(3, 16),
            BackgroundColor3 = RED, BorderSizePixel = 0 }, f)
        text(f, { Position = UDim2.fromOffset(18, 6), Size = UDim2.new(1, -24, 0, 20), Text = title, TextSize = 14 })
    end
    return f
end

local function makeDraggable(handle, target, onClick)
    local dragging, moved, dragStart, startPos = false, false, nil, nil
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            dragStart, startPos = input.Position, target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if onClick and not moved then onClick() end
                end
            end)
        end
    end)
    table.insert(conns, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            if d.Magnitude > 5 then moved = true end
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
end

----------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------
local gui = new("ScreenGui", { Name = "BrainrotEggBreakerUI", ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, parentGui)

local WIN_W, WIN_H = 680, 490
local PAGE_W, PAGE_H = WIN_W - 140, WIN_H - 66 - 40

local baseScale = 1
pcall(function()
    local vp = workspace.CurrentCamera.ViewportSize
    baseScale = math.clamp(math.min((vp.X - 20) / WIN_W, (vp.Y - 20) / WIN_H), 0.45, 1)
end)

local main = new("Frame", {
    Name = "Main", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(WIN_W, WIN_H), BackgroundColor3 = Color3.fromRGB(10, 10, 13),
    BackgroundTransparency = 0.05, BorderSizePixel = 0, Active = true,
}, gui)
corner(main, 14)
local mainStroke = stroke(main, RED, 2)
new("UIGradient", { Color = ColorSequence.new(RED, Color3.fromRGB(110, 10, 16)), Rotation = 45 }, mainStroke)
new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(34, 8, 10), Color3.fromRGB(8, 8, 11)), Rotation = 90 }, main)
local uiScale = new("UIScale", { Scale = baseScale }, main)

-- Viền phát sáng (glow giả) quanh cửa sổ
for _, g in ipairs({ { 6, 0.82, 4 }, { 12, 0.92, 8 } }) do
    local ring = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, g[1] * 2, 1, g[1] * 2), BackgroundTransparency = 1, ZIndex = 0 }, main)
    corner(ring, 14 + g[1])
    stroke(ring, RED, g[3], g[2])
end

-- Top bar
local topbar = new("Frame", { Size = UDim2.new(1, 0, 0, 58), BackgroundTransparency = 1, Active = true }, main)
if CONFIG.LogoImage then
    new("ImageLabel", { Position = UDim2.fromOffset(14, 6), Size = UDim2.fromOffset(46, 46),
        BackgroundTransparency = 1, Image = CONFIG.LogoImage }, topbar)
else
    text(topbar, { Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(44, 42), Text = "👑",
        TextSize = 32, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = RED })
end
local TITLE_X0, TITLE_X1 = 70, WIN_W - 130
text(topbar, { Position = UDim2.fromOffset(TITLE_X0, 5), Size = UDim2.fromOffset(TITLE_X1 - TITLE_X0, 30),
    RichText = true, Font = Enum.Font.GothamBlack, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center,
    Text = '<i>Brainrot <font color="#ff2a2a">Egg Breaker</font></i>' })
local subLabel = text(topbar, { Position = UDim2.fromOffset(TITLE_X0, 34), Size = UDim2.fromOffset(TITLE_X1 - TITLE_X0, 20),
    RichText = true, Font = Enum.Font.GothamMedium, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center,
    Text = '<i>Zone 1 Automation</i>' })
local lineL = new("Frame", { Size = UDim2.fromOffset(60, 2), BackgroundColor3 = RED, BorderSizePixel = 0 }, topbar)
local lineR = new("Frame", { Size = UDim2.fromOffset(60, 2), BackgroundColor3 = RED, BorderSizePixel = 0 }, topbar)
local function placeLines()
    local w = subLabel.TextBounds.X
    local cx = (TITLE_X0 + TITLE_X1) / 2
    lineL.Position = UDim2.fromOffset(cx - w / 2 - 72, 44)
    lineR.Position = UDim2.fromOffset(cx + w / 2 + 12, 44)
end
subLabel:GetPropertyChangedSignal("TextBounds"):Connect(placeLines)
task.defer(placeLines)

new("Frame", { Position = UDim2.new(0, 0, 0, 58), Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = RED, BackgroundTransparency = 0.45, BorderSizePixel = 0 }, main)

local minBtn = neonButton(topbar, "–", UDim2.new(1, -84, 0, 14), UDim2.fromOffset(34, 30), "dark")
local closeBtn = neonButton(topbar, "✕", UDim2.new(1, -44, 0, 14), UDim2.fromOffset(34, 30), "dark")
minBtn.TextSize = 18
closeBtn.TextColor3 = RED
makeDraggable(topbar, main)

-- Footer
text(main, { Position = UDim2.new(0, 16, 1, -32), Size = UDim2.new(0.5, 0, 0, 24), RichText = true,
    Font = Enum.Font.GothamMedium, TextSize = 13,
    Text = '<font color="#ff2a2a">⚡</font> <i>Auto • Fast • Smooth</i>' })
text(main, { Position = UDim2.new(0.5, 0, 1, -32), Size = UDim2.new(0.5, -16, 0, 24), RichText = true,
    Font = Enum.Font.GothamMedium, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right,
    Text = '<font color="#ff2a2a">👑</font> <i>Made for Brainrot</i>' })
local perfLabel = text(main, { Position = UDim2.new(0.3, 0, 1, -32), Size = UDim2.new(0.4, 0, 0, 24), Text = "",
    TextSize = 12, Font = Enum.Font.Gotham, TextColor3 = GRAY, TextXAlignment = Enum.TextXAlignment.Center })

-- Sidebar + pages
local sidebar = panel(main, UDim2.fromOffset(10, 66), UDim2.fromOffset(112, WIN_H - 66 - 40))
local pages = new("Frame", { Position = UDim2.fromOffset(130, 66), Size = UDim2.fromOffset(PAGE_W, PAGE_H),
    BackgroundTransparency = 1 }, main)

local tabDefs = { { "Main", "🏠" }, { "Hop", "🔁" }, { "Settings", "⚙" }, { "Info", "ℹ" }, { "About", "★" } }
local tabButtons, pageFrames = {}, {}

local function selectTab(name)
    for n, b in pairs(tabButtons) do
        local on = (n == name)
        tw(b.btn, 0.15, { BackgroundTransparency = on and 0.55 or 1 })
        b.stroke.Transparency = on and 0 or 1
        b.icon.TextColor3 = on and RED or GRAY
        b.lbl.TextColor3 = on and RED or GRAY
        if on and not pageFrames[n].Visible then
            pageFrames[n].Position = UDim2.fromOffset(0, 12)
            tw(pageFrames[n], 0.18, { Position = UDim2.fromOffset(0, 0) })
        end
        pageFrames[n].Visible = on
    end
end

for i, def in ipairs(tabDefs) do
    local name, icon = def[1], def[2]
    local btn = new("TextButton", {
        Position = UDim2.fromOffset(6, 8 + (i - 1) * 62), Size = UDim2.new(1, -12, 0, 56),
        BackgroundColor3 = RED_DARK, BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
        BorderSizePixel = 0,
    }, sidebar)
    corner(btn, 8)
    local st = stroke(btn, RED, 1.6, 1)
    local ic = text(btn, { Position = UDim2.fromOffset(0, 5), Size = UDim2.new(1, 0, 0, 28), Text = icon,
        TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = GRAY })
    local lb = text(btn, { Position = UDim2.fromOffset(0, 33), Size = UDim2.new(1, 0, 0, 18), Text = name,
        TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = GRAY })
    tabButtons[name] = { btn = btn, stroke = st, icon = ic, lbl = lb }
    btn.MouseButton1Click:Connect(function() selectTab(name) end)
    pageFrames[name] = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, pages)
end

----------------------------------------------------------------
-- TOGGLE ROW (dùng chung, có ô nhập số tuỳ chọn)
----------------------------------------------------------------
local inputRange = {
    WalkSpeed = { 16, 200 }, FastAttackDelay = { 0.0001, 1 }, FlySpeed = { 5, 200 },
    SpreadRadius = { 5, 300 }, HammerScale = { 1, 120 }, AutoHopMax = { 2, 30 },
}

-- Thông báo nhỏ (toast) giữa phía trên màn hình
local toastLabel = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -50),
    Size = UDim2.fromOffset(340, 34), BackgroundColor3 = Color3.fromRGB(14, 14, 18), TextColor3 = WHITE,
    Font = Enum.Font.GothamBold, TextSize = 13, Text = "", TextTruncate = Enum.TextTruncate.AtEnd,
    BorderSizePixel = 0, ZIndex = 50 }, gui)
corner(toastLabel, 10)
stroke(toastLabel, RED, 1.6)
local toastToken = 0
local function toast(msg)
    toastToken = toastToken + 1
    local my = toastToken
    toastLabel.Text = msg
    tw(toastLabel, 0.2, { Position = UDim2.new(0.5, 0, 0, 14) })
    task.delay(2.2, function()
        if toastToken == my and toastLabel.Parent then
            tw(toastLabel, 0.25, { Position = UDim2.new(0.5, 0, 0, -50) })
        end
    end)
end

-- Đồng bộ trạng thái giữa các công tắc (Settings / nút nổi bên trái)
local toggleRefreshers = {}
local function onToggleChange(key, fn)
    toggleRefreshers[key] = toggleRefreshers[key] or {}
    table.insert(toggleRefreshers[key], fn)
end
local function setState(key, value)
    State[key] = value
    for _, fn in ipairs(toggleRefreshers[key] or {}) do fn() end
end

local function makeToggle(parent, icon, label, y, key, inputKey, sub)
    local h = sub and 46 or 38
    local nameW = inputKey and -190 or -130
    local row = new("Frame", { Position = UDim2.new(0, 8, 0, y), Size = UDim2.new(1, -16, 0, h),
        BackgroundColor3 = Color3.fromRGB(18, 18, 22), BorderSizePixel = 0 }, parent)
    corner(row, 8)
    local rowStroke = stroke(row, Color3.fromRGB(50, 50, 58), 1)
    text(row, { Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(32, h), Text = icon, TextSize = 20,
        TextXAlignment = Enum.TextXAlignment.Center })
    text(row, { Position = UDim2.fromOffset(44, sub and 5 or 0), Size = UDim2.new(1, nameW, 0, sub and 20 or h),
        Text = label, TextSize = inputKey and 13 or 14, TextWrapped = true })
    if sub then
        text(row, { Position = UDim2.fromOffset(44, 25), Size = UDim2.new(1, nameW, 0, 16), Text = sub,
            TextSize = 10, Font = Enum.Font.Gotham, TextColor3 = GRAY })
    end
    if inputKey then
        local box = new("TextBox", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -88, 0.5, 0),
            Size = UDim2.fromOffset(50, 24), BackgroundColor3 = Color3.fromRGB(8, 8, 10),
            Text = tostring(CONFIG[inputKey]), TextColor3 = YELLOW, Font = Enum.Font.GothamBold, TextSize = 13,
            ClearTextOnFocus = false, BorderSizePixel = 0 }, row)
        corner(box, 6)
        stroke(box, Color3.fromRGB(130, 30, 36), 1.2)
        box.FocusLost:Connect(function()
            local v = tonumber(box.Text)
            local r = inputRange[inputKey]
            if v then CONFIG[inputKey] = math.clamp(v, r[1], r[2]) end
            box.Text = tostring(CONFIG[inputKey])
        end)
    end

    local sw = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(72, 28), Text = "", AutoButtonColor = false, BorderSizePixel = 0,
        BackgroundColor3 = Color3.fromRGB(45, 45, 52) }, row)
    corner(sw, 14)
    local swStroke = stroke(sw, RED, 1.4, 1)
    local lbl = text(sw, { Size = UDim2.new(1, -26, 1, 0), Font = Enum.Font.GothamBlack, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Center })
    local knob = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(22, 22),
        BackgroundColor3 = WHITE, BorderSizePixel = 0 }, sw)
    corner(knob, 11)

    local function refresh()
        local on = State[key]
        lbl.Text = on and "BẬT" or "TẮT"
        lbl.TextColor3 = on and WHITE or GRAY
        lbl.Position = on and UDim2.fromOffset(0, 0) or UDim2.fromOffset(26, 0)
        tw(knob, 0.15, { Position = on and UDim2.new(1, -25, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) })
        tw(sw, 0.15, { BackgroundColor3 = on and RED_DARK or Color3.fromRGB(45, 45, 52) })
        tw(rowStroke, 0.15, { Color = on and Color3.fromRGB(150, 24, 30) or Color3.fromRGB(50, 50, 58) })
        swStroke.Transparency = on and 0 or 1
    end
    onToggleChange(key, refresh)
    sw.MouseButton1Click:Connect(function()
        setState(key, not State[key])
        toast(label .. (State[key] and "  •  BẬT" or "  •  TẮT"))
    end)
    refresh()
end

----------------------------------------------------------------
-- PAGE: MAIN (đúng bố cục ảnh mẫu)
----------------------------------------------------------------
local mainPage = pageFrames.Main
local leftW = 0.58

local funcPanel = panel(mainPage, UDim2.fromOffset(0, 0), UDim2.new(leftW, -4, 0, 192), "Chức Năng Chính")
makeToggle(funcPanel, "🔨", "Tự động cầm búa", 34, "Equip", nil, "Cầm búa 1 lần, tự cầm lại nếu mất")
makeToggle(funcPanel, "🕊", "Bay sát đất Zone 1", 86, "Flight", nil, "Quét kín vùng đã đặt, khóa trong ranh giới")
makeToggle(funcPanel, "💥", "Tự động đập trứng", 138, "Smash", nil, "Fast Attack / Lan rộng chỉnh ở Settings")

local zonePanel = panel(mainPage, UDim2.fromOffset(0, 200), UDim2.new(leftW, -4, 0, PAGE_H - 200), "Đặt Vùng Bay")
local btnA = neonButton(zonePanel, "📍 Đặt góc 1", UDim2.fromOffset(8, 34), UDim2.new(0.5, -12, 0, 38), "red")
local btnB = neonButton(zonePanel, "📍 Đặt góc 2", UDim2.new(0.5, 4, 0, 34), UDim2.new(0.5, -12, 0, 38), "red")
local btnShow = neonButton(zonePanel, "👁 Hiện viền vùng", UDim2.fromOffset(8, 80), UDim2.new(1, -16, 0, 38), "dark")
local btnReset = neonButton(zonePanel, "🗑 Xóa vùng", UDim2.fromOffset(8, 126), UDim2.new(1, -16, 0, 38), "red")

local infoPanel = panel(mainPage, UDim2.new(leftW, 4, 0, 0), UDim2.new(1 - leftW, -4, 0, 244), "Thông Tin Vùng")
text(infoPanel, { Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 0, 18), Text = "Kích thước vùng:",
    Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = GRAY })
local sizeLabel = text(infoPanel, { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 30),
    Text = "XXX x XXX studs", TextSize = 20, TextColor3 = RED, Font = Enum.Font.GothamBlack,
    TextXAlignment = Enum.TextXAlignment.Center })

local checkRow = new("Frame", { Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 22),
    BackgroundTransparency = 1 }, infoPanel)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
    VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, checkRow)
local checkIcon = new("TextLabel", { Size = UDim2.fromOffset(18, 18), BackgroundColor3 = RED, Text = "✗",
    TextColor3 = WHITE, Font = Enum.Font.GothamBlack, TextSize = 12, BorderSizePixel = 0, LayoutOrder = 1 }, checkRow)
corner(checkIcon, 9)
local checkLabel = text(checkRow, { Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X,
    Text = "Chưa đặt vùng", TextSize = 13, TextColor3 = RED, LayoutOrder = 2 })

local preview = new("Frame", { Position = UDim2.fromOffset(12, 114), Size = UDim2.new(1, -24, 0, 120),
    BackgroundColor3 = Color3.fromRGB(40, 6, 8), BorderSizePixel = 0 }, infoPanel)
corner(preview, 6)
local previewStroke = stroke(preview, Color3.fromRGB(110, 25, 30), 1.6)
new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(70, 8, 12), Color3.fromRGB(14, 6, 8)), Rotation = 90 }, preview)
local cornerSquares = {}
for _, a in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
    table.insert(cornerSquares, new("Frame", { AnchorPoint = Vector2.new(a[1], a[2]),
        Position = UDim2.fromScale(a[1], a[2]), Size = UDim2.fromOffset(10, 10),
        BackgroundColor3 = Color3.fromRGB(110, 25, 30), BorderSizePixel = 0 }, preview))
end

local statusPanel = panel(mainPage, UDim2.new(leftW, 4, 0, 252), UDim2.new(1 - leftW, -4, 0, PAGE_H - 252), nil)
text(statusPanel, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 20), Text = "〰 Trạng Thái:", TextSize = 14 })
local statusValue = text(statusPanel, { Position = UDim2.fromOffset(8, 30), Size = UDim2.new(1, -16, 1, -54),
    Text = "Đang đứng yên", TextSize = 18, TextColor3 = GREEN, Font = Enum.Font.GothamBlack,
    TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
local diagLabel = text(statusPanel, { Position = UDim2.new(0, 8, 1, -22), Size = UDim2.new(1, -16, 0, 18),
    Text = "", TextSize = 10, Font = Enum.Font.Gotham, TextColor3 = GRAY, TextXAlignment = Enum.TextXAlignment.Center })

local function clearOutline()
    for _, p in ipairs(outlineParts) do p:Destroy() end
    outlineParts = {}
end

local function drawOutline()
    clearOutline()
    if not bounds then return end
    local hrp = getHRP()
    local y = hrp and hrp.Position.Y or 5
    local pts = {
        Vector3.new(bounds.minX, y, bounds.minZ), Vector3.new(bounds.maxX, y, bounds.minZ),
        Vector3.new(bounds.maxX, y, bounds.maxZ), Vector3.new(bounds.minX, y, bounds.maxZ),
    }
    for i = 1, 4 do
        local a, b = pts[i], pts[i % 4 + 1]
        local p = Instance.new("Part")
        p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
        p.Material = Enum.Material.Neon
        p.Color = Color3.fromRGB(255, 60, 60)
        p.Transparency = 0.3
        p.Size = Vector3.new(0.5, 0.5, (b - a).Magnitude)
        p.CFrame = CFrame.lookAt((a + b) / 2, b)
        p.Parent = workspace
        table.insert(outlineParts, p)
    end
end

local refreshZone
function refreshZone()
    recomputeBounds()
    btnA.Text = cornerA and "✓ Góc 1 đã đặt" or "📍 Đặt góc 1"
    btnB.Text = cornerB and "✓ Góc 2 đã đặt" or "📍 Đặt góc 2"
    local ok = bounds ~= nil
    local icon, label, col
    if ok then
        sizeLabel.Text = string.format("%d x %d studs", math.floor(bounds.maxX - bounds.minX), math.floor(bounds.maxZ - bounds.minZ))
        icon, label, col = "✓", "Đã đặt vùng ✓", GREEN
    elseif cornerA and cornerB then
        sizeLabel.Text = string.format("%d x %d studs", math.floor(math.abs(cornerA.X - cornerB.X)), math.floor(math.abs(cornerA.Z - cornerB.Z)))
        icon, label, col = "!", "Vùng quá nhỏ (giảm Margin)", YELLOW
    elseif cornerA or cornerB then
        sizeLabel.Text = "XXX x XXX studs"
        icon, label, col = "!", "Cần đặt đủ 2 góc", YELLOW
    else
        sizeLabel.Text = "XXX x XXX studs"
        icon, label, col = "✗", "Chưa đặt vùng", RED
    end
    sizeLabel.TextColor3 = ok and WHITE or RED
    checkIcon.Text, checkIcon.BackgroundColor3 = icon, col
    checkLabel.Text, checkLabel.TextColor3 = label, col
    previewStroke.Color = ok and RED or Color3.fromRGB(110, 25, 30)
    for _, sq in ipairs(cornerSquares) do sq.BackgroundColor3 = ok and RED or Color3.fromRGB(110, 25, 30) end
end

btnA.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if hrp then cornerA = hrp.Position; refreshZone(); if #outlineParts > 0 then drawOutline() end end
end)
btnB.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if hrp then cornerB = hrp.Position; refreshZone(); if #outlineParts > 0 then drawOutline() end end
end)
btnShow.MouseButton1Click:Connect(function()
    if #outlineParts > 0 then clearOutline() else drawOutline() end
end)
btnReset.MouseButton1Click:Connect(function()
    cornerA, cornerB, bounds = nil, nil, nil
    clearOutline()
    refreshZone()
end)
refreshZone()
----------------------------------------------------------------
-- PAGE: HOP (Server Hop: Ít người / Server mới / Hop nhanh / Tự động hop)
----------------------------------------------------------------
local hopPage = pageFrames.Hop
text(hopPage, { Position = UDim2.fromOffset(4, 0), Size = UDim2.fromOffset(40, 40), Text = "🔁", TextSize = 28,
    TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = RED })
text(hopPage, { Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -170, 0, 26), Text = "Server Hop",
    Font = Enum.Font.GothamBlack, TextSize = 22 })
text(hopPage, { Position = UDim2.fromOffset(48, 26), Size = UDim2.new(1, -170, 0, 18),
    Text = "Chuyển sang server ít người hoặc server mới!", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = GRAY })
local refreshBtn = neonButton(hopPage, "⟳ Làm mới", UDim2.new(1, -112, 0, 4), UDim2.fromOffset(108, 34), "dark")

local modeLow = neonButton(hopPage, "", UDim2.fromOffset(0, 50), UDim2.new(1 / 3, -4, 0, 34), "dark")
local modeFresh = neonButton(hopPage, "", UDim2.new(1 / 3, 2, 0, 50), UDim2.new(1 / 3, -4, 0, 34), "dark")
local hopNowBtn = neonButton(hopPage, "⚡ Hop nhanh", UDim2.new(2 / 3, 4, 0, 50), UDim2.new(1 / 3, -4, 0, 34), "red")

makeToggle(hopPage, "🔄", "Tự động hop khi server > N người", 90, "AutoHop", "AutoHopMax")

text(hopPage, { Position = UDim2.fromOffset(4, 134), Size = UDim2.new(1, -8, 0, 30), TextWrapped = true,
    Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = YELLOW,
    Text = "⚠ Roblox không cho biết tuổi server: \"Server mới\" là ước lượng (rất ít người + FPS cao). Sau khi hop, hãy chạy lại script." })

local headY = 168
local colX = { 0.02, 0.42, 0.60, 0.79 }
local heads = { "Tên Server / ID", "Người chơi", "Ping • FPS", "Hành động" }
for i, h in ipairs(heads) do
    text(hopPage, { Position = UDim2.new(colX[i], 0, 0, headY), Size = UDim2.new(0.3, 0, 0, 18), Text = h,
        TextSize = 12, TextColor3 = GRAY })
end

local listFrame = new("ScrollingFrame", {
    Position = UDim2.fromOffset(0, headY + 22), Size = UDim2.new(1, 0, 0, PAGE_H - headY - 22 - 32),
    BackgroundColor3 = Color3.fromRGB(8, 8, 10), BackgroundTransparency = 0.25, BorderSizePixel = 0,
    ScrollBarThickness = 4, ScrollBarImageColor3 = RED, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, hopPage)
corner(listFrame, 8)
stroke(listFrame, Color3.fromRGB(95, 20, 26), 1.2, 0.15)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, listFrame)
new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 6) }, listFrame)

local hopFooter = new("Frame", { Position = UDim2.new(0, 0, 1, -28), Size = UDim2.new(1, 0, 0, 28),
    BackgroundTransparency = 1 }, hopPage)
local scanLabel = text(hopFooter, { Size = UDim2.new(0.55, 0, 1, 0), Text = "Chưa quét", TextSize = 12, TextColor3 = GRAY })
local marqClip = new("Frame", { Position = UDim2.fromScale(0.55, 0), Size = UDim2.fromScale(0.45, 1),
    BackgroundTransparency = 1, ClipsDescendants = true }, hopFooter)
local marq = text(marqClip, { Size = UDim2.fromOffset(260, 28), Text = ">>> Hop ngay để không bỏ lỡ! <<<",
    TextSize = 12, TextColor3 = RED })

local rawServers = {}
local hopMode = "low"
local scanning, hopping = false, false
local joinClock = os.clock()

local function httpGet(url)
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and res then return res end
    local req = (syn and syn.request) or http_request or request
    if req then
        local ok2, r = pcall(req, { Url = url, Method = "GET" })
        if ok2 and r and r.Body then return r.Body end
    end
end

local function sortedServers()
    local list = {}
    for _, s in ipairs(rawServers) do
        if s.id ~= game.JobId and (s.playing or 0) < (s.maxPlayers or 0) then table.insert(list, s) end
    end
    if hopMode == "fresh" then
        local few = {}
        for _, s in ipairs(list) do if (s.playing or 0) <= 2 then table.insert(few, s) end end
        if #few > 0 then list = few end
        table.sort(list, function(a, b)
            if (a.fps or 0) ~= (b.fps or 0) then return (a.fps or 0) > (b.fps or 0) end
            return (a.ping or 9e9) < (b.ping or 9e9)
        end)
    else
        table.sort(list, function(a, b)
            if (a.playing or 0) ~= (b.playing or 0) then return (a.playing or 0) < (b.playing or 0) end
            return (a.ping or 9e9) < (b.ping or 9e9)
        end)
    end
    return list
end

local function hopTo(s, btn)
    if hopping then return end
    hopping = true
    if btn then btn.Text = "Đang hop…" end
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, player)
    end)
    if not ok then
        hopping = false
        warn("[Hop] " .. tostring(err))
        if btn then
            btn.Text = "Lỗi!"
            task.delay(1.5, function() if btn.Parent then btn.Text = "Hop Ngay >" end end)
        end
    else
        task.delay(12, function() hopping = false end)
    end
end
table.insert(conns, TeleportService.TeleportInitFailed:Connect(function() hopping = false end))

local function clearRows()
    for _, c in ipairs(listFrame:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
end

local function addRow(idx, s)
    local row = new("Frame", { Size = UDim2.new(1, 0, 0, 38), LayoutOrder = idx,
        BackgroundColor3 = Color3.fromRGB(18, 18, 22), BorderSizePixel = 0 }, listFrame)
    corner(row, 6)
    text(row, { Position = UDim2.new(colX[1], 0, 0, 2), Size = UDim2.new(0.38, 0, 0, 18),
        Text = "🥚 Server #" .. idx, TextSize = 13 })
    text(row, { Position = UDim2.new(colX[1], 0, 0, 19), Size = UDim2.new(0.38, 0, 0, 16),
        Text = string.sub(s.id, 1, 13) .. "…", TextSize = 10, Font = Enum.Font.Gotham, TextColor3 = GRAY })
    text(row, { Position = UDim2.new(colX[2], 0, 0, 0), Size = UDim2.new(0.17, 0, 1, 0),
        Text = string.format("%d/%d", s.playing or 0, s.maxPlayers or 0), TextSize = 13, TextColor3 = YELLOW })
    text(row, { Position = UDim2.new(colX[3], 0, 0, 0), Size = UDim2.new(0.18, 0, 1, 0), TextSize = 11, TextColor3 = GREEN,
        Text = string.format("%s ms • %s", s.ping and tostring(math.floor(s.ping)) or "?", s.fps and tostring(math.floor(s.fps)) or "?") })
    local hop = neonButton(row, "Hop Ngay >", UDim2.new(colX[4], 0, 0.5, -14), UDim2.new(0.19, 0, 0, 28), "red")
    hop.TextSize = 11
    hop.MouseButton1Click:Connect(function() hopTo(s, hop) end)
end

local function renderList()
    clearRows()
    local list = sortedServers()
    for i, s in ipairs(list) do
        if i > 40 then break end
        addRow(i, s)
    end
    return list
end

local function updateModeButtons()
    modeLow.Text = (hopMode == "low" and "● " or "") .. "👥 Ít người"
    modeFresh.Text = (hopMode == "fresh" and "● " or "") .. "🆕 Server mới"
    modeLow.TextColor3 = hopMode == "low" and RED or WHITE
    modeFresh.TextColor3 = hopMode == "fresh" and RED or WHITE
end
updateModeButtons()

local function scanServers()
    if scanning then return end
    scanning = true
    scanLabel.Text = "Đang quét server…"
    local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", game.PlaceId)
    local body = httpGet(url)
    local msg
    if body then
        local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
        if ok and data and data.data then
            rawServers = data.data
        elseif ok and data and data.errors then
            msg = "API lỗi: " .. tostring(data.errors[1] and data.errors[1].message or "?")
        end
    else
        msg = "Không lấy được danh sách (kiểm tra executor/HttpGet)"
    end
    local list = renderList()
    local okDate, tStr = pcall(os.date, "%H:%M:%S")
    scanLabel.Text = msg or string.format("Đã quét %d server  •  Cập nhật: %s", #list, (okDate and tStr) or "?")
    scanning = false
end

modeLow.MouseButton1Click:Connect(function()
    hopMode = "low"; updateModeButtons()
    if #rawServers > 0 then renderList() else task.spawn(scanServers) end
end)
modeFresh.MouseButton1Click:Connect(function()
    hopMode = "fresh"; updateModeButtons()
    if #rawServers > 0 then renderList() else task.spawn(scanServers) end
end)
refreshBtn.MouseButton1Click:Connect(function() task.spawn(scanServers) end)
hopNowBtn.MouseButton1Click:Connect(function()
    task.spawn(function()
        if #rawServers == 0 then scanServers() end
        local list = sortedServers()
        if list[1] then hopTo(list[1]) end
    end)
end)

-- Tự động hop: chỉ khi server hiện tại đông hơn ngưỡng, có cooldown, và server đích phải ít người hơn
task.spawn(function()
    local lastScan = 0
    while gui.Parent do
        task.wait(5)
        local count = #Players:GetPlayers()
        if State.AutoHop and not hopping and os.clock() - joinClock > 20 and count > CONFIG.AutoHopMax then
            if os.clock() - lastScan > 30 then
                lastScan = os.clock()
                scanServers()
            end
            local list = sortedServers()
            if list[1] and (list[1].playing or 0) < count then hopTo(list[1]) end
        end
    end
end)

task.spawn(function()
    while gui.Parent do
        marq.Position = UDim2.new(1, 0, 0, 0)
        local t = TweenService:Create(marq, TweenInfo.new(7, Enum.EasingStyle.Linear),
            { Position = UDim2.new(0, -260, 0, 0) })
        t:Play()
        t.Completed:Wait()
    end
end)

----------------------------------------------------------------
-- PAGE: SETTINGS (chia nhóm: Di chuyển / Chiến đấu / Thông số)
----------------------------------------------------------------
local setPanel = panel(pageFrames.Settings, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), "Cài đặt nâng cao")
local setScroll = new("ScrollingFrame", { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -34),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = RED,
    CanvasSize = UDim2.fromOffset(0, 600) }, setPanel)

local sy = 4
local function sectionHeader(title)
    text(setScroll, { Position = UDim2.fromOffset(12, sy), Size = UDim2.new(1, -24, 0, 18), Text = title,
        TextSize = 12, TextColor3 = RED })
    new("Frame", { Position = UDim2.fromOffset(12, sy + 19), Size = UDim2.new(1, -24, 0, 1),
        BackgroundColor3 = RED, BackgroundTransparency = 0.6, BorderSizePixel = 0 }, setScroll)
    sy = sy + 28
end
local function toggleRow(icon, label, key, inputKey)
    makeToggle(setScroll, icon, label, sy, key, inputKey)
    sy = sy + 42
end
local function plainRow()
    local row = new("Frame", { Position = UDim2.new(0, 8, 0, sy), Size = UDim2.new(1, -16, 0, 36),
        BackgroundColor3 = Color3.fromRGB(18, 18, 22), BorderSizePixel = 0 }, setScroll)
    corner(row, 8)
    sy = sy + 42
    return row
end
local function numRow(label, key, min, max)
    local row = plainRow()
    text(row, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -120, 1, 0), Text = label, TextSize = 13 })
    local box = new("TextBox", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(86, 26), BackgroundColor3 = Color3.fromRGB(8, 8, 10), Text = tostring(CONFIG[key]),
        TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 13, ClearTextOnFocus = false,
        BorderSizePixel = 0 }, row)
    corner(box, 6)
    stroke(box, Color3.fromRGB(130, 30, 36), 1.2)
    box.FocusLost:Connect(function()
        local v = tonumber(box.Text)
        if v then CONFIG[key] = math.clamp(v, min, max) end
        box.Text = tostring(CONFIG[key])
        if key == "Margin" then
            refreshZone()
            if #outlineParts > 0 then drawOutline() end
        end
    end)
end

sectionHeader("✈  DI CHUYỂN")
toggleRow("✈", "Fly bay trên không", "Fly", "FlySpeed")
toggleRow("🏃", "Tăng tốc chạy", "Speed", "WalkSpeed")
do
    local row = plainRow()
    text(row, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -196, 1, 0), TextSize = 12, TextWrapped = true,
        Text = "Kiểu tăng tốc (đổi nếu bị giật)" })
    local modeBtn = neonButton(row, "", UDim2.new(1, -176, 0.5, -14), UDim2.fromOffset(168, 28), "dark")
    modeBtn.TextSize = 12
    local function refreshSpeedMode() modeBtn.Text = "⇄ " .. SPEED_MODE_LABEL[CONFIG.SpeedMode] end
    refreshSpeedMode()
    modeBtn.MouseButton1Click:Connect(function()
        local idx = table.find(SPEED_MODES, CONFIG.SpeedMode) or 1
        CONFIG.SpeedMode = SPEED_MODES[idx % #SPEED_MODES + 1]
        refreshSpeedMode()
        toast("Kiểu tăng tốc: " .. SPEED_MODE_LABEL[CONFIG.SpeedMode])
    end)
end
toggleRow("🐾", "Tăng tốc cả khi ôm pet (dễ bị kéo lại)", "CarryBoost")
toggleRow("👻", "Bay xuyên trứng", "Noclip")

sectionHeader("⚔  CHIẾN ĐẤU")
toggleRow("⚡", "Fast Attack (giây/đòn)", "FastAttack", "FastAttackDelay")
toggleRow("💫", "Đánh lan rộng AoE (bán kính)", "Spread", "SpreadRadius")
toggleRow("🔨", "Búa to (x lần)", "BigHammer", "HammerScale")
toggleRow("⏸", "Ngưng đánh khi chạy nhanh/ôm pet", "PauseOnRun")

sectionHeader("⚙  THÔNG SỐ")
numRow("Số đòn tối đa mỗi khung hình", "MaxSwingsPerFrame", 1, 30)
numRow("Độ cao bay (studs)", "FlightHeight", 1, 30)
numRow("Tốc độ bay tối đa", "FlightSpeed", 10, 120)
numRow("Khoảng cách hàng quét", "RowSpacing", 4, 40)
numRow("Đệm an toàn Margin", "Margin", 0, 30)
numRow("Delay đập thường (giây)", "SmashDelay", 0.02, 1)
do
    local row = plainRow()
    text(row, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -180, 1, 0), Text = "Tên búa chính xác", TextSize = 13 })
    local hammerBox = new("TextBox", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(150, 26), BackgroundColor3 = Color3.fromRGB(8, 8, 10), Text = "",
        PlaceholderText = "(để trống = tự dò)", PlaceholderColor3 = GRAY, TextColor3 = WHITE,
        Font = Enum.Font.GothamBold, TextSize = 12, ClearTextOnFocus = false, BorderSizePixel = 0 }, row)
    corner(hammerBox, 6)
    stroke(hammerBox, Color3.fromRGB(130, 30, 36), 1.2)
    hammerBox.FocusLost:Connect(function()
        CONFIG.HammerExactName = (hammerBox.Text ~= "") and hammerBox.Text or nil
    end)
end
setScroll.CanvasSize = UDim2.fromOffset(0, sy + 8)

----------------------------------------------------------------
-- PAGE: INFO / ABOUT
----------------------------------------------------------------
local infoPage = panel(pageFrames.Info, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), "Hướng dẫn")
local infoScroll = new("ScrollingFrame", { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -34),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = RED,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, infoPage)
text(infoScroll, { Position = UDim2.fromOffset(14, 4), Size = UDim2.new(1, -28, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
    RichText = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.Gotham, TextSize = 13,
    Text = '<font color="#ff2a2a"><b>CÁCH DÙNG NHANH</b></font>\n'
        .. '1. Đứng ở góc bãi trứng → <b>Đặt góc 1</b>; đi tới góc đối diện → <b>Đặt góc 2</b>; <b>Hiện viền vùng</b> để kiểm tra (vùng là hình chữ nhật thẳng trục).\n'
        .. '2. Bật <b>Cầm búa</b>, <b>Bay sát đất</b>, <b>Đập trứng</b>.\n\n'
        .. '<font color="#ff2a2a"><b>NÚT NỔI BÊN TRÁI</b></font>\n'
        .. '👑 ẩn/hiện menu (kéo để di chuyển)  •  ✈ bật/tắt Fly  •  💫 bật/tắt Đánh lan rộng. Phím RightShift cũng ẩn/hiện menu.\n\n'
        .. '<font color="#ff2a2a"><b>FLY</b></font>\n'
        .. 'Bay tự do trên không. Khi bật sẽ hiện nút ▲ ▼ bên phải (PC: Space / LeftShift). Đi tới + ngước camera lên/xuống để lên/xuống. Fly bật thì Bay sát đất tạm dừng.\n\n'
        .. '<font color="#ff2a2a"><b>CHIẾN ĐẤU</b></font>\n'
        .. '<font color="#ffcd3c">Fast Attack:</font> nhập số GIÂY giữa 2 đòn (tối thiểu 0.0001, tối đa số đòn/khung hình ở Thông số). Dưới 0.005 server rất dễ lag.\n'
        .. '<font color="#ffcd3c">Đánh lan rộng (AoE):</font> mỗi nhịp đánh, chạm búa vào mọi trứng trong bán kính (cần Đập trứng + cầm búa + executor có firetouchinterest; game dùng remote thì gán CONFIG.SpreadFire).\n'
        .. '<font color="#ffcd3c">Búa to:</font> phóng to Handle búa (tối đa x120, có hiệu lực nếu game tính va chạm ở client).\n'
        .. '<font color="#ffcd3c">Ngưng đánh khi chạy/ôm pet:</font> tránh nhân vật khựng khi chạy về với pet.\n\n'
        .. '<font color="#ff2a2a"><b>CHỐNG GIẬT</b></font>\n'
        .. 'Tăng tốc chỉ cộng thêm tốc độ gốc, tự giảm khi bị server kéo lại. Bị giật thì đổi <b>Kiểu tăng tốc</b> trong Settings và giảm tốc độ. Giữa footer có Ping/FPS; ô Trạng Thái có WS/RB (RB tăng liên tục = server đang kéo lại).' })

local aboutPage = panel(pageFrames.About, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), "Giới thiệu")
text(aboutPage, { Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 1, -44), RichText = true,
    TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.Gotham, TextSize = 14,
    Text = '<font color="#ff2a2a"><b>Brainrot Egg Breaker</b></font> - Zone 1 Automation\nPhiên bản: v5 (Neon Red UI)\n\n'
        .. 'Tự cầm búa • Bay quét kín vùng • Tự đập trứng • Tăng tốc • Fast Attack • Server Hop.' })

----------------------------------------------------------------
-- NÚT BẬT/TẮT UI (nút nổi + phím tắt)
----------------------------------------------------------------
local uiVisible = true
local function setVisible(v)
    uiVisible = v
    if v then
        uiScale.Scale = baseScale * 0.9
        main.Visible = true
        TweenService:Create(uiScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = baseScale }):Play()
    else
        main.Visible = false
    end
end

-- Nút nổi bên trái: 👑 menu (kéo thả), ✈ Fly, 💫 AoE
local dock = new("Frame", { Name = "Dock", Position = UDim2.new(0, 10, 0.5, -96), Size = UDim2.fromOffset(56, 192),
    BackgroundTransparency = 1, Active = true }, gui)
local function dockButton(icon, caption, y)
    local b = new("TextButton", { Position = UDim2.fromOffset(4, y), Size = UDim2.fromOffset(48, 48),
        BackgroundColor3 = Color3.fromRGB(14, 14, 18), Text = icon, TextSize = 22, Font = Enum.Font.GothamBold,
        TextColor3 = RED, AutoButtonColor = false, BorderSizePixel = 0, Active = true }, dock)
    corner(b, 24)
    local st = stroke(b, RED, 2)
    text(dock, { Position = UDim2.fromOffset(0, y + 49), Size = UDim2.fromOffset(56, 12), Text = caption,
        TextSize = 9, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = GRAY })
    return b, st
end
local floatBtn, fbStroke = dockButton("👑", "MENU", 0)
new("UIGradient", { Color = ColorSequence.new(RED, Color3.fromRGB(100, 8, 14)), Rotation = 45 }, fbStroke)
local flyBtn, flyStroke = dockButton("✈", "FLY", 64)
local aoeBtn, aoeStroke = dockButton("💫", "AOE", 128)
makeDraggable(floatBtn, dock, function() setVisible(not uiVisible) end)

local function styleDock(btn, st, on)
    tw(btn, 0.15, { BackgroundColor3 = on and RED_DARK or Color3.fromRGB(14, 14, 18) })
    btn.TextColor3 = on and WHITE or RED
    st.Thickness = on and 3 or 2
end
flyBtn.MouseButton1Click:Connect(function()
    setState("Fly", not State.Fly)
    toast("✈ Fly: " .. (State.Fly and "BẬT" or "TẮT"))
end)
aoeBtn.MouseButton1Click:Connect(function()
    setState("Spread", not State.Spread)
    toast("💫 Đánh lan rộng: " .. (State.Spread and "BẬT" or "TẮT"))
end)
onToggleChange("Fly", function() styleDock(flyBtn, flyStroke, State.Fly) end)
onToggleChange("Spread", function() styleDock(aoeBtn, aoeStroke, State.Spread) end)
minBtn.MouseButton1Click:Connect(function() setVisible(false) end)

table.insert(conns, UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == CONFIG.ToggleKey then setVisible(not uiVisible) end
end))

selectTab("Main")

----------------------------------------------------------------
-- A. TỰ ĐỘNG CẦM BÚA (chỉ cầm 1 lần, có kiểm tra + debounce, không lặp lệnh)
----------------------------------------------------------------
local function isHammer(tool)
    if not tool:IsA("Tool") then return false end
    if CONFIG.HammerExactName then return tool.Name == CONFIG.HammerExactName end
    local n = string.lower(tool.Name)
    for _, k in ipairs(CONFIG.HammerKeywords) do
        if string.find(n, k, 1, true) then return true end
    end
    return false
end

local function heldHammer()
    local char = getChar()
    if not char then return nil end
    for _, t in ipairs(char:GetChildren()) do
        if isHammer(t) then return t end
    end
end

-- Trả về true nếu đã gọi EquipTool (đúng 1 lần). Đang cầm rồi thì KHÔNG gọi lại.
local function equipHammerOnce()
    local hum = getHum()
    if not hum or hum.Health <= 0 then return false end
    if heldHammer() then return false end
    local bp = player:FindFirstChildOfClass("Backpack")
    if not bp then return false end
    for _, t in ipairs(bp:GetChildren()) do
        if isHammer(t) then
            hum:EquipTool(t)
            return true
        end
    end
    return false
end

task.spawn(function()
    local fails, lastTry = 0, 0
    while gui.Parent do
        if State.Equip then
            if heldHammer() then
                fails = 0
            elseif fails < 4 and os.clock() - lastTry >= 1.5 then
                lastTry = os.clock()
                pcall(equipHammerOnce)
                task.wait(0.5) -- chờ game cập nhật rồi mới kiểm tra
                if heldHammer() then
                    fails = 0
                else
                    fails = fails + 1
                    if fails == 4 then
                        warn("[Equip] Không cầm được búa sau 4 lần. Kiểm tra 'Tên búa chính xác' trong Settings.")
                    end
                end
            end
        else
            fails = 0
        end
        task.wait(0.3)
    end
end)

----------------------------------------------------------------
-- A2. BÚA TO (phóng to Handle để vùng chạm rộng hơn -> trúng nhiều trứng hơn)
----------------------------------------------------------------
local scaledHammers = {} -- [handle] = { tool, size, collide, massless }

local function restoreHandle(handle, o)
    if handle.Parent then
        pcall(function()
            handle.Size = o.size
            handle.CanCollide = o.collide
            handle.Massless = o.massless
        end)
    end
end

local function restoreHammers()
    for handle, o in pairs(scaledHammers) do
        restoreHandle(handle, o)
        scaledHammers[handle] = nil
    end
end

local function applyBigHammer()
    local tool = heldHammer()
    -- búa đã bỏ xuống/đổi búa: trả kích thước cũ
    for handle, o in pairs(scaledHammers) do
        if not tool or o.tool ~= tool or not handle.Parent then
            restoreHandle(handle, o)
            scaledHammers[handle] = nil
        end
    end
    if not tool then return end
    local handle = tool:FindFirstChild("Handle")
    if not (handle and handle:IsA("BasePart")) then return end

    local o = scaledHammers[handle]
    if not o then
        o = { tool = tool, size = handle.Size, collide = handle.CanCollide, massless = handle.Massless }
        scaledHammers[handle] = o
    end
    local k = CONFIG.HammerScale
    local want = Vector3.new(math.min(o.size.X * k, 2048), math.min(o.size.Y * k, 2048), math.min(o.size.Z * k, 2048))
    if (handle.Size - want).Magnitude > 0.01 then handle.Size = want end
    handle.CanCollide = false -- búa to không được đẩy/kẹt nhân vật
    handle.Massless = true
end

task.spawn(function()
    while gui.Parent do
        if State.BigHammer then
            pcall(applyBigHammer)
        elseif next(scaledHammers) then
            restoreHammers()
        end
        task.wait(0.25)
    end
end)
----------------------------------------------------------------
-- B. BAY SÁT ĐẤT (chống kẹt, chống kéo lùi, xuyên trứng)
----------------------------------------------------------------
local function buildWaypoints(b)
    local pts = {}
    local z = b.minZ
    local dir = 1
    while z <= b.maxZ do
        local xa, xb = b.minX, b.maxX
        if dir == -1 then xa, xb = xb, xa end
        table.insert(pts, Vector3.new(xa, 0, z))
        table.insert(pts, Vector3.new(xb, 0, z))
        z = z + CONFIG.RowSpacing
        dir = -dir
    end
    if pts[#pts].Z < b.maxZ - 0.1 then
        local last = pts[#pts]
        table.insert(pts, Vector3.new(last.X, 0, b.maxZ))
        table.insert(pts, Vector3.new(last.X == b.minX and b.maxX or b.minX, 0, b.maxZ))
    end
    for i = #pts - 1, 1, -1 do table.insert(pts, pts[i]) end
    return pts
end

local function isEggPart(inst)
    local cur = inst
    for _ = 1, 6 do
        if not cur or cur == workspace then break end
        local n = string.lower(cur.Name)
        for _, k in ipairs(CONFIG.EggKeywords) do
            if string.find(n, k, 1, true) then return true end
        end
        cur = cur.Parent
    end
    return false
end

-- Dò mặt đất từ ngay phía trên nhân vật (+10) để không dính tường/hàng rào cao ở mép vùng;
-- bỏ qua trứng, người chơi khác và part không va chạm.
local function groundY(pos, char)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.RespectCanCollide = true
    local ex = { char }
    for _, p in ipairs(outlineParts) do table.insert(ex, p) end
    params.FilterDescendantsInstances = ex
    local origin = Vector3.new(pos.X, pos.Y + 10, pos.Z)
    for _ = 1, 8 do
        local res = workspace:Raycast(origin, Vector3.new(0, -250, 0), params)
        if not res then return nil end
        local hit = res.Instance
        local model = hit:FindFirstAncestorOfClass("Model")
        local skip = (State.Noclip and isEggPart(hit))
            or (model and model:FindFirstChildOfClass("Humanoid") ~= nil)
        if not skip then return res.Position.Y end
        table.insert(ex, hit)
        params.FilterDescendantsInstances = ex
    end
    return nil
end

local savedCollide = {}
local function setNoclip(on)
    if on then
        local char = getChar()
        if not char then return end
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") and d.CanCollide then
                savedCollide[d] = true
                d.CanCollide = false
            end
        end
    else
        for part in pairs(savedCollide) do
            if part.Parent then part.CanCollide = true end
            savedCollide[part] = nil
        end
    end
end

table.insert(conns, RunService.Stepped:Connect(function()
    if State.Noclip and ((State.Flight and bounds) or State.Fly) then
        setNoclip(true)
    elseif next(savedCollide) then
        setNoclip(false)
    end
end))

local waypoints, wpIndex, lastY, lastBoundsKey
local flightCap, fLastPos, fLastVel = 1, nil, nil
local wpBest, wpStuck = math.huge, 0

local function stopFlight()
    if bodyVel then bodyVel:Destroy() bodyVel = nil end
    local hum = getHum()
    if hum then hum.PlatformStand = false end
    waypoints = nil
    fLastPos, fLastVel = nil, nil
    setNoclip(false)
end

local function flightStep(dt)
    if State.Fly then -- Fly bật thì bay sát đất tạm dừng
        if bodyVel then
            bodyVel:Destroy()
            bodyVel = nil
            waypoints = nil
            fLastPos, fLastVel = nil, nil
        end
        return
    end
    if not State.Flight or not bounds then
        if bodyVel then stopFlight() end
        return
    end
    local char, hrp = getChar(), getHRP()
    if not char or not hrp then return end
    dt = math.max(dt, 1 / 240)

    local key = string.format("%.1f_%.1f_%.1f_%.1f", bounds.minX, bounds.maxX, bounds.minZ, bounds.maxZ)
    if key ~= lastBoundsKey then waypoints = nil lastBoundsKey = key end

    local p = hrp.Position
    local cx = math.clamp(p.X, bounds.minX, bounds.maxX)
    local cz = math.clamp(p.Z, bounds.minZ, bounds.maxZ)

    if not waypoints then
        waypoints = buildWaypoints(bounds)
        local best, bd = 1, math.huge
        for i, w in ipairs(waypoints) do
            local d = (Vector2.new(w.X, w.Z) - Vector2.new(cx, cz)).Magnitude
            if d < bd then best, bd = i, d end
        end
        wpIndex = best
        lastY = p.Y
        wpBest, wpStuck = math.huge, 0
        fLastPos, fLastVel = nil, nil
    end

    if not bodyVel or bodyVel.Parent ~= hrp then
        if bodyVel then bodyVel:Destroy() end
        bodyVel = Instance.new("BodyVelocity")
        bodyVel.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        bodyVel.Velocity = Vector3.zero
        bodyVel.Parent = hrp
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = true end

    -- Phát hiện bị server kéo lùi so với hướng đang bay -> tự giảm tốc độ bay, hồi dần
    if fLastPos and fLastVel then
        local moved = p - fLastPos
        local vh = Vector3.new(fLastVel.X, 0, fLastVel.Z)
        if vh.Magnitude > 5 then
            local u = vh.Unit
            local back = -(moved.X * u.X + moved.Z * u.Z)
            if back > 3 then
                flightCap = math.max(0.3, flightCap * 0.7)
                Diag.rb = Diag.rb + 1
            end
        end
    end
    flightCap = math.min(1, flightCap + dt * 0.01)
    Diag.flightCap = flightCap

    -- Độ cao: đổi từ từ (tối đa 25 studs/giây) để không giật khi gặp vật cản
    local gy = groundY(p, char)
    local desired = (gy and gy + CONFIG.FlightHeight) or lastY
    lastY = lastY + math.clamp(desired - lastY, -25 * dt, 25 * dt)
    local vy = math.clamp((lastY - p.Y) * 8, -40, 40)

    local speed = CONFIG.FlightSpeed * flightCap
    local ox, oz = p.X - cx, p.Z - cz
    local overflow = math.max(math.abs(ox), math.abs(oz))
    local vx, vz = 0, 0

    if overflow > 1.5 then
        -- ra ngoài vùng khá xa: bay mượt về lại (quá 80 studs thì đưa về ngay)
        local toIn = Vector3.new(cx - p.X, 0, cz - p.Z)
        local d = toIn.Magnitude
        if d > 80 then
            hrp.CFrame = CFrame.new(cx, p.Y, cz) * (hrp.CFrame - hrp.CFrame.Position)
            hrp.AssemblyLinearVelocity = Vector3.zero
        elseif d > 0 then
            local u = toIn.Unit
            local spd = math.min(speed, d / math.max(dt, 1 / 120))
            vx, vz = u.X * spd, u.Z * spd
        end
    else
        local wp = waypoints[wpIndex]
        local flat = Vector3.new(wp.X - p.X, 0, wp.Z - p.Z)
        local dist = flat.Magnitude

        -- Chống kẹt: 1.5 giây không tiến gần thêm điểm đến thì bỏ qua, sang điểm kế
        if dist < wpBest - 0.5 then wpBest = dist wpStuck = 0 else wpStuck = wpStuck + dt end
        if dist < 3 or wpStuck > 1.5 then
            wpIndex = wpIndex % #waypoints + 1
            wpBest, wpStuck = math.huge, 0
        end

        if dist > 0.1 then
            local u = flat.Unit
            vx, vz = u.X * speed, u.Z * speed
        end
        -- Khóa cứng: bước kế mà vượt biên thì triệt tiêu thành phần đó; lấn nhẹ ra mép thì đẩy nhẹ vào
        local nx, nz = p.X + vx * dt * 2, p.Z + vz * dt * 2
        if nx < bounds.minX or nx > bounds.maxX then vx = 0 end
        if nz < bounds.minZ or nz > bounds.maxZ then vz = 0 end
        vx = vx - ox * 5
        vz = vz - oz * 5
    end

    local vel = Vector3.new(vx, vy, vz)
    bodyVel.Velocity = vel
    fLastPos, fLastVel = p, vel
end

local lastFlightErr
table.insert(conns, RunService.Heartbeat:Connect(function(dt)
    local ok, err = pcall(flightStep, dt)
    if not ok and err ~= lastFlightErr then
        lastFlightErr = err
        warn("[Flight] " .. tostring(err))
    end
end))

----------------------------------------------------------------
-- B2. FLY BAY TRÊN KHÔNG (bay tự do; đứng yên thì giữ nguyên độ cao)
----------------------------------------------------------------
local flyVel
local flyUp, flyDown = false, false
local flyCap, fyLastPos, fyLastVel = 1, nil, nil

local function stopFly()
    if flyVel then flyVel:Destroy() flyVel = nil end
    local hum = getHum()
    if hum then hum.PlatformStand = false end
    fyLastPos, fyLastVel = nil, nil
end

local function flyStep(dt)
    if not State.Fly then
        if flyVel then stopFly() end
        return
    end
    local char, hrp, hum = getChar(), getHRP(), getHum()
    if not (char and hrp and hum) or hum.Health <= 0 then return end
    dt = math.max(dt, 1 / 240)

    if not flyVel or flyVel.Parent ~= hrp then
        if flyVel then flyVel:Destroy() end
        flyVel = Instance.new("BodyVelocity")
        flyVel.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        flyVel.Velocity = Vector3.zero
        flyVel.Parent = hrp
    end
    hum.PlatformStand = true

    local p = hrp.Position
    -- bị server kéo lùi -> tự giảm tốc độ bay, hồi dần
    if fyLastPos and fyLastVel then
        local moved = p - fyLastPos
        local vh = Vector3.new(fyLastVel.X, 0, fyLastVel.Z)
        if vh.Magnitude > 5 then
            local u = vh.Unit
            local back = -(moved.X * u.X + moved.Z * u.Z)
            if back > 3 then
                flyCap = math.max(0.3, flyCap * 0.7)
                Diag.rb = Diag.rb + 1
            end
        end
    end
    flyCap = math.min(1, flyCap + dt * 0.01)

    local speed = CONFIG.FlySpeed * flyCap
    local dir = hum.MoveDirection
    local flat = Vector3.new(dir.X, 0, dir.Z)
    local vyIn = (flyUp and 1 or 0) - (flyDown and 1 or 0)

    -- đi tới + ngước camera lên/xuống thì bay lên/xuống theo hướng nhìn
    local pitch = 0
    local cam = workspace.CurrentCamera
    if cam and flat.Magnitude > 0.05 then
        local look = cam.CFrame.LookVector
        local lh = math.sqrt(look.X * look.X + look.Z * look.Z)
        if lh > 0.05 then
            local fwd = flat:Dot(Vector3.new(look.X, 0, look.Z).Unit)
            pitch = math.clamp(fwd * (look.Y / lh), -1.5, 1.5)
        end
    end

    local v = flat * speed + Vector3.new(0, (vyIn + pitch) * speed, 0)
    if v.Magnitude > speed then v = v.Unit * speed end
    flyVel.Velocity = v
    fyLastPos, fyLastVel = p, v
end

local lastFlyErr
table.insert(conns, RunService.Heartbeat:Connect(function(dt)
    local ok, err = pcall(flyStep, dt)
    if not ok and err ~= lastFlyErr then
        lastFlyErr = err
        warn("[Fly] " .. tostring(err))
    end
end))

-- Nút ▲ ▼ trên màn hình (mobile) + phím Space / LeftShift (PC)
local flyUI = new("Frame", { Name = "FlyControls", AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(56, 124), BackgroundTransparency = 1,
    Visible = false }, gui)
local function flyButton(label, y, setter)
    local b = new("TextButton", { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(56, 56),
        BackgroundColor3 = Color3.fromRGB(14, 14, 18), Text = label, TextColor3 = RED, Font = Enum.Font.GothamBlack,
        TextSize = 24, AutoButtonColor = false, BorderSizePixel = 0 }, flyUI)
    corner(b, 14)
    stroke(b, RED, 2)
    local function isPress(i)
        return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
    end
    b.InputBegan:Connect(function(i) if isPress(i) then setter(true) end end)
    b.InputEnded:Connect(function(i) if isPress(i) then setter(false) end end)
end
flyButton("▲", 0, function(v) flyUp = v end)
flyButton("▼", 68, function(v) flyDown = v end)
onToggleChange("Fly", function()
    flyUI.Visible = State.Fly
    if not State.Fly then flyUp, flyDown = false, false end
end)

table.insert(conns, UserInputService.InputBegan:Connect(function(i, gpe)
    if gpe then return end
    if i.KeyCode == Enum.KeyCode.Space then flyUp = true
    elseif i.KeyCode == Enum.KeyCode.LeftShift or i.KeyCode == Enum.KeyCode.LeftControl then flyDown = true end
end))
table.insert(conns, UserInputService.InputEnded:Connect(function(i)
    if i.KeyCode == Enum.KeyCode.Space then flyUp = false
    elseif i.KeyCode == Enum.KeyCode.LeftShift or i.KeyCode == Enum.KeyCode.LeftControl then flyDown = false end
end))

----------------------------------------------------------------
-- C. ĐẬP TRỨNG + FAST ATTACK
----------------------------------------------------------------
local function clickPos()
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
    return Vector2.new(vp.X * 0.5, vp.Y * 0.35) -- giữa màn hình, tránh thanh hotbar ở dưới
end

local lastClick = 0
local function swingOnce()
    if CONFIG.SmashRemote then
        CONFIG.SmashRemote:FireServer(table.unpack(CONFIG.SmashRemoteArgs))
    end
    local tool = heldHammer() or (getChar() and getChar():FindFirstChildOfClass("Tool"))
    if tool then tool:Activate() end
    -- Click giả tối đa 10 lần/giây (Fast Attack dùng tool:Activate cho phần còn lại) để không spam input gây giật
    local now = os.clock()
    if now - lastClick >= 0.1 then
        lastClick = now
        VirtualUser:CaptureController()
        local pos = clickPos()
        VirtualUser:Button1Down(pos)
        VirtualUser:Button1Up(pos)
    end
end

-- Ngưng đánh khi đang chạy nhanh / ôm pet: đánh liên tục (animation + click) làm nhân vật khựng -> giật
local function pauseSmash()
    if not State.PauseOnRun then return false end
    if carrying then return true end
    if State.Speed and not State.Flight and not State.Fly then
        local hum = getHum()
        if hum and hum.MoveDirection.Magnitude > 0.05 then return true end
    end
    return false
end

-- Đánh lan rộng: chạm búa vào mọi trứng trong bán kính (firetouchinterest) hoặc gọi CONFIG.SpreadFire
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
local warnedTouch = false

local spreadCache, spreadCacheAt = {}, 0
local function spreadTargets(hrp)
    local now = os.clock()
    if now - spreadCacheAt > 0.2 then
        spreadCacheAt = now
        overlap.FilterDescendantsInstances = { getChar() }
        local found = {}
        for _, part in ipairs(workspace:GetPartBoundsInRadius(hrp.Position, CONFIG.SpreadRadius, overlap)) do
            if isEggPart(part) then
                table.insert(found, part)
                if #found >= 60 then break end
            end
        end
        spreadCache = found
    end
    return spreadCache
end

local function spreadHit()
    local hrp = getHRP()
    if not hrp then return end
    local tool = heldHammer()
    local handle = tool and tool:FindFirstChild("Handle")
    local n = 0
    for _, part in ipairs(spreadTargets(hrp)) do
        if part.Parent then
            n = n + 1
            if CONFIG.SpreadFire then
                CONFIG.SpreadFire(part)
            elseif handle and firetouchinterest then
                firetouchinterest(handle, part, 0)
                firetouchinterest(handle, part, 1)
            elseif not warnedTouch then
                warnedTouch = true
                warn("[Spread] Executor không có firetouchinterest hoặc chưa cầm búa. Đặt CONFIG.SpreadFire hoặc dùng Búa to.")
            end
        end
    end
    Diag.spreadN = n
end

local swingAcc, spreadAcc = 0, 0
table.insert(conns, RunService.Heartbeat:Connect(function(dt)
    if not State.Smash then
        swingAcc, spreadAcc = 0, 0
        Diag.smashPaused = false
        return
    end
    if pauseSmash() then
        swingAcc, spreadAcc = 0, 0
        Diag.smashPaused = true
        return
    end
    Diag.smashPaused = false

    local delay = State.FastAttack and math.max(CONFIG.FastAttackDelay, 0.0001) or math.max(CONFIG.SmashDelay, 0.02)
    local maxN = State.FastAttack and CONFIG.MaxSwingsPerFrame or 2
    swingAcc = swingAcc + math.min(dt, 0.1)
    local n = 0
    while swingAcc >= delay and n < maxN do
        swingAcc = swingAcc - delay
        n = n + 1
        pcall(swingOnce)
    end
    if swingAcc > delay * 2 then swingAcc = 0 end -- bỏ phần dồn thừa, không đánh bù một loạt

    -- AoE Fast Attack: quét lan theo nhịp đánh. Bật Fast Attack thì quét mỗi khung hình có đánh,
    -- không thì mỗi SpreadInterval giây.
    if State.Spread and n > 0 then
        spreadAcc = spreadAcc + dt
        if State.FastAttack or spreadAcc >= CONFIG.SpreadInterval then
            spreadAcc = 0
            pcall(spreadHit)
        end
    end
end))

-- Fast Attack: tăng tốc animation vung búa (bỏ animation lặp như đi/ôm pet để không làm giật)
table.insert(conns, RunService.Heartbeat:Connect(function()
    if not State.FastAttack or carrying then return end
    local animSpeed = math.clamp((1 / math.max(CONFIG.FastAttackDelay, 0.0001)) / 3, 1, 6)
    local hum = getHum()
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not animator then return end
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local pr = track.Priority
        if pr ~= Enum.AnimationPriority.Core and pr ~= Enum.AnimationPriority.Idle
            and pr ~= Enum.AnimationPriority.Movement and not track.Looped then
            if track.Speed ~= animSpeed then track:AdjustSpeed(animSpeed) end
        end
    end
end))

----------------------------------------------------------------
-- D. TĂNG TỐC CHẠY (4 kiểu) - tính trên đúng nhịp vật lý
----------------------------------------------------------------
-- Chống giật:
--  * Kiểu CFrame/WalkSpeed/Vận tốc chạy ở Stepped (trước vật lý), kiểu Heartbeat chạy sau vật lý:
--    đổi qua lại để chọn kiểu mượt nhất với game của bạn
--  * Phần cộng thêm được làm mượt, tăng dần 0.25s
--  * Bị server kéo lùi -> tự giảm tốc; kéo liên tục -> tạm dừng 6 giây
--  * Ôm pet mặc định không tăng tốc; Fast Attack không spam click giả nữa
local speedBlend, speedCap, lastPos, normalWS = 0, 1, nil, nil
local speedPausedUntil, rbEvents = 0, {}
local speedExtra, speedDir = 0, nil
local gameWS, ourWS = nil, nil   -- gameWS: WalkSpeed thật của game; ourWS: giá trị mình đang ghi (kiểu walkspeed)
local lastRbToast = 0
local speedRay = RaycastParams.new()
speedRay.FilterType = Enum.RaycastFilterType.Exclude
speedRay.RespectCanCollide = true

local function readGameWS(hum)
    local v = hum.WalkSpeed
    if not (ourWS and math.abs(v - ourWS) < 0.001) then gameWS = v end
    return gameWS or v
end

local function restoreWalkSpeed()
    local hum = getHum()
    if hum and ourWS and gameWS then
        pcall(function() hum.WalkSpeed = gameWS end)
    end
    ourWS = nil
end

local function speedActive(hum, hrp)
    if not (State.Speed and hum and hrp) then return false end
    if hum.Health <= 0 or hum.Sit then return false end
    if State.Flight and bounds then return false end
    if State.Fly then return false end
    if carrying and not State.CarryBoost then return false end
    if os.clock() < speedPausedUntil then return false end
    return true
end

table.insert(conns, player.CharacterAdded:Connect(function()
    normalWS, lastPos, speedBlend, speedCap, rbEvents, carrying = nil, nil, 0, 1, {}, false
    speedExtra, speedDir, gameWS, ourWS = 0, nil, nil, nil
end))

task.spawn(function()
    while gui.Parent do
        local char, hum = getChar(), getHum()
        local c = false
        local ws = gameWS or (hum and hum.WalkSpeed)
        if ws and normalWS and ws < normalWS * 0.95 then c = true end
        if char and not c then
            for _, d in ipairs(char:GetChildren()) do
                if d:IsA("Model") or d:IsA("Accessory") or d:IsA("Tool") then
                    local n = string.lower(d.Name)
                    for _, k in ipairs(CONFIG.CarryKeywords) do
                        if string.find(n, k, 1, true) then c = true break end
                    end
                end
                if c then break end
            end
        end
        carrying = c
        Diag.carrying = c
        task.wait(0.3)
    end
end)

local function speedTick(dt, phase)
    local mode = CONFIG.SpeedMode
    local owner = (mode == "heartbeat") and "heartbeat" or "stepped"
    if phase ~= owner then return end
    dt = math.clamp(dt, 1 / 240, 1 / 20)

    local hum, hrp = getHum(), getHRP()
    local ws = hum and readGameWS(hum) or nil
    if ws and (not normalWS or ws > normalWS) then normalWS = ws end
    Diag.gameWS = ws
    Diag.paused = os.clock() < speedPausedUntil

    local active = speedActive(hum, hrp)
    local dir = active and hum.MoveDirection or Vector3.zero
    if not active or dir.Magnitude < 0.05 then
        speedBlend, speedExtra, lastPos, speedDir = 0, 0, nil, nil
        if ourWS then restoreWalkSpeed() end
        return
    end
    if mode ~= "walkspeed" and ourWS then restoreWalkSpeed() end
    dir = Vector3.new(dir.X, 0, dir.Z).Unit
    speedDir = dir

    -- bị server kéo lùi (rubber-band): lùi > 1.5 studs so với hướng đi
    if lastPos then
        local moved = hrp.Position - lastPos
        local back = -(moved.X * dir.X + moved.Z * dir.Z)
        if back > 1.5 then
            speedCap = speedCap * 0.6
            if speedCap < 0.05 then speedCap = 0 end
            Diag.rb = Diag.rb + 1
            local now = os.clock()
            if now - lastRbToast > 6 then
                lastRbToast = now
                toast("⚠ Bị server kéo lại → tự giảm tốc")
            end
            table.insert(rbEvents, now)
            while #rbEvents > 0 and now - rbEvents[1] > 4 do table.remove(rbEvents, 1) end
            if #rbEvents >= 3 then
                speedPausedUntil = now + 6
                speedCap = 0.5
                rbEvents = {}
                lastPos, speedExtra = nil, 0
                if ourWS then restoreWalkSpeed() end
                toast("⏸ Tạm dừng tăng tốc 6 giây (bị kéo liên tục)")
                return
            end
        end
    end
    speedCap = math.min(1, speedCap + dt * 0.003)
    Diag.speedCap = speedCap

    local target = CONFIG.WalkSpeed * (ws / math.max(normalWS, 1))
    speedBlend = math.min(1, speedBlend + dt / 0.25)
    local want = math.max(0, target - ws) * speedBlend * speedCap
    speedExtra = speedExtra + (want - speedExtra) * math.min(1, dt * 10) -- làm mượt

    if mode == "cframe" or mode == "heartbeat" then
        if speedExtra > 0.05 then
            local step = dir * speedExtra * dt
            speedRay.FilterDescendantsInstances = { getChar() }
            if not workspace:Raycast(hrp.Position, dir * (step.Magnitude + 2), speedRay) then
                hrp.CFrame = hrp.CFrame + step
            end
        end
    elseif mode == "walkspeed" then
        if speedExtra > 0.05 then
            local total = ws + speedExtra
            ourWS = total
            if hum.WalkSpeed ~= total then hum.WalkSpeed = total end
        elseif ourWS then
            restoreWalkSpeed()
        end
    else -- velocity
        if speedExtra > 0.05 then
            local total = ws + speedExtra
            local v = hrp.AssemblyLinearVelocity
            hrp.AssemblyLinearVelocity = Vector3.new(dir.X * total, v.Y, dir.Z * total)
        end
    end
    lastPos = hrp.Position
end

table.insert(conns, RunService.Stepped:Connect(function(_, dt) speedTick(dt, "stepped") end))
table.insert(conns, RunService.Heartbeat:Connect(function(dt) speedTick(dt, "heartbeat") end))

-- Ping / FPS ở giữa footer (giúp biết giật là do mạng hay do máy)
local fpsFrames = 0
table.insert(conns, RunService.Heartbeat:Connect(function() fpsFrames = fpsFrames + 1 end))
task.spawn(function()
    local Stats = game:GetService("Stats")
    while gui.Parent do
        task.wait(0.5)
        local fps = fpsFrames * 2
        fpsFrames = 0
        local ping = 0
        pcall(function() ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
        perfLabel.Text = string.format("📶 %d ms  •  %d FPS", math.floor(ping), fps)
        perfLabel.TextColor3 = (ping > 250 or fps < 25) and YELLOW or GRAY
    end
end)

----------------------------------------------------------------
-- STATUS
----------------------------------------------------------------
task.spawn(function()
    while gui.Parent do
        local txt, col = "Đang đứng yên", GREEN
        if State.Flight and not bounds then
            txt, col = "Chưa đặt vùng bay!", YELLOW
        elseif State.Flight and State.Smash then
            txt = "Bay sát đất + đập trứng"
        elseif State.Smash then
            txt = "Đang đập trứng"
        elseif State.Flight then
            txt = "Đang bay sát mặt đất"
        end
        if State.Smash and Diag.smashPaused then txt, col = "Tạm ngưng đánh (đang chạy/ôm pet)", YELLOW end
        local extra = {}
        if State.Speed then
            table.insert(extra, Diag.paused and "⚡ Speed tạm dừng" or ("⚡ Speed " .. CONFIG.WalkSpeed))
        end
        if State.FastAttack then table.insert(extra, "🔥 Fast " .. CONFIG.FastAttackDelay .. "s") end
        if State.Fly then table.insert(extra, "✈ Fly " .. CONFIG.FlySpeed) end
        if State.Spread then table.insert(extra, "💫 Lan " .. CONFIG.SpreadRadius .. " (" .. (Diag.spreadN or 0) .. ")") end
        if State.BigHammer then table.insert(extra, "🔨 Búa x" .. CONFIG.HammerScale) end
        if #extra > 0 then txt = txt .. "\n" .. table.concat(extra, "  ") end
        statusValue.Text = txt
        statusValue.TextColor3 = col
        flyUI.Visible = State.Fly

        local hum = getHum()
        diagLabel.Text = string.format("WS %s • RB %d • tốc %d%% • bay %d%%%s",
            Diag.gameWS and tostring(math.floor(Diag.gameWS)) or "?", Diag.rb,
            math.floor(Diag.speedCap * 100), math.floor(Diag.flightCap * 100),
            (Diag.carrying and " • ÔM" or "") .. " • " .. CONFIG.SpeedMode)
        task.wait(0.3)
    end
end)

table.insert(conns, player.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end))

----------------------------------------------------------------
-- ĐÓNG / DỌN DẸP
----------------------------------------------------------------
local function destroyAll()
    State.Equip, State.Flight, State.Smash, State.Speed, State.FastAttack, State.AutoHop =
        false, false, false, false, false, false
    State.BigHammer = false
    State.Fly, State.Spread = false, false
    pcall(stopFly)
    pcall(restoreHammers)
    pcall(restoreWalkSpeed)
    pcall(stopFlight)
    clearOutline()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    if gui then gui:Destroy() end
end
env.__BrainrotCleanup = destroyAll
closeBtn.MouseButton1Click:Connect(destroyAll)

task.spawn(scanServers)

end -- hết safeMain()

-- V6: chạy script chính; lỗi runtime -> hiện hộp đỏ báo lỗi + số dòng để dễ sửa
local ok, err = xpcall(safeMain, function(e)
    local tb = ""
    pcall(function() tb = "\n" .. debug.traceback(tostring(e), 2) end)
    return tostring(e) .. tb
end)
if not ok then
    warn("[BrainrotEggBreaker v6] LỖI: " .. tostring(err))
    pcall(function()
        local sg = Instance.new("ScreenGui")
        sg.Name = "BrainrotEggBreakerError"
        sg.ResetOnSpawn = false
        sg.Parent = player:WaitForChild("PlayerGui")
        local box = Instance.new("TextLabel")
        box.BackgroundColor3 = Color3.fromRGB(40, 0, 0)
        box.BackgroundTransparency = 0.1
        box.TextColor3 = Color3.new(1, 1, 1)
        box.Font = Enum.Font.Gotham
        box.TextSize = 12
        box.TextWrapped = true
        box.TextXAlignment = Enum.TextXAlignment.Left
        box.TextYAlignment = Enum.TextYAlignment.Top
        box.Size = UDim2.new(0.9, 0, 0.45, 0)
        box.Position = UDim2.new(0.05, 0, 0.05, 0)
        box.Text = "❌ BRAINROT EGG BREAKER v6 - LỖI:\n" .. tostring(err)
            .. "\n\nChụp màn hình lỗi này gửi lại để được sửa tiếp."
        box.Parent = sg
        local pad = Instance.new("UIPadding", box)
        pad.PaddingTop, pad.PaddingLeft, pad.PaddingRight, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 10)
        local close = Instance.new("TextButton")
        close.Text = "X ĐÓNG"
        close.Font = Enum.Font.GothamBold
        close.TextSize = 12
        close.TextColor3 = Color3.new(1, 1, 1)
        close.BackgroundColor3 = Color3.fromRGB(120, 0, 0)
        close.Size = UDim2.new(0, 80, 0, 26)
        close.Position = UDim2.new(1, -90, 1, -34)
        close.Parent = sg
        close.MouseButton1Click:Connect(function() sg:Destroy() end)
    end)
end
