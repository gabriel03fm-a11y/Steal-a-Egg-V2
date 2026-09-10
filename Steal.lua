-- Egg Stealer V2 Script
-- Lennon Hub V2
-- Compatível com Delta Executor e outros executores populares

-- Serviços
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

-- Jogador
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local head = character:WaitForChild("Head")

-- Variáveis
local autoStealEnabled = false
local rareEggs = {}
local stolenEggs = {}
local rareEggValue = 5000000 -- 5 milhões
local guiEnabled = true
local dragging = false
local dragStart = nil
local startPos = nil
local eggESP = {}

-- Função para criar GUI
local function createGUI()
    -- Criar ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EggStealerV2"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = CoreGui
    
    -- Frame principal
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 350, 0, 450)
    mainFrame.Position = UDim2.new(0.7, 0, 0.2, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    
    -- Barra de título
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 40)
    titleBar.Position = UDim2.new(0, 0, 0, 0)
    titleBar.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame
    
    -- Título
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "TitleLabel"
    titleLabel.Size = UDim2.new(0.8, 0, 1, 0)
    titleLabel.Position = UDim2.new(0.1, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "Egg Stealer V2"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextScaled = true
    titleLabel.Font = Enum.Font.SourceSansBold
    titleLabel.Parent = titleBar
    
    -- Botão de minimizar
    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Name = "MinimizeBtn"
    minimizeBtn.Size = UDim2.new(0, 30, 0, 30)
    minimizeBtn.Position = UDim2.new(0.8, 0, 0, 5)
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
    minimizeBtn.BorderSizePixel = 0
    minimizeBtn.Text = "_"
    minimizeBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
    minimizeBtn.TextScaled = true
    minimizeBtn.Font = Enum.Font.SourceSansBold
    minimizeBtn.Parent = titleBar
    
    -- Botão de fechar
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseBtn"
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(0.9, 0, 0, 5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextScaled = true
    closeBtn.Font = Enum.Font.SourceSansBold
    closeBtn.Parent = titleBar
    
    -- Frame de conteúdo
    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "ContentFrame"
    contentFrame.Size = UDim2.new(1, 0, 1, -40)
    contentFrame.Position = UDim2.new(0, 0, 0, 40)
    contentFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    contentFrame.BorderSizePixel = 0
    contentFrame.Parent = mainFrame
    
    -- Toggle de Auto Steal
    local autoStealFrame = Instance.new("Frame")
    autoStealFrame.Name = "AutoStealFrame"
    autoStealFrame.Size = UDim2.new(0.9, 0, 0, 50)
    autoStealFrame.Position = UDim2.new(0.05, 0, 0.05, 0)
    autoStealFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    autoStealFrame.BorderSizePixel = 0
    autoStealFrame.Parent = contentFrame
    
    local autoStealLabel = Instance.new("TextLabel")
    autoStealLabel.Name = "AutoStealLabel"
    autoStealLabel.Size = UDim2.new(0.6, 0, 1, 0)
    autoStealLabel.Position = UDim2.new(0, 0, 0, 0)
    autoStealLabel.BackgroundTransparency = 1
    autoStealLabel.Text = "Auto Steal Egg"
    autoStealLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    autoStealLabel.TextScaled = true
    autoStealLabel.Font = Enum.Font.SourceSans
    autoStealLabel.TextXAlignment = Enum.TextXAlignment.Left
    autoStealLabel.Parent = autoStealFrame
    
    local autoStealToggle = Instance.new("TextButton")
    autoStealToggle.Name = "AutoStealToggle"
    autoStealToggle.Size = UDim2.new(0, 60, 0, 30)
    autoStealToggle.Position = UDim2.new(0.7, 0, 0, 10)
    autoStealToggle.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    autoStealToggle.BorderSizePixel = 0
    autoStealToggle.Text = "OFF"
    autoStealToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    autoStealToggle.TextScaled = true
    autoStealToggle.Font = Enum.Font.SourceSansBold
    autoStealToggle.Parent = autoStealFrame
    
    -- Tracker de Ovos Raros
    local trackerFrame = Instance.new("Frame")
    trackerFrame.Name = "TrackerFrame"
    trackerFrame.Size = UDim2.new(0.9, 0, 0.7, 0)
    trackerFrame.Position = UDim2.new(0.05, 0, 0.15, 0)
    trackerFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    trackerFrame.BorderSizePixel = 0
    trackerFrame.Parent = contentFrame
    
    local trackerLabel = Instance.new("TextLabel")
    trackerLabel.Name = "TrackerLabel"
    trackerLabel.Size = UDim2.new(1, 0, 0, 30)
    trackerLabel.Position = UDim2.new(0, 0, 0, 0)
    trackerLabel.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    trackerLabel.BorderSizePixel = 0
    trackerLabel.Text = "Rare Eggs Tracker"
    trackerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    trackerLabel.TextScaled = true
    trackerLabel.Font = Enum.Font.SourceSansBold
    trackerLabel.Parent = trackerFrame
    
    local eggsList = Instance.new("ScrollingFrame")
    eggsList.Name = "EggsList"
    eggsList.Size = UDim2.new(1, 0, 1, -30)
    eggsList.Position = UDim2.new(0, 0, 0, 30)
    eggsList.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    eggsList.BorderSizePixel = 0
    eggsList.ScrollBarThickness = 10
    eggsList.Parent = trackerFrame
    
    -- Botão flutuante (quando GUI minimizada)
    local floatingBtn = Instance.new("TextButton")
    floatingBtn.Name = "FloatingBtn"
    floatingBtn.Size = UDim2.new(0, 60, 0, 60)
    floatingBtn.Position = UDim2.new(0.9, 0, 0.1, 0)
    floatingBtn.BackgroundColor3 = Color3.fromRGB(255, 150, 0)
    floatingBtn.BorderSizePixel = 0
    floatingBtn.Text = "ES"
    floatingBtn.TextColor3 = Color
