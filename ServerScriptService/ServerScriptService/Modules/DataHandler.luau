local module = {}
local HttpService        = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Players            = game:GetService("Players")

local ItemsFolder      = ReplicatedStorage:WaitForChild("Assets").Items
local OverheadTemplate = ReplicatedStorage:WaitForChild("Assets").UI.Overhead

local ProfileService   = require(ReplicatedStorage.Modules:WaitForChild("ProfileService"))
local Utils            = require(ReplicatedStorage.Modules:WaitForChild("Utils"))
local DevProducts      = require(ReplicatedStorage.Modules:WaitForChild("DevProducts"))
local GamePasses       = require(ReplicatedStorage.Modules:WaitForChild("GamePasses"))
local Network          = require(ReplicatedStorage:WaitForChild("Modules").Network)
local ChairInfo        = require(ReplicatedStorage.Modules:WaitForChild("ChairInfo"))
local DailyRewardsInfo = require(ReplicatedStorage.Modules.DailyRewards)
local PlaytimeRewardsInfo = require(ReplicatedStorage.Modules.PlaytimeRewards)

Network.define("AddCurrency")
Network.define("EquipChair")
Network.define("ClaimDaily")
Network.define("CompleteTutorial")
Network.define("UpdateChairs")
Network.define("ShowTutorial")
Network.define("DailyClaimResult")
Network.define("Notify")
Network.define("StealStreakSuccess")
Network.define("StealStreakVictim")
Network.define("OpenCase")
Network.define("ShowChairReward")
Network.define("OpenPack")
Network.define("OPRolls_Update")
Network.define("OPRolls_Bought")
Network.define("OPRolls_ShowButtons")
Network.define("OPRolls_HideButtons")
Network.define("ShowRevenge")
Network.define("Rebirth_Request")
Network.define("Rebirth_Result")
Network.define("Rebirth_Show")
Network.define("CaseRollDone")
Network.define("CaseRollBusy")
Network.define("FreeGiftStatus")
Network.define("LeaveReward_Status")
Network.define("LeaveReward_Result")
Network.define("LuckEvent_Update")

local LEAVE_REWARD_COOLDOWN = 86400
local LEAVE_REWARD_LUCK     = 100

local EVENT_CYCLE    = 15 * 60
local EVENT_DURATION = 5 * 60

-- ─────────────────────────────────────────────────────────────────────────────

local ProfileTemplate = {
	Cash                  = 0,
	Wins                  = 0,
	Losses                = 0,
	Chairs                = {"Basic"},
	Effects               = {},
	Items                 = {},
	Streak                = 0,
	EquippedChair         = "Basic",
	DailyDay              = 1,
	DailyLastClaim        = 0,
	-- NOTE: CashMultiplier is NOT saved to disk anymore.
	-- It is recalculated fresh on every Load() so there is never a stale value.
	-- The key is kept in the template only so Reconcile() doesn't error on
	-- older profiles that still have it; it gets overwritten immediately.
	CashMultiplier        = 1,
	TutorialDone          = false,
	GamesAsPresenter      = 0,
	TruthfulDeclarations  = 0,
	RebirthLevel          = 0,
	FreeGiftClaimed       = false,
	LuckBonusLastClaim    = 0,
}

local ProfileStore = ProfileService.GetProfileStore(
	"PlayerDatav_7",
	ProfileTemplate
)

local Profiles            = {}
local LeaderboardModule
local StreakStealerModule
local CasesHandlerRef     = nil

local pendingSaveStreaks   = {}
local pendingRevenge      = {}
local sessionRolls        = {}
local rollLocked          = {}
local pendingBoughtNotifs = {}
local pendingCasePurchases = {}
local sessionStartTimes       = {}   -- [userId] = os.time() when they joined
local claimedPlaytimeRewards  = {}   -- [userId][rewardIndex] = true

local MAX_FRIEND_BONUS        = 0.5
local FRIEND_BONUS_PER_FRIEND = 0.1

-- ─── 2x Luck Event State ─────────────────────────────────────────────────────
local luckEventActive = false

local function getLuckEventPhase()
	local t       = os.time() % EVENT_CYCLE
	local active  = t < EVENT_DURATION
	local remaining = active and (EVENT_DURATION - t) or (EVENT_CYCLE - t)
	return active, remaining
end
-- ─────────────────────────────────────────────────────────────────────────────

local function getRebirthRequirement(level)
	return math.floor(450 * (1.75 ^ level))
end

function module.GetSessionRolls(userId)
	return sessionRolls[userId] or { op = 0, superOp = 0 }
end

function module.GetAndClearSessionRolls(userId)
	local rolls = sessionRolls[userId] or { op = 0, superOp = 0 }
	sessionRolls[userId] = nil
	return rolls
end

function module.ClearSessionRolls(userId)
	sessionRolls[userId] = nil
end

function module.ConsumeOneRoll(userId, rollType)
	local rolls = sessionRolls[userId]
	if not rolls or not rollType then return end
	if rollType == "superOp" then
		rolls.superOp = math.max(0, (rolls.superOp or 0) - 1)
	elseif rollType == "op" then
		rolls.op = math.max(0, (rolls.op or 0) - 1)
	end
end

function module.SetRollLocked(userId, locked)
	rollLocked[userId] = locked
	if not locked then
		local queue = pendingCasePurchases[userId]
		if queue and #queue > 0 then
			-- Flush ONE queued purchase; the rest flush on the next CaseRollDone.
			-- (Firing them all at once would overlap roll animations.)
			local receiptInfo = table.remove(queue, 1)
			if #queue == 0 then pendingCasePurchases[userId] = nil end
			local player = Players:GetPlayerByUserId(userId)
			if player and receiptInfo then
				local ItemName, Type = Utils.GetProductNameById(receiptInfo.ProductId)
				local caseName = DevProducts[ItemName] and DevProducts[ItemName].CaseName
				if caseName then
					rollLocked[userId] = true
					if Type == "Pack" then
						Network.sendToClient(player, "OpenPack", caseName)
					else
						-- "Case", "OPRoll", "SuperOPRoll" all resolve to a crate open
						Network.sendToClient(player, "OpenCase", caseName)
						Network.sendToClient(player, "Notify",
							"🎉 Opening queued " .. caseName .. "...", "Confirmation")
					end
				end
			end
		end
	end
end

function module.FlushPendingBoughtNotifs(playerA, playerB)
	local function flush(p, opp)
		local n = pendingBoughtNotifs[p.UserId]
		if not n then return end
		pendingBoughtNotifs[p.UserId] = nil
		for _, v in ipairs(n) do
			Network.sendToClient(p, "OPRolls_Bought", v.text, v.r, v.g, v.b)
			if opp then Network.sendToClient(opp, "OPRolls_Bought", v.text, v.r, v.g, v.b) end
		end
	end
	flush(playerA, playerB)
	flush(playerB, playerA)
