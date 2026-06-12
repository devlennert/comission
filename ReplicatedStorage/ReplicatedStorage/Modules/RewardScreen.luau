--[[
	This module handles the reward screen that appears when the player unlocks a new item.
	Its purpose is to provide only visual effects and and NOT backend services
	
	Things it does do:
	- Provide a visually appealing interface animations
	
	Things it doesn't do:
	- Amount of items unlocked
	- Giving item to player
]]


local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Network = require(ReplicatedStorage:WaitForChild("Modules").Network)
local ChairInfo = require(ReplicatedStorage.Modules:WaitForChild("ChairInfo"))


local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CameraShaker = require(script.Parent.CameraShaker)

local template = script:WaitForChild("Template")
local unlockSound = script:WaitForChild("Unlock")

local screen = playerGui:WaitForChild("RewardScreen")
local bar = screen.Main.Bar
local bgEffects = screen.BackgroundEffects
local barFullSize = bar.Size
local templateSize = template.Size

local TWEEN_EXPAND = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_COLLAPSE = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local TWEEN_ITEM = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_BG = TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
local TWEEN_SLIDE_IN = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local TWEEN_SLIDE_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local active = false

local function slideFrameOut(frame)
	if not frame then return end
	frame:SetAttribute("_OriginalPos", frame.Position)
	TweenService:Create(frame, TWEEN_SLIDE_IN, {
		Position = UDim2.new(frame.Position.X.Scale, frame.Position.X.Offset, 1.2, 0)
	}):Play()
end

local function slideFrameBack(frame)
	if not frame then return end
	local pos = frame:GetAttribute("_OriginalPos")
	if not pos then return end
	TweenService:Create(frame, TWEEN_SLIDE_OUT, {
		Position = pos
	}):Play()
end

local function clearRewards()
	for _, child in bar:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function revealItems(rewards)
	for i, data in rewards do
		local clone = template:Clone()
		clone.Name = "Reward" .. i
		clone.Size = UDim2.new(0, 0, 0, 0)
		clone.Visible = true
		clone.Parent = bar

		if data.setup then
			data.setup(clone)
		end

		unlockSound.PlaybackSpeed = 1 + (i - 1) * 0.2
		unlockSound:Play()
		CameraShaker("Hard Bump")

		local tween = TweenService:Create(clone, TWEEN_ITEM, { Size = templateSize })
		tween:Play()
		tween.Completed:Wait()
	end
end

local RewardScreen = {}

function RewardScreen.Show(rewards)
	if active then return end
	active = true

	rewards = rewards or {{}, {}, {}}

	local testFrame = playerGui:WaitForChild("MainUI"):FindFirstChild("Test")

	screen.Enabled = true
	bar.Visible = true
	bar.Rotation = 0
	bar.Size = UDim2.new(0.05, 0, 0.01, 0)

	slideFrameOut(testFrame)
	TweenService:Create(bgEffects, TWEEN_BG, { GroupTransparency = 0.1 }):Play()

	local expandTween = TweenService:Create(bar, TWEEN_EXPAND, {
		Rotation = 2,
		Size = barFullSize
	})
	expandTween:Play()
	expandTween.Completed:Wait()

	revealItems(rewards)

	UserInputService.InputBegan:Wait()

	unlockSound:Stop()
	unlockSound.PlaybackSpeed = 1
	clearRewards()

	local collapseTween = TweenService:Create(bar, TWEEN_COLLAPSE, {
		Rotation = 0,
		Size = UDim2.new(barFullSize.X.Scale, barFullSize.X.Offset, 0, 0)
	})
	collapseTween:Play()
	collapseTween.Completed:Wait()

	TweenService:Create(bgEffects, TWEEN_BG, { GroupTransparency = 1 }):Play()
	slideFrameBack(testFrame)

	bar.Visible = false
	screen.Enabled = false
	active = false
end


local RARITY_COLORS = {
	Common    = Color3.fromRGB(180, 180, 180),
	Rare      = Color3.fromRGB(85,  155, 255),
	Legendary = Color3.fromRGB(255, 175,  50),
	Mythical  = Color3.fromRGB(200,  80, 255),
}

Network.onClient("ShowChairReward", function(chairName)
	local info = ChairInfo[chairName]
	if not info then
		warn("[ChairRewardHandler] No ChairInfo entry for:", chairName)
		return
	end

	RewardScreen.Show({
		{
			setup = function(frame)
				local main = frame:FindFirstChild("Main")
				if not main then return end

				local icon   = main:FindFirstChild("Icon")
				local rarity = main:FindFirstChild("Rarity")
				local title  = main:FindFirstChild("Title")

				if icon   then icon.Image       = info.ImageId              end
				if title  then title.Text        = info.Name                 end
				if rarity then
					rarity.Text      = info.Rarity
					rarity.TextColor3 = RARITY_COLORS[info.Rarity]
						or Color3.fromRGB(255, 255, 255)
				end
			end,
		},
	})
end)

return RewardScreen
