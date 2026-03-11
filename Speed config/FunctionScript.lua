-- ============================================================
-- HYBRID CONTROLLER — POWER, RPM RÉEL & OVERSPEED PROTECTION
-- ============================================================
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 🟢 1. CHARGEMENT BIBLIOTHÈQUE 
local PowerCurvesData = nil
pcall(function() PowerCurvesData = require(ReplicatedStorage:WaitForChild("PowerCurvesLibrary", 5)) end)

-- 🟢 RECHERCHE DU SOMMET DE L'ÉOLIENNE
local TurbineRoot = script.Parent
while TurbineRoot and TurbineRoot.Parent and TurbineRoot.Parent ~= workspace do
	if TurbineRoot.Parent:IsA("Folder") then break end
	if TurbineRoot:GetAttribute("IsTurbineRoot") then break end
	TurbineRoot = TurbineRoot.Parent
end
TurbineRoot:SetAttribute("IsWindTurbine", true)

-- Twist Cache
local BladesFunc = script.Parent.Parent
local CF = BladesFunc and BladesFunc:FindFirstChild("CF")
local Twist = CF and CF:FindFirstChild("Twist")
if Twist then Twist.BottomParamA = 0; Twist.BottomParamB = 0 end

-- 🟢 2. IDENTIFICATION COURBE & LECTURE DES STATS
local myCurve = nil
local MAX_KW = 4500 
local MAX_RPM = 17.5 

local turbineRealName = string.gsub(TurbineRoot.Name, " %(start new%)", "")
turbineRealName = string.gsub(turbineRealName, " %d+$", "")

