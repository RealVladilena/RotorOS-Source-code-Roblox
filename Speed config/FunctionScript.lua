-- ============================================================
-- HYBRID CONTROLLER — POWER, RPM & OVERSPEED 
-- ============================================================
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 1. COURBE DE PUISSANCE
local PowerCurvesData
pcall(function()
	PowerCurvesData = require(ReplicatedStorage:WaitForChild("PowerCurvesLibrary", 5))
end)

-- 2. RACINE DE L'ÉOLIENNE
local TurbineRoot = script.Parent
while TurbineRoot and TurbineRoot.Parent and TurbineRoot.Parent ~= workspace do
	if TurbineRoot.Parent:IsA("Folder") or TurbineRoot:GetAttribute("IsTurbineRoot") then break end
	TurbineRoot = TurbineRoot.Parent
end
TurbineRoot:SetAttribute("IsWindTurbine", true)

-- Twist cache
local BladesFunc = script.Parent.Parent
local CF    = BladesFunc and BladesFunc:FindFirstChild("CF")
local Twist = CF and CF:FindFirstChild("Twist")
if Twist then Twist.BottomParamA = 0; Twist.BottomParamB = 0 end

-- 3. COURBE & STATS
local myCurve  = nil
local MAX_KW   = 4500
local MAX_RPM  = 17.5

local turbineName = TurbineRoot.Name
	:gsub(" %(start new%)", "")
	:gsub(" %d+$", "")

