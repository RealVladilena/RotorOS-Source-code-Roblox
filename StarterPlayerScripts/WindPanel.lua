-- ============================================================
-- INTERFACE MÉTÉO SCADA — LocalScript 
-- ============================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player    = Players.LocalPlayer
local windEvent = ReplicatedStorage:WaitForChild("WindControlEvent")

local matModel = workspace:WaitForChild("Mat de mesure")
local prompt   = matModel:FindFirstChild("WindPrompt", true)
if not prompt then
	task.wait(2)
	prompt = matModel:FindFirstChild("WindPrompt", true)
end

local Colors = {
	Background = Color3.fromRGB(26,  28,  41),
	Accent     = Color3.fromRGB(74,  193, 193),
	DarkPurple = Color3.fromRGB(58,  40,  92),
	Text       = Color3.fromRGB(255, 255, 255),
	MutedText  = Color3.fromRGB(160, 170, 190),
}

-- ── UI ──────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name          = "WindControlGUI"
screenGui.ResetOnSpawn  = false
screenGui.Parent        = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size             = UDim2.new(0, 320, 0, 300)
mainFrame.AnchorPoint      = Vector2.new(0.5, 0.5)
mainFrame.Position         = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.BackgroundColor3 = Colors.Background
mainFrame.Visible          = false
mainFrame.Parent           = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)
local uiStroke = Instance.new("UIStroke", mainFrame)
uiStroke.Color = Colors.Accent; uiStroke.Thickness = 2

-- Libère la souris (PC/Console)
local mouseUnlocker = Instance.new("TextButton")
mouseUnlocker.Size = UDim2.new(0,0,0,0); mouseUnlocker.Text = ""
mouseUnlocker.Modal = true; mouseUnlocker.Parent = mainFrame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,0,0,60); title.BackgroundTransparency = 1
title.Text = "💨 STATION MÉTÉO"; title.TextColor3 = Colors.Accent
title.Font = Enum.Font.GothamBold; title.TextSize = 22; title.Parent = mainFrame

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0,40,0,40); closeBtn.Position = UDim2.new(1,-50,0,10)
closeBtn.Text = "X"; closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 18
closeBtn.BackgroundColor3 = Colors.DarkPurple; closeBtn.TextColor3 = Colors.Accent
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1,0); closeBtn.Parent = mainFrame

local modeBtn = Instance.new("TextButton")
modeBtn.Size = UDim2.new(0.85,0,0,45); modeBtn.Position = UDim2.new(0.075,0,0,70)
modeBtn.Font = Enum.Font.GothamBold; modeBtn.TextSize = 16
Instance.new("UICorner", modeBtn).CornerRadius = UDim.new(0,8); modeBtn.Parent = mainFrame

local function createInputRow(yPos, labelText, defaultVal)
	local label = Instance.new("TextLabel", mainFrame)
	label.Size = UDim2.new(0.4,0,0,40); label.Position = UDim2.new(0.075,0,0,yPos)
	label.BackgroundTransparency = 1; label.Text = labelText
	label.TextColor3 = Colors.Text; label.Font = Enum.Font.GothamSemibold
	label.TextXAlignment = Enum.TextXAlignment.Left; label.TextSize = 16

	local input = Instance.new("TextBox", mainFrame)
	input.Size = UDim2.new(0.4,0,0,40); input.Position = UDim2.new(0.525,0,0,yPos)
	input.BackgroundColor3 = Colors.DarkPurple; input.TextColor3 = Colors.Text
	input.Text = defaultVal; input.Font = Enum.Font.Gotham; input.TextSize = 16
	input.ClearTextOnFocus = false
	Instance.new("UICorner", input).CornerRadius = UDim.new(0,6)
	return input
end

local speedInput = createInputRow(130, "Vitesse (m/s):", "8.0")
local angleInput = createInputRow(180, "Direction (°):", "0")

local applyBtn = Instance.new("TextButton")
applyBtn.Size = UDim2.new(0.85,0,0,45); applyBtn.Position = UDim2.new(0.075,0,0,240)
applyBtn.Text = "APPLIQUER (MANUEL)"; applyBtn.Font = Enum.Font.GothamBold; applyBtn.TextSize = 16
Instance.new("UICorner", applyBtn).CornerRadius = UDim.new(0,8); applyBtn.Parent = mainFrame

local isManual = false

local function updateUI()
	if isManual then
		modeBtn.Text = "MODE : MANUEL"
		modeBtn.BackgroundColor3 = Colors.DarkPurple; modeBtn.TextColor3 = Colors.Text
		applyBtn.BackgroundColor3 = Colors.Accent; applyBtn.TextColor3 = Colors.Background
		applyBtn.AutoButtonColor = true
		speedInput.Interactable = true; angleInput.Interactable = true
	else
		modeBtn.Text = "MODE : AUTOMATIQUE"
		modeBtn.BackgroundColor3 = Colors.Accent; modeBtn.TextColor3 = Colors.Background
		applyBtn.BackgroundColor3 = Colors.Background; applyBtn.TextColor3 = Colors.MutedText
		applyBtn.AutoButtonColor = false
		speedInput.Interactable = false; angleInput.Interactable = false
	end
end

-- Affichage en temps réel — throttlé à 10 Hz (inutile à 60 Hz pour un affichage texte)
local DISPLAY_TICK = 0.1
local displayAccum = 0

RunService.RenderStepped:Connect(function(dt)
	if isManual or not mainFrame.Visible then return end
	displayAccum += dt
	if displayAccum < DISPLAY_TICK then return end
	displayAccum -= DISPLAY_TICK

	local wind  = workspace.GlobalWind
	local speed = wind.Magnitude
	local angle = math.deg(math.atan2(wind.X, wind.Z)) % 360

	speedInput.Text = string.format("%.1f", speed)
	angleInput.Text = string.format("%d",   math.floor(angle))
end)

-- ── ÉVÉNEMENTS ──────────────────────────────────────────────
if prompt then
	prompt.Triggered:Connect(function(who)
		if who == player then mainFrame.Visible = true end
	end)
end

closeBtn.MouseButton1Click:Connect(function() mainFrame.Visible = false end)

modeBtn.MouseButton1Click:Connect(function()
	isManual = not isManual
	windEvent:FireServer("SetMode", isManual)
	updateUI()
end)

applyBtn.MouseButton1Click:Connect(function()
	if not isManual then return end
	local s = tonumber(speedInput.Text)
	local a = tonumber(angleInput.Text)
	if s and a then windEvent:FireServer("SetWind", s, a) end
end)

updateUI()