--[[
	TimerCinematicCamera (LocalScript)
	When the local player sits in a timer-table seat (a Seat1/Seat2 inside a
	TableGroup that contains a TimerRig), the camera smoothly glides into a slow
	orbit around the table. Standing up, dying, or being removed from the seat
	restores normal camera control.
]]

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local Workspace   = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ── Tunables ──────────────────────────────────────────────────────────────
local ORBIT_SPEED = math.rad(8)   -- rotation speed (radians/sec) ~ full loop in 45s
local RADIUS      = 14            -- horizontal distance from table center
local HEIGHT      = 9             -- camera height above table center
local LOOK_HEIGHT = 2             -- look slightly above the tabletop / at the rig
local EASE_TIME   = 0.85          -- seconds to smoothly glide into the orbit
local CINEMATIC_FOV = nil         -- set e.g. 60 for a tighter cinematic look, or nil to keep default
-- ──────────────────────────────────────────────────────────────────────────

local orbitConn = nil
local active    = false
local savedFOV  = nil

local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Returns the TableGroup if `seat` is a valid timer-table seat, else nil.
local function timerGroupFromSeat(seat)
	if not seat then return nil end
	if seat.Name ~= "Seat1" and seat.Name ~= "Seat2" then return nil end
	local group = seat.Parent
	if not group then return nil end
	if not group:FindFirstChild("TimerRig") then return nil end
	return group
end

local function getTableCenter(group)
	local t = group:FindFirstChild("table")
	if t and t:IsA("Model") then
		local cf = t:GetBoundingBox()
		return cf.Position
	end
	local rig = group:FindFirstChild("TimerRig")
	if rig then return rig:GetPivot().Position end
	return group:GetPivot().Position
end

local function stopCinematic()
	if orbitConn then orbitConn:Disconnect(); orbitConn = nil end
	if not active then return end
	active = false
	camera.CameraType = Enum.CameraType.Custom
	if savedFOV then camera.FieldOfView = savedFOV; savedFOV = nil end
end

local function startCinematic(group)
	if player:GetAttribute("InDuel") then return end  -- duel controls the camera
	stopCinematic()
	active = true

	camera = Workspace.CurrentCamera
	local center = getTableCenter(group)
	local lookAt = center + Vector3.new(0, LOOK_HEIGHT, 0)

	-- Begin the orbit at the camera's current angle for a seamless handoff.
	local startVec = camera.CFrame.Position - center
	local angle = math.atan2(startVec.Z, startVec.X)
	local startCF = camera.CFrame

	if CINEMATIC_FOV then
		savedFOV = camera.FieldOfView
		camera.FieldOfView = CINEMATIC_FOV
	end
	camera.CameraType = Enum.CameraType.Scriptable

	local elapsed = 0
	local lastT = os.clock()
	orbitConn = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = now - lastT
		lastT = now
		elapsed += dt
		angle += ORBIT_SPEED * dt

		local pos = center + Vector3.new(math.cos(angle) * RADIUS, HEIGHT, math.sin(angle) * RADIUS)
		local targetCF = CFrame.lookAt(pos, lookAt)

		if elapsed < EASE_TIME then
			camera.CFrame = startCF:Lerp(targetCF, smoothstep(elapsed / EASE_TIME))
		else
			camera.CFrame = targetCF
		end
	end)
end

local function hookCharacter(char)
	local hum = char:WaitForChild("Humanoid")
	hum.Seated:Connect(function(isSeated, seat)
		if isSeated then
			local group = timerGroupFromSeat(seat)
			if group then
				startCinematic(group)
			else
				stopCinematic()
			end
		else
			stopCinematic()
		end
	end)
	hum.Died:Connect(stopCinematic)
end

player.CharacterAdded:Connect(hookCharacter)
if player.Character then hookCharacter(player.Character) end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if Workspace.CurrentCamera then camera = Workspace.CurrentCamera end
end)

-- While a duel is running, the duel system owns the camera; pause the orbit and
-- resume it afterwards if the player is still seated at a timer table.
player:GetAttributeChangedSignal("InDuel"):Connect(function()
	if player:GetAttribute("InDuel") then
		stopCinematic()
	else
		local char  = player.Character
		local hum   = char and char:FindFirstChildOfClass("Humanoid")
		local group = timerGroupFromSeat(hum and hum.SeatPart)
		if group then startCinematic(group) end
	end
end)
