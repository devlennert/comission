local module = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Player = game.Players.LocalPlayer
local PlayerGui = Player.PlayerGui
local ChairInfo = require(ReplicatedStorage.Modules.ChairInfo)
local CaseInfo = require(ReplicatedStorage.Modules.CaseInfo)
local Network = require(ReplicatedStorage.Modules.Network)
local Notification = require(script.Parent.Notification)
local RewardScreen = require(ReplicatedStorage.Modules.RewardScreen)

local UI = PlayerGui:WaitForChild("UI")
local RollingFrame = UI:WaitForChild("AbilityRolling")

-- Lock: prevents opening a second case while one is already rolling
local isRolling = false

local TickSound = Instance.new("Sound")
TickSound.SoundId = "rbxassetid://140404505414006"
TickSound.Volume = 0.6
TickSound.RollOffMaxDistance = 0
TickSound.Parent = RollingFrame

local WinSound = Instance.new("Sound")
WinSound.SoundId = "rbxassetid://140231021022259"
WinSound.Volume = 0.8
WinSound.RollOffMaxDistance = 0
WinSound.Parent = RollingFrame

local ScrollingFrame = RollingFrame:WaitForChild("ScrollingFrame")
local Template = ScrollingFrame:WaitForChild("Template")

local RARITY_ORDER = {"Common", "Rare", "Legendary", "Mythical"}

local RARITY_COLORS = {
	Common    = Color3.fromRGB(160, 160, 160),
	Rare      = Color3.fromRGB(50,  120, 220),
	Legendary = Color3.fromRGB(180,  80, 220),
	Mythical  = Color3.fromRGB(220,  50,  50),
}

local RARITY_REWARD_COLORS = {
	Common    = Color3.fromRGB(180, 180, 180),
	Rare      = Color3.fromRGB(85,  155, 255),
	Legendary = Color3.fromRGB(255, 175,  50),
	Mythical  = Color3.fromRGB(200,  80, 255),
}

local function pickRarity(chances)
	local roll = math.random(1, 100)
	local cumulative = 0
	for _, rarity in ipairs(RARITY_ORDER) do
		cumulative += (chances[rarity] or 0)
		if roll <= cumulative then return rarity end
	end
	return "Common"
end

local function getChairsByRarity(rarity)
	local chairs = {}
	for _, chairData in pairs(ChairInfo) do
		if chairData.Rarity == rarity then table.insert(chairs, chairData) end
	end
	return chairs
end

