-- ============================================================
-- PERFECTION WELD
-- ============================================================
local NEVER_BREAK_JOINTS = false

local Hub = script.Parent
local BladesFolder = Hub:FindFirstChild("Blades")

local function CallOnChildren(Instance, FunctionToCall)
	FunctionToCall(Instance)
	for _, Child in next, Instance:GetChildren() do
		CallOnChildren(Child, FunctionToCall)
	end
end

local function GetNearestParent(Instance, ClassName)
	local Ancestor = Instance
	repeat
		Ancestor = Ancestor.Parent
		if Ancestor == nil then
			return nil
		end
	until Ancestor:IsA(ClassName)
	return Ancestor
end

local function GetBricks(StartInstance)
	local List = {}
	CallOnChildren(StartInstance, function(Item)
		if not Item:IsA("BasePart") then return end
		if Item:FindFirstChild("NoPerfWeld") then return end

		-- On empêche la soudure des pièces des pales par PerfectionWeld
		local inBladeModel = false
		for i = 1, 3 do
			local bModel = BladesFolder and BladesFolder:FindFirstChild("blade" .. i)
			if bModel and Item:IsDescendantOf(bModel) then
				inBladeModel = true
				break
			end
		end

		if not inBladeModel then
			List[#List+1] = Item
		end
	end)
	return List
end

local function Modify(Instance, Values)
	assert(type(Values) == "table", "Values is not a table")
	for Index, Value in next, Values do
		if type(Index) == "number" then
			Value.Parent = Instance
		else
			Instance[Index] = Value
		end
	end
	return Instance
end

local function Make(ClassType, Properties)
	return Modify(Instance.new(ClassType), Properties)
end

local Surfaces = {"TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface"}
local HingSurfaces = {"Hinge", "Motor", "SteppingMotor"}

local function HasWheelJoint(Part)
	for _, SurfaceName in pairs(Surfaces) do
		for _, HingSurfaceName in pairs(HingSurfaces) do
			if Part[SurfaceName].Name == HingSurfaceName then
				return true
			end
		end
	end
	return false
end

local function ShouldBreakJoints(Part)
	if NEVER_BREAK_JOINTS then return false end
	if Part:FindFirstChild("NoPerfWeld") then return false end
	if HasWheelJoint(Part) then return false end
	local Connected = Part:GetConnectedParts()
	if #Connected == 1 then return false end
	for _, Item in pairs(Connected) do
		if HasWheelJoint(Item) then
			return false
		elseif not Item:IsDescendantOf(script.Parent) then
			return false
		end
	end
	return true
end

local function WeldTogether(Part0, Part1, JointType, WeldParent)
	JointType = JointType or "Weld"
	local RelativeValue = Part1:FindFirstChild("qRelativeCFrameWeldValue")
	local NewWeld = Part1:FindFirstChild("qCFrameWeldThingy") or Instance.new(JointType)
	Modify(NewWeld, {
		Name   = "qCFrameWeldThingy";
		Part0  = Part0;
		Part1  = Part1;
		C0     = CFrame.new();
		C1     = RelativeValue and RelativeValue.Value or Part1.CFrame:toObjectSpace(Part0.CFrame);
		Parent = Part1;
	})
	if not RelativeValue then
		RelativeValue = Make("CFrameValue", {
			Parent     = Part1;
			Name       = "qRelativeCFrameWeldValue";
			Archivable = true;
			Value      = NewWeld.C1;
		})
	end
	return NewWeld
end

local function WeldParts(Parts, MainPart, JointType, DoNotUnanchor)
	for _, Part in pairs(Parts) do
		if ShouldBreakJoints(Part) then
			Part:BreakJoints()
		end
	end
	for _, Part in pairs(Parts) do
		if Part ~= MainPart and not Part:FindFirstChild("NoPerfWeld") then
			WeldTogether(MainPart, Part, JointType, MainPart)
		end
	end
	if not DoNotUnanchor then
		for _, Part in pairs(Parts) do
			Part.Anchored = false
		end
		MainPart.Anchored = false
	end
end

local function PerfectionWeld()
	local Tool = GetNearestParent(script, "Tool")
	local Parts = GetBricks(script.Parent)
	local PrimaryPart = Tool and Tool:FindFirstChild("Handle") and Tool.Handle:IsA("BasePart") and Tool.Handle
		or script.Parent:IsA("Model") and script.Parent.PrimaryPart
		or Parts[1]
	if PrimaryPart then
		WeldParts(Parts, PrimaryPart, "Weld", false)
	else
		warn("qWeld - Unable to weld part")
	end
	return Tool
end

local Tool = PerfectionWeld()

if Tool and script.ClassName == "Script" then
	script.Parent.AncestryChanged:connect(function()
		PerfectionWeld()
	end)
end

-- ============================================================
-- BLADE PITCH CONTROLLER (GESTION INDÉPENDANTE DES 3 PALES)
-- ============================================================

local RunService   = game:GetService("RunService")
local SpeedConfig  = Hub.Parent.Parent["Speed config"]
local pitchMotors  = {}
local currentPitches = {90, 90, 90} -- 3 angles séparés

if not BladesFolder then return end

-- 🛑 INITIALISATION DES 3 VARIABLES DANS LE DOSSIER
for i = 1, 3 do
	local ba = SpeedConfig:FindFirstChild("BladeAngle" .. i)
	if not ba then
		ba = Instance.new("NumberValue")
		ba.Name = "BladeAngle" .. i
		ba.Value = 90
		ba.Parent = SpeedConfig
	end
end

local function linkBladeToPitch(index)
	local pitchPart = BladesFolder:FindFirstChild("pitch" .. index)
	local bladeModel = BladesFolder:FindFirstChild("blade" .. index)

	if pitchPart and bladeModel and bladeModel:IsA("Model") then
		local mainBladePart = bladeModel.PrimaryPart or bladeModel:FindFirstChildWhichIsA("BasePart", true)
		if not mainBladePart then return end
		bladeModel.PrimaryPart = mainBladePart

		local bladeParts = {}
		for _, p in ipairs(bladeModel:GetDescendants()) do
			if p:IsA("BasePart") then
				table.insert(bladeParts, p)
				p:BreakJoints()
			end
		end
		WeldParts(bladeParts, mainBladePart, "Weld", true)

		local motor = Instance.new("Motor6D")
		motor.Name = "PitchMotor"
		motor.Part0 = pitchPart
		motor.Part1 = mainBladePart

		local offset = pitchPart.CFrame:ToObjectSpace(mainBladePart.CFrame)
		motor.C0 = CFrame.new()
		motor.C1 = offset:Inverse()
		motor.Parent = pitchPart

		for _, p in ipairs(bladeParts) do
			p.Anchored = false
			p.CanCollide = false
		end

		pitchMotors[index] = motor
	end
end

for i = 1, 3 do linkBladeToPitch(i) end

-- Boucle de rendu : Tourne chaque moteur indépendamment
RunService.Heartbeat:Connect(function()
	for i = 1, 3 do
		if pitchMotors[i] then
			-- On applique la rotation individuelle
			pitchMotors[i].C0 = CFrame.Angles(0, -math.rad(currentPitches[i]), 0)
		end
	end
end)

-- Écoute les changements des 3 variables en temps réel
for i = 1, 3 do
	local ba = SpeedConfig:FindFirstChild("BladeAngle" .. i)
	if ba then
		currentPitches[i] = ba.Value
		ba.Changed:Connect(function(newAngle)
			currentPitches[i] = newAngle
		end)
	end
end
