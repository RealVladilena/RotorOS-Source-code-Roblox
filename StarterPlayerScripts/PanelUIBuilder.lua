-- ============================================================
-- UI BUILDER — RotorOS REMOTE 4 
-- ============================================================
local Players                = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local RunService             = game:GetService("RunService")
local UserInputService       = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local event     = ReplicatedStorage:WaitForChild("TurbineControlEvent")

local turbinesList    = {}
local activeTargetIndex = 0

local P = {
	BgMain      = Color3.fromHex("#F4F6F8"),
	BgLeft      = Color3.fromHex("#1E222A"),
	BgTop       = Color3.fromHex("#181B21"),
	TopText     = Color3.fromHex("#FFFFFF"),
	TreeTxt     = Color3.fromHex("#A0AAB5"),
	RowEven     = Color3.fromHex("#FFFFFF"),
	RowOdd      = Color3.fromHex("#F8F9FB"),
	CellTxt     = Color3.fromHex("#333333"),
	GridLine    = Color3.fromHex("#E2E6EA"),
	StatusGreen = Color3.fromHex("#2ECC71"),
	StatusGray  = Color3.fromHex("#95A5A6"),
	StatusRed   = Color3.fromHex("#E74C3C"),
	StatusYel   = Color3.fromHex("#F1C40F"),
	BarPower    = Color3.fromHex("#E3000F"),
	BarWind     = Color3.fromHex("#3498DB"),
	BarRpm      = Color3.fromHex("#F1C40F"),
	BoxBg       = Color3.fromHex("#FFFFFF"),
	BoxBorder   = Color3.fromHex("#D1D8E0"),
	BtnBase     = Color3.fromHex("#ECF0F1"),
	BtnStop     = Color3.fromHex("#FFD9D9"),
	BtnStart    = Color3.fromHex("#D9FFDF"),
	BtnIdle     = Color3.fromHex("#FFF4CC"),
	BtnText     = Color3.fromHex("#2C3E50"),
}

local FontMain = Enum.Font.Gotham
local FontBold = Enum.Font.GothamBold

local function Make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local function AddCorner(parent, radius)
	return Make("UICorner", {CornerRadius = UDim.new(0, radius)}, parent)
end

local function MakeLabel(parent, text, pos, size, align, color, font)
	return Make("TextLabel", {
		Parent = parent, Position = pos, Size = size, Text = text,
		Font = font or FontMain, TextSize = 13, TextColor3 = color or P.CellTxt,
		TextXAlignment = align or Enum.TextXAlignment.Left,
		BackgroundTransparency = 1, TextScaled = false,
	})
end

local function MakeModernBtn(parent, text, pos, size, bgColor)
	local btn = Make("TextButton", {
		Parent = parent, Position = pos, Size = size, Text = text,
		Font = FontBold, TextSize = 12, TextColor3 = P.BtnText,
		BackgroundColor3 = bgColor or P.BtnBase, AutoButtonColor = true, BorderSizePixel = 0,
	})
	AddCorner(btn, 6)
	return btn
end

local function getTurbineInfo(turbineRoot)
	local topModel  = turbineRoot
	local parkFolder = "Wind energy converter"
	local current   = turbineRoot
	while current and current.Parent and current.Parent ~= workspace do
		current = current.Parent
		if current:IsA("Model")  then topModel   = current end
		if current:IsA("Folder") then parkFolder = current.Name end
	end
	return topModel.Name:gsub(" %(start new%)", ""), parkFolder
end

-- ── FENÊTRE PRINCIPALE ──────────────────────────────────────
local gui = Make("ScreenGui", {Name="RotorOS - PRTS Vision Scada", ResetOnSpawn=false, Enabled=false}, playerGui)