end

function module.NotifyOPRollsBought(buyer, rollType, getOpponent)
	local opCount    = sessionRolls[buyer.UserId] and sessionRolls[buyer.UserId].op    or 0
	local superCount = sessionRolls[buyer.UserId] and sessionRolls[buyer.UserId].superOp or 0
	local isSuper    = rollType == "SuperOPRoll"
	local label      = isSuper and "Super OP Roll" or "OP Roll"
	local color      = isSuper and {r=0,g=255,b=255} or {r=255,g=0,b=255}
	local boughtStr  = buyer.Name .. " Bought " .. label
	Network.sendToClient(buyer, "OPRolls_Update", opCount, superCount)
	if rollLocked[buyer.UserId] then
		if not pendingBoughtNotifs[buyer.UserId] then pendingBoughtNotifs[buyer.UserId] = {} end
		table.insert(pendingBoughtNotifs[buyer.UserId], {text=boughtStr, r=color.r, g=color.g, b=color.b})
	else
		Network.sendToClient(buyer, "OPRolls_Bought", boughtStr, color.r, color.g, color.b)
		local opp = getOpponent and getOpponent(buyer) or nil
		if opp then Network.sendToClient(opp, "OPRolls_Bought", boughtStr, color.r, color.g, color.b) end
	end
end

function module.SetRevengePending(loserUserId, data)
	pendingRevenge[loserUserId] = data
end

-- "Remove Loss" / Revenge product: undoes the buyer's most recent duel loss as
-- if they had won it — grants the win-reward cash, restores the win streak they
-- had before the loss reset it, and removes the loss from their record.
-- Uses the pendingRevenge data stashed by TimerDuelHandler.endMatch.
function module.RemoveLoss(player)
	local profile = Profiles[player]
	if not profile then return false end

	local data = pendingRevenge[player.UserId]
	if not data then
		Network.sendToClient(player, "Notify", "No recent loss to undo!", "Warning")
		return false
	end
	pendingRevenge[player.UserId] = nil

	-- 1) Remove one loss (floored at 0)
	local current = profile.Data.Losses or 0
	profile.Data.Losses = math.max(0, current - 1)
	local lv = player:FindFirstChild("Losses")
	if lv then lv.Value = profile.Data.Losses end

	-- 2) Restore the win streak the player had before the loss reset it,
	--    then add the +1 they'd have gotten for winning.
	local restored = (data.loserStreak or 0) + 1
	module.SetCurrency(player, restored, "Streak")

	-- 3) Grant the win-reward cash (CashMult applies inside AddCurrency).
	module.AddCurrency(player, data.cash or 0, "Cash")
	-- 4) Count it as a win on the record.
	module.AddCurrency(player, 1, "Wins")

	Network.sendToClient(player, "Notify",
		"⚡ Loss undone! Cash + streak restored.", "Confirmation")
	return true
end

function module.ExecuteRevenge(loser)
	local data = pendingRevenge[loser.UserId]
	if not data then return false end
	pendingRevenge[loser.UserId] = nil

	local loserProfile = Profiles[loser]
	if loserProfile then
		loserProfile.Data.Cash = (loserProfile.Data.Cash or 0) + data.cash
		local ls = loser:FindFirstChild("leaderstats")
		if ls and ls:FindFirstChild("Cash") then
			ls.Cash.Value = loserProfile.Data.Cash
		end
	end

	module.SetCurrency(loser, data.loserStreak, "Streak")

	local winner = Players:GetPlayerByUserId(data.winnerUserId)
	if winner then
		local winnerProfile = Profiles[winner]
		if winnerProfile then
			winnerProfile.Data.Cash = math.max(0, (winnerProfile.Data.Cash or 0) - data.cash)
			local ls = winner:FindFirstChild("leaderstats")
			if ls and ls:FindFirstChild("Cash") then
				ls.Cash.Value = winnerProfile.Data.Cash
			end
		end
		module.SetCurrency(winner, 0, "Streak")
		Network.sendToClient(winner, "Notify", "💀 Your opponent got REVENGE! You lost your cash and streak!", "Warning")
	end

	Network.sendToClient(loser, "Notify", "⚡ REVENGE! You stole " .. data.cash .. " cash back + streak restored!", "Confirmation")
	return true
end

local function countFriendsInServer(player)
	local friendCount = 0
	for _, otherPlayer in pairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			local success, isFriend = pcall(function()
				return player:IsFriendsWith(otherPlayer.UserId)
			end)
			if success and isFriend then
				friendCount = friendCount + 1
			end
		end
	end
	return friendCount
end

-- ─── Game passes ─────────────────────────────────────────────────────────────
-- Ownership is cached per session so we don't hit MarketplaceService on every
-- cash payout. Populated on join (cacheGamePasses) and refreshed when a pass is
-- purchased mid-session (PromptGamePassPurchaseFinished).
local gamePassOwned = {}  -- [userId] = { [passId] = true/false }

local function ownsPass(player, passId)
	local owned = gamePassOwned[player.UserId]
	if owned ~= nil and owned[passId] ~= nil then
		return owned[passId]
	end
	-- Not cached yet — query once and store the result.
	local has = false
	pcall(function()
		has = MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	gamePassOwned[player.UserId] = gamePassOwned[player.UserId] or {}
	gamePassOwned[player.UserId][passId] = has
	return has
end

local function cacheGamePasses(player)
	gamePassOwned[player.UserId] = {}
	for _, pass in pairs(GamePasses) do
		if pass.ID then
			local has = false
			pcall(function()
				has = MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.ID)
			end)
			gamePassOwned[player.UserId][pass.ID] = has
		end
	end
end

function module.OwnsGamePass(player, passKey)
	local pass = GamePasses[passKey]
	if not pass or not pass.ID then return false end
	return ownsPass(player, pass.ID)
end

