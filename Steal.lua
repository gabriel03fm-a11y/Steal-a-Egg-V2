--=====================================================================
-- ULTIMATE COMBAT SUITE
-- Aimbot + ESP + FOV + Target System + Mobile Support
--=====================================================================

--=====================================================================
-- 1. SERVICES
--=====================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

--=====================================================================
-- 2. VARIABLES & DEFAULTS
--=====================================================================
local Config = {
    -- Aimbot
    AimbotEnabled = false,
    AimAssist = false,
    AimMode = "Toggle", -- Toggle / Hold
    AimKey = Enum.KeyCode.E,
    AimOnlyWhenAiming = false,
    AimOnlyVisible = true,
    AimUseFOV = true,
    FOVSize = 120,
    FOVMin = 50,
    FOVMax = 400,
    Smoothness = 0.25,
    Sensitivity = 1.0,
    Prediction = 0.15,
    PredX = 1, PredY = 1, PredZ = 1,
    OffsetY = 0,
    OffsetX = 0,
    MaxDistance = 500,
    MinDistance = 0,
    Priority = "Closest to Cursor",
    BodyPart = "Head",
    IgnoreVisibility = false,

    -- Target
    TargetLock = false,
    AutoSwitchTarget = true,
    SwitchOnDeath = true,
    SwitchOutOfFOV = true,
    IgnoreTeam = true,
    IgnoreFriends = false,
    IgnoreNPC = true,
    Blacklist = {},

    -- ESP
    ESPEnabled = false,
    BoxESP = true,
    CornerBox = false,
    Box3D = false,
    SkeletonESP = false,
    TracerESP = false,
    HealthBar = true,
    HealthText = true,
    DistanceESP = true,
    NameESP = true,
    DisplayNameESP = false,
    TeamESP = false,
    ToolESP = false,
    HeadDot = false,
    Highlight = false,
    Chams = false,
    ESPMaxDistance = 1000,
    ShowTeammates = false,
    ShowNPCs = false,
    BoxThickness = 1.5,
    BoxTransparency = 0.4,
    BoxColor = Color3.fromRGB(255, 60, 60),
    TeamColor = Color3.fromRGB(60, 200, 255),
    RainbowMode = false,
    SkeletonThickness = 1.5,
    SkeletonTransparency = 0.3,
    SkeletonColor = Color3.fromRGB(255, 255, 255),
    TracerOrigin = "Bottom",
    TracerThickness = 1.5,
    TracerColor = Color3.fromRGB(255, 255, 255),

    -- Chams
    ChamsFill = Color3.fromRGB(255, 0, 0),
    ChamsOutline = Color3.fromRGB(255, 255, 255),
    ChamsFillAlpha = 0.5,
    ChamsOutlineAlpha = 0.8,

    -- FOV Circle
    FOVCircleEnabled = true,
    FOVThickness = 2,
    FOVTransparency = 0.5,
    FOVFilled = false,
    FOVColor = Color3.fromRGB(255, 255, 255),
    FOVOnlyDuringAim = false,

    -- Visual
    CrosshairEnabled = false,
    CrosshairStyle = "Cross", -- Cross/Dot/Circle/Four Lines
    CrosshairSize = 12,
    CrosshairThickness = 2,
    CrosshairGap = 4,
    CrosshairColor = Color3.fromRGB(0, 255, 100),
    CrosshairTransparency = 0.2,

    -- Target Indicator
    TargetIndicator = true,

    -- Misc
    FPSCounter = false,
    PingCounter = false,
    AntiAFK = true,

    -- Mobile
    MobileAimBtn = true,
    MobileLockBtn = true,
    MobileESPBtn = false,
    MobileFOVBtn = false,
    MobileBtnSize = 50,
    MobileBtnTransparency = 0.35,
}

local Defaults = {}
for k, v in pairs(Config) do Defaults[k] = v end

-- Runtime state
local State = {
    CurrentTarget = nil,
    LockedTarget = nil,
    AimKeyDown = false,
    Connections = {},
    ESPObjects = {}, -- [player] = {drawings/objects}
    Blacklist = {},
    UI = {},
    MobileBtns = {},
    Notifications = {},
}