local mainFrame = Make("Frame", {
	Size=UDim2.new(0.85,0,0.85,0), Position=UDim2.new(0.075,0,0.075,0),
	BackgroundColor3=P.BgMain, BorderSizePixel=0,
}, gui)
AddCorner(mainFrame, 10)
Make("UISizeConstraint", {Parent=mainFrame, MaxSize=Vector2.new(1200,800), MinSize=Vector2.new(800,500)})

local topBar = Make("Frame", {Parent=mainFrame, Size=UDim2.new(1,0,0,40), BackgroundColor3=P.BgTop})
AddCorner(topBar, 10)
Make("Frame", {Parent=topBar, Size=UDim2.new(1,0,0,10), Position=UDim2.new(0,0,1,-10), BackgroundColor3=P.BgTop, BorderSizePixel=0})
MakeLabel(topBar, "  ⚡ RotorOS - PRTS Vision SCADA System", UDim2.new(0,15,0,0), UDim2.new(1,-50,1,0), Enum.TextXAlignment.Left, P.TopText, FontBold)

local closeBtn = Make("TextButton", {
	Parent=topBar, Position=UDim2.new(1,-40,0,8), Size=UDim2.new(0,24,0,24),
	Text="X", BackgroundColor3=P.StatusRed, TextColor3=Color3.new(1,1,1), Font=FontBold, TextSize=14,
})
AddCorner(closeBtn, 12)

local leftPanel = Make("Frame", {Parent=mainFrame, Position=UDim2.new(0,0,0,40), Size=UDim2.new(0.22,0,1,-40), BackgroundColor3=P.BgLeft, BorderSizePixel=0})
Make("Frame", {Parent=leftPanel, Size=UDim2.new(1,0,0,10), BackgroundColor3=P.BgLeft, BorderSizePixel=0})
AddCorner(leftPanel, 10)
Make("Frame", {Parent=leftPanel, Size=UDim2.new(0,10,1,0), Position=UDim2.new(1,-10,0,0), BackgroundColor3=P.BgLeft, BorderSizePixel=0})

local treeScroll = Make("ScrollingFrame", {
	Parent=leftPanel, Size=UDim2.new(1,0,1,-10), Position=UDim2.new(0,0,0,10),
	BackgroundTransparency=1, ScrollBarThickness=4,
	CanvasSize=UDim2.new(0,0,0,0), AutomaticCanvasSize=Enum.AutomaticSize.Y,
})
Make("UIListLayout", {Parent=treeScroll, SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,2)})

local rightPanel  = Make("Frame", {Parent=mainFrame, Position=UDim2.new(0.22,0,0,40), Size=UDim2.new(0.78,0,1,-40), BackgroundTransparency=1})
local tableHeader = Make("Frame", {Parent=rightPanel, Size=UDim2.new(1,0,0,40), BackgroundColor3=P.RowEven, BorderSizePixel=0})
Make("Frame", {Parent=tableHeader, Size=UDim2.new(1,0,0,1), Position=UDim2.new(0,0,1,-1), BackgroundColor3=P.GridLine, BorderSizePixel=0})

local COLS = {
	{lbl="SCADA ID",   w=0.10},
	{lbl="Alias / Name",w=0.20},
	{lbl="Status",     w=0.10},
	{lbl="Power (kW)", w=0.20},
	{lbl="Wind (m/s)", w=0.20},
	{lbl="RPM",        w=0.20},
}
local xPos = 0
for _, c in ipairs(COLS) do
	MakeLabel(tableHeader, c.lbl, UDim2.new(xPos,15,0,0), UDim2.new(c.w,-15,1,0), Enum.TextXAlignment.Left, Color3.fromHex("#7F8C8D"), FontBold)
	xPos += c.w
end

local tableScroll = Make("ScrollingFrame", {
	Parent=rightPanel, Position=UDim2.new(0,0,0,40), Size=UDim2.new(1,0,1,-95),
	BackgroundTransparency=1, BorderSizePixel=0, ScrollBarThickness=6,
	CanvasSize=UDim2.new(0,0,0,0), AutomaticCanvasSize=Enum.AutomaticSize.Y,
})

