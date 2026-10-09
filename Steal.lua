--[[
====================================================================
    🥚 EGG HUB  |  Steal an Egg — Hub Profissional
    Versão: 1.0.0
    Mobile-first • Auto-detecção • Cleanup seguro
====================================================================
    Este script NÃO assume nomes de RemoteEvents, pastas ou objetos
    específicos do jogo. Toda estrutura relevante é descoberta em
    runtime. Quando algo não puder ser identificado, existe um
    sistema de configuração manual marcado com [AJUSTE MANUAL].
====================================================================
]]

--==================================================================
-- [SEÇÃO 1] SERVICES
--==================================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Workspace          = game:GetService("Workspace")
local HttpService        = game:GetService("HttpService")
local GuiService         = game:GetService("GuiService")

local LocalPlayer  = Players.LocalPlayer
local PlayerGui    = LocalPlayer:WaitForChild("PlayerGui")
local Camera       = Workspace.CurrentCamera

--==================================================================
-- [SEÇÃO 2] CONFIG (defaults — podem ser alterados via UI)
--==================================================================
local CONFIG = {
    -- Geral
    Enabled       = true,
    Notifications = true,
    Sounds        = true,
    UIAnimation   = true,
    CompactMode   = false,

    -- Performance
    UpdateRate    = 0.5,
    ESPUpdateRate = 0.15,
    DetectionRate = 1.0,
    LowPerformance = false,

    -- UI
    UIScale        = 1.0,
    Transparency   = 0.05,
    AnimationSpeed = 0.25,
    ButtonSize     = 44,

    -- Filtros
    MinValue       = 0,
    MaxDistance    = 500,
    UseValueFilter = true,
    UseRarityFilter = false,
    RarityFilter   = {},          -- [nomeDaRaridade] = true
    PriorityMode   = "Highest Value", -- Highest Value | Highest Rarity | Closest | Custom

    -- Auto Steal
    AutoSteal      = false,

    -- Instant Steal
    InstantSteal   = false,
    InstantDelay   = 100,

    -- Auto Farm
    AutoFarm       = false,
    AutoCollect    = true,
    AutoPickup     = true,
    AutoClaim      = false,
    AutoSell       = false,
    AutoReturn     = false,

    -- ESP
    EggESP         = false,
    EggName        = true,
    EggValue       = true,
    EggRarity      = true,
    EggDistance    = true,
    PlayerESP      = false,
    PlayerBox      = true,
    PlayerNameTag  = true,
    PlayerDistTag  = true,
    PlayerHighlight= false,
    ESPMaxDistance = 500,

    -- Favoritos
    Favorites      = {},          -- [nomeOvo] = true
    OnlyFavorites  = false,
    AutoStealFavorites = false,
    FavoritePriority   = false,

    -- Blacklist
    Blacklist      = {},          -- [nomeOvo] = true

    -- Debug
    Debug          = false,
}

--==================================================================
-- [SEÇÃO 3] VARIÁVEIS / STATE
--==================================================================
local STATE = {
    Eggs            = {},       -- lista de ovos detectados
    Rarities        = {},       -- set de raridades vistas
    Connections     = {},       -- todas as conexões
    ESPObjects      = {},       -- [instance] = { billboard = ..., highlight = ... }
    PlayerESPObjects= {},       -- [player] = { ... }
    Remotes         = { steal=nil, collect=nil, claim=nil, sell=nil, all={} },
    UI              = {},       -- referências da UI
    Running         = { AutoSteal=false, InstantSteal=false, AutoFarm=false, EggESP=false, PlayerESP=false, Detection=false },
    LastStealTime   = 0,
    Destroyed       = false,
    Stats = {
        StartTime     = os.clock(),
        EggsDetected  = 0,
        EggsStolen    = 0,
        ValueTotal    = 0,
        BestEgg       = "-",
        BestValue     = 0,
        Actions       = 0,
        Failures      = 0,
    },
}

--==================================================================
-- [SEÇÃO 4] UTILITÁRIOS
--==================================================================
local Utils = {}

function Utils.track(conn)
    table.insert(STATE.Connections, conn)
    return conn
end

function Utils.untrackAll()
    for _, c in ipairs(STATE.Connections) do
        pcall(function() c:Disconnect() end)
    end
    STATE.Connections = {}
end

function Utils.formatNumber(n)
    n = tonumber(n) or 0
    if n >= 1e12 then return string.format("%.2fT", n/1e12) end
    if n >= 1e9  then return string.format("%.2fB", n/1e9) end
    if n >= 1e6  then return string.format("%.2fM", n/1e6) end
    if n >= 1e3  then return string.format("%.2fK", n/1e3) end
    return tostring(math.floor(n))
end

function Utils.parseShortNumber(s)
    s = tostring(s):lower():gsub("%s","")
    local n, suf = s:match("^(%d+%.?%d*)([kmbt]?)$")
    if not n then return tonumber(s) or 0 end
    n = tonumber(n)
    if suf == "k" then return n * 1e3 end
    if suf == "m" then return n * 1e6 end
    if suf == "b" then return n * 1e9 end
    if suf == "t" then return n * 1e12 end
    return n
end

function Utils.formatTime(sec)
    sec = math.floor(sec)
    local h = math.floor(sec/3600)
    local m = math.floor((sec%3600)/60)
    local s = sec%60
    return string.format("%02d:%02d:%02d", h, m, s)
end

function Utils.isMobile()
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Utils.viewportSize()
    return Camera.ViewportSize
end

function Utils.getRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

function Utils.safeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        STATE.Stats.Failures = STATE.Stats.Failures + 1
        if CONFIG.Debug then warn("[EggHub]", err) end
    end
    return ok, err
end

function Utils.rarityWeight(r)
    r = tostring(r):lower()
    local weights = {
        common = 1, uncommon = 2, rare = 3, epic = 4,
        legendary = 5, mythic = 6, secret = 7,
        godly = 8, divine = 9, celestial = 10,
    }
    for key, w in pairs(weights) do
        if r:find(key) then return w end
    end
    return 0
end

--==================================================================
-- [SEÇÃO 5] DETECÇÃO AUTOMÁTICA
--==================================================================
local Detection = {}

-- Heurística para detectar um "ovo":
--   1) Nome contém "egg" (case-insensitive)
--   2) OU possui atributo IsEgg / EggValue
--   3) É BasePart ou Model com PrimaryPart
function Detection.isEgg(obj)
    if not obj or not obj.Parent then return false end
    if not (obj:IsA("BasePart") or obj:IsA("Model")) then return false end
    local n = obj.Name:lower()
    if n:find("egg") then return true end
    if obj:GetAttribute("IsEgg") then return true end
    if obj:GetAttribute("EggValue") then return true end
    -- [AJUSTE MANUAL] Adicione aqui tags/nomes específicos do jogo se necessário.
    return false
end

local function extractValue(obj)
    -- Attribute primeiro
    for _, attr in ipairs({"Value","EggValue","Worth","Price"}) do
        local v = obj:GetAttribute(attr)
        if v and tonumber(v) then return tonumber(v) end
    end
    -- Objetos filhos
    for _, c in ipairs(obj:GetChildren()) do
        if (c:IsA("NumberValue") or c:IsA("IntValue") or c:IsA("StringValue")) then
            local cn = c.Name:lower()
            if cn:find("value") or cn:find("worth") or cn:find("price") then
                local raw = c.Value
                if type(raw) == "number" then return raw end
                if type(raw) == "string" then return Utils.parseShortNumber(raw) end
            end
        end
    end
    return 0
end

local function extractRarity(obj)
    local r = obj:GetAttribute("Rarity")
    if r then return tostring(r) end
    for _, c in ipairs(obj:GetChildren()) do
        if c:IsA("StringValue") and c.Name:lower():find("rarity") then
            return c.Value
        end
    end
    return "Unknown"
end

local function extractOwner(obj)
    local o = obj:GetAttribute("Owner") or obj:GetAttribute("PlacedBy") or obj:GetAttribute("Creator")
    if o then return tostring(o) end
    for _, c in ipairs(obj:GetChildren()) do
        local cn = c.Name:lower()
        if cn:find("owner") or cn:find("placed") then
            if c:IsA("StringValue") then return c.Value end
            if c:IsA("ObjectValue") and c.Value then return c.Value.Name end
        end
    end
    return nil
end

local function extractPosition(obj)
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") then
        local p = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
        if p then return p.Position end
    end
    return nil
end

function Detection.scanEggs()
    local list = {}
    local root = Utils.getRoot()
    local rootPos = root and root.Position or Vector3.zero
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if Detection.isEgg(obj) then
            local pos = extractPosition(obj)
            if pos then
                local name = obj.Name
                table.insert(list, {
                    instance = obj,
                    name     = name,
                    value    = extractValue(obj),
                    rarity   = extractRarity(obj),
                    owner    = extractOwner(obj),
                    position = pos,
                    distance = (rootPos - pos).Magnitude,
                    available = true,        -- [AJUSTE MANUAL] lógica pode variar
                    locked    = false,
                    selected  = false,
                })
                STATE.Rarities[extractRarity(obj)] = true
            end
        end
    end
    STATE.Stats.EggsDetected = #list
    return list
end

function Detection.scanRemotes()
    STATE.Remotes = { steal=nil, collect=nil, claim=nil, sell=nil, all={} }
    local roots = { ReplicatedStorage, Workspace, LocalPlayer:FindFirstChild("PlayerScripts") }
    for _, root in ipairs(roots) do
        if root then
            for _, obj in ipairs(root:GetDescendants()) do
                if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                    table.insert(STATE.Remotes.all, obj)
                    local n = obj.Name:lower()
                    if not STATE.Remotes.steal and (n:find("steal") or n:find("take") or n:find("grab")) then
                        STATE.Remotes.steal = obj
                    end
                    if not STATE.Remotes.collect and (n:find("collect") or n:find("pickup") or n:find("pick")) then
                        STATE.Remotes.collect = obj
                    end
                    if not STATE.Remotes.claim and (n:find("claim") or n:find("reward")) then
                        STATE.Remotes.claim = obj
                    end
                    if not STATE.Remotes.sell and (n:find("sell") or n:find("cash")) then
                        STATE.Remotes.sell = obj
                    end
                end
            end
        end
    end
    if CONFIG.Debug then
        print(("[EggHub] Remotes: total=%d steal=%s collect=%s claim=%s sell=%s"):format(
            #STATE.Remotes.all,
            tostring(STATE.Remotes.steal and STATE.Remotes.steal.Name),
            tostring(STATE.Remotes.collect and STATE.Remotes.collect.Name),
            tostring(STATE.Remotes.claim and STATE.Remotes.claim.Name),
            tostring(STATE.Remotes.sell and STATE.Remotes.sell.Name)
        ))
    end