-- ─── CashMultiplier ───────────────────────────────────────────────────────────
-- Recalculates the friend + rebirth bonus multiplier and writes it to BOTH
-- Profile.Data and the player instance value so they are always in sync.
-- Called immediately (no yield) inside Load() before any game can start.
local function updateCashMultiplier(player)
	local friendCount  = countFriendsInServer(player)
	local friendBonus  = math.min(friendCount * FRIEND_BONUS_PER_FRIEND, MAX_FRIEND_BONUS)
	local Profile      = Profiles[player]
	local rebirthBonus = 0
	if Profile then
		rebirthBonus = (Profile.Data.RebirthLevel or 0) * 0.25
	end
	-- Equipped chair's CashMult (percent) folds into the multiplier too.
	local chairBonus = 0
	local equippedVal = player:FindFirstChild("EquippedChair")
	if equippedVal then
		local data = ChairInfo[equippedVal.Value]
		if data and data.CashMult then chairBonus = data.CashMult / 100 end
	end
	-- Game-pass cash boosts: 2x Coins doubles (+1.0x), VIP adds +0.5x. They stack.
	local passBonus = 0
	if module.OwnsGamePass(player, "2x Coins") then passBonus += 1.0 end
	if module.OwnsGamePass(player, "VIP")      then passBonus += 0.5 end
	-- Always >= 1.0 so it can never accidentally reduce a payout
	local multiplier = math.max(1.0, 1 + friendBonus + rebirthBonus + chairBonus + passBonus)
	print("[DATAHANDLER] updateCashMultiplier for", player.Name,
		"| friendBonus:", friendBonus, "| rebirthBonus:", rebirthBonus,
		"| chairBonus:", chairBonus, "| passBonus:", passBonus, "| final:", multiplier)
	if Profile then
		Profile.Data.CashMultiplier = multiplier
		local mv = player:FindFirstChild("CashMultiplier")
		if mv then mv.Value = multiplier end
		local fv = player:FindFirstChild("FriendBonus")
		if fv then fv.Value = friendBonus end
	end
end

local function updateAllPlayerMultipliers()
	for _, player in pairs(Players:GetPlayers()) do
		updateCashMultiplier(player)
	end
end

-- ─── Luck ────────────────────────────────────────────────────────────────────
local function getPlayerLuckValue(player)
	local chairLuck = 0
	local equippedVal = player:FindFirstChild("EquippedChair")
	if equippedVal then
		local data = ChairInfo[equippedVal.Value]
		chairLuck  = data and (data.Luck or 0) or 0
	end
	local bonusLuckVal = player:FindFirstChild("BonusLuck")
	local bonusLuck    = bonusLuckVal and bonusLuckVal.Value or 0
	local total        = chairLuck + bonusLuck
	if luckEventActive then
		total = total * 2
	end
	return total
end

local function computeTruthRate(profile)
	local total = profile.Data.GamesAsPresenter or 0
	if total == 0 then return 100 end
	return math.floor(((profile.Data.TruthfulDeclarations or 0) / total) * 100)
end

local function updateOverhead(player)
	if not player.Character then return end
	local head = player.Character:FindFirstChild("Head")
	if not head then return end
	local overhead = head:FindFirstChild("Overhead")
	if not overhead then
		print("[OVERHEAD] No Overhead found on", player.Name, "head — skipping update")
		return
	end

	local streakFrame = overhead:FindFirstChild("StreakFrame")
	if streakFrame then
		local streakCount = streakFrame:FindFirstChild("StreakCount")
		if streakCount then
			local streakVal = player:FindFirstChild("Streak")
			streakCount.Text = streakVal and tostring(streakVal.Value) or "0"
		end
	end

	-- The overhead "Luck" label (kept its instance name for back-compat) now
	-- flexes the equipped chair's NEW boosts instead of the dead Luck stat.
	local boostLabel = overhead:FindFirstChild("Luck", true)
	if boostLabel then
		local equippedVal = player:FindFirstChild("EquippedChair")
		local chairName   = equippedVal and equippedVal.Value or "Basic"
		boostLabel.Text   = ChairInfo.GetBoostString(chairName)
	end

	local truthLabel = overhead:FindFirstChild("TruthRate", true)
	if truthLabel then
		local profile = Profiles[player]
		local rate    = profile and computeTruthRate(profile) or 100
		truthLabel.Text    = rate .. "% Truth Rate"
		truthLabel.Visible = false
		print("[OVERHEAD] TruthRate updated (hidden):", rate .. "%", "for", player.Name)
	else
		print("[OVERHEAD] No TruthRate label found for", player.Name)
	end
end

local function createOverhead(player)
	if not player.Character then return end
	local head = player.Character:FindFirstChild("Head")
	if not head then return end
	for _, child in pairs(head:GetChildren()) do
		if child.Name == "Overhead" and child:IsA("BillboardGui") then
			child:Destroy()
		end
	end
	local overhead   = OverheadTemplate:Clone()
	overhead.Parent  = head
	overhead.Adornee = head
	overhead.Enabled = true
	local truthLabel = overhead:FindFirstChild("TruthRate", true)
	if truthLabel then truthLabel.Visible = false end
	updateOverhead(player)
end

-- ─── 2x Luck Event Broadcast ─────────────────────────────────────────────────
local function broadcastLuckEvent()
	local active, remaining = getLuckEventPhase()
	for _, player in ipairs(Players:GetPlayers()) do
		Network.sendToClient(player, "LuckEvent_Update", active, remaining)
	end
end
-- ─────────────────────────────────────────────────────────────────────────────

function module.Save(Player)
	local profile = Profiles[Player]
	if profile then
		if LeaderboardModule then
			LeaderboardModule.SavePlayerStats(Player)
		end
		profile:Release()
		Profiles[Player] = nil
	end
end