local bottomBar = Make("Frame", {Parent=rightPanel, Position=UDim2.new(0,-10,1,-55), Size=UDim2.new(1,10,0,55), BackgroundColor3=P.BgLeft, BorderSizePixel=0})
AddCorner(bottomBar, 10)
Make("Frame", {Parent=bottomBar, Size=UDim2.new(1,0,0,10), BackgroundColor3=P.BgLeft, BorderSizePixel=0})
Make("Frame", {Parent=bottomBar, Size=UDim2.new(0,10,1,0), BackgroundColor3=P.BgLeft, BorderSizePixel=0})

local bStartAll = MakeModernBtn(bottomBar,"▶ START ALL",UDim2.new(0,30,0,12), UDim2.new(0,110,0,30), P.BtnStart)
bStartAll.TextColor3 = P.StatusGreen
local bIdleAll  = MakeModernBtn(bottomBar,"⏸ IDLE (60°)",UDim2.new(0,150,0,12),UDim2.new(0,110,0,30), P.BtnIdle)
bIdleAll.TextColor3 = Color3.fromHex("#D35400")
local bStopAll  = MakeModernBtn(bottomBar,"⏹ STOP (90°)",UDim2.new(0,270,0,12),UDim2.new(0,110,0,30), P.BtnStop)
bStopAll.TextColor3 = P.StatusRed

local globalPwrLabel = MakeLabel(bottomBar,"⚡ TOTAL: 0 kW",UDim2.new(1,-220,0,12),UDim2.new(0,200,0,30),Enum.TextXAlignment.Right,Color3.fromHex("#F1C40F"),FontBold)
globalPwrLabel.TextSize = 15

-- ── POPUP DÉTAIL ────────────────────────────────────────────
local detailBg  = Make("Frame", {Parent=gui, Size=UDim2.new(1,0,1,0), BackgroundColor3=Color3.new(0,0,0), BackgroundTransparency=0.5, Visible=false})
local detailWin = Make("Frame", {Parent=detailBg, Size=UDim2.new(0.5,0,0.7,0), Position=UDim2.new(0.25,0,0.15,0), BackgroundColor3=P.BoxBg, BorderSizePixel=0})
AddCorner(detailWin, 12)
Make("UIStroke", {Parent=detailWin, Color=P.GridLine, Thickness=1})

local dTopBar  = Make("Frame", {Parent=detailWin, Size=UDim2.new(1,0,0,50), BackgroundTransparency=1})
local dTitleLbl = MakeLabel(dTopBar,"Turbine: E-112 EP8",UDim2.new(0,20,0,0),UDim2.new(1,-60,1,0),Enum.TextXAlignment.Left,P.CellTxt,FontBold)
dTitleLbl.TextSize = 16
Make("Frame", {Parent=dTopBar, Size=UDim2.new(1,-40,0,1), Position=UDim2.new(0,20,1,0), BackgroundColor3=P.GridLine, BorderSizePixel=0})

local dCloseBtn = Make("TextButton", {
	Parent=dTopBar, Position=UDim2.new(1,-40,0,13), Size=UDim2.new(0,24,0,24),
	Text="X", BackgroundColor3=P.BgMain, TextColor3=P.CellTxt, Font=FontBold, TextSize=12, BorderSizePixel=0,
})
AddCorner(dCloseBtn, 12)

local dContent = Make("Frame", {Parent=detailWin, Position=UDim2.new(0,0,0,50), Size=UDim2.new(1,0,1,-50), BackgroundTransparency=1, ClipsDescendants=false})