end

--==================================================================
-- [SEÇÃO 6] FILTROS
--==================================================================
local Filter = {}

function Filter.passes(egg)
    if not egg or not egg.instance or not egg.instance.Parent then return false end
    -- Blacklist
    if CONFIG.Blacklist[egg.name] then return false end
    -- Only Favorites
    if CONFIG.OnlyFavorites and not CONFIG.Favorites[egg.name] then return false end
    -- Value
    if CONFIG.UseValueFilter and egg.value < CONFIG.MinValue then return false end
    -- Distance
    if CONFIG.MaxDistance > 0 and egg.distance > CONFIG.MaxDistance then return false end
    -- Rarity
    if CONFIG.UseRarityFilter then
        local any = false
        for r, on in pairs(CONFIG.RarityFilter) do
            if on and egg.rarity == r then any = true break end
        end
        if not any then return false end
    end
    return true
end

function Filter.pickBest(eggs)
    local candidates = {}
    for _, e in ipairs(eggs) do
        if Filter.passes(e) then table.insert(candidates, e) end
    end
    if #candidates == 0 then return nil end

    local mode = CONFIG.PriorityMode
    -- FavoritePriority: se algum favorito estiver entre os candidatos, priorizar
    if CONFIG.FavoritePriority then
        local fav = {}
        for _, e in ipairs(candidates) do
            if CONFIG.Favorites[e.name] then table.insert(fav, e) end
        end
        if #fav > 0 then candidates = fav end
    end

    if mode == "Closest" then
        table.sort(candidates, function(a, b) return a.distance < b.distance end)
    elseif mode == "Highest Rarity" then
        table.sort(candidates, function(a, b)
            local wa, wb = Utils.rarityWeight(a.rarity), Utils.rarityWeight(b.rarity)
            if wa == wb then return a.value > b.value end
            return wa > wb
        end)
    elseif mode == "Custom" then
        -- Custom: raridade primeiro, depois valor, depois distância
        table.sort(candidates, function(a, b)
            local wa, wb = Utils.rarityWeight(a.rarity), Utils.rarityWeight(b.rarity)
            if wa ~= wb then return wa > wb end
            if a.value ~= b.value then return a.value > b.value end
            return a.distance < b.distance
        end)
    else -- Highest Value (default)
        table.sort(candidates, function(a, b) return a.value > b.value end)
    end
    return candidates[1]
end

--==================================================================
-- [SEÇÃO 7] NOTIFICAÇÕES
--==================================================================
local Notify = {}
local notifyHolder

function Notify.init(parent)
    notifyHolder = Instance.new("Frame")
    notifyHolder.Name = "NotifyHolder"
    notifyHolder.BackgroundTransparency = 1
    notifyHolder.AnchorPoint = Vector2.new(1, 0)
    notifyHolder.Position = UDim2.new(1, -10, 0, 60)
    notifyHolder.Size = UDim2.new(0, 240, 0, 400)
    notifyHolder.Parent = parent
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = notifyHolder
end

function Notify.push(text, color)
    if not CONFIG.Notifications or not notifyHolder then return end
    color = color or Color3.fromRGB(80, 180, 255)
    local box = Instance.new("Frame")
    box.BackgroundColor3 = Color3.fromRGB(22, 24, 32)
    box.BackgroundTransparency = 0.1
    box.BorderSizePixel = 0
    box.Size = UDim2.new(1, 0, 0, 40)
    box.Parent = notifyHolder

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = box

    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = 1
    stroke.Transparency = 0.3
    stroke.Parent = box

    local side = Instance.new("Frame")
    side.BackgroundColor3 = color
    side.BorderSizePixel = 0
    side.Size = UDim2.new(0, 4, 1, 0)
    side.Parent = box
    local sc = Instance.new("UICorner")
    sc.CornerRadius = UDim.new(0, 4)
    sc.Parent = side

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.new(0, 12, 0, 0)
    label.Size = UDim2.new(1, -18, 1, 0)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextColor3 = Color3.fromRGB(235, 235, 240)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextWrapped = true
    label.Text = text
    label.Parent = box

    box.BackgroundTransparency = 1
    label.TextTransparency = 1
    local t = TweenService:Create(box, TweenInfo.new(0.25), {BackgroundTransparency = 0.1})
    local t2 = TweenService:Create(label, TweenInfo.new(0.25), {TextTransparency = 0})
    t:Play(); t2:Play()

    task.delay(3, function()
        if not box or not box.Parent then return end
        local o1 = TweenService:Create(box, TweenInfo.new(0.3), {BackgroundTransparency = 1})
        local o2 = TweenService:Create(label, TweenInfo.new(0.3), {TextTransparency = 1})
        o1:Play(); o2:Play()
        o1.Completed:Connect(function() box:Destroy() end)
    end)
end

--==================================================================
-- [SEÇÃO 8] UI HELPERS
--==================================================================
local UIHelpers = {}

local THEME = {
    bg      = Color3.fromRGB(18, 19, 26),
    panel   = Color3.fromRGB(26, 28, 38),
    panel2  = Color3.fromRGB(34, 37, 50),
    accent  = Color3.fromRGB(120, 160, 255),
    accent2 = Color3.fromRGB(90, 220, 180),
    text    = Color3.fromRGB(230, 232, 240),
    textDim = Color3.fromRGB(160, 165, 180),
    danger  = Color3.fromRGB(255, 90, 90),
    ok      = Color3.fromRGB(90, 220, 130),
}

UIHelpers.THEME = THEME

function UIHelpers.corner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 10)
    c.Parent = parent
    return c
end

function UIHelpers.stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(60, 65, 85)
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0.4
    s.Parent = parent
    return s
end

function UIHelpers.padding(parent, px)
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0, px or 6)
    p.PaddingBottom = UDim.new(0, px or 6)
    p.PaddingLeft = UDim.new(0, px or 8)
    p.PaddingRight = UDim.new(0, px or 8)
    p.Parent = parent
    return p
end

function UIHelpers.makeButton(parent, text, height, color)
    local btn = Instance.new("TextButton")
    btn.BackgroundColor3 = color or THEME.panel2
    btn.BorderSizePixel = 0
    btn.Size = UDim2.new(1, 0, 0, height or 36)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 14
    btn.TextColor3 = THEME.text
    btn.Text = text
    btn.AutoButtonColor = false
    btn.Parent = parent
    UIHelpers.corner(btn, 8)
    UIHelpers.stroke(btn, Color3.fromRGB(70, 75, 100), 1, 0.5)
    UIHelpers.trackHover(btn)
    return btn
end

function UIHelpers.trackHover(btn)
    local base = btn.BackgroundColor3
    Utils.track(btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = base:Lerp(Color3.new(1,1,1), 0.08)}):Play()
    end))
    Utils.track(btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = base}):Play()
    end))
    Utils.track(btn.MouseButton1Down:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.08), {BackgroundColor3 = base:Lerp(Color3.new(0,0,0), 0.15)}):Play()
    end))
    Utils.track(btn.MouseButton1Up:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.08), {BackgroundColor3 = base}):Play()
    end))
end

-- Toggle moderno
function UIHelpers.makeToggle(parent, labelText, initial, onChange)
    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1, 0, 0, 34)
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(0.7, 0, 1, 0)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 13
    lbl.TextColor3 = THEME.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = labelText
    lbl.Parent = row

    local sw = Instance.new("TextButton")
    sw.AnchorPoint = Vector2.new(1, 0.5)
    sw.Position = UDim2.new(1, 0, 0.5, 0)
    sw.Size = UDim2.new(0, 46, 0, 24)
    sw.BackgroundColor3 = initial and THEME.accent2 or Color3.fromRGB(60,64,80)
    sw.BorderSizePixel = 0
    sw.Text = ""
    sw.AutoButtonColor = false
    sw.Parent = row
    UIHelpers.corner(sw, 12)

    local knob = Instance.new("Frame")
    knob.BackgroundColor3 = Color3.fromRGB(255,255,255)
    knob.BorderSizePixel = 0
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = initial and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
    knob.Parent = sw
    UIHelpers.corner(knob, 9)

    local state = initial
    Utils.track(sw.MouseButton1Click:Connect(function()
        state = not state
        local target = state and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        TweenService:Create(knob, TweenInfo.new(0.15), {Position = target}):Play()
        TweenService:Create(sw, TweenInfo.new(0.15), {BackgroundColor3 = state and THEME.accent2 or Color3.fromRGB(60,64,80)}):Play()
        if onChange then Utils.safeCall(onChange, state) end
    end))
    return { set = function(v)
        state = v
        knob.Position = v and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        sw.BackgroundColor3 = v and THEME.accent2 or Color3.fromRGB(60,64,80)
    end }
end

function UIHelpers.makeTextbox(parent, placeholder, initial, onSubmit)
    local box = Instance.new("TextBox")
    box.BackgroundColor3 = THEME.panel2
    box.BorderSizePixel = 0
    box.Size = UDim2.new(1, 0, 0, 32)
    box.Font = Enum.Font.Gotham
    box.TextSize = 13
    box.TextColor3 = THEME.text
    box.PlaceholderText = placeholder or ""
    box.PlaceholderColor3 = THEME.textDim
    box.Text = initial or ""
    box.ClearTextOnFocus = false
    box.Parent = parent
    UIHelpers.corner(box, 8)
    UIHelpers.stroke(box, Color3.fromRGB(70,75,100), 1, 0.5)
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = box
    Utils.track(box.FocusLost:Connect(function()
        if onSubmit then Utils.safeCall(onSubmit, box.Text) end
    end))
    return box
end