function module.Load(Player)
	print("[DATAHANDLER] Loading profile for", Player.Name)
	local profile = ProfileStore:LoadProfileAsync(tostring(Player.UserId))
	if profile then
		profile:Reconcile()

		-- ── Always reset CashMultiplier to 1 on load so there's never a
		--    stale saved value from a previous session with more friends/rebirth.
		--    updateCashMultiplier() below will set the real value immediately.
		profile.Data.CashMultiplier = 1

		Profiles[Player] = profile
		sessionStartTimes[Player.UserId]      = os.time()
		claimedPlaytimeRewards[Player.UserId] = {}
		local Cash               = profile.Data.Cash
		local Wins               = profile.Data.Wins
		local Items              = profile.Data.Items
		local Streak             = profile.Data.Streak
		local EquippedChair      = profile.Data.EquippedChair
		local Chairs             = profile.Data.Chairs
		local DailyDay           = profile.Data.DailyDay
		local DailyLastClaim     = profile.Data.DailyLastClaim
		local TutorialDone       = profile.Data.TutorialDone
		local RebirthLevel       = profile.Data.RebirthLevel or 0
		local FreeGiftClaimed    = profile.Data.FreeGiftClaimed or false
		local LuckBonusLastClaim = profile.Data.LuckBonusLastClaim or 0

		print("[DATAHANDLER]", Player.Name, "— Cash:", Cash, "| RebirthLevel:", RebirthLevel,
			"| FreeGiftClaimed:", FreeGiftClaimed,
			"| LuckBonusLastClaim:", LuckBonusLastClaim)

		if Cash then
			local l = Instance.new("Folder")
			l.Parent = Player
			l.Name   = "leaderstats"
			local c = Instance.new("NumberValue")
			c.Parent = l; c.Name = "Cash"; c.Value = Cash
		end
		if Wins then
			local c = Instance.new("NumberValue")
			c.Parent = Player.leaderstats; c.Name = "Wins"; c.Value = Wins
		end
		do
			-- Losses lives on the Player (not leaderstats) so it stays off the public list.
			local lv = Instance.new("NumberValue")
			lv.Parent = Player; lv.Name = "Losses"; lv.Value = profile.Data.Losses or 0
		end
		if Streak then
			local c = Instance.new("NumberValue")
			c.Parent = Player; c.Name = "Streak"; c.Value = Streak
			c.Changed:Connect(function() updateOverhead(Player) end)
			Player.CharacterAdded:Connect(function(character)
				character:WaitForChild("Head")
				task.wait(0.2)
				createOverhead(Player)
			end)
			if Player.Character then
				task.wait(0.2)
				createOverhead(Player)
			end
		end
		if EquippedChair then
			local c = Instance.new("StringValue")
			c.Parent = Player; c.Name = "EquippedChair"; c.Value = EquippedChair
		end

		if DailyDay then
			local c = Instance.new("NumberValue")
			c.Parent = Player; c.Name = "DailyDay"; c.Value = DailyDay
		end
		if DailyLastClaim then
			local c = Instance.new("NumberValue")
			c.Parent = Player; c.Name = "DailyLastClaim"; c.Value = DailyLastClaim
		end

		-- CashMultiplier instance — starts at 1, gets the real value below
		local cmv = Instance.new("NumberValue")
		cmv.Parent = Player; cmv.Name = "CashMultiplier"; cmv.Value = 1

		local fb = Instance.new("NumberValue")
		fb.Parent = Player; fb.Name = "FriendBonus"; fb.Value = 0

		local rl = Instance.new("NumberValue")
		rl.Parent = Player; rl.Name = "RebirthLevel"; rl.Value = RebirthLevel
		print("[DATAHANDLER] Created RebirthLevel value:", RebirthLevel, "for", Player.Name)

		local bl = Instance.new("NumberValue")
		bl.Parent = Player; bl.Name = "BonusLuck"; bl.Value = 0
		bl.Changed:Connect(function() updateOverhead(Player) end)

		local tutorialDoneValue = Instance.new("BoolValue")
		tutorialDoneValue.Parent = Player
		tutorialDoneValue.Name   = "TutorialDone"
		tutorialDoneValue.Value  = TutorialDone == true

		if Items then
			for _, item in Items do
				module.AddItem(Player, item)
			end
		end
		if Chairs then
			local b = Instance.new("Folder")
			b.Parent = Player; b.Name = "Chairs"
			for _, gun in Chairs do
				local a = Instance.new("StringValue")
				a.Parent = b; a.Name = gun
			end
		end

		-- ── Recalculate CashMultiplier IMMEDIATELY (no yield) so it's always
		--    correct before any game can start. This prevents stale saved values
		--    from a previous session with a different friend/rebirth state.
		--    Game-pass ownership requires a yielding web call, so we cache it in
		--    the background and re-run the multiplier once it's known.
		updateCashMultiplier(Player)
		-- Also update all others in case friend count changed
		task.spawn(updateAllPlayerMultipliers)

		task.spawn(function()
			cacheGamePasses(Player)
			if Profiles[Player] then          -- still in-game after the web call
				updateCashMultiplier(Player)  -- now includes 2x Coins / VIP
			end
		end)

		updateOverhead(Player)

		Network.sendToClient(Player, "FreeGiftStatus", FreeGiftClaimed)

		local leaveRewardReady = (os.time() - LuckBonusLastClaim) >= LEAVE_REWARD_COOLDOWN
		Network.sendToClient(Player, "LeaveReward_Status", leaveRewardReady)
		print("[DATAHANDLER]", Player.Name, "— LeaveRewardReady:", leaveRewardReady,
			"| secondsSinceClaim:", os.time() - LuckBonusLastClaim)

		local eventActive, eventRemaining = getLuckEventPhase()
		Network.sendToClient(Player, "LuckEvent_Update", eventActive, eventRemaining)
		print("[LUCKEVENT] Sent initial state to", Player.Name,
			"| active:", eventActive, "| remaining:", eventRemaining)

		if not TutorialDone then
			task.wait(1.5)
			Network.sendToClient(Player, "ShowTutorial")
		end

		print("[DATAHANDLER] Load complete for", Player.Name)
	else
		Player:Kick()
	end
end

-- ── AddCurrency ────────────────────────────────────────────────────────────────
-- For regular cash income (daily rewards, etc.) — applies CashMultiplier
-- (friend bonus + rebirth bonus) so those bonuses affect casual earnings.
function module.AddCurrency(Player, amount, Currency)
	local Profile = Profiles[Player]
	if Profile then
		local finalAmount = amount
		if Currency == "Cash" then
			local multiplier = math.max(1.0, Profile.Data.CashMultiplier or 1)
			finalAmount = math.floor(amount * multiplier)
		end
		Profile.Data[Currency] += finalAmount
		local CurrencyAmount = Profile.Data[Currency]
		if not Player.leaderstats:FindFirstChild(Currency) then
			Player[Currency].Value = CurrencyAmount
		else
			Player.leaderstats[Currency].Value = CurrencyAmount
		end
		if Currency == "Wins" or Currency == "Streak" then
			if LeaderboardModule then LeaderboardModule.SavePlayerStats(Player) end
		end
	end
end

-- ── AddCurrencyRaw ─────────────────────────────────────────────────────────────
-- For game prize payouts — skips CashMultiplier entirely.
-- cashPerRound already has luck baked in and is what was displayed on screen,
-- so the player gets exactly what they saw. No silent multipliers.
function module.AddCurrencyRaw(Player, amount, Currency)
	local Profile = Profiles[Player]
	if not Profile then return end
	Profile.Data[Currency] = (Profile.Data[Currency] or 0) + amount
	local CurrencyAmount = Profile.Data[Currency]
	if not Player.leaderstats:FindFirstChild(Currency) then
		Player[Currency].Value = CurrencyAmount
	else
		Player.leaderstats[Currency].Value = CurrencyAmount
	end
	if Currency == "Wins" or Currency == "Streak" then
		if LeaderboardModule then LeaderboardModule.SavePlayerStats(Player) end
	end
	print("[DATAHANDLER] AddCurrencyRaw:", Player.Name, "| +" .. amount, Currency,
		"| total:", CurrencyAmount)
end

function module.RemoveCurrency(Player, amount, Currency)
	local Profile = Profiles[Player]
	if Profile then
		Profile.Data[Currency] -= amount
		local CurrencyAmount = Profile.Data[Currency]
		if not Player.leaderstats:FindFirstChild(Currency) then
			Player[Currency].Value = CurrencyAmount
		else
			Player.leaderstats[Currency].Value = CurrencyAmount
		end
		if Currency == "Wins" or Currency == "Streak" then
			if LeaderboardModule then LeaderboardModule.SavePlayerStats(Player) end
		end
	end