if PowerCurvesData then
	for modelName, curve in pairs(PowerCurvesData) do
		if string.find(turbineRealName, modelName, 1, true) then
			myCurve = curve
			TurbineRoot:SetAttribute("HasPowerCurve", true)

			if curve.MaxRPM then MAX_RPM = curve.MaxRPM end

			local finalPoint = curve[#curve]
			if finalPoint then MAX_KW = finalPoint.p end
			break
		end
	end
end

-- 🟢 PIÈCES
task.wait(1.5) 
local yawUnion = TurbineRoot:FindFirstChild("YAW Union", true) or TurbineRoot:FindFirstChild("YAW", true)
local nacelle = TurbineRoot:FindFirstChild("Nacelle", true)
local kitBlades = TurbineRoot:FindFirstChild("Wind Turbine KIT BLADES", true) 
	or TurbineRoot:FindFirstChild("Rotor", true) 
	or TurbineRoot:FindFirstChild("Blades", true)

local statusLight = TurbineRoot:FindFirstChild("StatusLight", true)
local rotorHinge = TurbineRoot:FindFirstChild("HingeConstraint", true) or TurbineRoot:FindFirstChild("RotorHinge", true) 
local rotorMotor = TurbineRoot:FindFirstChild("RotorMotor", true)

local function getOrCreateValue(name, typeClass, default)
	local val = TurbineRoot:FindFirstChild(name) or Instance.new(typeClass)
	if not val.Parent then val.Name = name val.Value = default val.Parent = TurbineRoot end
	return val
end

local isOnValue = getOrCreateValue("IsOn", "BoolValue", true)
local stateValue = getOrCreateValue("CurrentState", "StringValue", "STOPPED")
local timerValue = getOrCreateValue("StormTimer", "IntValue", 0)
local isManualPitchVal = getOrCreateValue("IsManualPitch", "BoolValue", false)

local manualPitches = {
	getOrCreateValue("ManualPitch1", "NumberValue", 91.7),
	getOrCreateValue("ManualPitch2", "NumberValue", 91.7),
	getOrCreateValue("ManualPitch3", "NumberValue", 91.7)
}

local bladeAngleVals = {
	script.Parent:FindFirstChild("BladeAngle1") or TurbineRoot:FindFirstChild("BladeAngle1", true),
	script.Parent:FindFirstChild("BladeAngle2") or TurbineRoot:FindFirstChild("BladeAngle2", true),
	script.Parent:FindFirstChild("BladeAngle3") or TurbineRoot:FindFirstChild("BladeAngle3", true)
}

-- Paramètres de Pitch
local INITIAL_PITCH, IDLE_PITCH = 91.7, 70 
local WIND_CUT_IN, WIND_RATED, WIND_CUT_OUT = 3.0, 13.0, 25.0 
local PITCH_SPEED_START, PITCH_SPEED_REGULATE, PITCH_SPEED_STORM, PITCH_SPEED_STOP = 1.0, 2.5, 4.0, 3.0
local PITCH_SPEED_EMERGENCY = 8.0 

local turbineState = "STOPPED"
local currentPitches = {INITIAL_PITCH, INITIAL_PITCH, INITIAL_PITCH}
local pitchTargets = {INITIAL_PITCH, INITIAL_PITCH, INITIAL_PITCH}
local pitchSpeed = PITCH_SPEED_STOP
local displayPower, displayRpm, cooldownTimer = 0, 0, 0
local startupPhase, startupDelayTimer = 0, 0

local YAW_SPEED = 2.0
local currentYawAngle = 0
local yawInitialCFrame = yawUnion and yawUnion.CFrame or CFrame.new()

local nacelleOffset, rotorRelativeOffset = CFrame.new(), CFrame.new()
local rotorBasePart = nil

local function getSafeCFrame(obj)
	if not obj then return CFrame.new() end
	if obj:IsA("Model") then return obj:GetPivot() end
	if obj:IsA("BasePart") then return obj.CFrame end
	return CFrame.new()
end

if yawUnion then
	if nacelle then
		local mainPart = nacelle:FindFirstChildWhichIsA("BasePart")
		nacelleOffset = yawInitialCFrame:ToObjectSpace(getSafeCFrame(mainPart or nacelle))
	end
	if kitBlades then
		rotorBasePart = kitBlades.PrimaryPart or kitBlades:FindFirstChild("Hub", true) or kitBlades:FindFirstChildWhichIsA("BasePart", true) or kitBlades
		if rotorBasePart then 
			rotorRelativeOffset = yawInitialCFrame:ToObjectSpace(getSafeCFrame(rotorBasePart)) 
		end
	end
end

local localYawSpeed = YAW_SPEED + Random.new(yawUnion and math.floor(yawUnion.Position.X) or 1):NextNumber(-0.5, 0.5)
local globalWindCtrl = workspace:FindFirstChild("GlobalWindController")
local wSpeedVal = globalWindCtrl and globalWindCtrl:FindFirstChild("WindSpeed")
local wAngleVal = globalWindCtrl and globalWindCtrl:FindFirstChild("WindAngle")

local logicTimer = 0
local LOGIC_TICK_RATE = 0.1
local safeStartTimer = 0

-- 🟢 BOUCLE PRINCIPALE
RunService.Heartbeat:Connect(function(dt)
	safeStartTimer = safeStartTimer + dt
	logicTimer = logicTimer + dt

	local wSpeed, wAngle = 0, 0
	if globalWindCtrl then
		wSpeed = wSpeedVal and wSpeedVal.Value or 0
		wAngle = wAngleVal and wAngleVal.Value or 0
	else
		local wDir = workspace.GlobalWind
		wSpeed = wDir.Magnitude
		wAngle = math.deg(math.atan2(wDir.X, wDir.Z))
	end

	local isEnabled = isOnValue.Value 
	local avgPitch = (currentPitches[1] + currentPitches[2] + currentPitches[3]) * 0.333

	-- 👁️ YAW FLUIDE
	if yawUnion and nacelle and wSpeed >= 2 then
		local diff = (wAngle - currentYawAngle) % 360
		if diff > 180 then diff = diff - 360 elseif diff < -180 then diff = diff + 360 end

		if math.abs(diff) > 2.0 then 
			local step = math.sign(diff) * localYawSpeed * dt
			currentYawAngle = (currentYawAngle + (math.abs(step) > math.abs(diff) and diff or step)) % 360

			local newYawCFrame = CFrame.new(yawInitialCFrame.Position) * CFrame.Angles(0, math.rad(currentYawAngle), 0)
			yawUnion.CFrame = newYawCFrame
			nacelle:PivotTo(newYawCFrame * nacelleOffset) 

			if rotorBasePart and safeStartTimer > 1.5 then
				local currentRotorCFrame = getSafeCFrame(rotorBasePart)
				local currentRotorOrientation = currentRotorCFrame - currentRotorCFrame.Position
				local targetPosition = (newYawCFrame * rotorRelativeOffset).Position
				local newRotorCFrame = CFrame.new(targetPosition) * currentRotorOrientation
				if rotorBasePart:IsA("Model") then rotorBasePart:PivotTo(newRotorCFrame) else rotorBasePart.CFrame = newRotorCFrame end
			end
		end
	end

	-- 🧠 CERVEAU (États & Production)
	if logicTimer >= LOGIC_TICK_RATE then
		local logicDt = logicTimer
		logicTimer = 0 

		local pitchDiffMax = math.max(math.abs(currentPitches[1] - currentPitches[2]), math.abs(currentPitches[2] - currentPitches[3]), math.abs(currentPitches[1] - currentPitches[3]))

		-- 🚨 OVERSPEED DETECTION 
		if displayRpm > (MAX_RPM * 1.15) and turbineState == "RUNNING" then
			turbineState = "OVERSPEED"
			cooldownTimer = 30 
		end

		if turbineState == "STOPPED" then
			if isEnabled then
				isManualPitchVal.Value = false
				if wSpeed >= WIND_CUT_IN and wSpeed < WIND_CUT_OUT then turbineState = "STARTING" startupPhase = 0
				elseif wSpeed < WIND_CUT_IN and wSpeed > 0.5 then turbineState = "LACK_OF_WIND" end
			end
		elseif turbineState == "LACK_OF_WIND" then
			if not isEnabled then turbineState = "STOPPED"
			elseif wSpeed >= WIND_CUT_IN and wSpeed < WIND_CUT_OUT then turbineState = "STARTING" startupPhase = 0
			elseif wSpeed > WIND_CUT_OUT then turbineState = "STORM" cooldownTimer = 30 end
		elseif turbineState == "STARTING" then
			if wSpeed > WIND_CUT_OUT then turbineState = "STORM" cooldownTimer = 30
			elseif not isEnabled then turbineState = "STOPPED"
			elseif wSpeed < WIND_CUT_IN then turbineState = "LACK_OF_WIND"
			elseif startupPhase == 5 and avgPitch <= 1.0 then turbineState = "RUNNING" end
		elseif turbineState == "RUNNING" then
			if not isEnabled then turbineState = "STOPPED"
			elseif wSpeed > WIND_CUT_OUT then turbineState = "STORM" cooldownTimer = 30
			elseif wSpeed < WIND_CUT_IN then turbineState = "LACK_OF_WIND" end 
		elseif turbineState == "STORM" or turbineState == "OVERSPEED" then
			cooldownTimer = math.max(cooldownTimer - logicDt, 0)
			if cooldownTimer <= 0 then turbineState = "COOLDOWN" end
			if not isEnabled then turbineState = "STOPPED" end 
		elseif turbineState == "COOLDOWN" then
			if wSpeed < (WIND_CUT_OUT - 2) and isEnabled then
				if wSpeed >= WIND_CUT_IN then turbineState = "STARTING" startupPhase = 0 else turbineState = "LACK_OF_WIND" end
			end
			if not isEnabled then turbineState = "STOPPED" end
		end

		stateValue.Value = turbineState
		timerValue.Value = math.ceil(cooldownTimer)

		-- CIBLES PITCH
		if turbineState == "RUNNING" then
			local regPitch = wSpeed >= WIND_RATED and (25 * math.clamp((wSpeed - WIND_RATED) / (WIND_CUT_OUT - WIND_RATED), 0, 1)) or 0
			pitchTargets = {regPitch, regPitch, regPitch}
			pitchSpeed = PITCH_SPEED_REGULATE 

		elseif turbineState == "STARTING" then
			pitchSpeed = PITCH_SPEED_START 
			if startupPhase == 0 then
				pitchTargets = {INITIAL_PITCH, INITIAL_PITCH, INITIAL_PITCH}
				if pitchDiffMax < 0.5 and avgPitch >= (INITIAL_PITCH - 0.5) then startupPhase = 1 end
			elseif startupPhase == 1 then
				pitchTargets = {70, 70, 70}; if avgPitch <= 70.5 then startupPhase = 2; startupDelayTimer = 20 end
			elseif startupPhase == 2 then
				startupDelayTimer = startupDelayTimer - logicDt; if startupDelayTimer <= 0 then startupPhase = 3 end
			elseif startupPhase == 3 then
				pitchTargets = {20, 20, 20}; if avgPitch <= 20.5 then startupPhase = 4; startupDelayTimer = 15 end
			elseif startupPhase == 4 then
				startupDelayTimer = startupDelayTimer - logicDt; if startupDelayTimer <= 0 then startupPhase = 5 end
			elseif startupPhase == 5 then pitchTargets = {0, 0, 0} end

		elseif turbineState == "LACK_OF_WIND" then pitchTargets = {IDLE_PITCH, IDLE_PITCH, IDLE_PITCH}; pitchSpeed = PITCH_SPEED_STOP
		elseif turbineState == "STORM" then pitchTargets = {INITIAL_PITCH, INITIAL_PITCH, INITIAL_PITCH}; pitchSpeed = PITCH_SPEED_STORM
		elseif turbineState == "OVERSPEED" then
			pitchTargets = {INITIAL_PITCH, INITIAL_PITCH, INITIAL_PITCH}
			pitchSpeed = PITCH_SPEED_EMERGENCY 
		elseif turbineState == "STOPPED" or turbineState == "COOLDOWN" then
			if isManualPitchVal.Value then pitchTargets = {manualPitches[1].Value, manualPitches[2].Value, manualPitches[3].Value}
			else pitchTargets = {INITIAL_PITCH, INITIAL_PITCH, INITIAL_PITCH}; pitchSpeed = PITCH_SPEED_STOP end
		end

		-- PRODUCTION
		local targetPower = 0
		if (turbineState == "RUNNING" or turbineState == "STARTING") and avgPitch <= 20.0 then
			if myCurve then
				for j = 1, #myCurve - 1 do
					if wSpeed >= myCurve[j].w and wSpeed <= myCurve[j+1].w then
						targetPower = myCurve[j].p + (myCurve[j+1].p - myCurve[j].p) * ((wSpeed - myCurve[j].w) / (myCurve[j+1].w - myCurve[j].w)); break
					elseif wSpeed > myCurve[#myCurve].w then targetPower = MAX_KW end
				end
			else
				targetPower = wSpeed >= WIND_RATED and MAX_KW or (MAX_KW * math.clamp((wSpeed - WIND_CUT_IN) / (WIND_RATED - WIND_CUT_IN), 0, 1)^2 * (3 - 2 * math.clamp((wSpeed - WIND_CUT_IN) / (WIND_RATED - WIND_CUT_IN), 0, 1)))
			end
			targetPower = targetPower * Random.new():NextNumber(0.99, 1.01)
		end
		displayPower = math.clamp(displayPower + math.sign(targetPower - displayPower) * (MAX_KW / 20) * logicDt, 0, targetPower >= displayPower and targetPower or displayPower)
		if displayPower < 2 then displayPower = 0 end

		TurbineRoot:SetAttribute("CurrentYaw", currentYawAngle)
		TurbineRoot:SetAttribute("RealWindSpeed", wSpeed * 3.6)
		TurbineRoot:SetAttribute("CurrentRPM", displayRpm)
		TurbineRoot:SetAttribute("CurrentPower", displayPower)
		TurbineRoot:SetAttribute("MaxPowerVal", MAX_KW) 
		TurbineRoot:SetAttribute("MaxRPMVal", MAX_RPM)

		if statusLight then
			statusLight.Material = Enum.Material.Neon
			if turbineState == "RUNNING" then statusLight.Color = Color3.fromRGB(0, 255, 0)
			elseif turbineState == "STARTING" then statusLight.Color = Color3.fromRGB(255, 170, 0)
			elseif turbineState == "LACK_OF_WIND" then statusLight.Color = Color3.fromRGB(200, 200, 200)
			elseif turbineState == "OVERSPEED" then statusLight.Color = math.floor(tick() * 8) % 2 == 0 and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 255, 255) 
			elseif turbineState == "STORM" then statusLight.Color = math.floor(tick() * 4) % 2 == 0 and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(50, 0, 0)
			elseif turbineState == "COOLDOWN" then statusLight.Color = Color3.fromRGB(255, 255, 0)
			elseif turbineState == "STOPPED" then statusLight.Color = Color3.fromRGB(255, 0, 0) end
		end
	end

	-- 👁️ ANIMATION PITCH 
	for i = 1, 3 do
		if math.abs(currentPitches[i] - pitchTargets[i]) < (pitchSpeed * dt) then currentPitches[i] = pitchTargets[i]
		else currentPitches[i] = currentPitches[i] + math.sign(pitchTargets[i] - currentPitches[i]) * pitchSpeed * dt end
		if bladeAngleVals[i] then bladeAngleVals[i].Value = currentPitches[i] end
	end

	-- ⚙️ CALCUL DU RPM (CORRIGÉ POUR TRANSITION FLUIDE)
	local targetLogicalRpm = 0

	-- 1. On calcule d'abord la vitesse idéale "Cible" par rapport à la puissance du vent actuel
	local idealRpm = 0
	if wSpeed >= WIND_RATED then 
		idealRpm = MAX_RPM
	else
		local windRatio = math.clamp((wSpeed - WIND_CUT_IN) / (WIND_RATED - WIND_CUT_IN), 0.1, 1)
		local minStartRPM = MAX_RPM * 0.35 
		idealRpm = minStartRPM + ((MAX_RPM - minStartRPM) * windRatio)
	end

	-- 2. On applique cette cible selon l'état
	if turbineState == "RUNNING" then
		targetLogicalRpm = idealRpm
		
	elseif turbineState == "STARTING" and startupPhase >= 3 then
		-- Au démarrage, on cible progressivement la vitesse idéale (et plus obligatoirement la vitesse MAX aveuglément)
		local pitchEffect = math.clamp(1 - (avgPitch / 91.7), 0, 1) 
		targetLogicalRpm = idealRpm * pitchEffect

	elseif turbineState == "LACK_OF_WIND" then 
		targetLogicalRpm = math.clamp(wSpeed, 0, 3) 
		
	else 
		targetLogicalRpm = wSpeed >= 3.0 and math.clamp(wSpeed * 0.2, 0.5, 2.5) or 0 
	end

	-- Frein mécanique (seulement si on ne démarre pas et on ne tourne pas)
	if avgPitch > 45 and turbineState ~= "RUNNING" and turbineState ~= "STARTING" and turbineState ~= "STOPPED" and turbineState ~= "STORM" and turbineState ~= "OVERSPEED" then 
		targetLogicalRpm = targetLogicalRpm * math.clamp(1 - ((avgPitch - 45) / 46.7), 0, 1) 
	end

	if turbineState == "OVERSPEED" then
		targetLogicalRpm = 0
		displayRpm = displayRpm - (displayRpm * dt * 0.8) 
	elseif turbineState == "STORM" or turbineState == "STOPPED" then
		targetLogicalRpm = 0
		displayRpm = displayRpm - (displayRpm * dt * 0.4) 
	else
		displayRpm = displayRpm + (targetLogicalRpm - displayRpm) * (dt * 0.15)
	end

	-- ⚙️ VISUEL (Twist / Physique)
	if Twist then
		local rpmPercentage = displayRpm / MAX_RPM
		local calcSpeed = -(rpmPercentage * 45.0) 
		Twist.BottomParamA = calcSpeed
		Twist.BottomParamB = calcSpeed
		
	elseif rotorHinge and rotorHinge:IsA("HingeConstraint") then
		rotorHinge.ActuatorType = Enum.ActuatorType.Motor
		rotorHinge.AngularVelocity = displayRpm * 0.10472
	elseif rotorMotor and (rotorMotor:IsA("Motor6D") or rotorMotor:IsA("Weld")) then
		rotorMotor.C0 = rotorMotor.C0 * CFrame.Angles(0, 0, math.rad(displayRpm * dt * 6))
	elseif kitBlades and not Twist then
		kitBlades:PivotTo(kitBlades:GetPivot() * CFrame.Angles(0, 0, math.rad(displayRpm * dt * 6)))
	end
end)