-- Mini-modèle éolienne
local tModel = Make("Frame", {Parent=dContent, Position=UDim2.new(0,40,0,40), Size=UDim2.new(0,100,0,180), BackgroundTransparency=1})
Make("Frame", {Parent=tModel, Position=UDim2.new(0.5,-2,0.2,0),   Size=UDim2.new(0,4,0.8,0), BackgroundColor3=Color3.fromHex("#D1D8E0"), BorderSizePixel=0})
Make("Frame", {Parent=tModel, Position=UDim2.new(0.5,-12,0.2,-6), Size=UDim2.new(0,24,0,12), BackgroundColor3=Color3.fromHex("#A5B1C2"), BorderSizePixel=0})
local hub = Make("Frame", {Parent=tModel, Position=UDim2.new(0.5,0,0.2,0), Size=UDim2.new(0,0,0,0), BackgroundTransparency=1})
for _, rot in ipairs({0, 120, -120}) do
	local bb = Make("Frame", {Parent=hub, Position=UDim2.new(0,0,0,0), Size=UDim2.new(0,0,0,0), Rotation=rot, BackgroundTransparency=1})
	Make("Frame", {Parent=bb, Position=UDim2.new(0,-2,0,-55), Size=UDim2.new(0,4,0,55), BackgroundColor3=Color3.fromHex("#7A8288"), BorderSizePixel=0})
end

local dStatusLbl = MakeLabel(dContent,"● Operational",UDim2.new(0,180,0,10),UDim2.new(0,250,0,20),Enum.TextXAlignment.Left,P.StatusGreen,FontBold)

local function MakeDetailBoxRow(y, lblText, unitText)
	MakeLabel(dContent, lblText, UDim2.new(0,180,0,y), UDim2.new(0,150,0,26), Enum.TextXAlignment.Left, P.CellTxt)
	local box = Make("Frame", {Parent=dContent, Position=UDim2.new(0,340,0,y), Size=UDim2.new(0,80,0,26), BackgroundColor3=P.RowOdd, BorderSizePixel=0})
	AddCorner(box, 4); Make("UIStroke", {Parent=box, Color=P.GridLine, Thickness=1})
	local valLbl = MakeLabel(box,"0.0",UDim2.new(0,0,0,0),UDim2.new(1,-8,1,0),Enum.TextXAlignment.Right,P.CellTxt,FontBold)
	MakeLabel(dContent, unitText, UDim2.new(0,430,0,y), UDim2.new(0,40,0,26), Enum.TextXAlignment.Left, Color3.fromHex("#7F8C8D"))
	return valLbl
end

local dWindVal  = MakeDetailBoxRow(45,  "Wind speed",   "m/s")
local dRpmVal   = MakeDetailBoxRow(75,  "Rotor speed",  "rpm")
local dPowerVal = MakeDetailBoxRow(105, "Active Power",  "kW")
local dPitch1   = MakeDetailBoxRow(145, "Pitch Blade 1", "°")
local dPitch2   = MakeDetailBoxRow(175, "Pitch Blade 2", "°")
local dPitch3   = MakeDetailBoxRow(205, "Pitch Blade 3", "°")

Make("Frame", {Parent=dContent, Position=UDim2.new(0,20,0,250), Size=UDim2.new(1,-40,0,1), BackgroundColor3=P.GridLine, BorderSizePixel=0})

local currentTarget = 1
local targetModes   = {"ALL","Blade 1","Blade 2","Blade 3"}
local pTargetBtn    = MakeModernBtn(dContent,"Target: ALL",  UDim2.new(0,20,0,270), UDim2.new(0,120,0,32))
local pInputBox     = Make("TextBox", {
	Parent=dContent, Position=UDim2.new(0,150,0,270), Size=UDim2.new(0,60,0,32),
	Text="", PlaceholderText="°", BackgroundColor3=P.RowOdd,
	Font=FontBold, TextSize=13, TextColor3=P.CellTxt, BorderSizePixel=0,
})
AddCorner(pInputBox, 6); Make("UIStroke", {Parent=pInputBox, Color=P.GridLine, Thickness=1})
local pForceBtn  = MakeModernBtn(dContent,"Force Pitch", UDim2.new(0,220,0,270), UDim2.new(0,100,0,32))
local pResetBtn  = MakeModernBtn(dContent,"Reset Auto",  UDim2.new(0,330,0,270), UDim2.new(0,100,0,32))
local togglePwrBtn = MakeModernBtn(dContent,"Stop Turbine", UDim2.new(0,20,1,-60), UDim2.new(1,-40,0,40), P.BtnStop)

