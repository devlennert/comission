-- devproducts:

	local module = {

		-------------------------------Cash---------------------

		["500 Cash"] = {

			Type = "Cash",

			ID = 3603966732,

			Amount = 500

		},

		["2500 Cash"] = {

			Type = "Cash",

			ID = 3603966770,

			Amount = 2500

		},

		["10000 Cash"] = {

			Type = "Cash",

			ID = 3603966831,

			Amount = 10000

		},

		----------------------------Skip-----------------------

		["SkipRebirth"] = {

			Type = "SkipRebirth",

			ID = 3603967165,

		},

		["Skip"] = {

			Type = "Skip",

			ID = 3603967215,

		},

		-- [DISABLED] RevealTruth — old bluffing-PvP "reveal opponent truth rate" product.

		-- No function in the timer-duel game (no presenters/declarations/Truth Rate).

		-- ID preserved for reference; re-enable by uncommenting if PvP ever returns.

		-- ["RevealTruth"] = {

		-- 	Type = "RevealTruth",

		-- 	ID = 3557623953,

		-- },

		----------------------------Mythical Chairs (direct)----

		["67"] = {

			Type = "Chair",

			ID = 3603968733,

		},

		["BombardinoCrocodilo"] = {

			Type = "Chair",

			ID = 3603969593,

		},

		["Error 404"] = {

			Type = "Chair",

			ID = 3603969825,

		},

		----------------------------Cases-----------------------

		["BasicCase"] = {

			Type = "Case",

			ID = 3603970527,

			CaseName = "Basic",

		},

		["EpicCase"] = {

			Type = "Case",

			ID = 3603970550,

			CaseName = "Epic",

		},

		["MythicalCase"] = {

			Type = "Case",

			ID = 3603973871,

			CaseName = "Mythical",

		},

		["RainbowCase"] = {

			Type = "Case",

			ID = 3603973907,

			CaseName = "Rainbow",

		},

		----------------------------StealCash------------------

		-- Tiered by the TARGET's cash (see StreakStealerClient.getProductForCash).

		["StealCash1"] = { Type = "StealCash", ID = 3603973949 },

		["StealCash2"] = { Type = "StealCash", ID = 3603973986 },

		["StealCash3"] = { Type = "StealCash", ID = 3603974038 },

		["StealCash4"] = { Type = "StealCash", ID = 3603974086 },

		----------------------------Rolls-----------------------

		["OPRoll"]            = { Type = "OPRoll",            ID = 3603974114, CaseName = "LuckyRoll"      }, -- instant boosted crate roll

		["SuperOPRoll"]       = { Type = "SuperOPRoll",       ID = 3603974163, CaseName = "SuperLuckyRoll" }, -- instant super-boosted crate roll

		["ServerOPRoll"]      = { Type = "ServerOPRoll",      ID = 3603974291 },

		["ServerSuperOPRoll"] = { Type = "ServerSuperOPRoll", ID = 3603974336 },

		-- Remove Loss — undoes the buyer's most recent duel loss (cash + streak +

		-- removes the loss). Repurposed from old "Revenge"; Type stays "Revenge".

		["Revenge"] = { Type = "Revenge", ID = 3603974440 },

		-- Troll — jumpscares the player who won the duel. Type stays "Troll".

		["Troll"]   = { Type = "Troll",   ID = 3603974477 },

		----------------------------Packs-----------------------

		["MythicalPack"] = { Type = "Pack", ID = 3603974477, CaseName = "Mythical" },
		["RainbowPack"]  = { Type = "Pack", ID = 3603974477, CaseName = "Rainbow"  },

	}

return module

