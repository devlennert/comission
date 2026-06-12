repeat task.wait() until game:IsLoaded()
repeat task.wait(0.5) until game.Players.LocalPlayer:FindFirstChild("PlayerGui"):FindFirstChild("UI")
repeat task.wait(0.5) until game.Players.LocalPlayer:FindFirstChild("leaderstats")
print("Client is fully loaded!")
game.StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
repeat
	local success = pcall(function() 
		game.StarterGui:SetCore("ResetButtonCallback", false) 
	end)
	task.wait(0.5)
until success 
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local UI = PlayerGui:WaitForChild("UI")
local Network = require(ReplicatedStorage.Modules.Network)
for i,module in script.Modules:GetChildren() do
	print(module)
	if module:IsA("ModuleScript") then
		task.spawn(function()
			local module2 = require(module)
			print(module)
		end)
	end
end
local Icon = require(ReplicatedStorage.Icon)
--local New = Icon.new()
--	:setName("Daily Rewards")
--	:setImage(82103447379785, "Deselected")
--	:setImage(129800503433419, "Selected")
--New:autoDeselect(false)
--New.toggled:Connect(function(isSelected)
--	UI.DailyRewards.Visible = isSelected
--end)
local Icon = require(game.ReplicatedStorage:WaitForChild("Icon"))
local MusicButton = Icon.new()
	:setName("Music  ")
	:setImage(14924003288, "Selected")
	:setImage(14924005719, "Deselected")
local Music = game.SoundService.Audio.Music
MusicButton:autoDeselect(false)
Music:Play()
MusicButton.toggled:Connect(function(isSelected)
	if isSelected then
		Music:Stop()
	else
		Music:Play()
	end
end)

local FriendBonus = Player:WaitForChild("FriendBonus")
UI.BoostLabel.Text = "Friend Boost: +" .. math.floor(FriendBonus.Value * 100) .. "%"
Network.send("Ready")
FriendBonus.Changed:Connect(function()
	UI.BoostLabel.Text = "Friend Boost: +" .. math.floor(FriendBonus.Value * 100) .. "%"
end)