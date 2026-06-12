local module = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = player.PlayerGui
local UI = PlayerGui:WaitForChild("UI")
local MainUI = PlayerGui:WaitForChild("MainUI")
local Network = require(ReplicatedStorage.Modules.Network)
local Animate = require(ReplicatedStorage.Modules.Animate)
local JumpscareImage = MainUI.Jumpscare

local function getCamera()
	while not workspace.CurrentCamera do
		workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
	end
	return workspace.CurrentCamera
end

function module.Jumpscare()
	JumpscareImage.Visible = true
	local jumpSound = Instance.new("Sound")
	jumpSound.SoundId = "rbxassetid://114342167442853"
	jumpSound.Volume = 1
	jumpSound.Parent = SoundService
	jumpSound:Play()
	game:GetService("Debris"):AddItem(jumpSound, 5)
	local camera = getCamera()
	Animate.ShakeCamera(camera, 1.5, 1)
	task.wait(1)
	JumpscareImage.Visible = false
end

function module.RestoreHiddenButtons()
end

Network.onClient("Jumpscare", function()
	module.Jumpscare()
end)

return module