local module = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Network = require(ReplicatedStorage.Modules.Network)
local MarketplaceService = game:GetService("MarketplaceService")
local DevProducts = require(ReplicatedStorage.Modules.DevProducts)
local Player = game.Players.LocalPlayer
local PlayerGui = Player.PlayerGui
local UI = PlayerGui.UI
local ShopFrame = UI.Shop.Main

-- Fetch a product's price honoring REGIONAL PRICING. GetProductInfo runs in the
-- context of the requesting player, so PriceInRobux is the localized price the
-- buyer would actually be charged (not a hardcoded value). Cached so we don't
-- re-hit the web service if the shop is reopened.
local priceCache = {}
local function fetchPrice(productId)
	if priceCache[productId] ~= nil then return priceCache[productId] end
	local price
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)
	if ok and info and info.PriceInRobux then
		price = info.PriceInRobux
		priceCache[productId] = price
	end
	return price
end

-- Write the localized price into a frame's Btn.txt label (async so one slow
-- lookup doesn't stall the others).
local function applyPrice(frame, productId)
	local btn = frame:FindFirstChild("Btn")
	local txt = btn and btn:FindFirstChild("txt")
	if not txt then return end
	task.spawn(function()
		local price = fetchPrice(productId)
		if price then
			txt.Text = tostring(price)
		end
	end)
end

function module.SetShop()
	for _, passFrame in ShopFrame:GetChildren() do
		if not passFrame:IsA("Frame") then continue end
		local btn = passFrame:FindFirstChild("Btn")
		if not btn then continue end

		local passName = passFrame.Name
		local passInfo = DevProducts[passName]

		if not passInfo then
			local noSpace = passName:gsub(" ", "")
			passInfo = DevProducts[noSpace]
		end

		if passInfo then
			if passInfo.Type == "Cash" then
				passFrame.PassName.Text = passInfo.Amount .. " Cash"
			end
			applyPrice(passFrame, passInfo.ID)  -- show the buyer's localized price
			btn.MouseButton1Click:Connect(function()
				MarketplaceService:PromptProductPurchase(Player, passInfo.ID)
			end)
		end
	end
end

-- Expose the price fetcher so other shop UIs (roll buttons, etc.) can reuse it.
function module.GetLocalizedPrice(productId)
	return fetchPrice(productId)
end

UI.DailyRewards.Skip.Btn.MouseButton1Click:Connect(function()
	MarketplaceService:PromptProductPurchase(Player, DevProducts["Skip"].ID)
end)

module.SetShop()

return module
