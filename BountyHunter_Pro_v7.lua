-- ================================================================
-- BOUNTY HUNTER PRO v7 - BLOX FRUITS
-- Clean rewrite: fix all bugs, kite mode, auto haki/v3/v4/pvp
-- ================================================================
repeat task.wait() until game:IsLoaded() and game.Players.LocalPlayer

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local StarterGui  = game:GetService("StarterGui")
local RS          = game:GetService("ReplicatedStorage")
local TS          = game:GetService("TeleportService")
local VIM         = game:GetService("VirtualInputManager")

local LP  = Players.LocalPlayer
local Cam = workspace.CurrentCamera

-- ================================================================
-- HELPERS (định nghĩa trước, dùng sau)
-- ================================================================
local function GetChar() return LP.Character end
local function GetHRP()
    local c = GetChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function GetHum()
    local c = GetChar()
    return c and c:FindFirstChild("Humanoid")
end
local function IsAlive(p)
    if not p or not p.Character then return false end
    local h = p.Character:FindFirstChildOfClass("Humanoid")
    return h ~= nil and h.Health > 0
end
local function GetMyHPPct()
    local h = GetHum()
    if not h or h.MaxHealth <= 0 then return 1 end
    return h.Health / h.MaxHealth
end

-- ================================================================
-- STATE
-- ================================================================
local S = {
    Running        = true,
    Target         = nil,
    TargetTimer    = 0,
    TargetReached  = false,
    SkillAllowed   = false,
    KiteMode       = false,
    InSafeZone     = false,
    AttackEnabled  = true,
    KillCount      = 0,
    CurrentWeapon  = "Melee",
    WeaponSwapTimer= 0,
    SkillActive    = false,
    ChaseTimeout   = 120,
    JobId          = game.JobId,
    Blacklist      = {},
    HopBusy        = false,
    -- "hunting" | "flying" | "kiting" | "safezone" | "waiting" | "hopping"
    Status         = "hunting",
    VisitedServers = {},
}

-- ================================================================
-- CONFIG
-- ================================================================
local CFG = {
    SafeZoneHP   = { Low = 4500, Full = 6000 },
    KiteHP       = { Enter = 0.50, Exit = 0.70 },
    FlySpeed     = 380,
    KiteHeight   = 160,
    KiteDist     = 100,
    HopMin       = 8,
    HopMax       = 10,
    ChaseTimeout = 120,
    SkillKeys    = { "Z", "X", "C", "V" },
    HoldTime     = 0.1,
    WebhookUrl   = "",
    Team         = getgenv().Team or "Pirates",
}

-- ================================================================
-- NOCLIP
-- ================================================================
RunService.Stepped:Connect(function()
    local c = GetChar()
    if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end
end)

-- ================================================================
-- GRAVITY / MOVERS
-- ================================================================
local function Grav(on) workspace.Gravity = on and 196.2 or 0 end

local function SetBV(v)
    local hrp = GetHRP(); if not hrp then return end
    local bv = hrp:FindFirstChild("_BV") or Instance.new("BodyVelocity", hrp)
    bv.Name = "_BV"; bv.MaxForce = Vector3.new(1e9,1e9,1e9); bv.P = 1e5; bv.Velocity = v
end
local function SetBP(pos)
    local hrp = GetHRP(); if not hrp then return end
    local bp = hrp:FindFirstChild("_BP") or Instance.new("BodyPosition", hrp)
    bp.Name = "_BP"; bp.MaxForce = Vector3.new(1e9,1e9,1e9); bp.D = 300; bp.P = 5e4; bp.Position = pos
end
local function SetBG(cf)
    local hrp = GetHRP(); if not hrp then return end
    local bg = hrp:FindFirstChild("_BG") or Instance.new("BodyGyro", hrp)
    bg.Name = "_BG"; bg.MaxTorque = Vector3.new(1e9,1e9,1e9); bg.D = 200; bg.CFrame = cf
end
local function ClearMovers()
    local hrp = GetHRP(); if not hrp then return end
    for _, n in ipairs({"_BV","_BP","_BG"}) do
        local o = hrp:FindFirstChild(n); if o then o:Destroy() end
    end
end

-- ================================================================
-- REMOTE SCANNER — scan toàn bộ RS, không phụ thuộc folder
-- ================================================================
local function ScanRemotes(keyword)
    -- trả về list remote có tên chứa keyword (case-insensitive)
    local results = {}
    local kw = keyword:lower()
    for _, obj in ipairs(RS:GetDescendants()) do
        if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction"))
            and obj.Name:lower():find(kw, 1, true) then
            table.insert(results, obj)
        end
    end
    return results
end
local function FireRemotes(keyword, ...)
    for _, r in ipairs(ScanRemotes(keyword)) do
        pcall(function()
            if r:IsA("RemoteEvent") then r:FireServer(...) end
        end)
    end