function UIHelpers.makeSlider(parent, labelText, minV, maxV, initial, onChange)
    local wrap = Instance.new("Frame")
    wrap.BackgroundTransparency = 1
    wrap.Size = UDim2.new(1, 0, 0, 44)
    wrap.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, 0, 0, 18)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextColor3 = THEME.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = labelText .. ": " .. tostring(initial)
    lbl.Parent = wrap

    local bar = Instance.new("Frame")
    bar.BackgroundColor3 = THEME.panel2
    bar.BorderSizePixel = 0
    bar.Position = UDim2.new(0, 0, 0, 24)
    bar.Size = UDim2.new(1, 0, 0, 8)
    bar.Parent = wrap
    UIHelpers.corner(bar, 4)

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = THEME.accent
    fill.BorderSizePixel = 0
    fill.Size = UDim2.new((initial - minV)/(maxV - minV), 0, 1, 0)
    fill.Parent = bar
    UIHelpers.corner(fill, 4)

    local dragging = false
    local function update(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local val = minV + (maxV - minV) * rel
        fill.Size = UDim2.new(rel, 0, 1, 0)
        lbl.Text = labelText .. ": " .. string.format("%.0f", val)
        if onChange then Utils.safeCall(onChange, val) end
    end

    Utils.track(bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            update(input.Position.X)
        end
    end))
    Utils.track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            update(input.Position.X)
        end
    end))
    Utils.track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    return {}
end

function UIHelpers.makeLabel(parent, text, color, size)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size = UDim2.new(1, 0, 0, size or 18)
    l.Font = Enum.Font.Gotham
    l.TextSize = 12
    l.TextColor3 = color or THEME.text
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextWrapped = true
    l.Text = text
    l.Parent = parent
    return l
end

function UIHelpers.makeSection(parent, title)
    local section = Instance.new("Frame")
    section.BackgroundColor3 = THEME.panel
    section.BorderSizePixel = 0
    section.Size = UDim2.new(1, 0, 0, 10) -- atualiza depois
    section.AutomaticSize = Enum.AutomaticSize.Y
    section.Parent = parent
    UIHelpers.corner(section, 10)
    UIHelpers.stroke(section, Color3.fromRGB(60,65,85), 1, 0.5)
    UIHelpers.padding(section, 10)

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = section

    if title then
        local t = Instance.new("TextLabel")
        t.BackgroundTransparency = 1
        t.Size = UDim2.new(1, 0, 0, 20)
        t.Font = Enum.Font.GothamBold
        t.TextSize = 13
        t.TextColor3 = THEME.accent
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Text = title
        t.LayoutOrder = -1
        t.Parent = section
    end
    return section
end

--==================================================================
-- [SEÇÃO 9] UI PRINCIPAL
--==================================================================
local UI = {}

local TABS = {
    { id = "home",       icon = "🏠", label = "Home" },
    { id = "steal",      icon = "🥚", label = "Steal" },
    { id = "eggs",       icon = "📋", label = "Eggs" },
    { id = "esp",        icon = "👁", label = "ESP" },
    { id = "favorites",  icon = "⭐", label = "Favorites" },
    { id = "stats",      icon = "📊", label = "Statistics" },
    { id = "settings",   icon = "⚙", label = "Settings" },
}

local activeTab = "home"
local Pages = {}
local NavButtons = {}

function UI.create()
    -- ScreenGui principal
    local gui = Instance.new("ScreenGui")
    gui.Name = "EggHub_UI_" .. tostring(math.random(1, 1e6))
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = PlayerGui
    STATE.UI.gui = gui

    -- Container de escala (não afeta o botão flutuante)
    local scaleWrap = Instance.new("Frame")
    scaleWrap.BackgroundTransparency = 1
    scaleWrap.Size = UDim2.new(1, 0, 1, 0)
    scaleWrap.Parent = gui
    STATE.UI.scaleWrap = scaleWrap

    local uiScale = Instance.new("UIScale")
    uiScale.Scale = CONFIG.UIScale
    uiScale.Parent = scaleWrap
    STATE.UI.uiScale = uiScale

    -- -------- Floating button --------
    local fb = Instance.new("TextButton")
    fb.Name = "FloatingButton"
    fb.Size = UDim2.new(0, 56, 0, 56)
    fb.Position = UDim2.new(0, 20, 0.5, -28)
    fb.BackgroundColor3 = THEME.panel
    fb.BorderSizePixel = 0
    fb.Text = "🥚"
    fb.Font = Enum.Font.GothamBold
    fb.TextSize = 26
    fb.TextColor3 = THEME.text
    fb.AutoButtonColor = false
    fb.Active = true
    fb.Draggable = false
    fb.Parent = scaleWrap
    UIHelpers.corner(fb, 28)
    UIHelpers.stroke(fb, THEME.accent, 2, 0.3)
    STATE.UI.floatingButton = fb

    -- Drag do botão flutuante
    UI.setupFloatingButtonDrag(fb)

    -- Abrir/fechar UI
    local clickAccum = 0
    local dragMoved = false
    Utils.track(fb.MouseButton1Down:Connect(function()
        TweenService:Create(fb, TweenInfo.new(0.1), {Size = UDim2.new(0, 52, 0, 52)}):Play()
    end))
    Utils.track(fb.MouseButton1Up:Connect(function()
        TweenService:Create(fb, TweenInfo.new(0.1), {Size = UDim2.new(0, 56, 0, 56)}):Play()
    end))

    -- -------- Main window --------
    local win = Instance.new("Frame")
    win.Name = "MainWindow"
    win.BackgroundColor3 = THEME.bg
    win.BorderSizePixel = 0
    win.AnchorPoint = Vector2.new(0.5, 0.5)
    win.Position = UDim2.new(0.5, 0, 0.5, 0)
    win.Size = UDim2.new(0, 640, 0, 420)
    win.ClipsDescendants = true
    win.Visible = true
    win.Parent = scaleWrap
    UIHelpers.corner(win, 14)
    UIHelpers.stroke(win, Color3.fromRGB(70, 75, 100), 1.2, 0.3)
    STATE.UI.window = win

    -- Sombras (usar um Frame com gradiente abaixo)
    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.Image = "rbxassetid://5028857084"
    shadow.ImageColor3 = Color3.new(0, 0, 0)
    shadow.ImageTransparency = 0.6
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(24, 24, 276, 276)
    shadow.BackgroundTransparency = 1
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.Position = UDim2.new(0.5, 0, 0.5, 8)
    shadow.Size = UDim2.new(1, 40, 1, 40)
    shadow.ZIndex = -1
    shadow.Parent = win

    -- Header
    local header = Instance.new("Frame")
    header.BackgroundColor3 = THEME.panel
    header.BorderSizePixel = 0
    header.Size = UDim2.new(1, 0, 0, 44)
    header.Parent = win
    local hc = UIHelpers.corner(header, 14)
    -- corte inferior
    local headerClip = Instance.new("Frame")
    headerClip.BackgroundColor3 = THEME.panel
    headerClip.BorderSizePixel = 0
    headerClip.Position = UDim2.new(0, 0, 1, -10)
    headerClip.Size = UDim2.new(1, 0, 0, 10)
    headerClip.Parent = header

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 14, 0, 0)
    title.Size = UDim2.new(0.6, 0, 1, 0)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.TextColor3 = THEME.text
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "🥚 EGG HUB"
    title.Parent = header

    local verLbl = Instance.new("TextLabel")
    verLbl.BackgroundTransparency = 1
    verLbl.AnchorPoint = Vector2.new(1, 0.5)
    verLbl.Position = UDim2.new(1, -50, 0.5, 0)
    verLbl.Size = UDim2.new(0, 80, 1, 0)
    verLbl.Font = Enum.Font.Gotham
    verLbl.TextSize = 11
    verLbl.TextColor3 = THEME.textDim
    verLbl.TextXAlignment = Enum.TextXAlignment.Right
    verLbl.Text = "v1.0.0"
    verLbl.Parent = header

    local closeBtn = Instance.new("TextButton")
    closeBtn.AnchorPoint = Vector2.new(1, 0.5)
    closeBtn.Position = UDim2.new(1, -8, 0.5, 0)
    closeBtn.Size = UDim2.new(0, 32, 0, 32)
    closeBtn.BackgroundColor3 = Color3.fromRGB(50, 54, 70)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "×"
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 20
    closeBtn.TextColor3 = THEME.text
    closeBtn.AutoButtonColor = false
    closeBtn.Parent = header
    UIHelpers.corner(closeBtn, 8)
    UIHelpers.trackHover(closeBtn)
    Utils.track(closeBtn.MouseButton1Click:Connect(function()
        UI.toggleWindow(false)
    end))
    STATE.UI.closeBtn = closeBtn

    -- Drag do header
    UI.setupWindowDrag(win, header)

    -- -------- Body --------
    local body = Instance.new("Frame")
    body.BackgroundTransparency = 1
    body.Position = UDim2.new(0, 0, 0, 44)
    body.Size = UDim2.new(1, 0, 1, -44)
    body.Parent = win

    -- Sidebar / Nav
    local nav = Instance.new("ScrollingFrame")
    nav.Name = "Nav"
    nav.BackgroundColor3 = THEME.panel
    nav.BorderSizePixel = 0
    nav.ScrollBarThickness = 2
    nav.ScrollBarImageColor3 = THEME.accent
    nav.CanvasSize = UDim2.new(0, 0, 0, 0)
    nav.AutomaticCanvasSize = Enum.AutomaticSize.Y
    nav.Parent = body
    STATE.UI.nav = nav

    local navLayout = Instance.new("UIListLayout")
    navLayout.Padding = UDim.new(0, 4)
    navLayout.SortOrder = Enum.SortOrder.LayoutOrder
    navLayout.Parent = nav
    UIHelpers.padding(nav, 6)

    -- Content
    local content = Instance.new("Frame")
    content.BackgroundTransparency = 1
    content.Parent = body
    STATE.UI.content = content

    -- Aplicar layout responsivo
    UI.applyResponsiveLayout()
    Utils.track(Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(UI.applyResponsiveLayout))
    Utils.track(UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(UI.applyResponsiveLayout))

    -- Construir abas (nav + páginas)
    for _, tab in ipairs(TABS) do
        local navBtn = Instance.new("TextButton")
        navBtn.Name = "Tab_" .. tab.id
        navBtn.BackgroundColor3 = Color3.fromRGB(0,0,0)
        navBtn.BackgroundTransparency = 1
        navBtn.BorderSizePixel = 0
        navBtn.Size = UDim2.new(1, 0, 0, 36)
        navBtn.Font = Enum.Font.GothamMedium
        navBtn.TextSize = 13
        navBtn.TextColor3 = THEME.textDim
        navBtn.TextXAlignment = Enum.TextXAlignment.Left
        navBtn.Text = "  " .. tab.icon .. "  " .. tab.label
        navBtn.AutoButtonColor = false
        navBtn.LayoutOrder = #NavButtons + 1
        navBtn.Parent = nav
        UIHelpers.corner(navBtn, 8)
        UIHelpers.trackHover(navBtn)
        Utils.track(navBtn.MouseButton1Click:Connect(function()
            UI.showTab(tab.id)
        end))
        table.insert(NavButtons, { id = tab.id, btn = navBtn })

        -- Página
        local page = Instance.new("ScrollingFrame")
        page.Name = "Page_" .. tab.id
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 4
        page.ScrollBarImageColor3 = THEME.accent
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.Visible = (tab.id == "home")
        page.Parent = content
        local pLayout = Instance.new("UIListLayout")
        pLayout.Padding = UDim.new(0, 8)
        pLayout.SortOrder = Enum.SortOrder.LayoutOrder
        pLayout.Parent = page
        UIHelpers.padding(page, 10)
        Pages[tab.id] = page
    end

    UI.buildHomePage()
    UI.buildStealPage()
    UI.buildEggsPage()
    UI.buildESPPage()
    UI.buildFavoritesPage()
    UI.buildStatsPage()
    UI.buildSettingsPage()

    UI.showTab("home")

    -- Notificações
    Notify.init(gui)