if PowerCurvesData then
	for modelName, curve in pairs(PowerCurvesData) do
		if turbineName:find(modelName, 1, true) then
			myCurve = curve
			TurbineRoot:SetAttribute("HasPowerCurve", true)
			if curve.MaxRPM then MAX_RPM = curve.MaxRPM end
			local last = curve[#curve]
			if last then MAX_KW = last.p end
			break
		end
	end
end

-- 4. PIÈCES (avec délai d'initialisation)
task.wait(1.5)
local yawUnion   = TurbineRoot:FindFirstChild("YAW Union", true) or TurbineRoot:FindFirstChild("YAW", true)
local nacelle    = TurbineRoot:FindFirstChild("Nacelle", true)
local kitBlades  = TurbineRoot:FindFirstChild("Wind Turbine KIT BLADES", true)
	or TurbineRoot:FindFirstChild("Rotor", true)
	or TurbineRoot:FindFirstChild("Blades", true)
local statusLight = TurbineRoot:FindFirstChild("StatusLight", true)
local rotorHinge  = TurbineRoot:FindFirstChild("HingeConstraint", true) or TurbineRoot:FindFirstChild("RotorHinge", true)
local rotorMotor  = TurbineRoot:FindFirstChild("RotorMotor", true)

-- Utilitaire : récupère ou crée une Value
local function getOrCreate(name, typeClass, default)
	local v = TurbineRoot:FindFirstChild(name)
	if not v then
		v = Instance.new(typeClass)
		v.Name, v.Value, v.Parent = name, default, TurbineRoot
	end
	return v
end

local isOnValue       = getOrCreate("IsOn",         "BoolValue",   true)
local stateValue      = getOrCreate("CurrentState", "StringValue", "STOPPED")
local timerValue      = getOrCreate("StormTimer",   "IntValue",    0)
local isManualPitchVal= getOrCreate("IsManualPitch","BoolValue",   false)

local manualPitches = {
	getOrCreate("ManualPitch1", "NumberValue", 91.7),
	getOrCreate("ManualPitch2", "NumberValue", 91.7),
	getOrCreate("ManualPitch3", "NumberValue", 91.7),
}

local bladeAngleVals = {
	script.Parent:FindFirstChild("BladeAngle1") or TurbineRoot:FindFirstChild("BladeAngle1", true),
	script.Parent:FindFirstChild("BladeAngle2") or TurbineRoot:FindFirstChild("BladeAngle2", true),
	script.Parent:FindFirstChild("BladeAngle3") or TurbineRoot:FindFirstChild("BladeAngle3", true),
}

-- 5. CONSTANTES
local INIT_PITCH        = 91.7
local IDLE_PITCH        = 70
local WIND_CUT_IN       = 3.0
local WIND_RATED        = 13.0
local WIND_CUT_OUT      = 25.0
local PS_START          = 1.0
local PS_REGULATE       = 2.5
local PS_STORM          = 4.0
local PS_STOP           = 3.0
local PS_EMERGENCY      = 8.0
local RPM_MIN_RATIO     = 0.35   -- ratio min de MAX_RPM au démarrage
local OVERSPEED_RATIO   = 1.15   -- seuil déclenchement overspeed
local LOGIC_TICK        = 0.1    -- intervalle cerveau (s)
local YAW_SPEED         = 2.0

-- 6. ÉTAT
local turbineState    = "STOPPED"
local currentPitches  = {INIT_PITCH, INIT_PITCH, INIT_PITCH}
local pitchTargets    = {INIT_PITCH, INIT_PITCH, INIT_PITCH}
local pitchSpeed      = PS_STOP
local displayPower    = 0
local displayRpm      = 0
local cooldownTimer   = 0
local startupPhase    = 0
local startupDelay    = 0
local logicTimer      = 0
local safeStartTimer  = 0

-- 7. YAW
local currentYawAngle   = 0
local yawInitialCFrame  = yawUnion and yawUnion.CFrame or CFrame.new()
local nacelleOffset     = CFrame.new()
local rotorRelativeOffset = CFrame.new()
local rotorBasePart     = nil

local localYawSpeed = YAW_SPEED + Random.new(
	yawUnion and math.floor(yawUnion.Position.X) or 1
):NextNumber(-0.5, 0.5)

local function getSafeCFrame(obj)
	if not obj then return CFrame.new() end
	if obj:IsA("Model") then return obj:GetPivot() end
	if obj:IsA("BasePart") then return obj.CFrame end
	return CFrame.new()
end

if yawUnion then
	if nacelle then
		local mp = nacelle:FindFirstChildWhichIsA("BasePart")
		nacelleOffset = yawInitialCFrame:ToObjectSpace(getSafeCFrame(mp or nacelle))
	end
	if kitBlades then
		rotorBasePart = kitBlades.PrimaryPart
			or kitBlades:FindFirstChild("Hub", true)
			or kitBlades:FindFirstChildWhichIsA("BasePart", true)
			or kitBlades
		if rotorBasePart then
			rotorRelativeOffset = yawInitialCFrame:ToObjectSpace(getSafeCFrame(rotorBasePart))
		end
	end
end

-- 8. SOURCES VENT
local globalWindCtrl = workspace:FindFirstChild("GlobalWindController")
local wSpeedVal = globalWindCtrl and globalWindCtrl:FindFirstChild("WindSpeed")
local wAngleVal = globalWindCtrl and globalWindCtrl:FindFirstChild("WindAngle")

-- Helper : interpolation linéaire sur la courbe de puissance
local function interpolatePower(wSpeed)
	if not myCurve then
		local r = math.clamp((wSpeed - WIND_CUT_IN) / (WIND_RATED - WIND_CUT_IN), 0, 1)
		return MAX_KW * r * r * (3 - 2 * r)
	end
	if wSpeed > myCurve[#myCurve].w then return MAX_KW end
	for j = 1, #myCurve - 1 do
		local a, b = myCurve[j], myCurve[j + 1]
		if wSpeed >= a.w and wSpeed <= b.w then
			return a.p + (b.p - a.p) * ((wSpeed - a.w) / (b.w - a.w))
		end
	end
	return 0
end

-- Helper : couleur du voyant selon l'état
local STATUS_COLORS = {
	RUNNING      = Color3.fromRGB(0, 255, 0),
	STARTING     = Color3.fromRGB(255, 170, 0),
	LACK_OF_WIND = Color3.fromRGB(200, 200, 200),
	COOLDOWN     = Color3.fromRGB(255, 255, 0),
	STOPPED      = Color3.fromRGB(255, 0, 0),
}

local function updateStatusLight(state)
	if not statusLight then return end
	statusLight.Material = Enum.Material.Neon
	if state == "OVERSPEED" then
		statusLight.Color = math.floor(tick() * 8) % 2 == 0
			and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 255, 255)
	elseif state == "STORM" then
		statusLight.Color = math.floor(tick() * 4) % 2 == 0
			and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(50, 0, 0)
	else
		statusLight.Color = STATUS_COLORS[state] or Color3.fromRGB(255, 0, 0)
	end
end

-- ============================================================
-- BOUCLE PRINCIPALE
-- ============================================================
RunService.Heartbeat:Connect(function(dt)
	safeStartTimer += dt
	logicTimer      += dt

	-- Lecture vent
	local wSpeed, wAngle = 0, 0
	if globalWindCtrl then
		wSpeed = wSpeedVal and wSpeedVal.Value or 0
		wAngle = wAngleVal and wAngleVal.Value or 0
	else
		local dir = workspace.GlobalWind
		wSpeed = dir.Magnitude
		wAngle = math.deg(math.atan2(dir.X, dir.Z))
	end

	local isEnabled = isOnValue.Value
	local avgPitch  = (currentPitches[1] + currentPitches[2] + currentPitches[3]) / 3

	-- ── YAW ──────────────────────────────────────────────────
	if yawUnion and nacelle and wSpeed >= 2 then
		local diff = ((wAngle - currentYawAngle) % 360)
		if diff > 180 then diff -= 360 end
		if math.abs(diff) > 2.0 then
			local step = math.sign(diff) * localYawSpeed * dt
			if math.abs(step) > math.abs(diff) then step = diff end
			currentYawAngle = (currentYawAngle + step) % 360

			local newYaw = CFrame.new(yawInitialCFrame.Position) * CFrame.Angles(0, math.rad(currentYawAngle), 0)
			yawUnion.CFrame = newYaw
			nacelle:PivotTo(newYaw * nacelleOffset)

			if rotorBasePart and safeStartTimer > 1.5 then
				local cf = getSafeCFrame(rotorBasePart)
				local orient = cf - cf.Position
				local pos = (newYaw * rotorRelativeOffset).Position
				local newCF = CFrame.new(pos) * orient
				if rotorBasePart:IsA("Model") then rotorBasePart:PivotTo(newCF)
				else rotorBasePart.CFrame = newCF end
			end
		end
	end

	-- ── CERVEAU (logique à taux réduit) ──────────────────────
	if logicTimer >= LOGIC_TICK then
		local ldt = logicTimer
		logicTimer = 0

		local pitchMax = math.max(
			math.abs(currentPitches[1] - currentPitches[2]),
			math.abs(currentPitches[2] - currentPitches[3]),
			math.abs(currentPitches[1] - currentPitches[3])
		)

		-- Détection overspeed
		if displayRpm > MAX_RPM * OVERSPEED_RATIO and turbineState == "RUNNING" then
			turbineState = "OVERSPEED"; cooldownTimer = 30
		end

		-- Machine à états
		if turbineState == "STOPPED" then
			if isEnabled then
				isManualPitchVal.Value = false
				if wSpeed >= WIND_CUT_IN and wSpeed < WIND_CUT_OUT then
					turbineState = "STARTING"; startupPhase = 0
				elseif wSpeed < WIND_CUT_IN and wSpeed > 0.5 then
					turbineState = "LACK_OF_WIND"
				end
			end

		elseif turbineState == "LACK_OF_WIND" then
			if not isEnabled then turbineState = "STOPPED"
			elseif wSpeed >= WIND_CUT_IN and wSpeed < WIND_CUT_OUT then turbineState = "STARTING"; startupPhase = 0
			elseif wSpeed > WIND_CUT_OUT then turbineState = "STORM"; cooldownTimer = 30 end

		elseif turbineState == "STARTING" then
			if not isEnabled then turbineState = "STOPPED"
			elseif wSpeed > WIND_CUT_OUT then turbineState = "STORM"; cooldownTimer = 30
			elseif wSpeed < WIND_CUT_IN then turbineState = "LACK_OF_WIND"
			elseif startupPhase == 5 and avgPitch <= 1.0 then turbineState = "RUNNING" end

		elseif turbineState == "RUNNING" then
			if not isEnabled then turbineState = "STOPPED"
			elseif wSpeed > WIND_CUT_OUT then turbineState = "STORM"; cooldownTimer = 30
			elseif wSpeed < WIND_CUT_IN then turbineState = "LACK_OF_WIND" end

		elseif turbineState == "STORM" or turbineState == "OVERSPEED" then
			cooldownTimer = math.max(cooldownTimer - ldt, 0)
			if cooldownTimer <= 0 then turbineState = "COOLDOWN" end
			if not isEnabled then turbineState = "STOPPED" end

		elseif turbineState == "COOLDOWN" then
			if not isEnabled then turbineState = "STOPPED"
			elseif wSpeed < WIND_CUT_OUT - 2 then
				turbineState = wSpeed >= WIND_CUT_IN and "STARTING" or "LACK_OF_WIND"
				if turbineState == "STARTING" then startupPhase = 0 end
			end
		end

		stateValue.Value  = turbineState
		timerValue.Value  = math.ceil(cooldownTimer)

		-- ── CIBLES PITCH ──────────────────────────────────────
		local function setAllPitch(p, speed)
			pitchTargets[1] = p; pitchTargets[2] = p; pitchTargets[3] = p
			pitchSpeed = speed
		end

		if turbineState == "RUNNING" then
			local reg = wSpeed >= WIND_RATED
				and (25 * math.clamp((wSpeed - WIND_RATED) / (WIND_CUT_OUT - WIND_RATED), 0, 1))
				or 0
			setAllPitch(reg, PS_REGULATE)

		elseif turbineState == "STARTING" then
			pitchSpeed = PS_START
			if startupPhase == 0 then
				setAllPitch(INIT_PITCH, PS_START)
				if pitchMax < 0.5 and avgPitch >= INIT_PITCH - 0.5 then startupPhase = 1 end
			elseif startupPhase == 1 then
				setAllPitch(70, PS_START); if avgPitch <= 70.5 then startupPhase = 2; startupDelay = 20 end
			elseif startupPhase == 2 then
				startupDelay -= ldt; if startupDelay <= 0 then startupPhase = 3 end
			elseif startupPhase == 3 then
				setAllPitch(20, PS_START); if avgPitch <= 20.5 then startupPhase = 4; startupDelay = 15 end
			elseif startupPhase == 4 then
				startupDelay -= ldt; if startupDelay <= 0 then startupPhase = 5 end
			elseif startupPhase == 5 then
				setAllPitch(0, PS_START)
			end

		elseif turbineState == "LACK_OF_WIND" then setAllPitch(IDLE_PITCH, PS_STOP)
		elseif turbineState == "STORM"         then setAllPitch(INIT_PITCH, PS_STORM)
		elseif turbineState == "OVERSPEED"     then setAllPitch(INIT_PITCH, PS_EMERGENCY)
		elseif turbineState == "STOPPED" or turbineState == "COOLDOWN" then
			if isManualPitchVal.Value then
				pitchTargets[1] = manualPitches[1].Value
				pitchTargets[2] = manualPitches[2].Value
				pitchTargets[3] = manualPitches[3].Value
			else
				setAllPitch(INIT_PITCH, PS_STOP)
			end
		end

		-- ── PRODUCTION ────────────────────────────────────────
		local targetPower = 0
		if (turbineState == "RUNNING" or turbineState == "STARTING") and avgPitch <= 20.0 then
			targetPower = interpolatePower(wSpeed)
			targetPower *= Random.new():NextNumber(0.99, 1.01)
		end
		local powerStep = MAX_KW / 20 * ldt
		if targetPower > displayPower then
			displayPower = math.min(displayPower + powerStep, targetPower)
		elseif targetPower < displayPower then
			displayPower = math.max(displayPower - powerStep, targetPower)
		end
		if displayPower < 2 then displayPower = 0 end

		-- ── ATTRIBUTS (batch) ─────────────────────────────────
		TurbineRoot:SetAttribute("CurrentYaw",   currentYawAngle)
		TurbineRoot:SetAttribute("RealWindSpeed", wSpeed * 3.6)
		TurbineRoot:SetAttribute("CurrentRPM",   displayRpm)
		TurbineRoot:SetAttribute("CurrentPower", displayPower)
		TurbineRoot:SetAttribute("MaxPowerVal",  MAX_KW)
		TurbineRoot:SetAttribute("MaxRPMVal",    MAX_RPM)

		updateStatusLight(turbineState)
	end

	-- ── ANIMATION PITCH (chaque frame) ───────────────────────
	local pitchStep = pitchSpeed * dt
	for i = 1, 3 do
		local diff = pitchTargets[i] - currentPitches[i]
		currentPitches[i] = math.abs(diff) < pitchStep
			and pitchTargets[i]
			or currentPitches[i] + math.sign(diff) * pitchStep
		if bladeAngleVals[i] then bladeAngleVals[i].Value = currentPitches[i] end
	end

	-- ── CALCUL RPM ───────────────────────────────────────────
	-- RPM idéal selon le vent
	local windRatio = math.clamp((wSpeed - WIND_CUT_IN) / (WIND_RATED - WIND_CUT_IN), 0.1, 1)
	local idealRpm  = MAX_RPM * RPM_MIN_RATIO + (MAX_RPM * (1 - RPM_MIN_RATIO)) * windRatio

	local targetRpm = 0
	if turbineState == "RUNNING" then
		targetRpm = idealRpm
	elseif turbineState == "STARTING" and startupPhase >= 3 then
		targetRpm = idealRpm * math.clamp(1 - (avgPitch / INIT_PITCH), 0, 1)
	elseif turbineState == "LACK_OF_WIND" then
		targetRpm = math.clamp(wSpeed, 0, 3)
	else
		targetRpm = wSpeed >= 3.0 and math.clamp(wSpeed * 0.2, 0.5, 2.5) or 0
	end

	-- Frein mécanique si pale fermée et hors rotation active
	if avgPitch > 45
		and turbineState ~= "RUNNING" and turbineState ~= "STARTING"
		and turbineState ~= "STOPPED" and turbineState ~= "STORM"
		and turbineState ~= "OVERSPEED"
	then
		targetRpm *= math.clamp(1 - (avgPitch - 45) / 46.7, 0, 1)
	end

	-- Décélération selon l'état
	if turbineState == "OVERSPEED" then
		displayRpm = math.max(displayRpm - displayRpm * dt * 0.8, 0)
	elseif turbineState == "STORM" or turbineState == "STOPPED" then
		targetRpm  = 0
		displayRpm = math.max(displayRpm - displayRpm * dt * 0.4, 0)
	else
		displayRpm += (targetRpm - displayRpm) * dt * 0.15
	end

	-- ── VISUEL ROTOR ─────────────────────────────────────────
	if Twist then
		local s = -(displayRpm / MAX_RPM) * 45.0
		Twist.BottomParamA = s; Twist.BottomParamB = s

	elseif rotorHinge and rotorHinge:IsA("HingeConstraint") then
		rotorHinge.ActuatorType   = Enum.ActuatorType.Motor
		rotorHinge.AngularVelocity = displayRpm * 0.10472

	elseif rotorMotor and (rotorMotor:IsA("Motor6D") or rotorMotor:IsA("Weld")) then
		rotorMotor.C0 = rotorMotor.C0 * CFrame.Angles(0, 0, math.rad(displayRpm * dt * 6))

	elseif kitBlades then
		kitBlades:PivotTo(kitBlades:GetPivot() * CFrame.Angles(0, 0, math.rad(displayRpm * dt * 6)))
	end
end)