--=====================================================================
--  AIM ASSIST + ESP (Mobile UI) - Ambiente Autorizado
--  Autor: (você)
--  Requisitos: API do seu ambiente de jogo (getPlayers, getPosition, etc.)
--  Sem dependências externas.
--=====================================================================

--=====================================================================
-- 1) CONFIGURAÇÕES PADRÃO
--=====================================================================
local Config = {
    -- Aim Assist
    AimEnabled      = false,
    FOV             = 120,      -- raio em pixels (2D)
    MaxDistance     = 500,      -- studs/unidades
    Smoothness      = 0.15,     -- 0..1 (menor = mais suave)
    TargetPart      = "Head",   -- "Head" | "Torso" | "Body"
    TeamCheck       = true,
    IgnoreDead      = true,

    -- ESP
    EspEnabled      = false,
    EspNames        = true,
    EspDistance     = true,
    EspBox          = true,
    EspLine         = true,
    EspHighlight    = true,
    EspOnlyEnemies  = false,
    EspMaxDistance  = 800,

    -- Cores
    ColorEnemy      = Color3.fromRGB(255, 60,  60),
    ColorAlly       = Color3.fromRGB(60,  200, 255),
    ColorLine       = Color3.fromRGB(255, 255, 255),
}

--=====================================================================
-- 2) REFERÊNCIAS DO AMBIENTE (ADAPTE À SUA API)
--=====================================================================
-- Estas funções devem ser substituídas pelas APIs reais do seu jogo.
local Env = {}

-- Retorna a lista de jogadores no servidor: { {name=, team=, isDead=, model=} }
function Env.GetPlayers() return {} end

-- Retorna a posição da parte do jogador (Vector3) e se é visível
function Env.GetPartPosition(player, partName) return nil end

-- Retorna a posição da câmera local
function Env.GetCameraPosition() return Vector3.zero end

-- Retorna o CFrame da câmera local
function Env.GetCameraCFrame() return CFrame.new() end

-- Retorna o viewport (largura, altura)
function Env.GetViewportSize() return 1920, 1080 end

-- Retorna a equipe do jogador local
function Env.GetLocalTeam() return nil end

-- Retorna o jogador local
function Env.GetLocalPlayer() return nil end

-- WorldToScreen: converte posição 3D em 2D na tela (x, y, onScreen)
function Env.WorldToScreen(worldPos) return 0, 0, false end

-- Move o mouse/câmera (aim). Adapte para sua API.
function Env.MoveMouse(dx, dy) end

-- Cria highlight (contorno) no modelo do jogador
function Env.CreateHighlight(model) return nil end

-- Remove highlight
function Env.RemoveHighlight(highlight) end

-- Cria desenho 2D (linha, caixa, texto). Use Drawing API ou equivalente.
function Env.CreateDrawing(kind, props) return nil end

-- Remove desenho
function Env.RemoveDrawing(drawing) end

--=====================================================================
-- 3) ESTADO INTERNO
--=====================================================================
local State = {
    CurrentTarget   = nil,       -- referência ao jogador alvo
    EspObjects      = {},        -- [player] = { box=, name=, dist=, line=, highlight= }
    LastTeam        = nil,
    Connections     = {},
    Running         = true,
    UI              = {},
}

--=====================================================================
-- 4) UTILITÁRIOS
--=====================================================================
local function isAlly(player)
    if not Config.TeamCheck then return false end
    local localTeam = Env.GetLocalTeam()
    if not localTeam then return false end
    return player.team == localTeam
end

local function isValidTarget(player)
    if not player then return false end
    if Config.IgnoreDead and player.isDead then return false end
    if isAlly(player) then return false end
    return true
end

local function getTargetPart(player)
    local partName = Config.TargetPart
    if partName == "Head" then
        return Env.GetPartPosition(player, "Head")
    elseif partName == "Torso" then
        return Env.GetPartPosition(player, "Torso")
            or Env.GetPartPosition(player, "UpperTorso")
    else -- Body
        return Env.GetPartPosition(player, "HumanoidRootPart")
    end