end

-- Layout responsivo: sidebar larga no PC, tabs horizontais em mobile
function UI.applyResponsiveLayout()
    local win = STATE.UI.window
    local nav = STATE.UI.nav
    local content = STATE.UI.content
    if not win or not nav or not content then return end
    local vp = Utils.viewportSize()
    local isMobile = vp.X < 720 or Utils.isMobile()

    if isMobile then
        -- janela ocupa quase toda a tela
        win.Size = UDim2.new(1, -16, 1, -40)
        win.Position = UDim2.new(0.5, 0, 0.5, 10)

        nav.Position = UDim2.new(0, 0, 0, 0)
        nav.Size = UDim2.new(1, 0, 0, 44)
        nav.ScrollingDirection = Enum.ScrollingDirection.X
        nav.CanvasSize = UDim2.new(0, #TABS * 100, 0, 0)
        nav.AutomaticCanvasSize = Enum.AutomaticSize.X

        local list = nav:FindFirstChildOfClass("UIListLayout")
        if list then
            list.FillDirection = Enum.FillDirection.Horizontal
            list.Padding = UDim.new(0, 4)
            list.VerticalAlignment = Enum.VerticalAlignment.Center
        end
        for _, entry in ipairs(NavButtons) do
            entry.btn.Size = UDim2.new(0, 96, 1, -6)
            entry.btn.TextXAlignment = Enum.TextXAlignment.Center
            entry.btn.Text = entry.btn.Text:gsub("^%s+","")
        end

        content.Position = UDim2.new(0, 0, 0, 48)
        content.Size = UDim2.new(1, 0, 1, -48)

        for _, page in pairs(Pages) do
            page.Size = UDim2.new(1, 0, 1, 0)
        end
    else
        win.Size = UDim2.new(0, 680, 0, 460)
        win.Position = UDim2.new(0.5, 0, 0.5, 0)

        nav.Position = UDim2.new(0, 0, 0, 0)
        nav.Size = UDim2.new(0, 150, 1, 0)
        nav.ScrollingDirection = Enum.ScrollingDirection.Y
        nav.CanvasSize = UDim2.new(0, 0, 0, 0)
        nav.AutomaticCanvasSize = Enum.AutomaticSize.Y

        local list = nav:FindFirstChildOfClass("UIListLayout")
        if list then
            list.FillDirection = Enum.FillDirection.Vertical
            list.Padding = UDim.new(0, 4)
        end
        for _, entry in ipairs(NavButtons) do
            entry.btn.Size = UDim2.new(1, 0, 0, 36)
            entry.btn.TextXAlignment = Enum.TextXAlignment.Left
            local tab = nil
            for _, t in ipairs(TABS) do if t.id == entry.id then tab = t break end end
            if tab then entry.btn.Text = "  " .. tab.icon .. "  " .. tab.label end
        end

        content.Position = UDim2.new(0, 150, 0, 0)
        content.Size = UDim2.new(1, -150, 1, 0)

        for _, page in pairs(Pages) do
            page.Size = UDim2.new(1, 0, 1, 0)
        end
    end
end

function UI.showTab(id)
    activeTab = id
    for _, entry in ipairs(NavButtons) do
        local on = entry.id == id
        entry.btn.TextColor3 = on and THEME.text or THEME.textDim
        entry.btn.BackgroundTransparency = on and 0.6 or 1
        entry.btn.BackgroundColor3 = THEME.panel2
    end
    for pageId, page in pairs(Pages) do
        page.Visible = (pageId == id)
    end
end

function UI.toggleWindow(force)
    local win = STATE.UI.window
    if not win then return end
    local open = force
    if open == nil then open = not win.Visible end
    if open then
        win.Visible = true
        win.Size = UDim2.new(win.Size.X.Scale, win.Size.X.Offset, 0, 0)
        if CONFIG.UIAnimation then
            local target = (Utils.viewportSize().X < 720 or Utils.isMobile())
                and UDim2.new(1, -16, 1, -40) or UDim2.new(0, 680, 0, 460)
            TweenService:Create(win, TweenInfo.new(CONFIG.AnimationSpeed, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {Size = target}):Play()
        end
    else
        if CONFIG.UIAnimation then
            local t = TweenService:Create(win, TweenInfo.new(CONFIG.AnimationSpeed, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                {Size = UDim2.new(win.Size.X.Scale, win.Size.X.Offset, 0, 0)})
            t:Play()
            t.Completed:Connect(function() win.Visible = false end)
        else
            win.Visible = false
        end
    end
end

-- Drag da janela (header)
function UI.setupWindowDrag(win, handle)
    local dragging, startPos, startInput = false, nil, nil
    Utils.track(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startInput = input.Position
            startPos = win.Position
        end
    end))
    Utils.track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - startInput
            win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
    Utils.track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

-- Drag do botão flutuante (com persistência de posição)
function UI.setupFloatingButtonDrag(fb)
    local dragging, moved = false, false
    local startPos, startInput = nil, nil
    Utils.track(fb.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            startInput = input.Position
            startPos = fb.Position
        end
    end))
    Utils.track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - startInput
            if math.abs(delta.X) > 4 or math.abs(delta.Y) > 4 then moved = true end
            fb.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
    Utils.track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if dragging and not moved then
                -- Clique simples: abre/fecha a UI
                UI.toggleWindow(nil)
            end
            dragging = false
        end
    end))
end

--==================================================================
-- [SEÇÃO 10] PÁGINAS
--==================================================================
function UI.buildHomePage()
    local p = Pages.home
    local hero = UIHelpers.makeSection(p, "Status do Hub")
    local statusLbl = UIHelpers.makeLabel(hero, "Script: Online  •  Versão 1.0.0", THEME.ok, 16)
    local infoLbl = UIHelpers.makeLabel(hero, "Ovos detectados: 0  •  Melhor ovo: -", THEME.textDim, 14)
    STATE.UI.homeStatus = infoLbl

    local quick = UIHelpers.makeSection(p, "Ações Rápidas")
    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1, 0, 0, 38)
    row.Parent = quick
    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.new(0.5, -6, 0, 34)
    grid.CellPadding = UDim2.new(0, 6, 0, 6)
    grid.Parent = row

    local b1 = UIHelpers.makeButton(row, "Auto Steal", 34, THEME.panel2)
    b1.MouseButton1Click:Connect(function()
        CONFIG.AutoSteal = not CONFIG.AutoSteal
        b1.BackgroundColor3 = CONFIG.AutoSteal and THEME.accent2 or THEME.panel2
        Notify.push("Auto Steal: " .. (CONFIG.AutoSteal and "ON" or "OFF"), CONFIG.AutoSteal and THEME.ok or THEME.danger)
        if CONFIG.AutoSteal then AutoSteal.start() else AutoSteal.stop() end
    end)

    local b2 = UIHelpers.makeButton(row, "Instant Steal", 34, THEME.panel2)
    b2.MouseButton1Click:Connect(function()
        CONFIG.InstantSteal = not CONFIG.InstantSteal
        b2.BackgroundColor3 = CONFIG.InstantSteal and THEME.accent2 or THEME.panel2
        Notify.push("Instant Steal: " .. (CONFIG.InstantSteal and "ON" or "OFF"), CONFIG.InstantSteal and THEME.ok or THEME.danger)
        if CONFIG.InstantSteal then InstantSteal.start() else InstantSteal.stop() end
    end)

    local b3 = UIHelpers.makeButton(row, "ESP", 34, THEME.panel2)
    b3.MouseButton1Click:Connect(function()
        CONFIG.EggESP = not CONFIG.EggESP
        b3.BackgroundColor3 = CONFIG.EggESP and THEME.accent2 or THEME.panel2
        Notify.push("ESP: " .. (CONFIG.EggESP and "ON" or "OFF"), CONFIG.EggESP and THEME.ok or THEME.danger)
        if CONFIG.EggESP then ESP.start() else ESP.stop() end
    end)

    local b4 = UIHelpers.makeButton(row, "Auto Farm", 34, THEME.panel2)
    b4.MouseButton1Click:Connect(function()
        CONFIG.AutoFarm = not CONFIG.AutoFarm
        b4.BackgroundColor3 = CONFIG.AutoFarm and THEME.accent2 or THEME.panel2
        Notify.push("Auto Farm: " .. (CONFIG.AutoFarm and "ON" or "OFF"), CONFIG.AutoFarm and THEME.ok or THEME.danger)
        if CONFIG.AutoFarm then AutoFarm.start() else AutoFarm.stop() end
    end)

    local stats = UIHelpers.makeSection(p, "Ativos no momento")
    local activeLbl = UIHelpers.makeLabel(stats, "Nenhuma função ativa.", THEME.textDim, 14)
    STATE.UI.homeActive = activeLbl

    local debug = UIHelpers.makeSection(p, "Debug / Detecção")
    local debugLbl = UIHelpers.makeLabel(debug, "Aguardando scan...", THEME.textDim, 13)
    STATE.UI.homeDebug = debugLbl
    local refreshBtn = UIHelpers.makeButton(debug, "🔄 Re-detectar objetos", 32)
    refreshBtn.MouseButton1Click:Connect(function()
        Detection.scanRemotes()
        STATE.Eggs = Detection.scanEggs()
        Notify.push("Re-detecção concluída.", THEME.accent)
        UI.updateHomeDebug()
    end)