end
local function PressHotkey(keyCode)
    pcall(function() VIM:SendKeyEvent(true,  keyCode, false, game) end)
    task.wait(0.05)
    pcall(function() VIM:SendKeyEvent(false, keyCode, false, game) end)
end

-- ================================================================
-- AUTO POWER: V3, V4, HAKI (chạy liên tục mỗi 1.5s)
-- ================================================================
task.spawn(function()
    task.wait(4) -- chờ game load đủ remote
    while S.Running do
        pcall(function()
            -- V4
            FireRemotes("v4")
            FireRemotes("race4")
            FireRemotes("transform4")
            -- V3
            FireRemotes("v3")
            FireRemotes("race3")
            FireRemotes("transform3")
            -- Buso Haki / Armament
            FireRemotes("buso", true)
            FireRemotes("armament", true)
            FireRemotes("haki", true)
            FireRemotes("aura", true)
            -- Ken Haki / Observation
            FireRemotes("ken", true)
            FireRemotes("observation", true)
            -- Phím tắt H = Buso, J = Ken (Blox Fruits mặc định)
            PressHotkey(Enum.KeyCode.H)
            task.wait(0.1)
            PressHotkey(Enum.KeyCode.J)
        end)
        task.wait(1.5)
    end
end)

-- ================================================================
-- AUTO PVP (chạy mỗi 4s và khi respawn)
-- ================================================================
local function TurnOnPVP()
    pcall(function()
        FireRemotes("pvp", true)
        FireRemotes("pvp")
        LP:SetAttribute("PVP", true)
    end)
end
task.spawn(function()
    task.wait(3)
    while S.Running do
        TurnOnPVP()
        task.wait(4)
    end
end)

-- ================================================================
-- JOIN TEAM
-- ================================================================
local function JoinTeam()
    pcall(function()
        local tn = CFG.Team:lower()
        for _, t in ipairs(game.Teams:GetTeams()) do
            if t.Name:lower():find(tn, 1, true) then
                FireRemotes("jointeam", t)
                FireRemotes("team", t)
            end
        end
    end)
end

-- ================================================================
-- PVP CHECK — kiểm tra target có thể tấn công không
-- ================================================================
local function CanAttack(p)
    if not p or not p.Character then return false end
    -- Kiểm tra attribute PVP = false
    local pvp = p:GetAttribute("PVP") or p:GetAttribute("pvp") or p:GetAttribute("IsPVP")
    if pvp == false then return false end
    -- Kiểm tra safe zone attribute
    local safe = p:GetAttribute("InSafeZone") or p:GetAttribute("SafeZone") or p:GetAttribute("isSafe")
    if safe == true then return false end
    -- Kiểm tra BoolValue PVP
    local pf = p:FindFirstChild("PVP") or (p.Character and p.Character:FindFirstChild("PVP"))
    if pf and pf:IsA("BoolValue") and pf.Value == false then return false end
    -- Kiểm tra safe zone tag trên character
    if p.Character then
        if p.Character:FindFirstChild("SafeZone") or p.Character:FindFirstChild("InSafeZone") then
            return false
        end
    end
    return true
end

-- ================================================================
-- TARGET SELECTION
-- ================================================================
local function GetTargets()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and IsAlive(p) and not S.Blacklist[p.UserId] and CanAttack(p) then
            table.insert(list, p)
        end
    end
    return list