end

local function distance3D(a, b)
    if not a or not b then return math.huge end
    return (a - b).Magnitude
end

--=====================================================================
-- 5) AIM ASSIST
--=====================================================================
local function findBestTarget()
    local camPos   = Env.GetCameraPosition()
    local vw, vh   = Env.GetViewportSize()
    local cx, cy   = vw / 2, vh / 2

    local best, bestDist = nil, math.huge
    local players = Env.GetPlayers()

    for _, p in ipairs(players) do
        if not isValidTarget(p) then goto continue end

        local partPos = getTargetPart(p)
        if not partPos then goto continue end

        local d3 = distance3D(camPos, partPos)
        if d3 > Config.MaxDistance then goto continue end

        local sx, sy, onScreen = Env.WorldToScreen(partPos)
        if not onScreen then goto continue end

        local dx, dy = sx - cx, sy - cy
        local dist2D = math.sqrt(dx * dx + dy * dy)
        if dist2D > Config.FOV then goto continue end

        if dist2D < bestDist then
            bestDist = dist2D
            best = p
        end

        ::continue::
    end

    return best, bestDist
end

local function applyAim(target)
    if not target then return end
    local partPos = getTargetPart(target)
    if not partPos then return end

    local sx, sy, onScreen = Env.WorldToScreen(partPos)
    if not onScreen then return end

    local vw, vh = Env.GetViewportSize()
    local cx, cy = vw / 2, vh / 2

    -- delta em pixels, aplicando smoothness
    local dx = (sx - cx) * Config.Smoothness
    local dy = (sy - cy) * Config.Smoothness

    Env.MoveMouse(dx, dy)
end

local function updateAim()
    if not Config.AimEnabled then
        State.CurrentTarget = nil
        return
    end

    -- Reavalia o alvo frequentemente (atualização automática conforme movimento)
    local target = findBestTarget()
    State.CurrentTarget = target
    if target then applyAim(target) end
end

--=====================================================================
-- 6) ESP
--=====================================================================
local function ensureEspObject(player)
    if State.EspObjects[player] then return State.EspObjects[player] end

    local obj = {
        box       = Config.EspBox       and Env.CreateDrawing("Square",       {}) or nil,
        name      = Config.EspNames     and Env.CreateDrawing("Text",         {}) or nil,
        dist      = Config.EspDistance  and Env.CreateDrawing("Text",         {}) or nil,
        line      = Config.EspLine      and Env.CreateDrawing("Line",         {}) or nil,
        highlight = Config.EspHighlight and Env.CreateHighlight(player.model) or nil,
    }
    State.EspObjects[player] = obj
    return obj
end

local function removeEspObject(player)
    local obj = State.EspObjects[player]
    if not obj then return end
    if obj.box       then Env.RemoveDrawing(obj.box) end
    if obj.name      then Env.RemoveDrawing(obj.name) end
    if obj.dist      then Env.RemoveDrawing(obj.dist) end
    if obj.line      then Env.RemoveDrawing(obj.line) end
    if obj.highlight then Env.RemoveHighlight(obj.highlight) end
    State.EspObjects[player] = nil
end

