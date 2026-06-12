local module = {}
local UI = game.Players.LocalPlayer.PlayerGui:WaitForChild("MainUI")
local OTHERUI = game.Players.LocalPlayer.PlayerGui:WaitForChild("UI")
local Network = require(game.ReplicatedStorage.Modules.Network)
local Utils = require(game.ReplicatedStorage.Modules.Utils)
local MarketplaceService = game:GetService("MarketplaceService")
local DevProducts = require(game.ReplicatedStorage.Modules.DevProducts)

local MonFrame = UI.Monetization

for i, btn in MonFrame:GetChildren() do
	if btn:IsA("ImageButton") and DevProducts[btn.Name] then
		local productId = DevProducts[btn.Name].ID
		btn.MouseButton1Click:Connect(function()
			MarketplaceService:PromptProductPurchase(game.Players.LocalPlayer, productId)
		end)
		
	end
end

OTHERUI.ServerOPRoll.MouseButton1Click:Connect(function()
	MarketplaceService:PromptProductPurchase(game.Players.LocalPlayer,DevProducts["ServerOPRoll"].ID)
end)
OTHERUI.ServerSuperOPRoll.MouseButton1Click:Connect(function()
	MarketplaceService:PromptProductPurchase(game.Players.LocalPlayer,DevProducts["ServerSuperOPRoll"].ID)
end)



return module
