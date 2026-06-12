--[[
	RewardClient
	Handles UI popups, billboard updates, and sound effects for the Free Reward system
	Parent: StarterPlayerScripts
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for RemoteEvent
local ObbyRewardUI = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RemoteEvents"):WaitForChild("ObbyRewardUI")

-- Wait for ObbyWinner and its children
local ObbyWinner = workspace:WaitForChild("ObbyWinner", 10)
if not ObbyWinner then
	warn("[RewardClient] ObbyWinner not found!")
	return
end

-- Get BillboardGuis (structure: ObbyWinner > Part > BillboardGui > TextLabel)
local freeRewardPart = ObbyWinner:WaitForChild("FREE REWARDS", 5)
local timerPart = ObbyWinner:WaitForChild("Timer", 5)

local freeRewardGui = freeRewardPart and freeRewardPart:FindFirstChild("BillboardGui")
local timerGui = timerPart and timerPart:FindFirstChild("BillboardGui")

-- Find TextLabels inside BillboardGuis
local function findTextLabel(gui)
	if not gui then return nil end
	return gui:FindFirstChildWhichIsA("TextLabel", true)
end

local freeRewardLabel = findTextLabel(freeRewardGui)
local timerLabel = findTextLabel(timerGui)

-- Sound references
local claimSound = ObbyWinner:WaitForChild("ClaimSound", 5)
local readySound = ObbyWinner:WaitForChild("ReadySound", 5)
local errorSound = ObbyWinner:WaitForChild("ErrorSound", 5)

-- State tracking
local cooldownEndTime = 0
local timerConnection = nil
local isReady = false
local hasPlayedReadySound = false

--[[ UTILITY FUNCTIONS ]]

-- Format seconds as M:SS
local function formatTime(seconds)
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%d:%02d", mins, secs)
end

-- Bounce/pulse tween on a TextLabel
local function playBounceAnimation(label)
	if not label then return end
	
	local originalSize = label.Size
	
	-- Scale up
	local tweenUp = TweenService:Create(label, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(originalSize.X.Scale * 1.3, originalSize.X.Offset, originalSize.Y.Scale * 1.3, originalSize.Y.Offset)
	})
	
	-- Scale back down
	local tweenDown = TweenService:Create(label, TweenInfo.new(0.2, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
		Size = originalSize
	})
	
	tweenUp:Play()
	tweenUp.Completed:Connect(function()
		tweenDown:Play()
	end)
end

--[[ BILLBOARD UPDATE FUNCTIONS ]]

local function setReadyState()
	isReady = true
	
	-- Hide timer
	if timerGui then
		timerGui.Enabled = false
	end
	
	-- Update FREE REWARD text
	if freeRewardLabel then
		freeRewardLabel.Text = "REWARD READY!"
		freeRewardLabel.TextColor3 = Color3.fromRGB(100, 255, 100) -- Green
		playBounceAnimation(freeRewardLabel)
	end
	
	-- Play ready sound (only once per ready state)
	if not hasPlayedReadySound and readySound then
		readySound:Play()
		hasPlayedReadySound = true
	end
end

local function setCooldownState(remaining)
	isReady = false
	hasPlayedReadySound = false
	
	-- Show timer
	if timerGui then
		timerGui.Enabled = true
	end
	if timerLabel then
		timerLabel.Text = formatTime(remaining)
	end
	
	-- Reset FREE REWARD text
	if freeRewardLabel then
		freeRewardLabel.Text = "FREE REWARD"
		freeRewardLabel.TextColor3 = Color3.fromRGB(255, 255, 255) -- White
	end
end

local function updateTimerDisplay()
	local remaining = cooldownEndTime - os.clock()
	
	if remaining <= 0 then
		-- Timer finished - reward is ready!
		if not isReady then
			setReadyState()
		end
		
		-- Stop the update loop
		if timerConnection then
			timerConnection:Disconnect()
			timerConnection = nil
		end
	else
		-- Still counting down
		setCooldownState(remaining)
	end
end

--[[ POPUP SYSTEM ]]

-- Create a temporary ScreenGui for popups
local function createPopupGui()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ObbyRewardPopup"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 100
	screenGui.Parent = playerGui
	return screenGui
end

-- Show a popup message with cartoony tween animation
local function showPopup(message, color, duration, customFont)
	local gui = createPopupGui()
	
	-- Create the text label
	local label = Instance.new("TextLabel")
	label.Name = "PopupLabel"
	label.Size = UDim2.new(0.7, 0, 0.15, 0)
	label.Position = UDim2.new(0.5, 0, 0.35, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Text = message
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = customFont or Enum.Font.GothamBlack
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	
	-- Add UIStroke for extra pop
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 3
	stroke.Transparency = 0.5
	stroke.Parent = label
	
	-- Add UIScale for bounce animation (starts small)
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0
	uiScale.Parent = label
	
	-- Bounce IN animation (pop effect)
	local tweenIn = TweenService:Create(uiScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1
	})
	tweenIn:Play()
	
	-- Slight float up while visible
	task.delay(0.35, function()
		local floatTween = TweenService:Create(label, TweenInfo.new(duration - 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0.32, 0)
		})
		floatTween:Play()
	end)
	
	-- Fade OUT animation
	task.delay(duration - 0.3, function()
		local tweenOut = TweenService:Create(uiScale, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Scale = 0
		})
		
		local textFade = TweenService:Create(label, TweenInfo.new(0.3), {
			TextTransparency = 1,
			TextStrokeTransparency = 1
		})
		
		local strokeOut = TweenService:Create(stroke, TweenInfo.new(0.3), {
			Transparency = 1
		})
		
		tweenOut:Play()
		textFade:Play()
		strokeOut:Play()
		
		tweenOut.Completed:Wait()
		gui:Destroy()
	end)
end

--[[ START COOLDOWN COUNTDOWN ]]

local function startCooldownDisplay(duration)
	cooldownEndTime = os.clock() + duration
	isReady = false
	hasPlayedReadySound = false
	
	-- Stop existing connection
	if timerConnection then
		timerConnection:Disconnect()
		timerConnection = nil
	end
	
	-- Update immediately
	updateTimerDisplay()
	
	-- Update every frame for smooth countdown
	timerConnection = RunService.Heartbeat:Connect(function()
		updateTimerDisplay()
	end)
end

--[[ REMOTE EVENT HANDLER ]]

ObbyRewardUI.OnClientEvent:Connect(function(action, data)
	if action == "CooldownStart" then
		-- Server tells us to start/reset the cooldown timer
		startCooldownDisplay(data)
		
	elseif action == "NotReady" then
		-- Player touched before ready - show time remaining
		local timeStr = formatTime(data)
		
		-- Play error sound
		if errorSound then
			errorSound:Play()
		end
		
		-- Show popup with red color and PressStart2P font
		showPopup("Not ready yet — claim in " .. timeStr, Color3.fromRGB(255, 60, 60), 2.5, Enum.Font.PressStart2P)
		
		-- Also sync our local timer with server's remaining time
		cooldownEndTime = os.clock() + data
		
	elseif action == "Claimed" then
		-- Player successfully claimed the reward!
		
		-- Play claim sound
		if claimSound then
			claimSound:Play()
		end
		
		-- Show +50 Cash popup with green color
		showPopup("+" .. tostring(data) .. " Cash", Color3.fromRGB(85, 255, 127), 2.5)
		
		-- Bounce animation on the billboard
		if freeRewardLabel then
			playBounceAnimation(freeRewardLabel)
		end
	end
end)

print("[RewardClient] Free Reward client initialized!")