local function updateEspObject(player, obj)
    local isAllyPlayer = isAlly(player)
    local color = isAllyPlayer and Config.ColorAlly or Config.ColorEnemy

    -- Verifica se deve mostrar
    local show = true
    if Config.EspOnlyEnemies and isAllyPlayer then show = false end
    if Config.IgnoreDead and player.isDead then show = false end

    local head = Env.GetPartPosition(player, "Head")
    local root = Env.GetPartPosition(player, "HumanoidRootPart") or head
    if not head or not root then show = false end

    local camPos = Env.GetCameraPosition()
    local d3 = distance3D(camPos, root)
    if d3 > Config.EspMaxDistance then show = false end

    if not show then
        if obj.box       then obj.box.Visible = false end
        if obj.name      then obj.name.Visible = false end
        if obj.dist      then obj.dist.Visible = false end
        if obj.line      then obj.line.Visible = false end
        if obj.highlight then obj.highlight.Enabled = false end
        return
    end

    local hx, hy, onH = Env.WorldToScreen(head)
    local rx, ry, onR = Env.WorldToScreen(root)
    if not onH or not onR then
        if obj.box  then obj.box.Visible = false end
        if obj.name then obj.name.Visible = false end
        if obj.dist then obj.dist.Visible = false end
        if obj.line then obj.line.Visible = false end
        return
    end

    local vw, vh = Env.GetViewportSize()
    local cx, cy = vw / 2, vh / 2

    local height = math.abs(ry - hy) * 2.2
    local width  = height * 0.55

    if obj.box then
        obj.box.Visible = true
        obj.box.Color   = color
        obj.box.Size    = Vector2.new(width, height)
        obj.box.Position = Vector2.new(rx - width / 2, ry - height / 2)
    end

    if obj.name then
        obj.name.Visible  = true
        obj.name.Color    = color
        obj.name.Text     = player.name
        obj.name.Position = Vector2.new(rx, ry - height / 2 - 16)
        obj.name.Center   = true
    end

    if obj.dist then
        obj.dist.Visible  = true
        obj.dist.Color    = color
        obj.dist.Text     = string.format("%d m", math.floor(d3))
        obj.dist.Position = Vector2.new(rx, ry + height / 2 + 4)
        obj.dist.Center   = true
    end

    if obj.line then
        obj.line.Visible = true
        obj.line.Color   = Config.ColorLine
        obj.line.From    = Vector2.new(cx, vh)
        obj.line.To      = Vector2.new(rx, ry)
    end

    if obj.highlight then
        obj.highlight.Enabled    = true
        obj.highlight.FillColor  = color
        obj.highlight.OutlineColor = color
    end
end

local function updateEsp()
    local players = Env.GetPlayers()
    local seen = {}

    for _, p in ipairs(players) do
        seen[p] = true
        if Config.EspEnabled then
            local obj = ensureEspObject(p)
            updateEspObject(p, obj)
        else
            removeEspObject(p)
        end
    end

    -- Limpeza de jogadores que saíram (evita memory leak)
    for p, _ in pairs(State.EspObjects) do
        if not seen[p] then removeEspObject(p) end
    end
end

--=====================================================================
-- 7) UI MOBILE (compacta, arrastável, com abas)
--=====================================================================
-- Adapte a criação de GUI à API do seu ambiente (ScreenGui, Frame, etc.)
-- Aqui uso uma abstração genérica: Ui.New(...)
local Ui = {}
function Ui.New(class, props) return {Class = class, Props = props or {}} end
function Ui.Destroy(obj) end
function Ui.Parent(child, parent) end
function Ui.SetProperty(obj, key, value) if obj then obj.Props[key] = value end end