end

function UI.updateHomeDebug()
    if not STATE.UI.homeDebug then return end
    STATE.UI.homeDebug.Text = string.format(
        "Ovos: %d   Remotes: %d   Steal: %s",
        #STATE.Eggs,
        #STATE.Remotes.all,
        STATE.Remotes.steal and STATE.Remotes.steal.Name or "n/d"
    )
end

function UI.refreshHomeInfo()
    if not STATE.UI.homeStatus then return end
    local best = "-"
    local bestV = 0
    for _, e in ipairs(STATE.Eggs) do
        if e.value > bestV then bestV = e.value; best = e.name end
    end
    STATE.UI.homeStatus.Text = string.format(
        "Ovos detectados: %d  •  Melhor: %s  (%s)",
        #STATE.Eggs, best, Utils.formatNumber(bestV)
    )
    local actives = {}
    if CONFIG.AutoSteal then table.insert(actives, "Auto Steal") end
    if CONFIG.InstantSteal then table.insert(actives, "Instant") end
    if CONFIG.EggESP then table.insert(actives, "Egg ESP") end
    if CONFIG.PlayerESP then table.insert(actives, "Player ESP") end
    if CONFIG.AutoFarm then table.insert(actives, "Auto Farm") end
    if STATE.UI.homeActive then
        STATE.UI.homeActive.Text = #actives > 0 and table.concat(actives, " • ") or "Nenhuma função ativa."
    end
end

function UI.buildStealPage()
    local p = Pages.steal
    -- Auto Steal
    local s1 = UIHelpers.makeSection(p, "🎯 Auto Steal")
    UIHelpers.makeToggle(s1, "Ativar Auto Steal", CONFIG.AutoSteal, function(v)
        CONFIG.AutoSteal = v
        if v then AutoSteal.start() else AutoSteal.stop() end
        Notify.push("Auto Steal " .. (v and "ativado" or "desativado"), v and THEME.ok or THEME.danger)
    end)
    UIHelpers.makeTextbox(s1, "Valor mínimo (ex: 100K, 1M)", tostring(CONFIG.MinValue), function(txt)
        CONFIG.MinValue = Utils.parseShortNumber(txt)
    end)
    UIHelpers.makeTextbox(s1, "Distância máxima (studs)", tostring(CONFIG.MaxDistance), function(txt)
        CONFIG.MaxDistance = tonumber(txt) or CONFIG.MaxDistance
    end)

    local prioSec = UIHelpers.makeSection(p, "Modo de Prioridade")
    for _, mode in ipairs({"Highest Value","Highest Rarity","Closest","Custom"}) do
        local btn = UIHelpers.makeButton(prioSec, mode, 30,
            CONFIG.PriorityMode == mode and THEME.accent or THEME.panel2)
        btn.MouseButton1Click:Connect(function()
            CONFIG.PriorityMode = mode
            for _, child in ipairs(prioSec:GetChildren()) do
                if child:IsA("TextButton") then
                    child.BackgroundColor3 = (child.Text == mode) and THEME.accent or THEME.panel2
                end
            end
        end)
    end

    -- Instant Steal
    local s2 = UIHelpers.makeSection(p, "⚡ Instant Steal")
    UIHelpers.makeToggle(s2, "Ativar Instant Steal", CONFIG.InstantSteal, function(v)
        CONFIG.InstantSteal = v
        if v then InstantSteal.start() else InstantSteal.stop() end
        Notify.push("Instant Steal " .. (v and "ativado" or "desativado"), v and THEME.ok or THEME.danger)
    end)
    local dRow = Instance.new("Frame"); dRow.BackgroundTransparency = 1; dRow.Size = UDim2.new(1,0,0,34); dRow.Parent = s2
    local dGrid = Instance.new("UIGridLayout")
    dGrid.CellSize = UDim2.new(0, 60, 0, 30); dGrid.CellPadding = UDim2.new(0, 4, 0, 4); dGrid.Parent = dRow
    for _, d in ipairs({0, 25, 50, 100, 250, 500}) do
        local b = UIHelpers.makeButton(dRow, tostring(d), 30,
            CONFIG.InstantDelay == d and THEME.accent or THEME.panel2)
        b.MouseButton1Click:Connect(function()
            CONFIG.InstantDelay = d
            for _, c in ipairs(dRow:GetChildren()) do
                if c:IsA("TextButton") then c.BackgroundColor3 = (c.Text == tostring(d)) and THEME.accent or THEME.panel2 end
            end
        end)
    end
    UIHelpers.makeTextbox(s2, "Delay customizado (ms)", tostring(CONFIG.InstantDelay), function(txt)
        CONFIG.InstantDelay = tonumber(txt) or CONFIG.InstantDelay
    end)

    -- Auto Farm
    local s3 = UIHelpers.makeSection(p, "🏃 Auto Farm")
    UIHelpers.makeToggle(s3, "Ativar Auto Farm", CONFIG.AutoFarm, function(v)
        CONFIG.AutoFarm = v
        if v then AutoFarm.start() else AutoFarm.stop() end
        Notify.push("Auto Farm " .. (v and "ativado" or "desativado"), v and THEME.ok or THEME.danger)
    end)
    UIHelpers.makeToggle(s3, "Auto Collect", CONFIG.AutoCollect, function(v) CONFIG.AutoCollect = v end)
    UIHelpers.makeToggle(s3, "Auto Pickup", CONFIG.AutoPickup, function(v) CONFIG.AutoPickup = v end)
    UIHelpers.makeToggle(s3, "Auto Claim", CONFIG.AutoClaim, function(v) CONFIG.AutoClaim = v end)
    UIHelpers.makeToggle(s3, "Auto Sell", CONFIG.AutoSell, function(v) CONFIG.AutoSell = v end)
    UIHelpers.makeToggle(s3, "Auto Return", CONFIG.AutoReturn, function(v) CONFIG.AutoReturn = v end)
end

function UI.buildEggsPage()
    local p = Pages.eggs

    local filters = UIHelpers.makeSection(p, "Filtro por Valor")
    local row = Instance.new("Frame"); row.BackgroundTransparency = 1; row.Size = UDim2.new(1,0,0,68); row.Parent = filters
    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.new(0, 60, 0, 30); grid.CellPadding = UDim2.new(0, 4, 0, 4); grid.Parent = row
    for _, v in ipairs({0, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11}) do
        local label = v == 0 and "Any" or Utils.formatNumber(v)
        local b = UIHelpers.makeButton(row, label, 30, CONFIG.MinValue == v and THEME.accent or THEME.panel2)
        b.MouseButton1Click:Connect(function()
            CONFIG.MinValue = v
            for _, c in ipairs(row:GetChildren()) do
                if c:IsA("TextButton") then c.BackgroundColor3 = (c.Text == label) and THEME.accent or THEME.panel2 end
            end
        end)
    end
    UIHelpers.makeTextbox(filters, "Valor mínimo personalizado", tostring(CONFIG.MinValue), function(txt)
        CONFIG.MinValue = Utils.parseShortNumber(txt)
    end)
    UIHelpers.makeToggle(filters, "Usar filtro de valor", CONFIG.UseValueFilter, function(v) CONFIG.UseValueFilter = v end)

    local rarSec = UIHelpers.makeSection(p, "Filtro por Raridade")
    UIHelpers.makeToggle(rarSec, "Usar filtro de raridade", CONFIG.UseRarityFilter, function(v) CONFIG.UseRarityFilter = v end)
    local rarHolder = Instance.new("Frame")
    rarHolder.BackgroundTransparency = 1
    rarHolder.Size = UDim2.new(1, 0, 0, 10)
    rarHolder.AutomaticSize = Enum.AutomaticSize.Y
    rarHolder.Parent = rarSec
    local rarLayout = Instance.new("UIGridLayout")
    rarLayout.CellSize = UDim2.new(0.5, -4, 0, 28)
    rarLayout.CellPadding = UDim2.new(0, 4, 0, 4)
    rarLayout.Parent = rarHolder
    STATE.UI.rarityHolder = rarHolder

    local listSec = UIHelpers.makeSection(p, "📋 Lista de Ovos")
    local sortRow = Instance.new("Frame"); sortRow.BackgroundTransparency = 1; sortRow.Size = UDim2.new(1,0,0,32); sortRow.Parent = listSec
    local sortGrid = Instance.new("UIGridLayout")
    sortGrid.CellSize = UDim2.new(0, 72, 0, 28); sortGrid.CellPadding = UDim2.new(0, 4, 0, 4); sortGrid.Parent = sortRow
    local sortModes = {"Valor","Raridade","Distância","Nome"}
    STATE.SortMode = "Valor"
    for _, m in ipairs(sortModes) do
        local b = UIHelpers.makeButton(sortRow, m, 28, m == "Valor" and THEME.accent or THEME.panel2)
        b.MouseButton1Click:Connect(function()
            STATE.SortMode = m
            for _, c in ipairs(sortRow:GetChildren()) do
                if c:IsA("TextButton") then c.BackgroundColor3 = (c.Text == m) and THEME.accent or THEME.panel2 end
            end
            UI.refreshEggList()
        end)
    end
    local refreshBtn = UIHelpers.makeButton(listSec, "🔄 Refresh", 30)
    refreshBtn.MouseButton1Click:Connect(function()
        STATE.Eggs = Detection.scanEggs()
        UI.refreshEggList()
        Notify.push("Lista atualizada.", THEME.accent)
    end)
    local container = Instance.new("Frame")
    container.BackgroundTransparency = 1
    container.Size = UDim2.new(1, 0, 0, 10)
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.Parent = listSec
    local cLayout = Instance.new("UIListLayout")
    cLayout.Padding = UDim.new(0, 4)
    cLayout.SortOrder = Enum.SortOrder.LayoutOrder
    cLayout.Parent = container
    STATE.UI.eggList = container
end