end

function module.SetCurrency(Player, amount, Currency)
	local Profile = Profiles[Player]
	if Profile then
		Profile.Data[Currency] = amount
		local CurrencyAmount = Profile.Data[Currency]
		if not Player.leaderstats:FindFirstChild(Currency) then
			Player[Currency].Value = CurrencyAmount
		else
			Player.leaderstats[Currency].Value = CurrencyAmount
		end
		if Currency == "Wins" or Currency == "Streak" then
			if LeaderboardModule then LeaderboardModule.SavePlayerStats(Player) end
		end
	end
end

function module.GetProfile(player)
	return Profiles[player]
end

function module.GetEquippedLuck(player)
	return getPlayerLuckValue(player)
end

function module.GetCombinedLuck(player1, player2)
	return getPlayerLuckValue(player1) + getPlayerLuckValue(player2)
end

function module.GetTruthRate(player)
	local profile = Profiles[player]
	if not profile then return 100 end
	return computeTruthRate(profile)
end

function module.RecordDeclaration(player, wasTrue)
	local profile = Profiles[player]
	if not profile then
		print("[TRUTHRATE] RecordDeclaration called but no profile found for", player.Name)
		return
	end
	profile.Data.GamesAsPresenter = (profile.Data.GamesAsPresenter or 0) + 1
	if wasTrue then
		profile.Data.TruthfulDeclarations = (profile.Data.TruthfulDeclarations or 0) + 1
	end
	local rate = computeTruthRate(profile)
	print("[TRUTHRATE]", player.Name, "was", wasTrue and "TRUTHFUL" or "LYING",
		"| Games:", profile.Data.GamesAsPresenter,
		"| Truthful:", profile.Data.TruthfulDeclarations,
		"| Rate:", rate .. "%")
	updateOverhead(player)
end

function module.EquipChair(player, Chair)
	local Profile = Profiles[player]
	if not table.find(Profile.Data.Chairs, Chair) then
		module.AddChair(player, Chair)
	end
	Profile.Data.EquippedChair = Chair
	player.EquippedChair.Value = Chair
	updateCashMultiplier(player)  -- chair's CashMult takes effect immediately
	Network.sendToClient(player, "UpdateChairs")
	updateOverhead(player)
end

-- ── Chair boost accessors (used by the duel reward logic) ──────────────────
-- Returns the equipped chair's flat bonus cash per round won (raw, unmultiplied).
function module.GetChairCashPerRound(player)
	local equippedVal = player:FindFirstChild("EquippedChair")
	if not equippedVal then return 0 end
	local data = ChairInfo[equippedVal.Value]
	return (data and data.CashPerRound) or 0
end

-- Returns the equipped chair's streak-bonus percent (per streak level).
function module.GetChairStreakBonus(player)
	local equippedVal = player:FindFirstChild("EquippedChair")
	if not equippedVal then return 0 end
	local data = ChairInfo[equippedVal.Value]
	return (data and data.StreakBonus) or 0
end

function module.AddChair(player, Chair)
	local Profile = Profiles[player]
	if not Profile then
		warn("[CHAIRS] AddChair called for", player and player.Name, "with no loaded profile — ignoring")
		return
	end
	if not ChairInfo[Chair] then
		warn("[CHAIRS] AddChair called with unknown chair:", tostring(Chair), "— ignoring")
		return
	end
	if not table.find(Profile.Data.Chairs, Chair) then
		table.insert(Profile.Data.Chairs, Chair)
		local a = Instance.new("StringValue")
		a.Parent = player.Chairs; a.Name = Chair
		Network.sendToClient(player, "UpdateChairs")
		task.spawn(function()
			task.wait(2.375)
			Network.sendToClient(player, "ShowChairReward", Chair)
		end)
	else
		Network.sendToClient(player, "Notify", "You already own this chair!", "Warning")
	end
end

function module.AddItem(Player, ItemName)
	local Profile = Profiles[Player]
	if Profile and not Profile.Data.Items[ItemName] then
		if not table.find(Profile.Data.Items, ItemName) then
			table.insert(Profile.Data.Items, ItemName)
		end
		local tool = ItemsFolder:FindFirstChild(ItemName)
		if tool then
			tool = tool:Clone()
			tool.Parent = Player.Backpack
		end
	end
end

function module.RemoveItem(Player, ItemName)
	local Profile = Profiles[Player]
	if Profile and not Profile.Data.Items[ItemName] then
		if table.find(Profile.Data.Items, ItemName) then
			table.remove(Profile.Data.Items, Profile.Data.Items[ItemName])
		end
		local tool = Player.Backpack:FindFirstChild(ItemName)
		if tool then tool:Destroy() end
	end
end

function module.ClearItems(Player)
	local Profile = Profiles[Player]
	if Profile then
		for i = #Profile.Data.Items, 1, -1 do
			local item = Profile.Data.Items[i]
			module.RemoveItem(Player, item)
		end
	end
end

function module.DoRebirth(player)
	print("[REBIRTH] DoRebirth called for", player.Name)
	local profile = Profiles[player]
	if not profile then
		print("[REBIRTH] No profile found for", player.Name)
		return false
	end

	local rebirthLevel = profile.Data.RebirthLevel or 0
	local required     = getRebirthRequirement(rebirthLevel)
	local currentCash  = profile.Data.Cash or 0

	print("[REBIRTH]", player.Name, "| level:", rebirthLevel, "| cash:", currentCash, "| required:", required)

	if currentCash < required then
		print("[REBIRTH] Not enough cash — rejecting")
		return false
	end

	profile.Data.Cash             = 0
	player.leaderstats.Cash.Value = 0
	print("[REBIRTH] Cash reset to 0")

	profile.Data.Chairs        = {"Basic"}
	profile.Data.EquippedChair = "Basic"
	player.EquippedChair.Value = "Basic"
	local chairFolder = player:FindFirstChild("Chairs")
	if chairFolder then
		for _, v in ipairs(chairFolder:GetChildren()) do v:Destroy() end
		local basic = Instance.new("StringValue")
		basic.Name = "Basic"; basic.Parent = chairFolder
		print("[REBIRTH] Chairs reset to Basic only")
	end

	local newLevel            = rebirthLevel + 1
	profile.Data.RebirthLevel = newLevel
	local rlVal = player:FindFirstChild("RebirthLevel")
	if rlVal then
		rlVal.Value = newLevel
		print("[REBIRTH] RebirthLevel value set to", newLevel)
	else
		print("[REBIRTH] WARNING — no RebirthLevel IntValue found on player!")
	end

	updateCashMultiplier(player)
	Network.sendToClient(player, "UpdateChairs")
	updateOverhead(player)

	local newMult = string.format("%.2f", 1 + newLevel * 0.25)
	print("[REBIRTH]", player.Name, "rebirthed to level", newLevel, "| multiplier now", newMult .. "x")

	Network.sendToClient(player, "Notify",
		"🌟 Rebirth " .. newLevel .. "! Cash multiplier: " .. newMult .. "x", "Confirmation")

	return true
