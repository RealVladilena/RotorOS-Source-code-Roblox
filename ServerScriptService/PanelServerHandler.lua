-- ============================================================
-- SERVER HANDLER 
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Event = ReplicatedStorage:FindFirstChild("TurbineControlEvent")
if not Event then
	Event = Instance.new("RemoteEvent")
	Event.Name  = "TurbineControlEvent"
	Event.Parent = ReplicatedStorage
end

-- Cache du GlobalWindController — cherché une seule fois, pas à chaque event
local windCtrl = workspace:FindFirstChild("GlobalWindController")
	or workspace:WaitForChild("GlobalWindController", 10)
local wSpeedVal = windCtrl and windCtrl:FindFirstChild("WindSpeed")
local wAngleVal = windCtrl and windCtrl:FindFirstChild("WindAngle")

-- Si le controller apparaît plus tard (cas rare)
if not windCtrl then
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "GlobalWindController" then
			windCtrl   = child
			wSpeedVal  = child:WaitForChild("WindSpeed",  5)
			wAngleVal  = child:WaitForChild("WindAngle",  5)
		end
	end)
end

local function applyToTargets(target, fn)
	if target == "ALL" then
		for _, obj in ipairs(workspace:GetDescendants()) do
			if obj:IsA("BoolValue") and obj.Name == "IsOn" then
				fn(obj.Parent)
			end
		end
	elseif target and typeof(target) == "Instance" then
		fn(target)
	end
end

Event.OnServerEvent:Connect(function(_player, action, target, data1, data2)
	if action == "TogglePower" then
		applyToTargets(target, function(t)
			local v = t:FindFirstChild("IsOn", true)
			if v then v.Value = data1 end
		end)

	elseif action == "SetWindSpeed" then
		if wSpeedVal then wSpeedVal.Value = data1 end

	elseif action == "SetWindAngle" then
		if wAngleVal then wAngleVal.Value = data1 end

	elseif action == "SetManualPitch" then
		applyToTargets(target, function(t)
			local onVal = t:FindFirstChild("IsOn", true)
			if onVal then onVal.Value = false end

			local isManual = t:FindFirstChild("IsManualPitch", true)
			if not isManual then return end
			isManual.Value = true

			-- data2 : 0=tous, 1=pale1, 2=pale2, 3=pale3
			for i = 1, 3 do
				if data2 == 0 or data2 == i then
					local m = t:FindFirstChild("ManualPitch" .. i, true)
					if m then m.Value = data1 end
				end
			end
		end)

	elseif action == "ResetPitch" then
		applyToTargets(target, function(t)
			local isManual = t:FindFirstChild("IsManualPitch", true)
			if isManual then isManual.Value = false end
		end)
	end
end)