--=====================================================================
-- 3. UTILITIES
--=====================================================================
local function Notify(title, text, duration)
    duration = duration or 2
    if not State.UI.NotifFrame then return end
    local n = Instance.new("Frame")
    n.Size = UDim2.new(0, 260, 0, 50)
    n.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
    n.BorderSizePixel = 0
    n.Position = UDim2.new(0.5, -130, 1, 20)
    n.Parent = State.UI.NotifFrame

    local corner = Instance.new("UICorner", n)
    corner.CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke", n)
    stroke.Color = Color3.fromRGB(80, 80, 90)
    stroke.Thickness = 1

    local t = Instance.new("TextLabel", n)
    t.Size = UDim2.new(1, -12, 0, 18)
    t.Position = UDim2.new(0, 6, 0, 4)
    t.BackgroundTransparency = 1
    t.Text = title
    t.TextColor3 = Color3.fromRGB(255, 255, 255)
    t.Font = Enum.Font.GothamBold
    t.TextSize = 13
    t.TextXAlignment = Enum.TextXAlignment.Left

    local d = Instance.new("TextLabel", n)
    d.Size = UDim2.new(1, -12, 0, 20)
    d.Position = UDim2.new(0, 6, 0, 22)
    d.BackgroundTransparency = 1
    d.Text = text
    d.TextColor3 = Color3.fromRGB(190, 190, 200)
    d.Font = Enum.Font.Gotham
    d.TextSize = 11
    d.TextXAlignment = Enum.TextXAlignment.Left
    d.TextWrapped = true

    TweenService:Create(n, TweenInfo.new(0.3), {Position = UDim2.new(0.5, -130, 1, -70 - (#State.Notifications * 60))}):Play()
    table.insert(State.Notifications, n)

    task.delay(duration, function()
        TweenService:Create(n, TweenInfo.new(0.3), {Position = UDim2.new(0.5, -130, 1, 40)}):Play()
        task.wait(0.35)
        for i, v in ipairs(State.Notifications) do
            if v == n then table.remove(State.Notifications, i) break end
        end
        n:Destroy()
    end)
end

local function GetCharacter(plr)
    if not plr or not plr.Parent then return nil end
    return plr.Character
end

local function GetHRP(plr)
    local char = GetCharacter(plr)
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function IsAlive(plr)
    local char = GetCharacter(plr)
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function IsTeammate(plr)
    if plr == LocalPlayer then return false end
    local lp = LocalPlayer.Team
    if not lp then return false end
    return plr.Team == lp
end

local function IsFriend(plr)
    return LocalPlayer:IsFriendsWith(plr.UserId)
end

local function IsBlacklisted(plr)
    return State.Blacklist[plr.UserId] == true
end

local function IsNPC(plr)
    return not plr:IsA("Player") or plr.Character and not plr.Character:FindFirstChildOfClass("Humanoid")
end

local function WorldToScreen(world)
    local sp, os = Camera:WorldToViewportPoint(world)
    return Vector2.new(sp.X, sp.Y), sp.Z > 0, os
end

local function GetDistance(plr)
    local hrp = GetHRP(plr)
    local lhrp = GetHRP(LocalPlayer)
    if not hrp or not lhrp then return math.huge end
    return (hrp.Position - lhrp.Position).Magnitude
end

local function GetBodyPart(char, part)
    if not char then return nil end
    if part == "Random" then
        local parts = {"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart", "Torso"}
        return char:FindFirstChild(parts[math.random(#parts)])
    end
    if part == "Closest to Cursor" then
        -- handled by target select
        return char:FindFirstChild("Head")
    end
    return char:FindFirstChild(part) or char:FindFirstChild("HumanoidRootPart")
end

local function IsVisible(plr)
    if Config.IgnoreVisibility then return true end
    local char = GetCharacter(plr)
    local lhrp = GetHRP(LocalPlayer)
    if not char or not lhrp then return false end
    local target = GetBodyPart(char, Config.BodyPart) or char:FindFirstChild("HumanoidRootPart")
    if not target then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char, LocalPlayer.Character, Camera}
    local result = Workspace:Raycast(lhrp.Position, target.Position - lhrp.Position, params)
    return result == nil
end

local function ScreenDistance(plr)
    local hrp = GetHRP(plr)
    if not hrp then return math.huge end
    local sp = WorldToScreen(hrp.Position)
    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    return (sp - center).Magnitude
end

local function CursorDistance(plr)
    local hrp = GetHRP(plr)
    if not hrp then return math.huge end
    local sp = WorldToScreen(hrp.Position)
    return (sp - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
end

--=====================================================================
-- 4. TARGET SYSTEM
--=====================================================================
local TargetSystem = {}

function TargetSystem.Valid(plr)
    if not plr or plr == LocalPlayer then return false end
    if not plr.Parent then return false end
    if not IsAlive(plr) then return false end
    if IsBlacklisted(plr) then return false end
    if Config.IgnoreTeam and IsTeammate(plr) then return false end
    if Config.IgnoreFriends and IsFriend(plr) then return false end
    if Config.IgnoreNPC and IsNPC(plr) then return false end
    local dist = GetDistance(plr)
    if dist > Config.MaxDistance or dist < Config.MinDistance then return false end
    if Config.AimUseFOV and ScreenDistance(plr) > Config.FOVSize then return false end
    if Config.AimOnlyVisible and not IsVisible(plr) then return false end
    return true
end

function TargetSystem.GetBest()
    local best, bestScore = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if TargetSystem.Valid(plr) then
            local score
            if Config.Priority == "Closest to Cursor" then
                score = CursorDistance(plr)
            elseif Config.Priority == "Closest Player" then
                score = GetDistance(plr)
            elseif Config.Priority == "Lowest Health" then
                local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
                score = hum and hum.Health or 9999
            elseif Config.Priority == "Highest Health" then
                local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
                score = hum and (9999 - hum.Health) or 9999
            elseif Config.Priority == "Visible First" then
                score = IsVisible(plr) and 0 or 9999
            else
                score = GetDistance(plr)
            end
            if score < bestScore then
                bestScore = score
                best = plr
            end
        end
    end
    return best
end

function TargetSystem.Update()
    if State.LockedTarget and TargetSystem.Valid(State.LockedTarget) and not Config.AutoSwitchTarget then
        State.CurrentTarget = State.LockedTarget
        return
    end
    local t = TargetSystem.GetBest()
    if State.CurrentTarget ~= t then
        if Config.SwitchOnDeath and State.CurrentTarget and not IsAlive(State.CurrentTarget) then
            State.CurrentTarget = t
        elseif Config.SwitchOutOfFOV and State.CurrentTarget then
            State.CurrentTarget = t
        else
            State.CurrentTarget = t
        end
    end
end

--=====================================================================
-- 5. AIMBOT
--=====================================================================
local Aimbot = {}

function Aimbot.GetAimPart(plr)
    local char = GetCharacter(plr)
    if not char then return nil end
    if Config.BodyPart == "Closest to Cursor" then
        local closest, closestDist = nil, math.huge
        for _, name in ipairs({"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart", "Torso"}) do
            local p = char:FindFirstChild(name)
            if p then
                local sp = WorldToScreen(p.Position)
                local d = (sp - Vector2.new(Mouse.X, Mouse.Y)).Magnitude
                if d < closestDist then closestDist = d; closest = p end
            end
        end
        return closest
    end
    return GetBodyPart(char, Config.BodyPart)
end

function Aimbot.IsActive()
    if not Config.AimbotEnabled and not Config.AimAssist then return false end
    if Config.AimMode == "Hold" then return State.AimKeyDown end
    return true
end

function Aimbot.Update(dt)
    if not Aimbot.IsActive() then return end
    local target = State.LockedTarget or State.CurrentTarget
    if not target or not TargetSystem.Valid(target) then return end

    local part = Aimbot.GetAimPart(target)
    if not part then return end

    -- Prediction
    local hrp = GetHRP(target)
    local pred = Vector3.zero
    if hrp and Config.Prediction > 0 then
        pred = hrp.Velocity * Config.Prediction * Vector3.new(Config.PredX, Config.PredY, Config.PredZ)
    end

    local aimPos = part.Position + pred + Vector3.new(Config.OffsetX, Config.OffsetY, 0)

    local camCF = Camera.CFrame
    local dir = (aimPos - camCF.Position).Unit
    local targetCF = CFrame.new(camCF.Position, camCF.Position + dir * 100)

    local smooth = 1 - math.clamp(Config.Smoothness, 0, 0.99)
    smooth = smooth * math.clamp(Config.Sensitivity, 0.1, 3)
    Camera.CFrame = camCF:Lerp(targetCF, math.clamp(smooth * (dt * 60), 0, 1))
end

--=====================================================================
-- 6. FOV CIRCLE
--=====================================================================
local FOVCircle = {}

function FOVCircle.Init()
    local circle = Drawing.new("Circle")
    circle.Thickness = Config.FOVThickness
    circle.Color = Config.FOVColor
    circle.Transparency = Config.FOVTransparency
    circle.Filled = Config.FOVFilled
    circle.NumSides = 60
    circle.Radius = Config.FOVSize
    circle.Visible = false
    FOVCircle.Instance = circle
end

function FOVCircle.Update()
    if not FOVCircle.Instance then return end
    local c = FOVCircle.Instance
    local active = Config.FOVCircleEnabled and (Config.AimbotEnabled or Config.AimAssist)
    if Config.FOVOnlyDuringAim then
        active = active and Aimbot.IsActive()
    end
    c.Visible = active
    c.Radius = Config.FOVSize
    c.Thickness = Config.FOVThickness
    c.Color = Config.FOVColor
    c.Transparency = Config.FOVTransparency
    c.Filled = Config.FOVFilled
    c.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
end

--=====================================================================
-- 7. ESP
--=====================================================================
local ESP = {}
ESP.Container = {} -- [player] = { box=, name=, health=... }

local function createDrawing(cls, props)
    local d = Drawing.new(cls)
    for k, v in pairs(props or {}) do d[k] = v end
    return d
end

local function clearESP(plr)
    local c = ESP.Container[plr]
    if not c then return end
    for _, obj in pairs(c) do
        if typeof(obj) == "Instance" then obj:Destroy()
        elseif typeof(obj) == "Drawing" then obj:Remove() end
    end
    ESP.Container[plr] = nil
end

local function createESP(plr)
    local c = {}
    c.box = createDrawing("Square", {Thickness = Config.BoxThickness, Transparency = Config.BoxTransparency, Color = Config.BoxColor, Filled = false, Visible = false})
    c.box2 = createDrawing("Square", {Thickness = Config.BoxThickness, Transparency = Config.BoxTransparency, Color = Config.BoxColor, Filled = false, Visible = false})
    c.box3 = createDrawing("Square", {Thickness = Config.BoxThickness, Transparency = Config.BoxTransparency, Color = Config.BoxColor, Filled = false, Visible = false})
    c.box4 = createDrawing("Square", {Thickness = Config.BoxThickness, Transparency = Config.BoxTransparency, Color = Config.BoxColor, Filled = false, Visible = false})

    c.name = createDrawing("Text", {Size = 14, Center = true, Outline = true, Color = Color3.fromRGB(255,255,255), Visible = false})
    c.dist = createDrawing("Text", {Size = 12, Center = true, Outline = true, Color = Color3.fromRGB(200,200,200), Visible = false})
    c.healthText = createDrawing("Text", {Size = 12, Center = true, Outline = true, Color = Color3.fromRGB(0,255,100), Visible = false})
    c.healthBarBg = createDrawing("Line", {Thickness = 2, Color = Color3.fromRGB(0,0,0), Visible = false})
    c.healthBar = createDrawing("Line", {Thickness = 2, Color = Color3.fromRGB(0,255,100), Visible = false})
    c.tracer = createDrawing("Line", {Thickness = Config.TracerThickness, Color = Config.TracerColor, Transparency = 0.3, Visible = false})
    c.headDot = createDrawing("Circle", {Radius = 3, Color = Color3.fromRGB(255,0,0), Filled = true, Visible = false})

    -- Skeleton lines (15 for R15)
    c.skeleton = {}
    for i = 1, 15 do
        c.skeleton[i] = createDrawing("Line", {Thickness = Config.SkeletonThickness, Color = Config.SkeletonColor, Transparency = Config.SkeletonTransparency, Visible = false})
    end

    c.highlight = nil -- set below

    ESP.Container[plr] = c
    return c
end

local function getColorFor(plr)
    if Config.RainbowMode then
        local t = tick() * 2
        return Color3.fromHSV((t % 1), 1, 1)
    end
    if IsTeammate(plr) then return Config.TeamColor end
    return Config.BoxColor
end

local function updateESPFor(plr)
    local c = ESP.Container[plr]
    if not c then c = createESP(plr) end

    local visible = Config.ESPEnabled and IsAlive(plr) and plr ~= LocalPlayer
    if visible and Config.IgnoreTeam and IsTeammate(plr) and not Config.ShowTeammates then
        visible = false
    end
    if visible and GetDistance(plr) > Config.ESPMaxDistance then visible = false end

    if not visible then
        for k, v in pairs(c) do
            if k == "skeleton" then
                for _, line in ipairs(v) do line.Visible = false end
            elseif k == "highlight" then
                if v then v.Enabled = false end
            elseif typeof(v) == "Drawing" then
                v.Visible = false
            end
        end
        return
    end

    local char = GetCharacter(plr)
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end

    local col = getColorFor(plr)
    local pos, onScreen = WorldToScreen(hrp.Position)
    if not onScreen then
        for k, v in pairs(c) do
            if k == "skeleton" then
                for _, line in ipairs(v) do line.Visible = false end
            elseif k == "highlight" then
                if v then v.Enabled = false end
            elseif typeof(v) == "Drawing" then
                v.Visible = false
            end
        end
        return
    end

    -- Box computation
    local topPos = WorldToScreen((hrp.CFrame * CFrame.new(0, 3, 0)).Position)
    local botPos = WorldToScreen((hrp.CFrame * CFrame.new(0, -3, 0)).Position)
    local height = math.abs(topPos.Y - botPos.Y)
    local width = height * 0.55

    -- 2D Box
    if Config.BoxESP and not Config.CornerBox then
        c.box.Size = Vector2.new(width, height)
        c.box.Position = Vector2.new(pos.X - width/2, pos.Y - height/2)
        c.box.Color = col
        c.box.Thickness = Config.BoxThickness
        c.box.Transparency = Config.BoxTransparency
        c.box.Visible = true
        c.box2.Visible = false; c.box3.Visible = false; c.box4.Visible = false
    elseif Config.CornerBox then
        c.box.Visible = false
        local cl = width * 0.25
        local x, y = pos.X - width/2, pos.Y - height/2
        c.box.Size = Vector2.new(cl, Config.BoxThickness)
        c.box.Position = Vector2.new(x, y)
        c.box.Color = col; c.box.Visible = true
        c.box2.Size = Vector2.new(Config.BoxThickness, cl)
        c.box2.Position = Vector2.new(x, y)
        c.box2.Color = col; c.box2.Visible = true
        c.box3.Size = Vector2.new(cl, Config.BoxThickness)
        c.box3.Position = Vector2.new(x + width - cl, y + height - Config.BoxThickness)
        c.box3.Color = col; c.box3.Visible = true
        c.box4.Size = Vector2.new(Config.BoxThickness, cl)
        c.box4.Position = Vector2.new(x + width - Config.BoxThickness, y + height - cl)
        c.box4.Color = col; c.box4.Visible = true
    else
        c.box.Visible = false; c.box2.Visible = false; c.box3.Visible = false; c.box4.Visible = false
    end

    -- Name
    if Config.NameESP then
        c.name.Text = Config.DisplayNameESP and plr.DisplayName or plr.Name
        c.name.Position = Vector2.new(pos.X, pos.Y - height/2 - 20)
        c.name.Color = col
        c.name.Visible = true
    else c.name.Visible = false end

    -- Distance
    if Config.DistanceESP then
        c.dist.Text = string.format("%dm", math.floor(GetDistance(plr)))
        c.dist.Position = Vector2.new(pos.X, pos.Y + height/2 + 4)
        c.dist.Visible = true
    else c.dist.Visible = false end

    -- Health
    if Config.HealthBar and hum then
        local hp = hum.Health / hum.MaxHealth
        local barH = height
        local x = pos.X - width/2 - 8
        c.healthBarBg.From = Vector2.new(x, pos.Y - barH/2)
        c.healthBarBg.To = Vector2.new(x, pos.Y + barH/2)
        c.healthBarBg.Visible = true
        c.healthBar.From = Vector2.new(x, pos.Y + barH/2)
        c.healthBar.To = Vector2.new(x, pos.Y + barH/2 - barH * hp)
        c.healthBar.Color = Color3.fromRGB(255 * (1-hp), 255 * hp, 0)
        c.healthBar.Visible = true
    else
        c.healthBarBg.Visible = false
        c.healthBar.Visible = false
    end

    if Config.HealthText and hum then
        c.healthText.Text = string.format("%d/%d", math.floor(hum.Health), math.floor(hum.MaxHealth))
        c.healthText.Position = Vector2.new(pos.X, pos.Y - height/2 - 36)
        c.healthText.Visible = true
    else c.healthText.Visible = false end

    -- Tracer
    if Config.TracerESP then
        local origin
        if Config.TracerOrigin == "Bottom" then origin = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
        elseif Config.TracerOrigin == "Top" then origin = Vector2.new(Camera.ViewportSize.X/2, 0)
        elseif Config.TracerOrigin == "Cursor" then origin = Vector2.new(Mouse.X, Mouse.Y)
        else origin = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2) end
        c.tracer.From = origin
        c.tracer.To = pos
        c.tracer.Color = col
        c.tracer.Thickness = Config.TracerThickness
        c.tracer.Visible = true
    else c.tracer.Visible = false end

    -- Head dot
    if Config.HeadDot then
        local hp = WorldToScreen((hrp.CFrame * CFrame.new(0, 3, 0)).Position)
        c.headDot.Position = hp
        c.headDot.Visible = true
    else c.headDot.Visible = false end

    -- Skeleton
    if Config.SkeletonESP and char then
        local bones = {
            {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
            {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
            {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
            {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
            {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"},
            {"UpperTorso", "LowerTorso"},
        }
        for i, bone in ipairs(bones) do
            local p1 = char:FindFirstChild(bone[1])
            local p2 = char:FindFirstChild(bone[2])
            local line = c.skeleton[i]
            if p1 and p2 then
                local s1, on1 = WorldToScreen(p1.Position)
                local s2, on2 = WorldToScreen(p2.Position)
                if on1 and on2 then
                    line.From = s1
                    line.To = s2
                    line.Color = col
                    line.Thickness = Config.SkeletonThickness
                    line.Transparency = Config.SkeletonTransparency
                    line.Visible = true
                else line.Visible = false end
            else line.Visible = false end
        end
    else
        for _, line in ipairs(c.skeleton) do line.Visible = false end
    end

    -- Highlight
    if Config.Highlight or Config.Chams then
        if not c.highlight then
            local h = Instance.new("Highlight")
            h.Name = "UC_Highlight"
            h.Parent = char
            c.highlight = h
        end
        c.highlight.Enabled = true
        c.highlight.Adornee = char
        c.highlight.FillColor = Config.ChamsFill
        c.highlight.OutlineColor = Config.ChamsOutline
        c.highlight.FillTransparency = Config.ChamsFillAlpha
        c.highlight.OutlineTransparency = Config.ChamsOutlineAlpha
    elseif c.highlight then
        c.highlight.Enabled = false
    end
end

function ESP.Update()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            pcall(updateESPFor, plr)
        end
    end
end

function ESP.Cleanup()
    for plr, _ in pairs(ESP.Container) do
        clearESP(plr)
    end
end

--=====================================================================
-- 8. CROSSHAIR & TARGET INDICATOR
--=====================================================================
local Crosshair = {}
function Crosshair.Init()
    Crosshair.lines = {}
    for i = 1, 4 do
        Crosshair.lines[i] = Drawing.new("Line")
        Crosshair.lines[i].Thickness = Config.CrosshairThickness
        Crosshair.lines[i].Color = Config.CrosshairColor
        Crosshair.lines[i].Visible = false
    end
    Crosshair.dot = Drawing.new("Circle")
    Crosshair.dot.Filled = true
    Crosshair.dot.Visible = false
    Crosshair.circle = Drawing.new("Circle")
    Crosshair.circle.Filled = false
    Crosshair.circle.NumSides = 40
    Crosshair.circle.Visible = false
end

function Crosshair.Update()
    if not Crosshair.lines then return end
    local visible = Config.CrosshairEnabled
    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    for _, l in ipairs(Crosshair.lines) do l.Visible = false end
    Crosshair.dot.Visible = false
    Crosshair.circle.Visible = false
    if not visible then return end

    local s = Config.CrosshairSize
    local g = Config.CrosshairGap
    local t = Config.CrosshairThickness
    local col = Config.CrosshairColor

    if Config.CrosshairStyle == "Cross" then
        Crosshair.lines[1].From = center - Vector2.new(s + g, 0)
        Crosshair.lines[1].To = center - Vector2.new(g, 0)
        Crosshair.lines[2].From = center + Vector2.new(g, 0)
        Crosshair.lines[2].To = center + Vector2.new(s + g, 0)
        Crosshair.lines[3].From = center - Vector2.new(0, s + g)
        Crosshair.lines[3].To = center - Vector2.new(0, g)
        Crosshair.lines[4].From = center + Vector2.new(0, g)
        Crosshair.lines[4].To = center + Vector2.new(0, s + g)
        for _, l in ipairs(Crosshair.lines) do
            l.Thickness = t; l.Color = col; l.Visible = true
        end
    elseif Config.CrosshairStyle == "Dot" then
        Crosshair.dot.Position = center
        Crosshair.dot.Radius = t
        Crosshair.dot.Color = col
        Crosshair.dot.Visible = true
    elseif Config.CrosshairStyle == "Circle" then
        Crosshair.circle.Position = center
        Crosshair.circle.Radius = s
        Crosshair.circle.Thickness = t
        Crosshair.circle.Color = col
        Crosshair.circle.Visible = true
    elseif Config.CrosshairStyle == "Four Lines" then
        Crosshair.lines[1].From = center - Vector2.new(s, 0)
        Crosshair.lines[1].To = center - Vector2.new(g, 0)
        Crosshair.lines[2].From = center + Vector2.new(g, 0)
        Crosshair.lines[2].To = center + Vector2.new(s, 0)
        Crosshair.lines[3].From = center - Vector2.new(0, s)
        Crosshair.lines[3].To = center - Vector2.new(0, g)
        Crosshair.lines[4].From = center + Vector2.new(0, g)
        Crosshair.lines[4].To = center + Vector2.new(0, s)
        for _, l in ipairs(Crosshair.lines) do
            l.Thickness = t; l.Color = col; l.Visible = true
        end
    end
end

local TargetIndicator = {}
function TargetIndicator.Init()
    TargetIndicator.title = createDrawing("Text", {Size = 16, Center = true, Outline = true, Color = Color3.fromRGB(255,255,255), Visible = false})
    TargetIndicator.name = createDrawing("Text", {Size = 14, Center = true, Outline = true, Color = Color3.fromRGB(255,255,255), Visible = false})
    TargetIndicator.info = createDrawing("Text", {Size = 12, Center = true, Outline = true, Color = Color3.fromRGB(200,200,200), Visible = false})
end

function TargetIndicator.Update()
    if not TargetIndicator.title then return end
    local visible = Config.TargetIndicator
    local t = State.CurrentTarget
    if visible and t and IsAlive(t) then
        local y = 30
        TargetIndicator.title.Text = "TARGET LOCKED"
        TargetIndicator.title.Position = Vector2.new(Camera.ViewportSize.X/2, y)
        TargetIndicator.title.Color = Color3.fromRGB(255, 80