local function getRandomChairForCase(caseName)
	local caseData = CaseInfo[caseName]
	if not caseData then
		warn("[CASEOPENER] No CaseInfo for:", caseName)
		local all = {}
		for _, v in pairs(ChairInfo) do table.insert(all, v) end
		return all[math.random(1, #all)]
	end
	local rarity = pickRarity(caseData.RarityChances)
	local pool = getChairsByRarity(rarity)
	if #pool == 0 then
		for i = #RARITY_ORDER, 1, -1 do
			pool = getChairsByRarity(RARITY_ORDER[i])
			if #pool > 0 then break end
		end
	end
	return pool[math.random(1, #pool)]
end

local function getAnyRandomChair()
	local all = {}
	for _, v in pairs(ChairInfo) do table.insert(all, v) end
	return all[math.random(1, #all)]
end

-- Core roll logic — works on any AbilityRolling frame clone
local function openOnFrame(frame, caseName)
	local sf = frame:WaitForChild("ScrollingFrame")
	local tmpl = sf:WaitForChild("Template")

	local existingLayout = sf:FindFirstChildOfClass("UIListLayout")
	if existingLayout then existingLayout.Enabled = false end

	for _, child in pairs(sf:GetChildren()) do
		if child:IsA("Frame") and child ~= tmpl then child:Destroy() end
	end

	local selectedChair = getRandomChairForCase(caseName)
	local totalItems = 100
	local winningPosition = math.random(45, 55)
	local winningItem
	local allItems = {}

	for i = 1, totalItems do
		local chairData = (i == winningPosition) and selectedChair or getAnyRandomChair()
		local rarity = chairData.Rarity or "Common"
		local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common

		local clone = tmpl:Clone()
		clone.Name = "Item" .. i
		clone.Visible = true
		pcall(function()
			clone.Main.AbilityImage.Image = chairData.ImageId
			clone.Main.AbilityImage.AbilityName.Text = chairData.Name
			clone.Main.AbilityImage.AbilityRarity.Text = rarity
			clone.Main.AbilityImage.AbilityRarity.TextColor3 = rarityColor
			clone.Main.BackgroundColor3 = rarityColor
			local uiStroke = clone.Main:FindFirstChildOfClass("UIStroke")
			if uiStroke then uiStroke.Color = rarityColor end
		end)

		local uiScale = clone:FindFirstChildOfClass("UIScale")
		if not uiScale then
			uiScale = Instance.new("UIScale")
			uiScale.Scale = 1
			uiScale.Parent = clone
		else
			uiScale.Scale = 1
		end

		clone.Parent = sf
		table.insert(allItems, clone)
		if i == winningPosition then winningItem = clone end
	end

	sf.CanvasPosition = Vector2.new(0, 0)
	task.wait(0.1)

	local paddingScale = 0.05
	if existingLayout and existingLayout.Padding then
		paddingScale = existingLayout.Padding.Scale
	end

	local cumX = 0
	local positions = {}
	for _, item in ipairs(allItems) do
		local w = item.AbsoluteSize.X
		local padding = w * paddingScale
		item.Position = UDim2.new(0, cumX + w * 0.5, 0.5, 0)
		positions[item] = {x = cumX, width = w}
		cumX = cumX + w + padding
	end

	local totalContentWidth = cumX - (allItems[#allItems].AbsoluteSize.X * paddingScale)
	sf.CanvasSize = UDim2.new(0, totalContentWidth, 0, 0)

	local centerInContent = positions[winningItem].x + (positions[winningItem].width * 0.5)
	local maxScroll = totalContentWidth - sf.AbsoluteSize.X

	local middle = frame:FindFirstChild("Middle")
	local middleLocalX = middle
		and (middle.AbsolutePosition.X + middle.AbsoluteSize.X * 0.5 - sf.AbsolutePosition.X)
		or (sf.AbsoluteSize.X * 0.5)

	local targetPosition = math.clamp(centerInContent - middleLocalX, 0, maxScroll)

	local cleanupConnection
	cleanupConnection = RunService.Heartbeat:Connect(function()
		local currentScroll = sf.CanvasPosition.X
		local viewWidth = sf.AbsoluteSize.X
		local buffer = viewWidth * 0.5
		for _, item in ipairs(allItems) do
			if item and item.Parent and positions[item] then
				local itemEnd = positions[item].x + positions[item].width
				if itemEnd < currentScroll - buffer and item ~= winningItem then
					item:Destroy()
				end
			end
		end
	end)

	local tween = TweenService:Create(sf,
		TweenInfo.new(8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ CanvasPosition = Vector2.new(targetPosition, 0) })
	tween:Play()

	local lastCenteredItem = nil
	local tickConnection = RunService.Heartbeat:Connect(function()
		local currentScroll = sf.CanvasPosition.X
		local centerX = currentScroll + middleLocalX
		local closest, closestDist = nil, math.huge
		for _, item in ipairs(allItems) do
			if item and item.Parent and positions[item] then
				local itemCenterX = positions[item].x + positions[item].width * 0.5
				local dist = math.abs(itemCenterX - centerX)
				if dist < closestDist then closestDist = dist; closest = item end
			end
		end
		if closest and closest ~= lastCenteredItem then
			lastCenteredItem = closest
			TickSound:Play()
		end
	end)

	tween.Completed:Wait()
	tickConnection:Disconnect()
	if cleanupConnection then cleanupConnection:Disconnect() end

	for _, item in ipairs(allItems) do
		if item and item.Parent and item ~= winningItem and positions[item] then
			if math.abs(positions[item].x - positions[winningItem].x) > sf.AbsoluteSize.X * 2 then
				item:Destroy()
			end
		end
	end

	local winUiScale = winningItem:FindFirstChildOfClass("UIScale")
	if winUiScale then
		TweenService:Create(winUiScale,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1.1 }):Play()
		task.wait(0.5)
		TweenService:Create(winUiScale,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ Scale = 1 }):Play()
	end

	return selectedChair
end

function module.Cleanup()
	RollingFrame.Visible = false
	for _, child in pairs(ScrollingFrame:GetChildren()) do
		if child:IsA("Frame") and child ~= Template then child:Destroy() end
	end
end

function module.Open(caseName)
	-- FIX: Hard guard — if already rolling, reject immediately and tell the server.
	-- The server holds this purchase as NotProcessedYet until CaseRollDone clears the lock.
	if isRolling then
		Notification.Notify("⏳ Finish your current roll first!", "Warning")
		return
	end
	isRolling = true

	RollingFrame.Visible = true

	local selectedChair = openOnFrame(RollingFrame, caseName)

	local wonChairName = selectedChair.Name
	local alreadyOwned = Player.Chairs:FindFirstChild(wonChairName) ~= nil
	if not alreadyOwned then WinSound:Play() end
	Network.send("AddChair", wonChairName)

	local rarityText = selectedChair.Rarity or "Common"
	Notification.Notify("🏆 You got " .. selectedChair.Name .. "! (" .. rarityText .. ")", "Confirmation")

	task.wait(1.5)
	module.Cleanup()

	-- FIX: Release client lock THEN tell the server the roll is done so it
	-- clears rollLocked and any queued purchase receipts can now be granted.
	isRolling = false
	Network.send("CaseRollDone")

	return selectedChair
end

function module.OpenPack(caseName)
	-- FIX: Same hard guard for packs.
	if isRolling then
		Notification.Notify("⏳ Finish your current roll first!", "Warning")
		return
	end
	isRolling = true

	-- Full-screen dark backdrop
	local overlay = Instance.new("Frame")
	overlay.Name = "TripleRollOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Position = UDim2.fromScale(0, 0)
	overlay.AnchorPoint = Vector2.new(0, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.4
	overlay.ZIndex = 20
	overlay.Parent = UI

	-- Centered container — same width as original RollingFrame, tall enough for 3 strips + gaps
	-- Original is 0.601 wide x 0.225 tall. 3 strips + 2 gaps (0.012 each) = 0.699 total height
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.Size = UDim2.new(0.65, 0, 0.78, 0)
	container.BackgroundTransparency = 1
	container.ZIndex = 21
	container.Parent = overlay

	local GAP = 0.012   -- gap between strips as fraction of container height
	local STRIP_H = (1 - GAP * 2) / 3  -- each strip's height fraction within container

	local strips = {}
	for i = 1, 3 do
		local strip = RollingFrame:Clone()
		strip.Name = "Strip" .. i
		strip.AnchorPoint = Vector2.new(0, 0)
		strip.Size = UDim2.new(1, 0, STRIP_H, 0)
		strip.Position = UDim2.new(0, 0, (i - 1) * (STRIP_H + GAP), 0)
		strip.BackgroundTransparency = 0
		strip.Visible = true
		strip.ZIndex = 22
		for _, s in ipairs(strip:GetDescendants()) do
			if s:IsA("Sound") then s:Destroy() end
		end
		local arc = strip:FindFirstChildOfClass("UIAspectRatioConstraint")
		if arc then arc:Destroy() end
		strip.Parent = container
		table.insert(strips, strip)
	end

	task.wait(0.15)

	local results = {}
	local done = 0
	local allDone = Instance.new("BindableEvent")

	for i, strip in ipairs(strips) do
		task.spawn(function()
			task.wait((i - 1) * 0.1)
			local chair = openOnFrame(strip, caseName)
			results[i] = chair
			done += 1
			if done == 3 then allDone:Fire() end
		end)
	end

	allDone.Event:Wait()
	allDone:Destroy()
	task.wait(1)
	overlay:Destroy()

	for _, chair in ipairs(results) do
		if chair then Network.send("AddChair", chair.Name) end
	end

	local rewardData = {}
	for _, chair in ipairs(results) do
		if not chair then continue end
		local chairData = chair
		table.insert(rewardData, {
			setup = function(frame)
				local main = frame:FindFirstChild("Main")
				if not main then return end
				local icon   = main:FindFirstChild("Icon")
				local rarity = main:FindFirstChild("Rarity")
				local title  = main:FindFirstChild("Title")
				if icon   then icon.Image        = chairData.ImageId end
				if title  then title.Text         = chairData.Name end
				if rarity then
					rarity.Text       = chairData.Rarity
					rarity.TextColor3 = RARITY_REWARD_COLORS[chairData.Rarity] or Color3.new(1,1,1)
				end
			end
		})
	end

	RewardScreen.Show(rewardData)

	-- FIX: Release client lock then notify server so queued receipts can grant.
	isRolling = false
	Network.send("CaseRollDone")
end

-- FIX: Server can push an "already rolling" rejection back to the client
-- if somehow a purchase slipped through before the lock was set.
Network.onClient("CaseRollBusy", function()
	Notification.Notify("⏳ Finish your current roll before buying another!", "Warning")
end)

Network.onClient("OpenCase", function(caseName)
	module.Open(caseName)
end)

Network.onClient("OpenPack", function(caseName)
	module.OpenPack(caseName)
end)

return module