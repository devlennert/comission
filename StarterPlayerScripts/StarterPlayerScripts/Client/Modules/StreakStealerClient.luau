local module = {}

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")
local TweenService       = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local PlayerGui   = localPlayer.PlayerGui
local Network     = require(ReplicatedStorage.Modules.Network)
local MainUI      = PlayerGui:WaitForChild("MainUI")

local PROMPT_DISTANCE = 12
local PROMPT_HOLD     = 0

-- Product IDs come from the DevProducts module so they can never drift from
-- the server's config again. Tiered by the TARGET's cash.
local DevProducts = require(ReplicatedStorage.Modules:WaitForChild("DevProducts"))
local STEAL_CASH_PRODUCTS = {
	{ threshold = 5000,      id = DevProducts["StealCash1"] and DevProducts["StealCash1"].ID },
	{ threshold = 50000,     id = DevProducts["StealCash2"] and DevProducts["StealCash2"].ID },
	{ threshold = 200000,    id = DevProducts["StealCash3"] and DevProducts["StealCash3"].ID },
	{ threshold = math.huge, id = DevProducts["StealCash4"] and DevProducts["StealCash4"].ID },
}

local function getProductForCash(cash)
	for _, tier in ipairs(STEAL_CASH_PRODUCTS) do
		if cash < tier.threshold then
			return tier.id
		end
	end
	return STEAL_CASH_PRODUCTS[#STEAL_CASH_PRODUCTS].id
end

local function showPopup(text, color)
	local popup = Instance.new("TextLabel")
	popup.AnchorPoint      = Vector2.new(0.5, 0.5)
	popup.Position         = UDim2.new(0.5, 0, 0.35, 0)
	popup.Size             = UDim2.new(0.55, 0, 0.1, 0)
	popup.BackgroundTransparency = 1
	popup.Text             = text
	popup.TextColor3       = color or Color3.fromRGB(255, 200, 50)
	popup.Font             = Enum.Font.GothamBold
	popup.TextScaled       = true
	popup.ZIndex           = 50
	popup.TextTransparency = 1
	popup.Parent           = MainUI
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3; stroke.Color = Color3.new(0,0,0); stroke.Parent = popup
	TweenService:Create(popup,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{TextTransparency = 0}):Play()
	task.delay(2.5, function()
		TweenService:Create(popup, TweenInfo.new(0.4), {TextTransparency = 1}):Play()
		task.wait(0.45)
		if popup and popup.Parent then popup:Destroy() end
	end)
end

-- [prompt] = ownerUserId — so we can find the right prompt when opponent changes
local promptByPlayer = {} -- [userId] = prompt
local matchOpponentId = nil -- UserId of current match opponent (nil = not in match)

local function setPromptForPlayer(userId, enabled)
	local prompt = promptByPlayer[userId]
	if prompt and prompt.Parent then
		prompt.Enabled = enabled
	end
end

local promptCooldowns = {}

local function addPromptToCharacter(targetPlayer, character)
	if targetPlayer == localPlayer then return end
	local hrp = character:WaitForChild("HumanoidRootPart", 5)
	if not hrp then return end

	local existing = hrp:FindFirstChild("StealCashPrompt")
	if existing then existing:Destroy() end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name                  = "StealCashPrompt"
	prompt.ActionText            = "Steal Cash"
	prompt.ObjectText            = "💰 Cash"
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.HoldDuration          = PROMPT_HOLD
	prompt.RequiresLineOfSight   = false
	prompt.Exclusivity           = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Parent                = hrp

	promptByPlayer[targetPlayer.UserId] = prompt

	-- Hide immediately if this player is our current opponent
	if matchOpponentId == targetPlayer.UserId then
		prompt.Enabled = false
	end

	prompt.AncestryChanged:Connect(function()
		if not prompt.Parent then
			if promptByPlayer[targetPlayer.UserId] == prompt then
				promptByPlayer[targetPlayer.UserId] = nil
			end
		end
	end)

	local function updatePrompt()
		-- Always hidden if they're our match opponent
		if matchOpponentId == targetPlayer.UserId then
			prompt.Enabled = false
			return
		end
		-- Hidden while EITHER side is in a duel/risk match: you can't steal while
		-- you're locked in a game, and nobody can steal from a player who's
		-- mid-game with a locked camera and no way to react.
		if targetPlayer:GetAttribute("InMatch") or localPlayer:GetAttribute("InMatch") then
			prompt.Enabled = false
			return
		end
		local cashVal = targetPlayer:FindFirstChild("leaderstats") and targetPlayer.leaderstats:FindFirstChild("Cash")
		local cash = cashVal and cashVal.Value or 0
		prompt.Enabled    = cash > 0
		prompt.ObjectText = cash > 0 and ("💰 $" .. tostring(cash)) or "💰 No Cash"
	end
	updatePrompt()

	-- Re-evaluate when either side enters/leaves a match.
	targetPlayer:GetAttributeChangedSignal("InMatch"):Connect(updatePrompt)
	localPlayer:GetAttributeChangedSignal("InMatch"):Connect(updatePrompt)

	local ls = targetPlayer:FindFirstChild("leaderstats")
	if ls then
		local cashVal = ls:FindFirstChild("Cash")
		if cashVal then cashVal.Changed:Connect(updatePrompt) end
	end

	prompt.Triggered:Connect(function()
		if matchOpponentId == targetPlayer.UserId then return end
		if targetPlayer:GetAttribute("InMatch") or localPlayer:GetAttribute("InMatch") then return end
		local uid = targetPlayer.UserId
		if promptCooldowns[uid] then return end
		promptCooldowns[uid] = true
		task.delay(2, function() promptCooldowns[uid] = nil end)

		local cashVal = targetPlayer:FindFirstChild("leaderstats") and targetPlayer.leaderstats:FindFirstChild("Cash")
		local cash = cashVal and cashVal.Value or 0
		if cash <= 0 then
			showPopup("💰 They have no cash!", Color3.fromRGB(200, 200, 200))
			return
		end

		local productId = getProductForCash(cash)
		showPopup("💰 Steal cash from " .. targetPlayer.Name .. "!", Color3.fromRGB(255, 200, 50))
		task.wait(0.3)
		Network.send("StealCash_Request", { targetUserId = uid })
		MarketplaceService:PromptProductPurchase(localPlayer, productId)
	end)
end

local function hookPlayer(targetPlayer)
	if targetPlayer == localPlayer then return end
	if targetPlayer.Character then
		task.spawn(addPromptToCharacter, targetPlayer, targetPlayer.Character)
	end
	targetPlayer.CharacterAdded:Connect(function(character)
		task.spawn(addPromptToCharacter, targetPlayer, character)
	end)
end

for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
Players.PlayerAdded:Connect(hookPlayer)

Players.PlayerRemoving:Connect(function(p)
	promptByPlayer[p.UserId] = nil
end)

-- Server sends opponent's UserId when match starts, nil/0 when it ends
Network.onClient("StealPrompt_MatchStart", function(opponentUserId)
	-- Re-enable old opponent if switching (shouldn't happen but safety net)
	if matchOpponentId then
		setPromptForPlayer(matchOpponentId, true)
	end
	matchOpponentId = opponentUserId
	if opponentUserId then
		setPromptForPlayer(opponentUserId, false)
	end
end)

Network.onClient("StealPrompt_MatchEnd", function()
	if matchOpponentId then
		setPromptForPlayer(matchOpponentId, true)
	end
	matchOpponentId = nil
end)

Network.onClient("StealCashSuccess", function(data)
	showPopup("💰 Stole $" .. tostring(data.amount or 0) .. " from " .. (data.fromName or "someone") .. "!", Color3.fromRGB(255, 200, 50))
end)

Network.onClient("StealCashVictim", function(data)
	showPopup("💀 " .. (data.byName or "someone") .. " stole your cash!", Color3.fromRGB(220, 50, 50))
end)

return module