local function buildUI()
    local gui = Ui.New("ScreenGui", {Name = "AssistUI"})

    -- Botão flutuante (abre/fecha)
    local toggle = Ui.New("TextButton", {
        Text = "🎯",
        Size = {60, 60},
        Position = {20, 200},
    })

    -- Painel principal
    local panel = Ui.New("Frame", {
        Size = {320, 420},
        Position = {100, 100},
        Visible = false,
    })

    -- Cabeçalho arrastável
    local header = Ui.New("TextButton", {
        Text = "⚙️ Assist",
        Size = {320, 36},
        Position = {0, 0},
    })

    -- Sistema de abas
    local tabs = {
        Aim  = Ui.New("Frame", {Size = {320, 380}, Position = {0, 36}}),
        Esp  = Ui.New("Frame", {Size = {320, 380}, Position = {0, 36}, Visible = false}),
        Cfg  = Ui.New("Frame", {Size = {320, 380}, Position = {0, 36}, Visible = false}),
    }
    local tabButtons = {
        Aim = Ui.New("TextButton", {Text = "Aim", Size = {100, 30}, Position = {0, 36}}),
        Esp = Ui.New("TextButton", {Text = "ESP", Size = {100, 30}, Position = {105, 36}}),
        Cfg = Ui.New("TextButton", {Text = "Cfg", Size = {100, 30}, Position = {210, 36}}),
    }

    local function selectTab(name)
        for k, f in pairs(tabs) do Ui.SetProperty(f, "Visible", k == name) end
    end

    -- Helper: switch ON/OFF
    local function makeSwitch(parent, label, key, onChange)
        local btn = Ui.New("TextButton", {
            Text = label .. ": " .. (Config[key] and "ON" or "OFF"),
            Size = {280, 30},
            Position = {10, 10},
        })
        btn.Props.OnClick = function()
            Config[key] = not Config[key]
            Ui.SetProperty(btn, "Text", label .. ": " .. (Config[key] and "ON" or "OFF"))
            if onChange then onChange() end
        end
        Ui.Parent(btn, parent)
        return btn
    end

    -- Helper: slider
    local function makeSlider(parent, label, key, minV, maxV, step, y)
        local lbl = Ui.New("Text", {Text = label .. ": " .. tostring(Config[key]),
                                    Size = {280, 20}, Position = {10, y}})
        local sld = Ui.New("Frame", {Size = {280, 20}, Position = {10, y + 20}})
        local knob = Ui.New("TextButton", {
            Text = "", Size = {20, 20}, Position = {0, 0},
        })
        sld.Props.OnInput = function(x)
            local ratio = math.clamp(x / 280, 0, 1)
            local val   = minV + (maxV - minV) * ratio
            val = math.floor(val / step + 0.5) * step
            Config[key] = val
            Ui.SetProperty(lbl, "Text", label .. ": " .. tostring(val))
            Ui.SetProperty(knob, "Position", {ratio * 260, 0})
        end
        Ui.Parent(lbl, parent); Ui.Parent(sld, parent); Ui.Parent(knob, sld)
        return lbl, sld
    end

    -- Helper: dropdown
    local function makeDropdown(parent, label, key, options, y)
        local lbl = Ui.New("Text", {Text = label .. ": " .. tostring(Config[key]),
                                    Size = {280, 20}, Position = {10, y}})
        local idx = 1
        for i, v in ipairs(options) do if v == Config[key] then idx = i end end
        local btn = Ui.New("TextButton", {
            Text = tostring(Config[key]), Size = {280, 30}, Position = {10, y + 20},
        })
        btn.Props.OnClick = function()
            idx = idx % #options + 1
            Config[key] = options[idx]
            Ui.SetProperty(btn, "Text", options[idx])
            Ui.SetProperty(lbl, "Text", label .. ": " .. options[idx])
        end
        Ui.Parent(lbl, parent); Ui.Parent(btn, parent)
        return btn
    end

    -- Aba AIM
    local y = 10
    makeSwitch(tabs.Aim, "Aim Assist", "AimEnabled", nil)
    y = y + 40
    makeSlider(tabs.Aim, "FOV", "FOV", 20, 500, 5, y) y = y + 50
    makeSlider(tabs.Aim, "Distância", "MaxDistance", 10, 2000, 10, y) y = y + 50
    makeSlider(tabs.Aim, "Smoothness", "Smoothness", 0.02, 1.0, 0.01, y) y = y + 50
    makeDropdown(tabs.Aim, "Parte do Corpo", "TargetPart",
                 {"Head", "Torso", "Body"}, y) y = y + 60
    makeSwitch(tabs.Aim, "Team Check", "TeamCheck", nil) y = y + 40
    makeSwitch(tabs.Aim, "Ignorar Mortos", "IgnoreDead", nil)

    -- Aba ESP
    y = 10
    makeSwitch(tabs.Esp, "ESP", "EspEnabled", nil) y = y + 40
    makeSwitch(tabs.Esp, "Nome", "EspNames", nil) y = y + 40
    makeSwitch(tabs.Esp, "Distância", "EspDistance", nil) y = y + 40
    makeSwitch(tabs.Esp, "Caixa", "EspBox", nil) y = y + 40
    makeSwitch(tabs.Esp, "Linha", "EspLine", nil) y = y + 40
    makeSwitch(tabs.Esp, "Highlight", "EspHighlight", nil) y = y + 40
    makeSwitch(tabs.Esp, "Somente Inimigos", "EspOnlyEnemies", nil) y = y + 40
    makeSlider(tabs.Esp, "Dist. Máx ESP", "EspMaxDistance", 50, 3000, 50, y)

    -- Aba Cfg
    local panic = Ui.New("TextButton", {
        Text = "🛑 DESATIVAR TUDO", Size = {280, 40}, Position = {10, 10},
    })
    panic.Props.OnClick = function()
        Config.AimEnabled = false
        Config.EspEnabled = false
        -- limpa ESP
        for p, _ in pairs(State.EspObjects) do removeEspObject(p) end
    end
    Ui.Parent(panic, tabs.Cfg)

    -- Botão flutuante e header
    toggle.Props.OnClick = function()
        panel.Props.Visible = not panel.Props.Visible
    end
    header.Props.OnDrag = function(dx, dy)
        local px, py = panel.Props.Position[1], panel.Props.Position[2]
        panel.Props.Position = {px + dx, py + dy}
    end

    -- Estrutura final
    Ui.Parent(header, panel)
    Ui.Parent(tabButtons.Aim, panel)
    Ui.Parent(tabButtons.Esp, panel)
    Ui.Parent(tabButtons.Cfg, panel)
    for _, f in pairs(tabs) do Ui.Parent(f, panel) end
    Ui.Parent(panel, gui)
    Ui.Parent(toggle, gui)

    State.UI = {gui = gui, panel = panel, toggle = toggle, tabs = tabs}