end

function module.DoRebirthFree(player)
	print("[REBIRTH] DoRebirthFree called for", player.Name)
	local profile = Profiles[player]
	if not profile then
		print("[REBIRTH] No profile found for", player.Name)
		return false
	end

	local rebirthLevel = profile.Data.RebirthLevel or 0
	local newLevel     = rebirthLevel + 1

	profile.Data.RebirthLevel = newLevel
	local rlVal = player:FindFirstChild("RebirthLevel")
	if rlVal then
		rlVal.Value = newLevel
		print("[REBIRTH] RebirthLevel (free) set to", newLevel)
	else
		print("[REBIRTH] WARNING — no RebirthLevel IntValue found on player!")
	end

	updateCashMultiplier(player)
	updateOverhead(player)

	local newMult = string.format("%.2f", 1 + newLevel * 0.25)
	print("[REBIRTH]", player.Name, "free rebirthed to level", newLevel, "| multiplier now", newMult .. "x")

	Network.sendToClient(player, "Notify",
		"🌟 Rebirth " .. newLevel .. "! Cash multiplier: " .. newMult .. "x", "Confirmation")

	return true
end

function module.GetRebirthRequirement(level)
	return getRebirthRequirement(level)
end

function module.ClaimDailyReward(Player)
	local Profile = Profiles[Player]
	if not Profile then return false end
	local currentTime = os.time()
	local lastClaim   = Profile.Data.DailyLastClaim
	local currentDay  = Profile.Data.DailyDay
	if currentTime - lastClaim >= DailyRewardsInfo.DailyTimer then
		local reward = DailyRewardsInfo[currentDay]
		if reward then
			if reward.RewardType == "Cash" then
				-- Daily rewards DO apply the multiplier (friend/rebirth bonus)
				module.AddCurrency(Player, reward.Amount, "Cash")
			elseif reward.RewardType == "Chair" then
				module.AddChair(Player, reward.Name)
			end
			Profile.Data.DailyLastClaim = currentTime
			Player.DailyLastClaim.Value = currentTime
			if currentDay < 7 then
				Profile.Data.DailyDay = currentDay + 1
				Player.DailyDay.Value = currentDay + 1
			else
				Profile.Data.DailyDay = 1
				Player.DailyDay.Value = 1
			end
			return true
		end
	end
	return false
end

function module.StorePendingStreak(player, amount)
	local uid = player.UserId
	pendingSaveStreaks[uid] = amount
	task.delay(15, function()
		if pendingSaveStreaks[uid] == amount then
			pendingSaveStreaks[uid] = nil
		end
	end)
end

function module.IsRollLocked(userId)
	return rollLocked[userId] == true
end

function module.RestorePendingStreak(player)
	local uid    = player.UserId
	local amount = pendingSaveStreaks[uid] or 0
	pendingSaveStreaks[uid] = nil
	if amount > 0 then
		module.SetCurrency(player, amount, "Streak")
	end
	return amount
end

function module.SetLeaderboardModule(leaderboardMod)
	LeaderboardModule = leaderboardMod
end

function module.SetStreakStealerModule(handler)
	StreakStealerModule = handler
end

function module.SetCasesHandler(handler)
	CasesHandlerRef = handler
	print("[TRUTHREVEAL] CasesHandler reference set")
end

local function grantCasePurchase(player, receiptInfo)
	local ItemName, Type = Utils.GetProductNameById(receiptInfo.ProductId)
	local caseName = DevProducts[ItemName] and DevProducts[ItemName].CaseName
	if not caseName then return end
	rollLocked[player.UserId] = true
	if Type == "Pack" then
		Network.sendToClient(player, "OpenPack", caseName)
	else
		-- "Case", "OPRoll", "SuperOPRoll" all open a single crate roll
		Network.sendToClient(player, "OpenCase", caseName)
		Network.sendToClient(player, "Notify", "🎉 Opening " .. caseName .. "...", "Confirmation")
	end
end