function UI.refreshRarityFilters()
    local holder = STATE.UI.rarityHolder
    if not holder then return end
    for _, c in ipairs(holder:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    for r, _ in pairs(STATE.Rarities) do
        local on = CONFIG.RarityFilter[r] == true
        local b = UIHelpers.makeButton(holder, (on and "☑ " or "☐ ") .. r, 28, on and THEME.accent or THEME.panel2)
        b.MouseButton1Click:Connect(function()
            CONFIG.RarityFilter[r] = not CONFIG.RarityFilter[r]
            local now = CONFIG.RarityFilter[r] == true
            b.Text = (now and "☑ " or "☐ ") .. r
            b.BackgroundColor3 = now and THEME.accent or THEME.panel2
        end)
    end
end

function UI.refreshEggList()
    local holder = STATE.UI.eggList
    if not holder then return end
    for _, c in ipairs(holder:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end
    local list = {}
    for _, e in ipairs(STATE.Eggs) do table.insert(list, e) end
    local mode = STATE.SortMode or "Valor"
    table.sort(list, function(a, b)
        if mode == "Valor" then return a.value > b.value end
        if mode == "Raridade" then return Utils.rarityWeight(a.rarity) > Utils.rarityWeight(b.rarity) end
        if mode == "Distância" then return a.distance < b.distance end
        if mode == "Nome" then return a.name < b.name end
        return false
    end)
    for i, e in ipairs(list) do
        local row = Instance.new("Frame")
        row.BackgroundColor3 = THEME.panel2
        row.BorderSizePixel = 0
        row.Size = UDim2.new(1, 0, 0, 40)
        row.LayoutOrder = i
        row.Parent = holder
        UIHelpers.corner(row, 8)

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Position = UDim2.new(0, 8, 0, 2)
        lbl.Size = UDim2.new(1, -80, 0, 20)
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = 12
        lbl.TextColor3 = THEME.text
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = string.format("%s • %s", e.name, Utils.formatNumber(e.value))
        lbl.Parent = row

        local sublbl = Instance.new("TextLabel")
        sublbl.BackgroundTransparency = 1
        sublbl.Position = UDim2.new(0, 8, 0, 20)
        sublbl.Size = UDim2.new(1, -80, 0, 18)
        sublbl.Font = Enum.Font.Gotham
        sublbl.TextSize = 11
        sublbl.TextColor3 = THEME.textDim
        sublbl.TextXAlignment = Enum.TextXAlignment.Left
        sublbl.Text = string.format("Raridade: %s  •  Dist: %.0f", e.rarity, e.distance)
        sublbl.Parent = row

        -- Botões (favorito / blacklist)
        local favBtn = Instance.new("TextButton")
        favBtn.BackgroundColor3 = CONFIG.Favorites[e.name] and THEME.accent2 or THEME.panel
        favBtn.BorderSizePixel = 0
        favBtn.AnchorPoint = Vector2.new(1, 0)
        favBtn.Position = UDim2.new(1, -6, 0, 6)
        favBtn.Size = UDim2.new(0, 28, 0, 28)
        favBtn.Text = "⭐"
        favBtn.Font = Enum.Font.GothamBold
        favBtn.TextSize = 14
        favBtn.AutoButtonColor = false
        favBtn.Parent = row
        UIHelpers.corner(favBtn, 6)
        favBtn.MouseButton1Click:Connect(function()
            CONFIG.Favorites[e.name] = not CONFIG.Favorites[e.name]
            favBtn.BackgroundColor3 = CONFIG.Favorites[e.name] and THEME.accent2 or THEME.panel
            Notify.push((CONFIG.Favorites[e.name] and "Adicionado aos favoritos: " or "Removido: ") .. e.name)
        end)

        local blBtn = Instance.new("TextButton")
        blBtn.BackgroundColor3 = CONFIG.Blacklist[e.name] and THEME.danger or THEME.panel
        blBtn.BorderSizePixel = 0
        blBtn.AnchorPoint = Vector2.new(1, 0)
        blBtn.Position = UDim2.new(1, -38, 0, 6)
        blBtn.Size = UDim2.new(0, 28, 0, 28)
        blBtn.Text = "🚫"
        blBtn.Font = Enum.Font.GothamBold
        blBtn.TextSize = 14
        blBtn.AutoButtonColor = false
        blBtn.Parent = row
        UIHelpers.corner(blBtn, 6)
        blBtn.MouseButton1Click:Connect(function()
            CONFIG.Blacklist[e.name] = not CONFIG.Blacklist[e.name]
            blBtn.BackgroundColor3 = CONFIG.Blacklist[e.name] and THEME.danger or THEME.panel
            Notify.push((CONFIG.Blacklist[e.name] and "Blacklist: " or "Removido da blacklist: ") .. e.name)
        end)
    end
end

function UI.buildESPPage()
    local p = Pages.esp
    local s1 = UIHelpers.makeSection(p, "👁 ESP de Ovos")
    UIHelpers.makeToggle(s1, "Egg ESP", CONFIG.EggESP, function(v)
        CONFIG.EggESP = v
        if v then ESP.start() else ESP.stop() end
    end)
    UIHelpers.makeToggle(s1, "Mostrar Nome", CONFIG.EggName, function(v) CONFIG.EggName = v end)
    UIHelpers.makeToggle(s1, "Mostrar Valor", CONFIG.EggValue, function(v) CONFIG.EggValue = v end)
    UIHelpers.makeToggle(s1, "Mostrar Raridade", CONFIG.EggRarity, function(v) CONFIG.EggRarity = v end)
    UIHelpers.makeToggle(s1, "Mostrar Distância", CONFIG.EggDistance, function(v) CONFIG.EggDistance = v end)

    local s2 = UIHelpers.makeSection(p, "👤 ESP de Jogadores")
    UIHelpers.makeToggle(s2, "Player ESP", CONFIG.PlayerESP, function(v)
        CONFIG.PlayerESP = v
        if v then ESP.startPlayers() else ESP.stopPlayers() end
    end)
    UIHelpers.makeToggle(s2, "Caixa", CONFIG.PlayerBox, function(v) CONFIG.PlayerBox = v end)
    UIHelpers.makeToggle(s2, "Nome", CONFIG.PlayerNameTag, function(v) CONFIG.PlayerNameTag = v end)
    UIHelpers.makeToggle(s2, "Distância", CONFIG.PlayerDistTag, function(v) CONFIG.PlayerDistTag = v end)
    UIHelpers.makeToggle(s2, "Highlight", CONFIG.PlayerHighlight, function(v) CONFIG.PlayerHighlight = v end)

    local s3 = UIHelpers.makeSection(p, "Distância Máxima do ESP")
    UIHelpers.makeSlider(s3, "Distância", 50, 2000, CONFIG.ESPMaxDistance, function(v)
        CONFIG.ESPMaxDistance = math.floor(v)
    end)
end

function UI.buildFavoritesPage()
    local p = Pages.favorites
    local s1 = UIHelpers.makeSection(p, "⭐ Favoritos")
    UIHelpers.makeToggle(s1, "Only Favorites (ignorar não-favoritos)", CONFIG.OnlyFavorites, function(v) CONFIG.OnlyFavorites = v end)
    UIHelpers.makeToggle(s1, "Auto Steal Favorites", CONFIG.AutoStealFavorites, function(v) CONFIG.AutoStealFavorites = v end)
    UIHelpers.makeToggle(s1, "Favorite Priority", CONFIG.FavoritePriority, function(v) CONFIG.FavoritePriority = v end)

    local s2 = UIHelpers.makeSection(s1, "Adicionar por nome")
    UIHelpers.makeTextbox(s2, "Nome do ovo", "", function(txt)
        if txt ~= "" then
            CONFIG.Favorites[txt] = true
            Notify.push("Favorito adicionado: " .. txt, THEME.ok)
            UI.refreshFavoritesList()
        end
    end)

    local list = UIHelpers.makeSection(p, "Lista de Favoritos")
    STATE.UI.favList = Instance.new("Frame")
    STATE.UI.favList.BackgroundTransparency = 1
    STATE.UI.favList.Size = UDim2.new(1, 0, 0, 10)
    STATE.UI.favList.AutomaticSize = Enum.AutomaticSize.Y
    STATE.UI.favList.Parent = list
    local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0,4); l.Parent = STATE.UI.favList
    UI.refreshFavoritesList()

    local bl = UIHelpers.makeSection(p, "🚫 Blacklist Manager")
    STATE.UI.blList = Instance.new("Frame")
    STATE.UI.blList.BackgroundTransparency = 1
    STATE.UI.blList.Size = UDim2.new(1, 0, 0, 10)
    STATE.UI.blList.AutomaticSize = Enum.AutomaticSize.Y
    STATE.UI.blList.Parent = bl
    local l2 = Instance.new("UIListLayout"); l2.Padding = UDim.new(0,4); l2.Parent = STATE.UI.blList
    UI.refreshBlacklist()
end

function UI.refreshFavoritesList()
    local h = STATE.UI.favList
    if not h then return end
    for _, c in ipairs(h:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end
    for name, _ in pairs(CONFIG.Favorites) do
        local row = Instance.new("Frame")
        row.BackgroundColor3 = THEME.panel2
        row.BorderSizePixel = 0
        row.Size = UDim2.new(1, 0, 0, 28)
        row.Parent = h
        UIHelpers.corner(row, 6)
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Position = UDim2.new(0, 8, 0, 0)
        lbl.Size = UDim2.new(1, -50, 1, 0)
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.TextColor3 = THEME.text
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = "⭐ " .. name
        lbl.Parent = row
        local rmb = Instance.new("TextButton")
        rmb.BackgroundColor3 = THEME.danger
        rmb.BorderSizePixel = 0
        rmb.AnchorPoint = Vector2.new(1, 0.5)
        rmb.Position = UDim2.new(1, -4, 0.5, 0)
        rmb.Size = UDim2.new(0, 60, 0, 22)
        rmb.Text = "Remover"
        rmb.Font = Enum.Font.Gotham
        rmb.TextSize = 11
        rmb.TextColor3 = Color3.new(1,1,1)
        rmb.AutoButtonColor = false
        rmb.Parent = row
        UIHelpers.corner(rmb, 4)
        rmb.MouseButton1Click:Connect(function()
            CONFIG.Favorites[name] = nil
            UI.refreshFavoritesList()
        end)
    end
end

function UI.refreshBlacklist()
    local h = STATE.UI.blList
    if not h then return end
    for _, c in ipairs(h:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end
    for name, _ in pairs(CONFIG.Blacklist) do
        local row = Instance.new("Frame")
        row.BackgroundColor3 = THEME.panel2
        row.BorderSizePixel = 0
        row.Size = UDim2.new(1, 0, 0, 28)
        row.Parent = h
        UIHelpers.corner(row, 6)
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Position = UDim2.new(0, 8, 0, 0)
        lbl.Size = UDim2.new(1, -50, 1, 0)
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.TextColor3 = THEME.text
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = "🚫 " .. name
        lbl.Parent = row
        local rmb = Instance.new("TextButton")
        rmb.BackgroundColor3 = THEME.accent
        rmb.BorderSizePixel = 0
        rmb.AnchorPoint = Vector2.new(1, 0.5)
        rmb.Position = UDim2.new(1, -4, 0.5, 0)
        rmb.Size = UDim2.new(0, 60, 0, 22)
        rmb.Text = "Remover"
        rmb.Font = Enum.Font.Gotham
        rmb.TextSize = 11
        rmb.TextColor3 = Color3.new(1,1,1)
        rmb.AutoButtonColor = false
        rmb.Parent = row
        UIHelpers.corner(rmb, 4)
        rmb.MouseButton1Click:Connect(function()
            CONFIG.Blacklist[name] = nil
            UI.refreshBlacklist()
        end)
    end
end

function UI.buildStatsPage()
    local p = Pages.stats
    local s = UIHelpers.makeSection(p, "📊 Estatísticas")
    STATE.UI.statsLbl = UIHelpers.makeLabel(s, "Carregando...", THEME.text, 14)
    STATE.UI.statsLbl.TextWrapped = true
    STATE.UI.statsLbl.Size = UDim2.new(1, 0, 0, 160)
    UI.refreshStats()
end

function UI.refreshStats()
    if not STATE.UI.statsLbl then return end
    local s = STATE.Stats
    local uptime = os.clock() - s.StartTime
    STATE.UI.statsLbl.Text = string.format(
        "Ovos detectados: %d\nOvos roubados: %d\nValor total: %s\nMelhor ovo: %s (%s)\nTempo: %s\nAções: %d\nFalhas: %d",
        s.EggsDetected, s.EggsStolen, Utils.formatNumber(s.ValueTotal),
        s.BestEgg, Utils.formatNumber(s.BestValue),
        Utils.formatTime(uptime), s.Actions, s.Failures
    )
end

function UI.buildSettingsPage()
    local p = Pages.settings
    local g = UIHelpers.makeSection(p, "Geral")
    UIHelpers.makeToggle(g, "Enable Script", CONFIG.Enabled, function(v) CONFIG.Enabled = v end)
    UIHelpers.makeToggle(g, "Notifications", CONFIG.Notifications, function(v) CONFIG.Notifications = v end)
    UIHelpers.makeToggle(g, "Sounds", CONFIG.Sounds, function(v) CONFIG.Sounds = v end)
    UIHelpers.makeToggle(g, "UI Animation", CONFIG.UIAnimation, function(v) CONFIG.UIAnimation = v end)
    UIHelpers.makeToggle(g, "Compact Mode", CONFIG.CompactMode, function(v) CONFIG.CompactMode = v end)
    UIHelpers.makeToggle(g, "Debug", CONFIG.Debug, function(v) CONFIG.Debug = v end)

    local perf = UIHelpers.makeSection(p, "Performance")
    UIHelpers.makeSlider(perf, "Update Rate", 0.1, 3, CONFIG.UpdateRate, function(v) CONFIG.UpdateRate = v end)
    UIHelpers.makeSlider(perf, "ESP Update Rate", 0.05, 1, CONFIG.ESPUpdateRate, function(v) CONFIG.ESPUpdateRate = v end)
    UIHelpers.makeSlider(perf, "Detection Rate", 0.25, 5, CONFIG.DetectionRate, function(v) CONFIG.DetectionRate = v end)
    UIHelpers.makeToggle(perf, "Low Performance Mode", CONFIG.LowPerformance, function(v) CONFIG.LowPerformance = v end)

    local ui = UIHelpers.makeSection(p, "UI")
    UIHelpers.makeSlider(ui, "UI Scale", 0.6, 1.6, CONFIG.UIScale, function(v)
        CONFIG.UIScale = v
        if STATE.UI.uiScale then STATE.UI.uiScale.Scale = v end
    end)
    UIHelpers.makeSlider(ui, "Animation Speed", 0.1, 1, CONFIG.AnimationSpeed, function(v) CONFIG.AnimationSpeed = v end)

    local info = UIHelpers.makeSection(p, "Sessão")
    UIHelpers.makeLabel(info, "As configurações são salvas durante a sessão.\nPara persistência permanente, é necessário um DataStore apropriado no servidor.", THEME.textDim, 12)
    local resetBtn = UIHelpers.makeButton(info, "🔄 Reset Settings", 32, THEME.danger)
    resetBtn.MouseButton1Click:Connect(function()
        Notify.push("Configurações resetadas (recomendado reexecutar o script).", THEME.danger)
    end)
end

--==================================================================
-- [SEÇÃO 11] AUTO STEAL
--==================================================================
AutoSteal = {}
local autoStealConn

function AutoSteal.start()
    if STATE.Running.AutoSteal then return end
    STATE.Running.AutoSteal = true
    STATE.Running.AutoSteal = true
    Notify.push("Auto Steal ativado", THEME.ok)
    local acc = 0
    autoStealConn = RunService.Heartbeat:Connect(function(dt)
        if not CONFIG.AutoSteal then return end
        acc = acc + dt
        if acc < CONFIG.UpdateRate then return end
        acc = 0
        Utils.safeCall(function()
            local best = Filter.pickBest(STATE.Eggs)
            if not best then return end
            local now = os.clock()
            if now - STATE.LastStealTime < 0.2 then return end
            STATE.LastStealTime = now
            AutoSteal.attempt(best)
        end)
    end)
    Utils.track(autoStealConn)
end

function AutoSteal.stop()
    STATE.Running.AutoSteal = false
    if autoStealConn then autoStealConn:Disconnect(); autoStealConn = nil end
end

function AutoSteal.attempt(egg)
    if not egg or not egg.instance or not egg.instance.Parent then return false end
    STATE.Stats.Actions = STATE.Stats.Actions + 1
    local ok = false
    -- Estratégia 1: RemoteEvent detectado
    if STATE.Remotes.steal then
        local ok1 = pcall(function()
            if STATE.Remotes.steal:IsA("RemoteEvent") then
                STATE.Remotes.steal:FireServer(egg.instance)
            elseif STATE.Remotes.steal:IsA("RemoteFunction") then
                STATE.Remotes.steal:InvokeServer(egg.instance)
            end
        end)
        ok = ok1
    end
    -- Estratégia 2: ProximityPrompt (fallback)
    if not ok then
        local prompt = egg.instance:FindFirstChildOfClass("ProximityPrompt")
            or (egg.instance:IsA("Model") and egg.instance:FindFirstChildWhichIsA("ProximityPrompt", true))
        if prompt then
            Utils.safeCall(function()
                if fireproximityprompt then
                    fireproximityprompt(prompt)
                else
                    -- fallback: usar tecla padrão caso o executor não exponha
                    prompt:InputHoldBegin()
                    task.wait(prompt.HoldDuration)
                    prompt:InputHoldEnd()
                end
            end)
            ok = true
        end
    end
    if ok then
        STATE.Stats.EggsStolen = STATE.Stats.EggsStolen + 1
        STATE.Stats.ValueTotal = STATE.Stats.ValueTotal + (egg.value or 0)
        if (egg.value or 0) > STATE.Stats.BestValue then
            STATE.Stats.BestValue = egg.value
            STATE.Stats.BestEgg = egg.name
        end
        Notify.push("Roubo tentado: " .. egg.name, THEME.ok)
    else
        STATE.Stats.Failures = STATE.Stats.Failures + 1
    end
    return ok
end

--==================================================================
-- [SEÇÃO 12] INSTANT STEAL
--==================================================================
InstantSteal = {}
local instantConn

function InstantSteal.start()
    if STATE.Running.InstantSteal then return end
    STATE.Running.InstantSteal = true
    Notify.push("Instant Steal ativado", THEME.ok)
    local lastExec = 0
    instantConn = RunService.Heartbeat:Connect(function()
        if not CONFIG.InstantSteal then return end
        local now = os.clock() * 1000
        if now - lastExec < CONFIG.InstantDelay then return end
        Utils.safeCall(function()
            local best = Filter.pickBest(STATE.Eggs)
            if best and best.instance and best.instance.Parent then
                lastExec = now
                AutoSteal.attempt(best)
            end
        end)
    end)
    Utils.track(instantConn)
end

function InstantSteal.stop()
    STATE.Running.InstantSteal = false
    if instantConn then instantConn:Disconnect(); instantConn = nil end
end

--==================================================================
-- [SEÇÃO 13] AUTO FARM
--==================================================================
AutoFarm = {}
local farmConn

function AutoFarm.start()
    if STATE.Running.AutoFarm then return end
    STATE.Running.AutoFarm = true
    Notify.push("Auto Farm ativado", THEME.ok)
    farmConn = RunService.Heartbeat:Connect(function()
        if not CONFIG.AutoFarm then return end
        Utils.safeCall(function()
            -- Auto Collect / Pickup
            if CONFIG.AutoCollect or CONFIG.AutoPickup then
                if STATE.Remotes.collect then
                    pcall(function()
                        if STATE.Remotes.collect:IsA("RemoteEvent") then
                            STATE.Remotes.collect:FireServer()
                        elseif STATE.Remotes.collect:IsA("RemoteFunction") then
                            STATE.Remotes.collect:InvokeServer()
                        end
                    end)
                end
            end
            if CONFIG.AutoClaim and STATE.Remotes.claim then
                pcall(function()
                    if STATE.Remotes.claim:IsA("RemoteEvent") then
                        STATE.Remotes.claim:FireServer()
                    elseif STATE.Remotes.claim:IsA("RemoteFunction") then
                        STATE.Remotes.claim:InvokeServer()
                    end
                end)
            end
            if CONFIG.AutoSell and STATE.Remotes.sell then
                pcall(function()
                    if STATE.Remotes.sell:IsA("RemoteEvent") then
                        STATE.Remotes.sell:FireServer()
                    elseif STATE.Remotes.sell:IsA("RemoteFunction") then
                        STATE.Remotes.sell:InvokeServer()
                    end
                end)
            end
            -- Auto Return: teleporta para um ponto inicial caso configurado
            if CONFIG.AutoReturn then
                -- [AJUSTE MANUAL] Coloque aqui o CFrame/posição de spawn caso queira.
            end
        end)
    end)
    Utils.track(farmConn)
end

function AutoFarm.stop()
    STATE.Running.AutoFarm = false
    if farmConn then farmConn:Disconnect(); farmConn = nil end
end

--==================================================================
-- [SEÇÃO 14] ESP
--==================================================================
ESP = {}
local espConn

function ESP.createBillboard(adornee, text)
    local bb = Instance.new("BillboardGui")
    bb.Name = "EggHub_ESP"
    bb.Adornee = adornee
    bb.Size = UDim2.new(0, 200, 0, 44)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Parent = PlayerGui
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 13
    lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    lbl.TextStrokeTransparency = 0.3
    lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
    lbl.Text = text
    lbl.Parent = bb
    return bb, lbl
end

function ESP.start()
    if STATE.Running.EggESP then return end
    STATE.Running.EggESP = true
    Notify.push("ESP ativado", THEME.ok)
    espConn = RunService.RenderStepped:Connect(function()
        if not CONFIG.EggESP and not CONFIG.PlayerESP then return end
        Utils.safeCall(function()
            local root = Utils.getRoot()
            local rootPos = root and root.Position or Vector3.zero
            -- Eggs
            local active = {}
            if CONFIG.EggESP then
                for _, e in ipairs(STATE.Eggs) do
                    if e.instance and e.instance.Parent then
                        active[e.instance] = true
                        local entry = STATE.ESPObjects[e.instance]
                        if not entry then
                            local adorn = e.instance:IsA("Model") and (e.instance.PrimaryPart or e.instance:FindFirstChildWhichIsA("BasePart", true)) or e.instance
                            if adorn then
                                local bb, lbl = ESP.createBillboard(adorn, e.name)
                                entry = { billboard = bb, label = lbl }
                                STATE.ESPObjects[e.instance] = entry
                            end
                        end
                        if entry and entry.label then
                            local parts = {}
                            if CONFIG.EggName then table.insert(parts, e.name) end
                            if CONFIG.EggValue then table.insert(parts, Utils.formatNumber(e.value)) end
                            if CONFIG.EggRarity then table.insert(parts, e.rarity) end
                            if CONFIG.EggDistance then table.insert(parts, string.format("%.0f", e.distance)) end
                            entry.label.Text = table.concat(parts, " | ")
                            if e.distance > CONFIG.ESPMaxDistance then
                                entry.billboard.Enabled = false
                            else
                                entry.billboard.Enabled = true
                            end
                        end
                    end
                end
            end
            -- Remover órfãos
            for inst, data in pairs(STATE.ESPObjects) do
                if not active[inst] or not inst.Parent then
                    if data.billboard then data.billboard:Destroy() end
                    if data.highlight then data.highlight:Destroy() end
                    STATE.ESPObjects[inst] = nil
                end
            end
        end)
    end)
    Utils.track(espConn)
end

function ESP.stop()
    STATE.Running.EggESP = false
    if espConn then espConn:Disconnect(); espConn = nil end
    for _, data in pairs(STATE.ESPObjects) do
        if data.billboard then data.billboard:Destroy() end
        if data.highlight then data.highlight:Destroy() end
    end
    STATE.ESPObjects = {}
end

function ESP.startPlayers()
    if STATE.Running.PlayerESP then return end
    STATE.Running.PlayerESP = true
    Notify.push("Player ESP ativado", THEME.ok)
    local conn = RunService.RenderStepped:Connect(function()
        if not CONFIG.PlayerESP then return end
        Utils.safeCall(function()
            local root = Utils.getRoot()
            local rootPos = root and root.Position or Vector3.zero
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character then
                    local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local dist = (hrp.Position - rootPos).Magnitude
                        local data = STATE.PlayerESPObjects[plr]
                        if not data then
                            local bb = Instance.new("BillboardGui")
                            bb.Size = UDim2.new(0, 180, 0, 36)
                            bb.StudsOffset = Vector3.new(0, 3, 0)
                            bb.AlwaysOnTop = true
                            bb.Parent = PlayerGui
                            local lbl = Instance.new("TextLabel")
                            lbl.BackgroundTransparency = 1
                            lbl.Size = UDim2.new(1,0,1,0)
                            lbl.Font = Enum.Font.GothamBold
                            lbl.TextSize = 13
                            lbl.TextColor3 = Color3.fromRGB(255, 220, 120)
                            lbl.TextStrokeTransparency = 0.3
                            lbl.Parent = bb
                            local hl
                            if CONFIG.PlayerHighlight then
                                hl = Instance.new("Highlight")
                                hl.FillColor = Color3.fromRGB(255, 90, 90)
                                hl.OutlineColor = Color3.new(1,1,1)
                                hl.Parent = plr.Character
                            end
                            data = { bb = bb, lbl = lbl, hl = hl }
                            STATE.PlayerESPObjects[plr] = data
                        end
                        data.bb.Adornee = hrp
                        local parts = {}
                        if CONFIG.PlayerNameTag then table.insert(parts, plr.Name) end
                        if CONFIG.PlayerDistTag then table.insert(parts, string.format("%.0f", dist)) end
                        data.lbl.Text = table.concat(parts, " | ")
                        data.bb.Enabled = dist <= CONFIG.ESPMaxDistance
                    end
                end
            end
            -- limpar
            for plr, data in pairs(STATE.PlayerESPObjects) do
                if not plr.Parent or not plr.Character then
                    if data.bb then data.bb:Destroy() end
                    if data.hl then data.hl:Destroy() end
                    STATE.PlayerESPObjects[plr] = nil
                end
            end
        end)
    end)
    Utils.track(conn)
end

function ESP.stopPlayers()
    STATE.Running.PlayerESP = false
    for plr, data in pairs(STATE.PlayerESPObjects) do
        if data.bb then data.bb:Destroy() end
        if data.hl then data.hl:Destroy() end
    end
    STATE.PlayerESPObjects = {}
end

--==================================================================
-- [SEÇÃO 15] LOOP DE DETECÇÃO (RunService — sem while true)
--==================================================================
local detectionAcc = 0
Utils.track(RunService.Heartbeat:Connect(function(dt)
    if STATE.Destroyed then return end
    detectionAcc = detectionAcc + dt
    if detectionAcc < CONFIG.DetectionRate then return end
    detectionAcc = 0
    Utils.safeCall(function()
        STATE.Eggs = Detection.scanEggs()
        if activeTab == "eggs" then UI.refreshEggList() end
        if activeTab == "home" then UI.updateHomeDebug(); UI.refreshHomeInfo() end
        UI.refreshRarityFilters()
    end)
end))

-- Atualizar estatísticas periodicamente
local statsAcc = 0
Utils.track(RunService.Heartbeat:Connect(function(dt)
    statsAcc = statsAcc + dt
    if statsAcc < 1 then return end
    statsAcc = 0
    if activeTab == "stats" then UI.refreshStats() end
    if activeTab == "home" then UI.refreshHomeInfo() end
end))

-- Detectar novos jogadores para ESP
Utils.track(Players.PlayerAdded:Connect(function(plr)
    if CONFIG.PlayerESP then
        -- o loop de ESP cuida da criação
    end
end))
Utils.track(Players.PlayerRemoving:Connect(function(plr)
    local data = STATE.PlayerESPObjects[plr]
    if data then
        if data.bb then data.bb:Destroy() end
        if data.hl then data.hl:Destroy() end
        STATE.PlayerESPObjects[plr] = nil
    end
end))

--==================================================================
-- [SEÇÃO 16] CLEANUP / DESTROY
--==================================================================
local function Cleanup()
    -- Parar todas as funções
    pcall(function() AutoSteal.stop() end)
    pcall(function() InstantSteal.stop() end)
    pcall(function() AutoFarm.stop() end)
    pcall(function() ESP.stop() end)
    pcall(function() ESP.stopPlayers() end)
    -- Desconectar eventos
    Utils.untrackAll()
    -- Limpar tabelas
    for _, data in pairs(STATE.ESPObjects) do
        if data.billboard then data.billboard:Destroy() end
        if data.highlight then data.highlight:Destroy() end
    end
    STATE.ESPObjects = {}
    for _, data in pairs(STATE.PlayerESPObjects) do
        if data.bb then data.bb:Destroy() end
        if data.hl then data.hl:Destroy() end
    end
    STATE.PlayerESPObjects = {}
    -- Notificar
    if CONFIG.Notifications then
        Notify.push("Hub limpo.", THEME.accent)
    end
end

local function Destroy()
    Cleanup()
    STATE.Destroyed = true
    if STATE.UI.gui then
        STATE.UI.gui:Destroy()
        STATE.UI.gui = nil
    end
end

-- Expor API global
_G.EggHub = {
    Config      = CONFIG,
    State       = STATE,
    Cleanup     = Cleanup,
    Destroy     = Destroy,
    Open        = function() UI.toggleWindow(true) end,
    Close       = function() UI.toggleWindow(false) end,
    Detect      = function() STATE.Eggs = Detection.scanEggs(); return STATE.Eggs end,
    Remotes     = Detection.scanRemotes,
    Notify      = Notify.push,
}

--==================================================================
-- [SEÇÃO 17] BOOT
--==================================================================
do
    UI.create()
    Detection.scanRemotes()
    STATE.Eggs = Detection.scanEggs()
    UI.updateHomeDebug()
    UI.refreshHomeInfo()
    UI.refreshEggList()
    UI.refreshRarityFilters()
    UI.refreshStats()
    Notify.push("🥚 Egg Hub carregado!", THEME.accent)
    if STATE.Remotes.steal then
        Notify.push("Remote de roubo detectado: " .. STATE.Remotes.steal.Name, THEME.ok)
    else
        Notify.push("Nenhum Remote de roubo detectado automaticamente.", THEME.danger)
    end
end