-- ── LOGIQUE ─────────────────────────────────────────────────
local rowFrames  = {}
local treeFrames = {}
local parkLabels = {}

-- Cache des références pitch par turbine (évite FindFirstChild répété à 60 fps)
-- pitchCache[turbineObj] = {b1, b2, b3}
local pitchCache = {}

local function MakeBar(parent, color, maxVal)
	Make("Frame", {Parent=parent, Position=UDim2.new(0,0,0.5,-4), Size=UDim2.new(0,8,0,8), BackgroundColor3=color, BorderSizePixel=0})
		:FindFirstChildWhichIsA("UICorner") or Make("UICorner", {CornerRadius=UDim.new(0,2)}, parent:FindFirstChild("Frame") or parent)
	-- Recré proprement
	local icon = Make("Frame", {Parent=parent, Position=UDim2.new(0,0,0.5,-4), Size=UDim2.new(0,8,0,8), BackgroundColor3=color, BorderSizePixel=0})
	AddCorner(icon, 2)
	local txt  = MakeLabel(parent,"0.0",UDim2.new(0,14,0,0),UDim2.new(0,40,1,0),Enum.TextXAlignment.Left,P.CellTxt,FontBold)
	local bg   = Make("Frame", {Parent=parent, Position=UDim2.new(0,60,0.5,-3), Size=UDim2.new(1,-65,0,6), BackgroundColor3=P.GridLine, BorderSizePixel=0})
	AddCorner(bg, 3)
	local fill = Make("Frame", {Parent=bg, Size=UDim2.new(0,0,1,0), BackgroundColor3=color, BorderSizePixel=0})
	AddCorner(fill, 3)
	return fill, txt, maxVal
end