local function ProcessReciept(receiptInfo)
	local PlayerId  = receiptInfo.PlayerId
	local ProductId = receiptInfo.ProductId
	local Player    = Players:GetPlayerByUserId(PlayerId)
	if Player then
		local ItemName, Type = Utils.GetProductNameById(ProductId)
		if Type == "Cash" then
			local Amount = DevProducts[ItemName].Amount
			module.AddCurrency(Player, Amount, "Cash")
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if Type == "Chair" then
			module.AddChair(Player, ItemName)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if Type == "Skip" then
			local Profile = Profiles[Player]
			if Profile then
				local currentTime = os.time()
				Profile.Data.DailyLastClaim = currentTime - DailyRewardsInfo.DailyTimer
				Player.DailyLastClaim.Value  = currentTime - DailyRewardsInfo.DailyTimer
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if Type == "SkipRebirth" then
			module.DoRebirthFree(Player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if Type == "Item" then
			module.AddItem(Player, ItemName)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if Type == "Case" or Type == "Pack" or Type == "OPRoll" or Type == "SuperOPRoll" then
			-- Lucky rolls (OPRoll/SuperOPRoll) are instant boosted crate opens —
			-- they ride the same queue/grant pipeline as normal case purchases.
			if rollLocked[PlayerId] then
				print("[CASEOPENER] Player", Player.Name, "is mid-roll — queuing", Type, "purchase")
				if not pendingCasePurchases[PlayerId] then
					pendingCasePurchases[PlayerId] = {}
				end
				table.insert(pendingCasePurchases[PlayerId], receiptInfo)
				Network.sendToClient(Player, "CaseRollBusy")
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			grantCasePurchase(Player, receiptInfo)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if Type == "Revenge" then
			-- Repurposed: "Remove Loss" — erases one loss from the buyer's record.
			module.RemoveLoss(Player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if Type == "Troll" then
			local rd = pendingRevenge[PlayerId]
			if rd and rd.winnerUserId then
				local target = Players:GetPlayerByUserId(rd.winnerUserId)
				if target then Network.sendToClient(target, "Jumpscare") end
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if Type == "ServerOPRoll" or Type == "ServerSuperOPRoll" then
			-- One player buys, EVERYONE in the server gets a lucky crate roll.
			local isSuper     = Type == "ServerSuperOPRoll"
			local crate       = isSuper and "SuperLuckyRoll" or "LuckyRoll"
			local rollProduct = isSuper and "SuperOPRoll" or "OPRoll"
			local productId   = DevProducts[rollProduct] and DevProducts[rollProduct].ID
			local color       = isSuper and {r=0,g=255,b=255} or {r=255,g=0,b=255}
			local boughtStr   = Player.Name .. " bought everyone a " .. (isSuper and "SUPER LUCKY ROLL" or "LUCKY ROLL") .. "!!"
			for _, p in ipairs(Players:GetPlayers()) do
				Network.sendToClient(p, "OPRolls_Bought", boughtStr, color.r, color.g, color.b)
				if rollLocked[p.UserId] then
					-- Mid-roll: queue a synthetic personal-roll receipt; it flushes
					-- through SetRollLocked when their current animation finishes.
					if productId then
						if not pendingCasePurchases[p.UserId] then pendingCasePurchases[p.UserId] = {} end
						table.insert(pendingCasePurchases[p.UserId], { ProductId = productId, PlayerId = p.UserId })
					end
				else
					rollLocked[p.UserId] = true
					Network.sendToClient(p, "OpenCase", crate)
				end
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if Type == "RevealTruth" then
			local pvpOpponent = CasesHandlerRef and CasesHandlerRef.GetOpponent(Player) or nil
			if pvpOpponent then
				local rate = module.GetTruthRate(pvpOpponent)
				print("[TRUTHREVEAL]", Player.Name, "revealed PvP opponent", pvpOpponent.Name, "rate:", rate .. "%")
				Network.sendToClient(Player, "Notify",
					"🔍 " .. pvpOpponent.Name .. "'s Truth Rate: " .. rate .. "%", "Confirmation")
			else
				local aiRate = CasesHandlerRef and CasesHandlerRef.GetAIOpponentTruthRate(Player) or nil
				if aiRate then
					print("[TRUTHREVEAL]", Player.Name, "revealed AI opponent rate:", aiRate .. "%")
					Network.sendToClient(Player, "Notify",
						"🔍 Opponent's Truth Rate: " .. aiRate .. "%", "Confirmation")
				else
					Network.sendToClient(Player, "Notify",
						"You must be in a game to reveal a Truth Rate!", "Warning")
				end
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if Type == "Save" then
			local restored = module.RestorePendingStreak(Player)
			Network.sendToClient(Player, "HC_HideSaveStreak")
			if restored > 0 then
				Network.sendToClient(Player, "Notify",
					"🔥 Your " .. restored .. " streak has been saved!", "Confirmation")
			else
				Network.sendToClient(Player, "Notify",
					"Your streak could not be restored (window expired).", "Warning")
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if Type == "StealCash" then
			if StreakStealerModule then
				local target = StreakStealerModule.GetAndClearTarget(Player)
				StreakStealerModule.ExecuteSteal(Player, target)
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if Type == "Steal" then
			if StreakStealerModule then
				local target = StreakStealerModule.GetAndClearTarget(Player)
				if target and target.Parent then
					local targetStreakVal = target:FindFirstChild("Streak")
					local stolenAmount    = targetStreakVal and targetStreakVal.Value or 0
					if stolenAmount > 0 then
						module.SetCurrency(Player, stolenAmount, "Streak")
						module.SetCurrency(target, 0, "Streak")
						Network.sendToClient(Player, "StealStreakSuccess", {
							amount   = stolenAmount,
							fromName = target.Name,
						})
						Network.sendToClient(target, "StealStreakVictim", {
							byName = Player.Name,
						})
					else
						Network.sendToClient(Player, "Notify",
							target.Name .. " has no streak left!", "Warning")
					end
				else
					Network.sendToClient(Player, "Notify",
						"Target player is no longer in the server.", "Warning")
				end
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	else
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

-- ─── Network handlers ────────────────────────────────────────────────────────

Network.onServer("CaseRollDone", function(player)
	print("[CASEOPENER] CaseRollDone from", player.Name, "— releasing roll lock")
	module.SetRollLocked(player.UserId, false)
end)

Network.onServer("Rebirth_Request", function(player)
	print("[REBIRTH] Rebirth_Request received from", player.Name)
	local profile = Profiles[player]
	if not profile then
		print("[REBIRTH] No profile — ignoring")
		return
	end
	local rebirthLevel = profile.Data.RebirthLevel or 0
	local required     = getRebirthRequirement(rebirthLevel)
	local currentCash  = profile.Data.Cash or 0
	print("[REBIRTH] cash:", currentCash, "| required:", required)
	if currentCash < required then
		Network.sendToClient(player, "Rebirth_Result", false, "Need $" .. required)
		return
	end
	local ok = module.DoRebirth(player)
	Network.sendToClient(player, "Rebirth_Result", ok, ok and "Confirmation" or "Failed")
end)

Network.onServer("AddCurrency", function(player, amount, currency)
	module.AddCurrency(player, amount, currency)
end)

Network.onServer("GiveFreeGift", function(player)
	local Profile = Profiles[player]
	if not Profile then return end

	if Profile.Data.FreeGiftClaimed then
		Network.sendToClient(player, "Notify", "You have already claimed this gift!", "Warning")
		return
	end

	local inGroup = false
	pcall(function() inGroup = player:IsInGroup(1049098079) end)
	if not inGroup then
		Network.sendToClient(player, "Notify", "You need to join the group first to claim this free chair!", "Warning")
		return
	end

	Profile.Data.FreeGiftClaimed = true
	module.AddChair(player, "Evil")
	Network.sendToClient(player, "Notify", "You got a free chair!", "Confirmation")
	Network.sendToClient(player, "FreeGiftStatus", true)
end)

Network.onServer("LeaveReward_Claim", function(player)
	local Profile = Profiles[player]
	if not Profile then return end

	local lastClaim   = Profile.Data.LuckBonusLastClaim or 0
	local elapsed     = os.time() - lastClaim
	local canClaim    = elapsed >= LEAVE_REWARD_COOLDOWN

	print("[LEAVEREWARD] Claim request from", player.Name,
		"| elapsed:", elapsed, "| canClaim:", canClaim)

	if not canClaim then
		local remaining = LEAVE_REWARD_COOLDOWN - elapsed
		local hours     = math.floor(remaining / 3600)
		local mins      = math.floor((remaining % 3600) / 60)
		Network.sendToClient(player, "Notify",
			string.format("⏳ Come back in %dh %dm for your next reward!", hours, mins), "Warning")
		Network.sendToClient(player, "LeaveReward_Result", false)
		Network.sendToClient(player, "LeaveReward_Status", false)
		return
	end

	Profile.Data.LuckBonusLastClaim = os.time()

	local bonusLuckVal = player:FindFirstChild("BonusLuck")
	if bonusLuckVal then
		bonusLuckVal.Value = bonusLuckVal.Value + LEAVE_REWARD_LUCK
		print("[LEAVEREWARD]", player.Name, "BonusLuck now:", bonusLuckVal.Value)
	end

	updateOverhead(player)

	Network.sendToClient(player, "Notify",
		"🍀 +" .. LEAVE_REWARD_LUCK .. "% Luck claimed! NOT PERMANENT", "Confirmation")
	Network.sendToClient(player, "LeaveReward_Result", true)
	Network.sendToClient(player, "LeaveReward_Status", false)
end)

Network.onServer("EquipChair", function(player, chair)
	if chair == nil then
		module.EquipChair(player, "Basic")
	else
		module.EquipChair(player, chair)
	end
end)

Network.onServer("AddChair", function(player, chair)
	module.AddChair(player, chair)
end)

Network.onServerInvoke("OwnsChair", function(player, Chair)
	local Profile = Profiles[player]
	if table.find(Profile.Data.Chairs, Chair) then
		return true
	else
		return false
	end
end)

Network.onServer("PlaytimeNotify", function(player, rewardIndex)
	local info = PlaytimeRewardsInfo[rewardIndex]
	if not info then return end
	Network.sendToClient(player, "Notify",
		"🎁 Playtime Reward #" .. rewardIndex .. " is ready to claim!", "Confirmation")
end)

Network.onServer("ClaimPlaytime", function(player, rewardIndex)
	local userId   = player.UserId
	local start    = sessionStartTimes[userId]
	local claimed  = claimedPlaytimeRewards[userId]

	if not start or not claimed then return end
	if claimed[rewardIndex] then return end

	local info = PlaytimeRewardsInfo[rewardIndex]
	if not info then return end

	local elapsed = os.time() - start
	if elapsed < info.TimeReq then return end   -- client can't spoof an early claim

	-- ── Mark claimed ──────────────────────────────────────────────────────────
	claimed[rewardIndex] = true

	-- ── Grant reward ──────────────────────────────────────────────────────────
	if info.RewardType == "Cash" then
		module.AddCurrency(player, info.Amount, "Cash")
		Network.sendToClient(player, "Notify",
			"💰 Playtime #" .. rewardIndex .. ": $" .. info.Amount .. " claimed!", "Confirmation")

	elseif info.RewardType == "OPRoll" or info.RewardType == "SuperRoll" then
		-- Playtime lucky rolls: instant boosted crate opens, same pipeline as the
		-- dev products. First roll opens now; any extras queue and flush as each
		-- roll animation finishes (CaseRollDone → SetRollLocked → next in queue).
		local isSuper   = info.RewardType == "SuperRoll"
		local crate     = isSuper and "SuperLuckyRoll" or "LuckyRoll"
		local product   = isSuper and "SuperOPRoll" or "OPRoll"
		local productId = DevProducts[product] and DevProducts[product].ID
		local amount    = info.Amount or 1
		for i = 1, amount do
			if i == 1 and not rollLocked[userId] then
				rollLocked[userId] = true
				Network.sendToClient(player, "OpenCase", crate)
			elseif productId then
				if not pendingCasePurchases[userId] then pendingCasePurchases[userId] = {} end
				table.insert(pendingCasePurchases[userId], { ProductId = productId, PlayerId = userId })
			end
		end
		Network.sendToClient(player, "Notify",
			"🎲 Playtime #" .. rewardIndex .. ": " .. amount .. "x " .. (isSuper and "Super Lucky Roll" or "Lucky Roll") .. " claimed!", "Confirmation")

	elseif info.RewardType == "Chair" then
		module.AddChair(player, info.ChairName)
		-- AddChair already sends its own notify + ShowChairReward, so no extra notify needed
	end

	Network.sendToClient(player, "PlaytimeClaimResult", rewardIndex, true)
end)

Network.onServer("ClaimDaily", function(player)
	local success = module.ClaimDailyReward(player)
	Network.sendToClient(player, "DailyClaimResult", success)
end)

Network.onServer("CompleteTutorial", function(player)
	local Profile = Profiles[player]
	if Profile then
		Profile.Data.TutorialDone = true
		if player:FindFirstChild("TutorialDone") then
			player.TutorialDone.Value = true
		end
	end
end)

MarketplaceService.ProcessReceipt = ProcessReciept

-- Mid-session game-pass purchase: refresh the ownership cache and re-apply the
-- cash multiplier so 2x Coins / VIP take effect immediately without a rejoin.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if not wasPurchased then return end
	gamePassOwned[player.UserId] = gamePassOwned[player.UserId] or {}
	gamePassOwned[player.UserId][passId] = true
	if Profiles[player] then
		updateCashMultiplier(player)
		if passId == (GamePasses["VIP"] and GamePasses["VIP"].ID) then
			Network.sendToClient(player, "Notify", "⭐ VIP activated! +50% cash.", "Confirmation")
		elseif passId == (GamePasses["2x Coins"] and GamePasses["2x Coins"].ID) then
			Network.sendToClient(player, "Notify", "💰 2x Coins activated!", "Confirmation")
		end
	end
end)

game.Players.PlayerAdded:Connect(function(player)
	module.Load(player)
end)

game.Players.PlayerRemoving:Connect(function(player)
	-- Clean up any active cases/cash session before saving
	if CasesHandlerRef then
		pcall(function() CasesHandlerRef.HandlePlayerLeft(player) end)
	end
	module.Save(player)
	pendingSaveStreaks[player.UserId]    = nil
	rollLocked[player.UserId]           = nil
	pendingCasePurchases[player.UserId] = nil
	sessionStartTimes[player.UserId]      = nil
	claimedPlaytimeRewards[player.UserId] = nil
	gamePassOwned[player.UserId]          = nil
	task.spawn(updateAllPlayerMultipliers)
end)

-- ─── 2x Luck Event Loop ───────────────────────────────────────────────────────
task.spawn(function()
	luckEventActive = getLuckEventPhase()
	while true do
		task.wait(1)
		local active, _ = getLuckEventPhase()
		if active ~= luckEventActive then
			luckEventActive = active
			broadcastLuckEvent()
			for _, player in ipairs(Players:GetPlayers()) do
				updateOverhead(player)
			end
			print("[LUCKEVENT]", active and "🍀 2x Luck event STARTED" or "🍀 2x Luck event ENDED")
		end
	end
end)
-- ─────────────────────────────────────────────────────────────────────────────

local StreakStealer = require(script.Parent.StreakStealer)
StreakStealer.SetDataHandler(module)
module.SetStreakStealerModule(StreakStealer)

print("[DATAHANDLER] Fully loaded")

return module