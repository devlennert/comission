local SoundModule = {}
local SoundService = game:GetService("SoundService")
local soundEffectsFolder = SoundService:WaitForChild("SoundEffects")
local activeSounds = {} -- Track arrays of sound instances by name
local nextSoundId = 0

function SoundModule.PlaySound(soundName, options)
	local soundAsset = soundEffectsFolder:FindFirstChild(soundName)
	if not soundAsset then
		warn("Sound not found: " .. soundName)
		return
	end

	options = options or {}
	local totalTime = options.totalTime
	local startTime = options.startTime or 0
	local volume = options.volume or soundAsset.Volume or 0.5
	local pitch = options.pitch or 1
	local looped = options.looped or false
	local parent = options.parent or SoundService
	local override = options.override

	-- DEFAULT BEHAVIOR: Stop existing instances of the same sound
	-- Set override to true if not explicitly specified
	if override == nil then
		override = true
	end

	-- Handle override
	if override then
		local soundsToStop = {}
		if type(override) == "string" then
			table.insert(soundsToStop, override)
		elseif type(override) == "table" then
			soundsToStop = override
		elseif override == true then
			table.insert(soundsToStop, soundName)
		end

		for _, nameToStop in ipairs(soundsToStop) do
			SoundModule.StopSound(nameToStop)
		end
	end

	-- Create sound instance
	local sound = Instance.new("Sound")
	sound.SoundId = soundAsset.SoundId or "rbxassetid://" .. soundAsset.Value
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.Looped = looped
	sound.TimePosition = startTime
	sound.Parent = parent

	-- Generate unique ID for this instance
	nextSoundId = nextSoundId + 1
	local soundId = nextSoundId

	-- Track this sound
	local soundData = {
		sound = sound,
		id = soundId,
		endedConnection = nil,
		cleanupTask = nil
	}

	-- Initialize array if needed
	if not activeSounds[soundName] then
		activeSounds[soundName] = {}
	end
	activeSounds[soundName][soundId] = soundData

	-- Cleanup function
	local function cleanup()
		if activeSounds[soundName] and activeSounds[soundName][soundId] == soundData then
			-- Disconnect events and cancel tasks
			if soundData.endedConnection then
				soundData.endedConnection:Disconnect()
				soundData.endedConnection = nil
			end
			if soundData.cleanupTask then
				task.cancel(soundData.cleanupTask)
				soundData.cleanupTask = nil
			end

			-- Destroy sound
			if sound and sound.Parent then
				sound:Destroy()
			end

			-- Remove from tracking
			activeSounds[soundName][soundId] = nil

			-- Clean up empty table
			if next(activeSounds[soundName]) == nil then
				activeSounds[soundName] = nil
			end
		end
	end

	-- Handle totalTime or natural ending
	if totalTime then
		soundData.cleanupTask = task.delay(totalTime, cleanup)
	elseif not looped then
		soundData.endedConnection = sound.Ended:Connect(cleanup)
	end

	sound:Play()

	return sound
end

-- Stop all instances of a sound by name
function SoundModule.StopSound(soundName)
	local soundInstances = activeSounds[soundName]
	if not soundInstances then
		return
	end

	-- Stop all instances of this sound
	for soundId, soundData in pairs(soundInstances) do
		local sound = soundData.sound

		-- Disconnect events
		if soundData.endedConnection then
			soundData.endedConnection:Disconnect()
		end

		-- Cancel delayed cleanup
		if soundData.cleanupTask then
			task.cancel(soundData.cleanupTask)
		end

		-- Stop and destroy the sound
		if sound and sound.Parent then
			sound:Stop()
			sound:Destroy()
		end
	end

	-- Remove all instances
	activeSounds[soundName] = nil
end

-- Stop all tracked sounds
function SoundModule.StopAllSounds()
	for soundName, _ in pairs(activeSounds) do
		SoundModule.StopSound(soundName)
	end
end

_G.PlaySound = SoundModule.PlaySound
return SoundModule