end

--=====================================================================
-- 8) LOOP PRINCIPAL (otimizado: 60 FPS aproximado, sem loop duplo)
--=====================================================================
local ACC = 0
local AIM_INTERVAL = 0.02   -- 50 Hz para mira
local ESP_INTERVAL = 0.05   -- 20 Hz para ESP (mais leve em mobile)

-- Adapte "RunService.Heartbeat" à API do seu ambiente
local function onHeartbeat(dt)
    if not State.Running then return end

    ACC = ACC + dt
    if ACC >= AIM_INTERVAL then
        updateAim()
        ACC = 0
    end

    State.EspAcc = (State.EspAcc or 0) + dt
    if State.EspAcc >= ESP_INTERVAL then
        updateEsp()
        State.EspAcc = 0
    end
end

-- Conecte ao evento de frame do seu ambiente:
-- Env.Connect("Heartbeat", onHeartbeat)
-- Guarde a conexão para limpar depois:
table.insert(State.Connections, onHeartbeat)

-- Atualiza team check automaticamente se a equipe local mudar
-- Env.Connect("LocalTeamChanged", function() State.LastTeam = Env.GetLocalTeam() end)

--=====================================================================
-- 9) LIMPEZA / SHUTDOWN
--=====================================================================
local function shutdown()
    State.Running = false
    for p, _ in pairs(State.EspObjects) do removeEspObject(p) end
    State.EspObjects = {}
    if State.UI.gui then Ui.Destroy(State.UI.gui) end
    for _, c in ipairs(State.Connections) do
        -- Env.Disconnect(c) -- adapte
    end
    State.Connections = {}
end

--=====================================================================
-- 10) INICIALIZAÇÃO
--=====================================================================
buildUI()

-- Expor API pública (opcional)
_G.Assist = {
    Config     = Config,
    Shutdown   = shutdown,
    SetTarget  = function(p) State.CurrentTarget = p end,
}

return _G.Assist
