-- ============================================================
-- SERVER HANDLER — Ordre Strict des Arguments Fixé
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Event = ReplicatedStorage:FindFirstChild("TurbineControlEvent")
if not Event then
	Event = Instance.new("RemoteEvent")
	Event.Name = "TurbineControlEvent"
	Event.Parent = ReplicatedStorage
end

-- FORMAT STRICT: (action, target, data1, data2)
Event.OnServerEvent:Connect(function(player, action, target, data1, data2)

	local targetList = {}
	if target == "ALL" then
		for _, obj in ipairs(workspace:GetDescendants()) do
			if obj:IsA("BoolValue") and obj.Name == "IsOn" then
				table.insert(targetList, obj.Parent)
			end
		end
	elseif target and typeof(target) == "Instance" then
		table.insert(targetList, target)
	end

	if action == "TogglePower" then
		for _, t in ipairs(targetList) do
			local onVal = t:FindFirstChild("IsOn", true)
			if onVal then onVal.Value = data1 end -- data1 est le booléen (On/Off)
		end

	elseif action == "SetWindSpeed" then
		for _, f in ipairs(workspace:GetDescendants()) do
			if f.Name == "GlobalWindController" and f:FindFirstChild("WindSpeed") then f.WindSpeed.Value = data1 end
		end

	elseif action == "SetWindAngle" then
		for _, f in ipairs(workspace:GetDescendants()) do
			if f.Name == "GlobalWindController" and f:FindFirstChild("WindAngle") then f.WindAngle.Value = data1 end
		end

	elseif action == "SetManualPitch" then
		for _, t in ipairs(targetList) do
			-- 🟢 ASTUCE CONFORT : Si on force le Pitch, on éteint la machine automatiquement
			local onVal = t:FindFirstChild("IsOn", true)
			if onVal then onVal.Value = false end 

			local isManual = t:FindFirstChild("IsManualPitch", true)
			if isManual then
				isManual.Value = true
				if data2 == 0 or data2 == 1 then local m = t:FindFirstChild("ManualPitch1", true) if m then m.Value = data1 end end
				if data2 == 0 or data2 == 2 then local m = t:FindFirstChild("ManualPitch2", true) if m then m.Value = data1 end end
				if data2 == 0 or data2 == 3 then local m = t:FindFirstChild("ManualPitch3", true) if m then m.Value = data1 end end
			end
		end

	elseif action == "ResetPitch" then
		for _, t in ipairs(targetList) do
			local isManual = t:FindFirstChild("IsManualPitch", true)
			if isManual then isManual.Value = false end
		end
	end
end)
