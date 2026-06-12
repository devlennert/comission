-- Chairs (Client)
local module = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Network = require(ReplicatedStorage.Modules.Network)
local ChairInfo = require(ReplicatedStorage.Modules.ChairInfo)
local Player = game.Players.LocalPlayer
local PlayerGui = Player.PlayerGui
local UI = PlayerGui.UI
local ChairsFrame = UI.Chairs
local ScrollingFrame = ChairsFrame.Main.Frame.ScrollingFrame
local ChairTemplate = ScrollingFrame.ChairTemplate
local RARITY_COLORS = {
	Common    = Color3.fromRGB(160, 160, 160),
	Rare      = Color3.fromRGB(50,  120, 220),
	Legendary = Color3.fromRGB(180,  80, 220),
	Mythical  = Color3.fromRGB(220,  50,  50),
}
local function UpdateChairs()
	local ownedChairs = Player.Chairs:GetChildren()
	local equippedChair = Player.EquippedChair.Value
	for _, child in ipairs(ScrollingFrame:GetChildren()) do
		if child:IsA("Frame") and child ~= ChairTemplate then
			child:Destroy()
		end
	end
	for _, chair in ipairs(ownedChairs) do
		local chairName = chair.Name
		local chairData = ChairInfo[chairName]
		if chairData then
			local clone = ChairTemplate:Clone()
			clone.Name = chairName
			clone.Visible = true
			clone.ChairName.Text = chairName
			clone.ChairIcon.Image = chairData.ImageId or ""
			local rarityLabel = clone:FindFirstChild("ChairRarity")
			if rarityLabel then
				local rarity = chairData.Rarity or "Common"
				rarityLabel.Text = rarity
				rarityLabel.TextColor3 = RARITY_COLORS[rarity] or RARITY_COLORS.Common
			end
			local boostLabel = clone:FindFirstChild("ChairLuck")
			if boostLabel then
				boostLabel.Text = ChairInfo.GetBoostString(chairData)
			end
			local isEquipped = (equippedChair == chairName)
			local equipButton = clone:FindFirstChild("Equip")
			if isEquipped then
				equipButton.Image = "rbxassetid://74651458335208"
				equipButton.Activated:Connect(function()
					Network.send("EquipChair", nil)
				end)
			else
				equipButton.Activated:Connect(function()
					Network.send("EquipChair", chairName)
				end)
			end
			clone.Parent = ScrollingFrame
		end
	end
end
Network.onClient("UpdateChairs", UpdateChairs)
UpdateChairs()
return module