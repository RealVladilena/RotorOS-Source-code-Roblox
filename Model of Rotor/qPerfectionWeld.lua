-- ============================================================
-- PERFECTION WELD 
-- ============================================================
local NEVER_BREAK_JOINTS = false

local Hub          = script.Parent
local BladesFolder = Hub:FindFirstChild("Blades")

-- Cache des modèles de pales pour éviter la recherche répétée
local bladeModels = {}
if BladesFolder then
	for i = 1, 3 do
		bladeModels[i] = BladesFolder:FindFirstChild("blade" .. i)
	end
end

-- Itération récursive sur les descendants
local function ForEachDescendant(root, fn)
	fn(root)
	for _, child in next, root:GetChildren() do
		ForEachDescendant(child, fn)
	end
end

local function GetNearestParent(inst, className)
	local ancestor = inst
	repeat
		ancestor = ancestor.Parent
		if ancestor == nil then return nil end
	until ancestor:IsA(className)
	return ancestor
end

-- Retourne les BaseParts soudables (hors pales, hors NoPerfWeld)
local function GetBricks(startInst)
	local list = {}
	ForEachDescendant(startInst, function(item)
		if not item:IsA("BasePart") then return end
		if item:FindFirstChild("NoPerfWeld") then return end
		for _, bm in ipairs(bladeModels) do
			if bm and item:IsDescendantOf(bm) then return end
		end
		list[#list + 1] = item
	end)
	return list
end

local function Modify(inst, values)
	for k, v in next, values do
		if type(k) == "number" then v.Parent = inst
		else inst[k] = v end
	end
	return inst
end

local function Make(classType, props)
	return Modify(Instance.new(classType), props)
end

local SURFACES      = {"TopSurface","BottomSurface","LeftSurface","RightSurface","FrontSurface","BackSurface"}
local HINGE_NAMES   = {Hinge=true, Motor=true, SteppingMotor=true}

local function HasWheelJoint(part)
	for _, s in ipairs(SURFACES) do
		if HINGE_NAMES[part[s].Name] then return true end
	end
	return false
end

local function ShouldBreakJoints(part)
	if NEVER_BREAK_JOINTS or part:FindFirstChild("NoPerfWeld") or HasWheelJoint(part) then return false end
	local connected = part:GetConnectedParts()
	if #connected == 1 then return false end
	for _, item in ipairs(connected) do
		if HasWheelJoint(item) or not item:IsDescendantOf(script.Parent) then return false end
	end
	return true
end

local function WeldTogether(part0, part1)
	local relVal   = part1:FindFirstChild("qRelativeCFrameWeldValue")
	local newWeld  = part1:FindFirstChild("qCFrameWeldThingy") or Instance.new("Weld")
	Modify(newWeld, {
		Name   = "qCFrameWeldThingy";
		Part0  = part0;
		Part1  = part1;
		C0     = CFrame.new();
		C1     = relVal and relVal.Value or part1.CFrame:ToObjectSpace(part0.CFrame);
		Parent = part1;
	})
	if not relVal then
		Make("CFrameValue", {
			Parent     = part1;
			Name       = "qRelativeCFrameWeldValue";
			Archivable = true;
			Value      = newWeld.C1;
		})
	end
	return newWeld
end

local function WeldParts(parts, mainPart, doNotUnanchor)
	for _, part in ipairs(parts) do
		if ShouldBreakJoints(part) then part:BreakJoints() end
	end
	for _, part in ipairs(parts) do
		if part ~= mainPart and not part:FindFirstChild("NoPerfWeld") then
			WeldTogether(mainPart, part)
		end
	end
	if not doNotUnanchor then
		for _, part in ipairs(parts) do part.Anchored = false end
		mainPart.Anchored = false
	end
end

local function PerfectionWeld()
	local tool  = GetNearestParent(script, "Tool")
	local parts = GetBricks(script.Parent)
	local primary =
		(tool and tool:FindFirstChild("Handle") and tool.Handle:IsA("BasePart") and tool.Handle)
		or (script.Parent:IsA("Model") and script.Parent.PrimaryPart)
		or parts[1]
	if primary then
		WeldParts(parts, primary, false)
	else
		warn("qWeld - Unable to weld part")
	end
	return tool
end

local Tool = PerfectionWeld()
if Tool and script.ClassName == "Script" then
	script.Parent.AncestryChanged:Connect(function() PerfectionWeld() end)
end

-- ============================================================
-- BLADE PITCH CONTROLLER (3 pales indépendantes)
-- ============================================================
local RunService  = game:GetService("RunService")
local SpeedConfig = Hub.Parent.Parent["Speed config"]

if not BladesFolder then return end

local currentPitches = {90, 90, 90}
local pitchMotors    = {}

-- Initialise les NumberValues dans SpeedConfig
for i = 1, 3 do
	if not SpeedConfig:FindFirstChild("BladeAngle" .. i) then
		local v = Instance.new("NumberValue")
		v.Name, v.Value, v.Parent = "BladeAngle" .. i, 90, SpeedConfig
	end
end

local function linkBladeToPitch(index)
	local pitchPart = BladesFolder:FindFirstChild("pitch" .. index)
	local bladeModel = bladeModels[index]
	if not (pitchPart and bladeModel and bladeModel:IsA("Model")) then return end

	local mainPart = bladeModel.PrimaryPart or bladeModel:FindFirstChildWhichIsA("BasePart", true)
	if not mainPart then return end
	bladeModel.PrimaryPart = mainPart

	local bladeParts = {}
	for _, p in ipairs(bladeModel:GetDescendants()) do
		if p:IsA("BasePart") then
			bladeParts[#bladeParts + 1] = p
			p:BreakJoints()
		end
	end
	WeldParts(bladeParts, mainPart, true)

	local motor = Instance.new("Motor6D")
	motor.Name  = "PitchMotor"
	motor.Part0 = pitchPart
	motor.Part1 = mainPart
	motor.C0    = CFrame.new()
	motor.C1    = (pitchPart.CFrame:ToObjectSpace(mainPart.CFrame)):Inverse()
	motor.Parent = pitchPart

	for _, p in ipairs(bladeParts) do
		p.Anchored   = false
		p.CanCollide = false
	end

	pitchMotors[index] = motor
end

for i = 1, 3 do linkBladeToPitch(i) end

-- Boucle de rendu : applique la rotation de chaque pale
RunService.Heartbeat:Connect(function()
	for i = 1, 3 do
		if pitchMotors[i] then
			pitchMotors[i].C0 = CFrame.Angles(0, -math.rad(currentPitches[i]), 0)
		end
	end
end)

-- Écoute les changements en temps réel
for i = 1, 3 do
	local ba = SpeedConfig:FindFirstChild("BladeAngle" .. i)
	if ba then
		currentPitches[i] = ba.Value
		ba.Changed:Connect(function(v) currentPitches[i] = v end)
	end
end