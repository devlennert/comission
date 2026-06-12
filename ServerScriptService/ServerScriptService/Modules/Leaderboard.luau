local module = {}
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FormatModule = require(ReplicatedStorage.Modules.FormatModule)

local MoneyOrderedDataStore = DataStoreService:GetOrderedDataStore("MoneyLeaderboard2")
local StreaksOrderedDataStore = DataStoreService:GetOrderedDataStore("StreaksLeaderboard2")

local MoneyLeaderboard = workspace.Map.Leaderboards:WaitForChild("MoneyLeaderboard").Leaderboard
local StreaksLeaderboard = workspace.Map.Leaderboards:WaitForChild("StreaksLeaderboard").Leaderboard

local GradientsFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Gradients")

local DataHandler

local LEADERBOARD_SIZE = 50
local UPDATE_INTERVAL = 45

local function clearLeaderboard(leaderboardModel)
	local surfacePart = leaderboardModel:FindFirstChild("SurfacePart")
	if not surfacePart then return end

	local surfaceGui = surfacePart:FindFirstChild("SurfaceGui")
	if not surfaceGui then return end

	local scrollingFrame = surfaceGui:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then return end

	for _, child in pairs(scrollingFrame:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "Template" then
			child:Destroy()
		end
	end
end

local function getTemplate(leaderboardModel)
	local surfacePart = leaderboardModel:FindFirstChild("SurfacePart")
	if not surfacePart then return nil end

	local surfaceGui = surfacePart:FindFirstChild("SurfaceGui")
	if not surfaceGui then return nil end

	local scrollingFrame = surfaceGui:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then return nil end

	local template = scrollingFrame:FindFirstChild("Template")
	return template, scrollingFrame
end

local function getGradientForPlace(place)
	if place == 1 then
		return GradientsFolder:FindFirstChild("1")
	elseif place == 2 then
		return GradientsFolder:FindFirstChild("2")
	elseif place == 3 then
		return GradientsFolder:FindFirstChild("3")
	else
		return GradientsFolder:FindFirstChild("Rest")
	end
end

local function getUserThumbnail(userId)
	local success, thumbnailUrl = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)

	if success then
		return thumbnailUrl
	else
		return "rbxasset://textures/ui/GuiImagePlaceholder.png"
	end
end

local function updateLeaderboard(leaderboardModel, orderedDataStore, statName)
	clearLeaderboard(leaderboardModel)

	local template, scrollingFrame = getTemplate(leaderboardModel)
	if not template or not scrollingFrame then 
		warn("[LEADERBOARD] Could not find template or scrolling frame for", leaderboardModel.Name)
		return 
	end

	local success, pages = pcall(function()
		return orderedDataStore:GetSortedAsync(false, LEADERBOARD_SIZE)
	end)

	if not success then
		warn("[LEADERBOARD] Failed to get sorted data:", pages)
		return
	end

	local entries = pages:GetCurrentPage()
	local place = 1

	for _, entry in ipairs(entries) do
		local userId = tonumber(entry.key)
		local statValue = entry.value

		if userId and statValue then
			local success, username = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)

			if success and username then
				local newFrame = template:Clone()
				newFrame.Name = "Player_" .. userId
				newFrame.Visible = true
				newFrame.LayoutOrder = place

				local playerNameLabel = newFrame:FindFirstChild("PlayerName")
				if playerNameLabel then
					playerNameLabel.Text = username
				end

				local placeLabel = newFrame:FindFirstChild("Place")
				if placeLabel then
					placeLabel.Text = "#" .. place
				end

				local statLabel = newFrame:FindFirstChild(statName)
				if statLabel then
					if statName == "Cash" then
						statLabel.Text = "$" .. tostring(FormatModule.Abbreviate(statValue))
					else
						statLabel.Text = tostring(statValue)
					end
				end

				local playerIcon = newFrame:FindFirstChild("PlayerIcon")
				if playerIcon then
					playerIcon.Image = getUserThumbnail(userId)
				end

				local gradient = getGradientForPlace(place)
				if gradient then
					local gradientClone = gradient:Clone()
					gradientClone.Parent = newFrame
				end

				newFrame.Parent = scrollingFrame

				place = place + 1
			end
		end
	end

	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, scrollingFrame.UIListLayout.AbsoluteContentSize.Y)
end

function module.UpdateMoneyLeaderboard()
	updateLeaderboard(MoneyLeaderboard, MoneyOrderedDataStore, "Cash")
end

function module.UpdateStreaksLeaderboard()
	updateLeaderboard(StreaksLeaderboard, StreaksOrderedDataStore, "Streaks")
end

function module.SavePlayerStats(player)
	if not DataHandler then return end

	local profile = DataHandler.GetProfile(player)
	if not profile then return end

	local userId = tostring(player.UserId)
	local cash = profile.Data.Cash or 0
	local streak = profile.Data.Streak or 0

	pcall(function()
		MoneyOrderedDataStore:SetAsync(userId, cash)
	end)

	pcall(function()
		StreaksOrderedDataStore:SetAsync(userId, streak)
	end)

	print("[LEADERBOARD] Saved stats for", player.Name, "- Cash:", cash, "Streak:", streak)
end

function module.Init(dataHandlerModule)
	DataHandler = dataHandlerModule

	module.UpdateMoneyLeaderboard()
	module.UpdateStreaksLeaderboard()

	spawn(function()
		while true do
			wait(UPDATE_INTERVAL)
			module.UpdateMoneyLeaderboard()
			module.UpdateStreaksLeaderboard()
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		module.SavePlayerStats(player)
	end)

	print("[LEADERBOARD] Leaderboard system initialized")
end

return module