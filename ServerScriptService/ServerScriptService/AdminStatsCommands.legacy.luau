--[[
	AdminStatsCommands  (Server Script — ServerScriptService)
	Dev chat commands to grant/set player stats.

	Type in chat:
	  /give <player> <amount> <stat>   -- ADD amount to a stat
	  /set  <player> <amount> <stat>   -- SET a stat to an exact value
	  /stats <player>                  -- print a player's current stats

	  <player> : full or partial username (case-insensitive), or "me"
	  <stat>   : cash | wins | losses | streak   (aliases: money, win, loss)

	Examples:
	  /give qsy4 25 wins
	  /give me 100000 cash
	  /give qsy4 -5 wins      (negative removes)
	  /set qsy4 0 streak

	Only names/UserIds in ADMINS (plus the place owner, and any Studio
	test player) can use these. Edit the ADMINS table below to add people.
]]

local Players     = game:GetService("Players")
local SSS         = game:GetService("ServerScriptService")
local DataHandler = require(SSS.Modules.DataHandler)

-- ── Who can use these commands ──────────────────────────────────────────
local ADMINS = {
	["qsy4"] = true,
	-- ["friendname"] = true,
	-- [123456789]   = true,   -- by UserId
}

local PREFIX = "/"

local STAT_ALIASES = {
	cash = "Cash", money = "Cash",
	wins = "Wins", win = "Wins",
	losses = "Losses", loss = "Losses",
	streak = "Streak",
}

local function isAdmin(player)
	if ADMINS[player.Name:lower()] then return true end
	if ADMINS[player.UserId] then return true end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then return true end
	if player.UserId < 1 then return true end   -- Studio test player
	return false
end

local function resolvePlayer(sender, query)
	query = (query or ""):lower()
	if query == "" or query == "me" or query == "self" then return sender end
	local prefixMatch
	for _, p in ipairs(Players:GetPlayers()) do
		local n = p.Name:lower()
		if n == query then return p end
		if not prefixMatch and n:sub(1, #query) == query then prefixMatch = p end
	end
	return prefixMatch
end

local function notify(msg)
	print("[ADMINSTATS] " .. msg)
end

local function applyGive(sender, targetQuery, amountStr, statStr, absolute)
	local target = resolvePlayer(sender, targetQuery)
	if not target then notify("no player matching '" .. tostring(targetQuery) .. "'") return end

	local amount = tonumber(amountStr)
	if not amount then notify("amount '" .. tostring(amountStr) .. "' is not a number") return end
	amount = math.floor(amount)

	local stat = STAT_ALIASES[(statStr or ""):lower()]
	if not stat then notify("unknown stat '" .. tostring(statStr) .. "' (use cash/wins/losses/streak)") return end

	local ok, err = pcall(function()
		if absolute then
			DataHandler.SetCurrency(target, amount, stat)
		elseif stat == "Cash" then
			DataHandler.AddCurrencyRaw(target, amount, "Cash")  -- exact, ignores cash multiplier
		else
			DataHandler.AddCurrency(target, amount, stat)
		end
	end)

	if ok then
		notify(string.format("%s %s %s %s%d  (by %s)",
			absolute and "SET" or "GAVE", target.Name, stat,
			absolute and "= " or "+", amount, sender.Name))
	else
		notify("failed: " .. tostring(err))
	end
end

local function printStats(sender, targetQuery)
	local target = resolvePlayer(sender, targetQuery)
	if not target then notify("no player matching '" .. tostring(targetQuery) .. "'") return end
	local profile = DataHandler.GetProfile and DataHandler.GetProfile(target)
	local data = profile and (profile.Data or profile)
	if not data or not data.Cash then notify(target.Name .. ": profile not loaded") return end
	notify(string.format("%s | Cash=%s Wins=%s Losses=%s Streak=%s",
		target.Name, tostring(data.Cash), tostring(data.Wins), tostring(data.Losses), tostring(data.Streak)))
end

local function onChatted(sender, message)
	if not isAdmin(sender) then return end
	if message:sub(1, #PREFIX) ~= PREFIX then return end
	local args = {}
	for w in message:sub(#PREFIX + 1):gmatch("%S+") do args[#args + 1] = w end
	local cmd = (args[1] or ""):lower()

	if cmd == "give" then
		applyGive(sender, args[2], args[3], args[4], false)
	elseif cmd == "set" then
		applyGive(sender, args[2], args[3], args[4], true)
	elseif cmd == "stats" then
		printStats(sender, args[2])
	end
end

Players.PlayerAdded:Connect(function(p)
	p.Chatted:Connect(function(msg) onChatted(p, msg) end)
end)
for _, p in ipairs(Players:GetPlayers()) do
	p.Chatted:Connect(function(msg) onChatted(p, msg) end)
end

print("[ADMINSTATS] ready | /give <player> <amount> <stat> | /set | /stats")