end
local function PickTarget(exclude)
    local list = GetTargets()
    local out = {}
    for _, p in ipairs(list) do
        if p ~= exclude then table.insert(out, p) end
    end
    if #out == 0 then return nil end
    return out[math.random(1, #out)]
end

-- ================================================================
-- SKILL SPAM
-- ================================================================
local SkillTasks = {}
local function StopSkills()
    for _, t in pairs(SkillTasks) do pcall(task.cancel, t) end
    SkillTasks = {}
    S.SkillActive = false
end
local function PressSkillKey(keyCode, hold)
    task.spawn(function()
        S.SkillActive = true
        pcall(function() VIM:SendKeyEvent(true,  keyCode, false, game) end)
        if hold > 0 then task.wait(hold) end
        pcall(function() VIM:SendKeyEvent(false, keyCode, false, game) end)
        task.wait(0.02)
        S.SkillActive = false
    end)
end
local function StartSkills()
    StopSkills()
    for _, key in ipairs(CFG.SkillKeys) do
        local ke = Enum.KeyCode[key]
        if ke then
            SkillTasks[key] = task.spawn(function()
                while S.Running do
                    if S.SkillAllowed and not S.KiteMode and S.AttackEnabled then
                        PressSkillKey(ke, CFG.HoldTime)
                    end
                    task.wait() -- next frame
                end
            end)
        end
    end
end

-- ================================================================
-- WEAPON SWAP
-- ================================================================
local function SwapWeapon()
    local c = GetChar(); if not c then return end
    local h = GetHum(); if not h then return end
    -- lấy tool đang cầm
    local held = c:FindFirstChildOfClass("Tool")
    local wType = held and held:GetAttribute("WeaponType") or S.CurrentWeapon
    local nextType = wType == "Melee" and "Sword" or "Melee"
    -- tìm trong backpack
    for _, t in ipairs(LP.Backpack:GetChildren()) do
        if t:IsA("Tool") and t:GetAttribute("WeaponType") == nextType then
            pcall(function() h:EquipTool(t) end)
            S.CurrentWeapon = nextType
            return
        end
    end
    -- không có loại kia, giữ nguyên
    if held then pcall(function() h:EquipTool(held) end) end
end

-- ================================================================
-- SERVER HOP — tìm server 8-10 người, không full
-- ================================================================
local function HopServer()
    if S.HopBusy then return end
    S.HopBusy = true; S.Status = "hopping"
    StopSkills(); S.SkillAllowed = false; S.KiteMode = false

    task.spawn(function()
        while S.Running do
            local ok, data = pcall(function()
                return HttpService:JSONDecode(
                    game:HttpGet("https://games.roblox.com/v1/games/"
                        ..game.PlaceId.."/servers/Public?sortOrder=Desc&limit=100")
                )
            end)
            if ok and data and data.data then
                local good, fallback = {}, {}
                for _, sv in ipairs(data.data) do
                    local playing = sv.playing or 0
                    local maxP    = sv.maxPlayers or 99
                    local full    = playing >= maxP
                    if sv.id ~= S.JobId and not S.VisitedServers[sv.id] and not full then
                        if playing >= CFG.HopMin and playing <= CFG.HopMax then
                            table.insert(good, sv)
                        elseif playing > 0 then
                            table.insert(fallback, sv)
                        end
                    end
                end
                local pool = #good > 0 and good or fallback
                if #pool > 0 then
                    local sv = pool[math.random(1, #pool)]
                    S.VisitedServers[sv.id] = true
                    local ok2 = pcall(TS.TeleportToPlaceInstance, TS, game.PlaceId, sv.id, LP)
                    if ok2 then task.wait(10) end
                else
                    S.VisitedServers = {} -- reset, thử lại
                end
            end
            task.wait(1)
        end
    end)
end

-- ================================================================
-- WEBHOOK
-- ================================================================
local function Webhook(name, bounty)
    if CFG.WebhookUrl == "" then return end
    pcall(function()
        game:HttpPost(CFG.WebhookUrl, HttpService:JSONEncode({embeds={{
            title = "🏴‍☠️ Kill!",
            description = "**"..name.."** | 💰 "..tostring(bounty),
            color = 0xFF5500
        }}}), false, "application/json")
    end)
end

-- ================================================================
-- FLY SYSTEM (Heartbeat)
-- ================================================================
local SWAP_CD = 3.5

RunService.Heartbeat:Connect(function(dt)
    if not S.Running then return end
    local hrp = GetHRP()
    local hum = GetHum()
    if not hrp or not hum then return end

    hum.PlatformStand = true
    Grav(false)

    -- == HOPPING / WAITING: bay lên trời ==
    if S.Status == "hopping" or S.Status == "waiting" then
        local safeY = 9999
        if hrp.Position.Y < safeY - 100 then
            SetBV(Vector3.new(0, CFG.FlySpeed, 0))
            local bp = hrp:FindFirstChild("_BP"); if bp then bp:Destroy() end
        else
            SetBV(Vector3.new(0,0,0))
            SetBP(Vector3.new(hrp.Position.X, safeY, hrp.Position.Z))
        end
        return
    end

    -- == SAFE ZONE: đứng yên ==
    if S.Status == "safezone" then
        SetBV(Vector3.new(0,0,0))
        return
    end

    -- Không có target
    if not S.Target or not IsAlive(S.Target) then
        S.SkillAllowed = false; S.KiteMode = false
        SetBV(Vector3.new(0,0,0)); return
    end

    local tHRP = S.Target.Character:FindFirstChild("HumanoidRootPart")
    if not tHRP then SetBV(Vector3.new(0,0,0)); return end

    local myPos = hrp.Position
    local tPos  = tHRP.Position

    -- == KITE MODE: máu thấp, bay lên xa ==
    if S.KiteMode then
        S.SkillAllowed = false
        local kiteTargetY = tPos.Y + CFG.KiteHeight
        local dist = (myPos - tPos).Magnitude

        local goalPos
        if dist < CFG.KiteDist then
            -- Quá gần: bay lùi + lên cao
            local away = (myPos - tPos)
            away = Vector3.new(away.X, 0, away.Z)
            if away.Magnitude > 0.01 then away = away.Unit end
            goalPos = myPos + away * 60 + Vector3.new(0, CFG.KiteHeight, 0)
            SetBV((goalPos - myPos).Unit * CFG.FlySpeed)
        else
            -- Đủ xa: hover giữ khoảng cách
            goalPos = Vector3.new(myPos.X, kiteTargetY, myPos.Z)
            SetBP(goalPos)
            SetBV(Vector3.new(0,0,0))
        end
        SetBG(CFrame.lookAt(myPos, Vector3.new(tPos.X, myPos.Y, tPos.Z)))
        return
    end

    -- == NORMAL: bay đến target và attack ==
    local goal = tPos + Vector3.new(0, 3, 0)
    local dist = (goal - myPos).Magnitude

    -- Swap weapon theo cooldown
    if tick() - S.WeaponSwapTimer > SWAP_CD then
        S.WeaponSwapTimer = tick()
        task.spawn(SwapWeapon)
    end

    if dist > 10 then
        -- Bay đến
        S.SkillAllowed = false
        S.Status = "flying"
        local dir = (goal - myPos).Unit
        SetBV(dir * CFG.FlySpeed)
        SetBG(CFrame.lookAt(myPos, myPos + dir))
        local bp = hrp:FindFirstChild("_BP"); if bp then bp:Destroy() end
    else
        -- Đã đến: bắt đầu tính timer + spam skill
        if not S.TargetReached then
            S.TargetReached = true
            S.TargetTimer   = tick()
            StartSkills()    -- bắt đầu skill loop ngay khi đến nơi
        end
        S.SkillAllowed = true
        S.Status       = "hunting"
        SetBV(Vector3.new(0,0,0))
        SetBP(Vector3.new(myPos.X, goal.Y, myPos.Z))
        SetBG(CFrame.lookAt(myPos, Vector3.new(tPos.X, myPos.Y, tPos.Z)))
    end
end)

-- ================================================================
-- HP MONITOR: kite logic + safe zone
-- ================================================================
task.spawn(function()
    while task.wait(0.15) do
        if not S.Running then break end
        local hum = GetHum()
        if not hum or hum.MaxHealth <= 0 then continue end

        local pct = hum.Health / hum.MaxHealth

        -- Safe zone (máu cực thấp)
        if hum.Health <= CFG.SafeZoneHP.Low and not S.InSafeZone then
            S.InSafeZone   = true
            S.AttackEnabled= false
            S.SkillAllowed = false
            S.KiteMode     = false
            S.Status       = "safezone"
            StopSkills(); ClearMovers(); Grav(false)
        elseif S.InSafeZone and hum.Health >= CFG.SafeZoneHP.Full then
            S.InSafeZone   = false
            S.AttackEnabled= true
            S.Status       = "hunting"
        end

        if S.InSafeZone then continue end

        -- Kite mode
        if pct < CFG.KiteHP.Enter and not S.KiteMode and S.Target then
            S.KiteMode    = true
            S.SkillAllowed= false
            S.Status      = "kiting"
            StopSkills()
        elseif pct >= CFG.KiteHP.Exit and S.KiteMode then
            S.KiteMode     = false
            S.TargetReached= false   -- bay lại gần target
            S.SkillAllowed = false
            S.Status       = "hunting"
        end
    end
end)

-- ================================================================
-- MAIN LOOP
-- ================================================================
task.spawn(function()
    task.wait(3)
    JoinTeam()
    TurnOnPVP()

    while S.Running do
        task.wait(0.15)
        if S.Status == "hopping" or S.Status == "safezone" then continue end

        -- Target chết → kill, blacklist
        if S.Target and not IsAlive(S.Target) then
            S.KillCount = S.KillCount + 1
            local bounty = 0
            pcall(function()
                bounty = S.Target:GetAttribute("Bounty") or 0
                if bounty == 0 and S.Target.leaderstats then
                    local b = S.Target.leaderstats:FindFirstChild("Bounty")
                    if b then bounty = b.Value end
                end
            end)
            Webhook(S.Target.Name, bounty)
            S.Blacklist[S.Target.UserId] = true
            S.Target       = nil
            S.SkillAllowed = false
            S.KiteMode     = false
            S.TargetReached= false
            StopSkills()
        end

        -- Cần target mới
        if not S.Target then
            local t = PickTarget(nil)
            if t then
                S.Target       = t
                S.TargetTimer  = tick()
                S.TargetReached= false
                S.SkillAllowed = false
                S.KiteMode     = false
                S.Status       = "hunting"
            else
                S.Status = "waiting"
                HopServer()
                continue
            end
        end

        -- Target tắt PVP → đổi target khác (không blacklist vĩnh viễn)
        if S.Target and not CanAttack(S.Target) then
            local t = PickTarget(S.Target)
            if t then
                S.Target       = t
                S.TargetTimer  = tick()
                S.TargetReached= false
                S.SkillAllowed = false
                S.KiteMode     = false
                S.Status       = "hunting"
                StopSkills()
            else
                S.Status = "waiting"; HopServer()
            end
            continue
        end

        -- Timeout 2 phút (chỉ tính sau khi đến nơi)
        if S.TargetReached and (tick() - S.TargetTimer) >= CFG.ChaseTimeout then
            S.Blacklist[S.Target.UserId] = true
            local t = PickTarget(nil)
            if t then
                S.Target       = t
                S.TargetTimer  = tick()
                S.TargetReached= false
                S.SkillAllowed = false
                S.KiteMode     = false
                S.Status       = "hunting"
                StopSkills()
            else
                S.Status = "waiting"; HopServer()
            end
        end
    end
end)

-- ================================================================
-- AIMBOT
-- ================================================================
local FOVCircle = Drawing.new("Circle")
FOVCircle.Color=Color3.fromRGB(255,80,80); FOVCircle.Thickness=1.5
FOVCircle.Filled=false; FOVCircle.NumSides=64; FOVCircle.Radius=150; FOVCircle.Visible=true

local AimArrow = Drawing.new("Triangle")
AimArrow.Color=Color3.fromRGB(0,255,120); AimArrow.Filled=true; AimArrow.Transparency=0.4

local AimLine = Drawing.new("Line")
AimLine.Color=Color3.fromRGB(255,200,0); AimLine.Thickness=1.5; AimLine.Transparency=0.5

RunService.RenderStepped:Connect(function()
    local mp = UIS:GetMouseLocation()
    FOVCircle.Position = mp

    local aimT = (IsAlive(S.Target) and S.Target) or nil
    if not aimT then
        -- fallback: player gần tâm màn hình nhất trong FOV
        local best, bestD = nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and IsAlive(p) then
                local root = p.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    local sp, on = Cam:WorldToViewportPoint(root.Position)
                    if on then
                        local d = (Vector2.new(sp.X,sp.Y)-mp).Magnitude
                        if d < 150 and d < bestD then bestD=d; best=p end
                    end
                end
            end
        end
        aimT = best
    end

    if aimT and aimT.Character then
        local root = aimT.Character:FindFirstChild("HumanoidRootPart")
        if root then
            local predicted = root.Position + root.Velocity * 0.13
            local smooth = S.SkillActive and 0.18 or 0.07
            Cam.CFrame = Cam.CFrame:Lerp(CFrame.new(Cam.CFrame.Position, predicted), smooth)
            local sp, on = Cam:WorldToViewportPoint(predicted)
            local ctr = Vector2.new(Cam.ViewportSize.X/2, Cam.ViewportSize.Y/2)
            if on then
                local ts = Vector2.new(sp.X, sp.Y)
                local ud = (ts-ctr).Magnitude>0 and (ts-ctr).Unit or Vector2.new(0,-1)
                local tip = ctr + ud * math.min((ts-ctr).Magnitude,100)
                local pr  = Vector2.new(-ud.Y, ud.X)
                AimArrow.PointA=tip; AimArrow.PointB=tip-ud*18+pr*8; AimArrow.PointC=tip-ud*18-pr*8
                AimArrow.Visible=true; AimLine.From=ctr; AimLine.To=ts; AimLine.Visible=true
            else
                local ed = (Vector2.new(sp.X,sp.Y)-ctr).Unit
                local edge = ctr + ed*130
                local pr = Vector2.new(-ed.Y,ed.X)
                AimArrow.PointA=edge; AimArrow.PointB=edge-ed*18+pr*8; AimArrow.PointC=edge-ed*18-pr*8
                AimArrow.Visible=true; AimLine.Visible=false
            end
            return
        end
    end
    AimArrow.Visible=false; AimLine.Visible=false
end)

-- ================================================================
-- ESP
-- ================================================================
local ESPs = {}
local function MakeESP(p)
    if ESPs[p] then return end
    local bg = Instance.new("BillboardGui")
    bg.Size=UDim2.new(0,190,0,55); bg.StudsOffset=Vector3.new(0,4,0); bg.AlwaysOnTop=true
    local nL = Instance.new("TextLabel",bg)
    nL.Size=UDim2.new(1,0,0.55,0); nL.BackgroundTransparency=1
    nL.TextStrokeTransparency=0; nL.Font=Enum.Font.GothamBold; nL.TextScaled=true
    local dL = Instance.new("TextLabel",bg)
    dL.Size=UDim2.new(1,0,0.45,0); dL.Position=UDim2.new(0,0,0.55,0)
    dL.BackgroundTransparency=1; dL.Font=Enum.Font.Gotham; dL.TextScaled=true
    dL.TextStrokeTransparency=0
    ESPs[p] = {bg=bg, nL=nL, dL=dL}
    RunService.RenderStepped:Connect(function()
        local c = p.Character
        if not c then return end
        local root = c:FindFirstChild("HumanoidRootPart")
        local myRoot = GetHRP()
        if root and myRoot then
            bg.Parent = root
            local d = math.floor((root.Position-myRoot.Position).Magnitude)
            local pvp = CanAttack(p)
            local isT = S.Target==p
            local skip= S.Blacklist[p.UserId]
            nL.Text = p.Name..(isT and " 🎯" or skip and " ✗" or "")
            dL.Text = d.."u "..(pvp and "⚔️" or "🛡")
            nL.TextColor3 = isT and Color3.fromRGB(255,50,50)
                or skip and Color3.fromRGB(110,110,110)
                or not pvp and Color3.fromRGB(80,120,255)
                or Color3.fromRGB(255,220,50)
            dL.TextColor3 = Color3.fromRGB(200,200,200)
        end
    end)
end
for _, p in ipairs(Players:GetPlayers()) do if p~=LP then MakeESP(p) end end
Players.PlayerAdded:Connect(MakeESP)
Players.PlayerRemoving:Connect(function(p)
    if ESPs[p] then
        if ESPs[p].bg then ESPs[p].bg:Destroy() end
        ESPs[p] = nil
    end
end)

-- ================================================================
-- UI
-- ================================================================
local old = LP.PlayerGui:FindFirstChild("BountyUI")
if old then old:Destroy() end

local SG = Instance.new("ScreenGui", LP.PlayerGui)
SG.Name="BountyUI"; SG.ResetOnSpawn=false; SG.IgnoreGuiInset=true
SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling

-- Fullscreen avatar (bust rõ hơn headshot)
local AvtBG = Instance.new("ImageLabel", SG)
AvtBG.Size=UDim2.new(1,0,1,0); AvtBG.Position=UDim2.new(0,0,0,0)
AvtBG.BackgroundTransparency=1
AvtBG.Image="rbxthumb://type=AvatarBust&id=16060333448&w=420&h=420"
AvtBG.ImageTransparency=0.5; AvtBG.ScaleType=Enum.ScaleType.Stretch; AvtBG.ZIndex=1

-- Dark overlay
local Ovl = Instance.new("Frame",SG)
Ovl.Size=UDim2.new(1,0,1,0); Ovl.BackgroundColor3=Color3.fromRGB(0,0,8)
Ovl.BackgroundTransparency=0.70; Ovl.BorderSizePixel=0; Ovl.ZIndex=2

-- Center panel
local Panel = Instance.new("Frame",SG)
Panel.Size=UDim2.new(0,460,0,300); Panel.Position=UDim2.new(0.5,-230,0.5,-160)
Panel.BackgroundColor3=Color3.fromRGB(5,10,20); Panel.BackgroundTransparency=0.35
Panel.BorderSizePixel=0; Panel.ZIndex=5
Instance.new("UICorner",Panel).CornerRadius=UDim.new(0,14)
local pStroke = Instance.new("UIStroke",Panel)
pStroke.Color=Color3.fromRGB(60,160,255); pStroke.Thickness=1.5; pStroke.Transparency=0.4

local function Lbl(parent, text, size, pos, color, font, zi)
    local l=Instance.new("TextLabel",parent)
    l.Text=text; l.Size=size; l.Position=pos; l.BackgroundTransparency=1
    l.TextColor3=color; l.Font=font or Enum.Font.Gotham
    l.TextScaled=true; l.TextStrokeTransparency=0.4; l.ZIndex=zi or 6
    return l
end

local Title = Lbl(Panel,"🏴‍☠️ Bounty Hunter Pro v7",
    UDim2.new(1,-20,0,38), UDim2.new(0,10,0,8),
    Color3.fromRGB(80,200,255), Enum.Font.GothamBlack)

-- Divider
local div=Instance.new("Frame",Panel); div.ZIndex=6
div.Size=UDim2.new(1,-30,0,1); div.Position=UDim2.new(0,15,0,52)
div.BackgroundColor3=Color3.fromRGB(60,160,255); div.BackgroundTransparency=0.5
div.BorderSizePixel=0

local TargLbl  = Lbl(Panel,"🎯 --", UDim2.new(1,-20,0,28), UDim2.new(0,10,0,58), Color3.fromRGB(255,255,255), Enum.Font.GothamBold)
local HPLbl    = Lbl(Panel,"❤️ --",  UDim2.new(1,-20,0,22), UDim2.new(0,10,0,88), Color3.fromRGB(100,255,120), Enum.Font.Gotham)
local DistLbl  = Lbl(Panel,"📏 --",  UDim2.new(1,-20,0,20), UDim2.new(0,10,0,112), Color3.fromRGB(180,180,180), Enum.Font.Gotham)
local MyHPLbl  = Lbl(Panel,"🧬 --",  UDim2.new(1,-20,0,20), UDim2.new(0,10,0,134), Color3.fromRGB(150,230,255), Enum.Font.Gotham)
local WepLbl   = Lbl(Panel,"⚔️ --",  UDim2.new(1,-20,0,20), UDim2.new(0,10,0,158), Color3.fromRGB(255,185,50), Enum.Font.Gotham)
local KillLbl  = Lbl(Panel,"💀 0",   UDim2.new(1,-20,0,20), UDim2.new(0,10,0,180), Color3.fromRGB(255,100,100), Enum.Font.GothamBold)
local StatLbl  = Lbl(Panel,"",       UDim2.new(1,-20,0,24), UDim2.new(0,10,0,204), Color3.fromRGB(255,200,50), Enum.Font.GothamBold)
local BLLbl    = Lbl(Panel,"",       UDim2.new(1,-20,0,18), UDim2.new(0,10,0,232), Color3.fromRGB(140,140,140), Enum.Font.Gotham)

-- Target HP bar
local THPbg = Instance.new("Frame",Panel); THPbg.ZIndex=6
THPbg.Size=UDim2.new(1,-20,0,8); THPbg.Position=UDim2.new(0,10,0,80)
THPbg.BackgroundColor3=Color3.fromRGB(30,30,30); THPbg.BackgroundTransparency=0.2; THPbg.BorderSizePixel=0
Instance.new("UICorner",THPbg).CornerRadius=UDim.new(1,0)
local THPbar = Instance.new("Frame",THPbg); THPbar.ZIndex=7
THPbar.Size=UDim2.new(1,0,1,0); THPbar.BackgroundColor3=Color3.fromRGB(80,255,120); THPbar.BorderSizePixel=0
Instance.new("UICorner",THPbar).CornerRadius=UDim.new(1,0)

-- My HP bar
local MHPbg = Instance.new("Frame",Panel); MHPbg.ZIndex=6
MHPbg.Size=UDim2.new(1,-20,0,6); MHPbg.Position=UDim2.new(0,10,0,126)
MHPbg.BackgroundColor3=Color3.fromRGB(20,20,20); MHPbg.BackgroundTransparency=0.2; MHPbg.BorderSizePixel=0
Instance.new("UICorner",MHPbg).CornerRadius=UDim.new(1,0)
local MHPbar = Instance.new("Frame",MHPbg); MHPbar.ZIndex=7
MHPbar.Size=UDim2.new(1,0,1,0); MHPbar.BackgroundColor3=Color3.fromRGB(50,200,255); MHPbar.BorderSizePixel=0
Instance.new("UICorner",MHPbar).CornerRadius=UDim.new(1,0)

-- Skip button
local SkipBtn = Instance.new("TextButton",SG)
SkipBtn.Size=UDim2.new(0,120,0,36); SkipBtn.Position=UDim2.new(1,-134,0,12)
SkipBtn.BackgroundColor3=Color3.fromRGB(255,255,255); SkipBtn.TextColor3=Color3.fromRGB(0,0,0)
SkipBtn.Text="⏭ Skip"; SkipBtn.Font=Enum.Font.GothamBold; SkipBtn.TextSize=13
SkipBtn.BorderSizePixel=0; SkipBtn.ZIndex=20
Instance.new("UICorner",SkipBtn).CornerRadius=UDim.new(0,8)
SkipBtn.MouseButton1Click:Connect(function()
    if S.Target then
        S.Blacklist[S.Target.UserId] = true
        S.Target=nil; S.SkillAllowed=false; S.KiteMode=false; S.TargetReached=false
        StopSkills()
        local t=PickTarget(nil)
        if t then S.Target=t; S.TargetTimer=tick(); S.Status="hunting"
        else S.Status="waiting"; HopServer() end
    end
end)

-- Reset button
local RstBtn = Instance.new("TextButton",SG)
RstBtn.Size=UDim2.new(0,120,0,26); RstBtn.Position=UDim2.new(1,-134,0,52)
RstBtn.BackgroundColor3=Color3.fromRGB(200,50,50); RstBtn.TextColor3=Color3.fromRGB(255,255,255)
RstBtn.Text="🔄 Reset"; RstBtn.Font=Enum.Font.Gotham; RstBtn.TextSize=11
RstBtn.BorderSizePixel=0; RstBtn.ZIndex=20
Instance.new("UICorner",RstBtn).CornerRadius=UDim.new(0,6)
RstBtn.MouseButton1Click:Connect(function()
    S.Blacklist={}
    if S.Status=="waiting" or S.Status=="hopping" then
        S.HopBusy=false; S.Status="hunting"
        local t=PickTarget(nil)
        if t then S.Target=t; S.TargetTimer=tick(); S.TargetReached=false end
    end
end)

-- ================================================================
-- UI UPDATE
-- ================================================================
RunService.RenderStepped:Connect(function()
    -- My HP
    local myHPpct = GetMyHPPct()
    MHPbar.Size = UDim2.new(math.clamp(myHPpct,0,1),0,1,0)
    MHPbar.BackgroundColor3 = myHPpct>0.7 and Color3.fromRGB(50,200,255)
        or myHPpct>0.5 and Color3.fromRGB(255,200,0) or Color3.fromRGB(255,60,60)
    MyHPLbl.Text = string.format("🧬 My HP: %d%%  %s",
        math.floor(myHPpct*100), S.KiteMode and "⬆️ KITING" or "")
    MyHPLbl.TextColor3 = myHPpct>0.7 and Color3.fromRGB(150,255,150)
        or myHPpct>0.5 and Color3.fromRGB(255,220,0) or Color3.fromRGB(255,80,80)

    -- Timer
    local timerTxt = S.TargetReached
        and (math.floor(math.max(0, CFG.ChaseTimeout-(tick()-S.TargetTimer))).."s")
        or (S.Target and "flying..." or "--")
    KillLbl.Text = string.format("💀 Kills: %d  ⏱ %s", S.KillCount, timerTxt)
    WepLbl.Text  = "⚔️ "..(S.CurrentWeapon)..(S.SkillActive and " ✦" or "")

    -- Blacklist count
    local bc=0; for _ in pairs(S.Blacklist) do bc=bc+1 end
    BLLbl.Text = bc>0 and ("🚫 Skipped/Killed: "..bc) or ""

    -- Status
    local stMap = {
        hopping  = {"🔄 Hopping server (8-10p)...", Color3.fromRGB(255,200,50)},
        waiting  = {"⏳ Searching server...",         Color3.fromRGB(255,150,50)},
        kiting   = {"⬆️ KITING — HP < 50%!",          Color3.fromRGB(255,60,60)},
        safezone = {"🛡 SAFE ZONE — Recovering...",    Color3.fromRGB(255,80,80)},
        flying   = {"✈️ Flying to target...",          Color3.fromRGB(100,200,255)},
        hunting  = {S.SkillAllowed and "⚡ Attacking!" or "🔍 Hunting...",
                    S.SkillAllowed and Color3.fromRGB(50,255,120) or Color3.fromRGB(200,200,200)},
    }
    local st = stMap[S.Status] or stMap.hunting
    StatLbl.Text = st[1]; StatLbl.TextColor3 = st[2]

    -- Target info
    if IsAlive(S.Target) then
        local tc = S.Target.Character
        local th = tc:FindFirstChild("Humanoid")
        local tr = tc:FindFirstChild("HumanoidRootPart")
        local mr = GetHRP()
        TargLbl.Text = "🎯 "..S.Target.Name
        if th and th.MaxHealth>0 then
            local r=th.Health/th.MaxHealth
            THPbar.Size=UDim2.new(math.clamp(r,0,1),0,1,0)
            THPbar.BackgroundColor3=r>0.5 and Color3.fromRGB(80,255,120)
                or r>0.25 and Color3.fromRGB(255,200,50) or Color3.fromRGB(255,60,60)
            HPLbl.Text=string.format("❤️ %d/%d (%d%%)",
                math.floor(th.Health),math.floor(th.MaxHealth),math.floor(r*100))
        end
        if tr and mr then
            DistLbl.Text="📏 "..(math.floor((tr.Position-mr.Position).Magnitude)).." studs"
        end
        Title.Text=string.format("🏴‍☠️ Bounty Hunter Pro v7 | %s", timerTxt)
    else
        TargLbl.Text="🎯 Searching..."
        HPLbl.Text="❤️ --"; DistLbl.Text="📏 --"
        THPbar.Size=UDim2.new(0,0,1,0)
        Title.Text="🏴‍☠️ Bounty Hunter Pro v7"
    end
end)

-- ================================================================
-- RESPAWN
-- ================================================================
LP.CharacterAdded:Connect(function()
    task.wait(2)
    Grav(false)
    TurnOnPVP()
    JoinTeam()
    S.Blacklist={}; S.Status="hunting"; S.HopBusy=false
    S.Target=nil; S.TargetReached=false; S.SkillAllowed=false; S.KiteMode=false
    S.InSafeZone=false; S.AttackEnabled=true
    StartSkills()
end)
if LP.Character then Grav(false); StartSkills() end

-- ================================================================
print("[BountyHunter Pro v7] ✅ Loaded!")
pcall(function()
    StarterGui:SetCore("SendNotification",{
        Title="🏴‍☠️ BHP v7",
        Text="✅ Loaded! Haki/V3/V4/Kite ON",
        Duration=4
    })
end)
