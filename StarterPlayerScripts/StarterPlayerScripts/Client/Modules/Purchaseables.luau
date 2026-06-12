local module = {}
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local DevProducts = require(ReplicatedStorage.Modules.DevProducts)
local Network = require(ReplicatedStorage.Modules.Network)
local Notification = require(script.Parent.Notification)
local Purchaseables = workspace.Map:WaitForChild("Purchaseables")


for i,prompt in Purchaseables:GetDescendants() do
	if prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function()
			if Network.request("OwnsChair", prompt:GetAttribute("ChairName")) == false then
				MarketplaceService:PromptProductPurchase(player, DevProducts[prompt:GetAttribute("ChairName")].ID)
			else
				Notification.Notify("You already own this chair!", "Warning")
			end
			
		end)
	end
end



return module