local function buildUI()
	for _, c in ipairs(treeScroll:GetChildren())  do if c:IsA("Frame") then c:Destroy() end end
	for _, c in ipairs(tableScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	rowFrames = {}; treeFrames = {}; parkLabels = {}; pitchCache = {}

	local parks = {}
	for i, turbine in ipairs(turbinesList) do
		local rName, rPark = getTurbineInfo(turbine)
		parks[rPark] = parks[rPark] or {}
		table.insert(parks[rPark], {index=i, name=rName, obj=turbine})
	end

	local order = 0
	local totalY = 0

	for parkName, machs in pairs(parks) do
		local pRow = Make("Frame", {Parent=treeScroll, Size=UDim2.new(1,0,0,26), BackgroundTransparency=1, LayoutOrder=order})
		local pLbl = MakeLabel(pRow,"📂 "..parkName.." [ 0 kW ]",UDim2.new(0,10,0,0),UDim2.new(1,-10,1,0),Enum.TextXAlignment.Left,P.TreeTxt,FontBold)
		parkLabels[parkName] = pLbl
		order += 1

		for _, m in ipairs(machs) do
			local i       = m.index
			local machId  = 3747 + i
			local realName = m.name .. (m.obj:GetAttribute("HasPowerCurve") and " [CURVE]" or "")

			-- Cache pitch references
			pitchCache[m.obj] = {
				m.obj:FindFirstChild("BladeAngle1", true),
				m.obj:FindFirstChild("BladeAngle2", true),
				m.obj:FindFirstChild("BladeAngle3", true),
			}

			-- Tree entry
			local tRow = Make("Frame", {Parent=treeScroll, Size=UDim2.new(1,-20,0,26), Position=UDim2.new(0,10,0,0), BackgroundTransparency=1, LayoutOrder=order})
			MakeLabel(tRow,"⚙ "..realName,UDim2.new(0,15,0,0),UDim2.new(1,-15,1,0),Enum.TextXAlignment.Left,P.TopText)
			local tBtn = Make("TextButton", {Parent=tRow, Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text=""})
			tBtn.MouseEnter:Connect(function()  tRow.BackgroundTransparency=0.9; tRow.BackgroundColor3=Color3.new(1,1,1); AddCorner(tRow,4) end)
			tBtn.MouseLeave:Connect(function()  tRow.BackgroundTransparency=1 end)
			tBtn.MouseButton1Click:Connect(function() activeTargetIndex=i; dTitleLbl.Text="Turbine: "..realName; detailBg.Visible=true end)
			table.insert(treeFrames, tRow)
			order += 1

			-- Table row
			local rBg  = (i%2==0) and P.RowEven or P.RowOdd
			local row  = Make("Frame", {Parent=tableScroll, Size=UDim2.new(1,0,0,36), BackgroundColor3=rBg, BorderSizePixel=0, Position=UDim2.new(0,0,0,totalY)})
			Make("Frame", {Parent=row, Size=UDim2.new(1,0,0,1), Position=UDim2.new(0,0,1,-1), BackgroundColor3=P.GridLine, BorderSizePixel=0})
			totalY += 36

			MakeLabel(row,tostring(machId), UDim2.new(0,15,0,0),UDim2.new(COLS[1].w,-15,1,0),Enum.TextXAlignment.Left,Color3.fromHex("#7F8C8D"))
			MakeLabel(row,realName,UDim2.new(COLS[1].w,15,0,0),UDim2.new(COLS[2].w,-15,1,0),Enum.TextXAlignment.Left,P.CellTxt,FontBold)
			local statusLbl = MakeLabel(row,"●",UDim2.new(COLS[1].w+COLS[2].w,15,0,0),UDim2.new(COLS[3].w,-15,1,0),Enum.TextXAlignment.Left)

			local tMaxKw   = m.obj:GetAttribute("MaxPowerVal") or 4500
			local colOff   = COLS[1].w + COLS[2].w + COLS[3].w

			local pwrCont  = Make("Frame", {Parent=row, Position=UDim2.new(colOff,15,0,0),              Size=UDim2.new(COLS[4].w,-25,1,0), BackgroundTransparency=1})
			local fPwr,tPwr,mPwr = MakeBar(pwrCont, P.BarPower, tMaxKw)
			local wndCont  = Make("Frame", {Parent=row, Position=UDim2.new(colOff+COLS[4].w,15,0,0),    Size=UDim2.new(COLS[5].w,-25,1,0), BackgroundTransparency=1})
			local fWnd,tWnd,mWnd = MakeBar(wndCont, P.BarWind, 25)
			local rpmCont  = Make("Frame", {Parent=row, Position=UDim2.new(colOff+COLS[4].w+COLS[5].w,15,0,0), Size=UDim2.new(COLS[6].w,-25,1,0), BackgroundTransparency=1})
			local fRpm,tRpm,mRpm = MakeBar(rpmCont, P.BarRpm, 20)

			local rBtn = Make("TextButton", {Parent=row, Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text=""})
			rBtn.MouseButton1Click:Connect(function() activeTargetIndex=i; dTitleLbl.Text="Turbine: "..realName; detailBg.Visible=true end)

			table.insert(rowFrames, {
				row=row, statusLbl=statusLbl, turbine=m.obj, parkName=parkName,
				fPwr=fPwr, tPwr=tPwr, mPwr=mPwr,
				fWnd=fWnd, tWnd=tWnd, mWnd=mWnd,
				fRpm=fRpm, tRpm=tRpm, mRpm=mRpm,
			})
		end
		Make("Frame", {Parent=treeScroll, Size=UDim2.new(1,0,0,8), BackgroundTransparency=1, LayoutOrder=order})
		order += 1
	end
end

-- ── BOUTONS ─────────────────────────────────────────────────
pTargetBtn.MouseButton1Click:Connect(function()
	currentTarget = currentTarget % 4 + 1
	pTargetBtn.Text = "Target: " .. targetModes[currentTarget]
end)

pForceBtn.MouseButton1Click:Connect(function()
	local p = tonumber(pInputBox.Text)
	local t = turbinesList[activeTargetIndex]
	if p and t then event:FireServer("SetManualPitch", t, p, currentTarget-1); pInputBox.Text="" end
end)

pResetBtn.MouseButton1Click:Connect(function()
	local t = turbinesList[activeTargetIndex]
	if t then event:FireServer("ResetPitch", t) end
end)

togglePwrBtn.MouseButton1Click:Connect(function()
	local t = turbinesList[activeTargetIndex]
	if not t then return end
	local val = t:FindFirstChild("IsOn", true)
	if val then event:FireServer("TogglePower", t, not val.Value) end
end)

bStartAll.MouseButton1Click:Connect(function() for _, t in ipairs(turbinesList) do event:FireServer("TogglePower", t, true)  end end)
bIdleAll.MouseButton1Click:Connect(function()  for _, t in ipairs(turbinesList) do event:FireServer("SetManualPitch", t, 60, 0) end end)
bStopAll.MouseButton1Click:Connect(function()  for _, t in ipairs(turbinesList) do event:FireServer("TogglePower", t, false) end end)

closeBtn.MouseButton1Click:Connect(function()   gui.Enabled=false; detailBg.Visible=false end)
dCloseBtn.MouseButton1Click:Connect(function()  detailBg.Visible=false end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if prompt.Name ~= "TurbinePrompt" or who ~= player then return end
	pcall(function()
		local seen = {}
		local temp = {}
		for _, obj in ipairs(workspace:GetDescendants()) do
			if obj:GetAttribute("IsWindTurbine") == true and not seen[obj] then
				seen[obj] = true
				table.insert(temp, obj)
			end
		end
		table.sort(temp, function(a,b) return a.Name < b.Name end)
		turbinesList = temp
		buildUI()
		gui.Enabled = true
	end)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape and gui.Enabled then
		if detailBg.Visible then detailBg.Visible=false else gui.Enabled=false end
	end
end)

-- ── BOUCLE DE MISE À JOUR ───────────────────────────────────
local rotorAngle  = 0
local UPDATE_TICK = 0.05   -- mise à jour tableau à 20 Hz (était 60 Hz)
local tickAccum   = 0

local STATUS_MAP = {
	RUNNING      = {"● RUN",   "StatusGreen"},
	STARTING     = {"● START", "StatusYel"},
	LACK_OF_WIND = {"● WAIT",  "StatusGray"},
}

RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then return end

	-- Animation rotor (toujours à 60 fps, c'est visuel)
	if detailBg.Visible and activeTargetIndex > 0 then
		local t = turbinesList[activeTargetIndex]
		if t then
			local rpm = t:GetAttribute("CurrentRPM") or 0
			if rpm ~= rpm then rpm = 0 end
			rotorAngle = (rotorAngle + rpm * 0.1) % 360
			hub.Rotation = rotorAngle
		end
	end

	-- Tableau & détail : throttlé à 20 Hz
	tickAccum += dt
	if tickAccum < UPDATE_TICK then return end
	tickAccum -= UPDATE_TICK

	local globalPower = 0
	local parkPowerMap = {}

	for _, rd in ipairs(rowFrames) do
		local t      = rd.turbine
		local state  = (t:FindFirstChild("CurrentState", true) or {Value="STOPPED"}).Value
		local power  = t:GetAttribute("CurrentPower") or 0
		local rpm    = t:GetAttribute("CurrentRPM")   or 0
		local wind   = (t:GetAttribute("RealWindSpeed") or 0) / 3.6

		-- NaN guard
		if power~=power then power=0 end
		if rpm~=rpm     then rpm=0   end
		if wind~=wind   then wind=0  end

		globalPower += power
		parkPowerMap[rd.parkName] = (parkPowerMap[rd.parkName] or 0) + power

		local sm = STATUS_MAP[state]
		if sm then rd.statusLbl.Text=sm[1]; rd.statusLbl.TextColor3=P[sm[2]]
		else       rd.statusLbl.Text="● STOP"; rd.statusLbl.TextColor3=P.StatusRed end

		local maxP = (rd.mPwr and rd.mPwr > 0) and rd.mPwr or 4500
		rd.fPwr.Size = UDim2.new(math.clamp(power/maxP, 0,1), 0, 1, 0)
		rd.tPwr.Text = string.format("%.0f", power)
		rd.fWnd.Size = UDim2.new(math.clamp(wind/rd.mWnd,  0,1), 0, 1, 0)
		rd.tWnd.Text = string.format("%.1f", wind)
		rd.fRpm.Size = UDim2.new(math.clamp(rpm/rd.mRpm,   0,1), 0, 1, 0)
		rd.tRpm.Text = string.format("%.1f", rpm)
	end

	for pName, lbl in pairs(parkLabels) do
		local pVal = parkPowerMap[pName] or 0
		lbl.Text = pVal > 1000
			and string.format("📂 %s [ %.2f MW ]", pName, pVal/1000)
			or  string.format("📂 %s [ %.0f kW ]", pName, pVal)
	end

	globalPwrLabel.Text = globalPower > 1000
		and string.format("⚡ TOTAL: %.2f MW", globalPower/1000)
		or  string.format("⚡ TOTAL: %.0f kW", globalPower)

	-- Détail popup
	if not (detailBg.Visible and activeTargetIndex > 0) then return end
	local t = turbinesList[activeTargetIndex]
	if not t then return end

	local state = (t:FindFirstChild("CurrentState", true) or {Value="STOPPED"}).Value
	local sm    = STATUS_MAP[state]
	if sm then dStatusLbl.Text=sm[1]:gsub("RUN","Operational"):gsub("START","Starting up"):gsub("WAIT","Standby (Wind)"); dStatusLbl.TextColor3=P[sm[2]]
	else       dStatusLbl.Text="● Stopped"; dStatusLbl.TextColor3=P.StatusRed end

	local p = t:GetAttribute("CurrentPower") or 0
	local w = (t:GetAttribute("RealWindSpeed") or 0) / 3.6
	local r = t:GetAttribute("CurrentRPM") or 0
	if p~=p then p=0 end; if w~=w then w=0 end; if r~=r then r=0 end

	dPowerVal.Text = string.format("%.1f", p)
	dWindVal.Text  = string.format("%.1f", w)
	dRpmVal.Text   = string.format("%.2f", r)

	-- Pitch via cache
	local pc = pitchCache[t]
	dPitch1.Text = pc and pc[1] and string.format("%.1f", pc[1].Value) or "--"
	dPitch2.Text = pc and pc[2] and string.format("%.1f", pc[2].Value) or "--"
	dPitch3.Text = pc and pc[3] and string.format("%.1f", pc[3].Value) or "--"

	local isOn = t:FindFirstChild("IsOn", true)
	if isOn and isOn.Value then
		togglePwrBtn.Text="SHUTDOWN TURBINE"; togglePwrBtn.BackgroundColor3=P.BtnStop; togglePwrBtn.TextColor3=P.StatusRed
	else
		togglePwrBtn.Text="START TURBINE";    togglePwrBtn.BackgroundColor3=P.BtnStart; togglePwrBtn.TextColor3=P.StatusGreen
	end
end)