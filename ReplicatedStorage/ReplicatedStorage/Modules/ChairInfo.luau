-- Chair boost stats (all optional; a chair can have 1, 2, or all 3):
--   CashMult     = percent added to the player's cash multiplier (e.g. 10 = +10% cash on every win)
--   CashPerRound = flat bonus cash awarded for EACH round you win (raw, not multiplied)
--   StreakBonus  = percent extra cash per current win-streak level (e.g. 2 = +2% per streak)
-- Luck is retained for backwards-compat but is no longer used by the duel game.
local module = {
	["Basic"] = {
		Name = "Basic",
		Rarity = "Common",
		ImageId = "rbxassetid://85968617500696",
		CashMult = 2,
	},
	["Yellow"] = {
		Name = "Yellow",
		Rarity = "Common",
		ImageId = "rbxassetid://83990726536027",
		CashMult = 3,
	},
	["Green"] = {
		Name = "Green",
		Rarity = "Common",
		ImageId = "rbxassetid://130792724407147",
		CashMult = 5,
	},
	["Bin"] = {
		Name = "Bin",
		Rarity = "Common",
		ImageId = "rbxassetid://93584868192284",
		CashPerRound = 5,
	},
	["Rock"] = {
		Name = "Rock",
		Rarity = "Common",
		ImageId = "rbxassetid://113810910097550",
		CashMult = 7,
	},
	["Mailbox"] = {
		Name = "Mailbox",
		Rarity = "Rare",
		ImageId = "rbxassetid://75246252051770",
		CashMult = 12,
	},
	["Beach"] = {
		Name = "Beach",
		Rarity = "Rare",
		ImageId = "rbxassetid://77415909453022",
		CashPerRound = 10,
	},
	["Football"] = {
		Name = "Football",
		Rarity = "Rare",
		ImageId = "rbxassetid://130877149543138",
		StreakBonus = 3,
	},
	["Toilet"] = {
		Name = "Toilet",
		Rarity = "Rare",
		ImageId = "rbxassetid://91841990749841",
		CashMult = 15,
	},
	["Chicken"] = {
		Name = "Chicken",
		Rarity = "Rare",
		ImageId = "rbxassetid://96467173082396",
		CashPerRound = 15,
	},
	["Invisible"] = {
		Name = "Invisible",
		Rarity = "Rare",
		ImageId = "rbxassetid://96483806819748",
		StreakBonus = 5,
	},
	["Evil"] = {
		Name = "Evil",
		Rarity = "Legendary",
		ImageId = "rbxassetid://117477690275396",
		CashMult = 25,
		StreakBonus = 4,
	},
	["Pumpkin"] = {
		Name = "Pumpkin",
		Rarity = "Legendary",
		ImageId = "rbxassetid://99841181579694",
		CashPerRound = 25,
	},
	["Wheelchair"] = {
		Name = "Wheelchair",
		Rarity = "Legendary",
		ImageId = "rbxassetid://109686293970492",
		CashMult = 30,
		CashPerRound = 15,
	},
	["Noob"] = {
		Name = "Noob",
		Rarity = "Legendary",
		ImageId = "rbxassetid://87776405564755",
		StreakBonus = 8,
	},
	["Office"] = {
		Name = "Office",
		Rarity = "Legendary",
		ImageId = "rbxassetid://88574499245168",
		CashMult = 35,
		CashPerRound = 20,
	},
	["Beanbag"] = {
		Name = "Beanbag",
		Rarity = "Legendary",
		ImageId = "rbxassetid://138301936209168",
		CashMult = 40,
		StreakBonus = 6,
	},
	["Throne"] = {
		Name = "Throne",
		Rarity = "Legendary",
		ImageId = "rbxassetid://137423173131019",
		Limited = true,
		CashMult = 45,
		CashPerRound = 25,
	},
	["Gamer"] = {
		Name = "Gamer",
		Rarity = "Legendary",
		ImageId = "rbxassetid://76835561466311",
		CashMult = 50,
		StreakBonus = 8,
	},
	["Present"] = {
		Name = "Present",
		Rarity = "Mythical",
		ImageId = "rbxassetid://86580657043320",
		CashMult = 60,
		CashPerRound = 30,
	},
	["67"] = {
		Name = "67",
		Rarity = "Mythical",
		ImageId = "rbxassetid://94667919736406",
		CashMult = 67,
		CashPerRound = 35,
		StreakBonus = 10,
	},
	["BombardinoCrocodilo"] = {
		Name = "BombardinoCrocodilo",
		Rarity = "Mythical",
		ImageId = "rbxassetid://85141883374775",
		CashMult = 75,
		CashPerRound = 40,
		StreakBonus = 12,
	},
	["Error 404"] = {
		Name = "Error 404",
		Rarity = "Mythical",
		ImageId = "rbxassetid://125010572936321",
		CashMult = 100,
		CashPerRound = 50,
		StreakBonus = 15,
	},
}

-- Canonical boost-string builder used EVERYWHERE a chair's stats are shown
-- (inventory cards, free-reward popup, daily rewards, purchase-station
-- billboards). Keeping it here means every surface reads identically and can
-- never drift back to the old "% Luck" wording.
--   accepts either a chair name (string) or a chair-data table.
function module.GetBoostString(chairOrName)
	local data = chairOrName
	if type(chairOrName) == "string" then data = module[chairOrName] end
	if type(data) ~= "table" then return "No Boost" end
	local parts = {}
	if data.CashMult and data.CashMult > 0 then
		table.insert(parts, "+" .. data.CashMult .. "% Cash")
	end
	if data.CashPerRound and data.CashPerRound > 0 then
		table.insert(parts, "+$" .. data.CashPerRound .. "/Round")
	end
	if data.StreakBonus and data.StreakBonus > 0 then
		table.insert(parts, "+" .. data.StreakBonus .. "% Streak")
	end
	if #parts == 0 then return "No Boost" end
	return table.concat(parts, "  ")
end

return module