return {
	
	["Common"] = {
		Name = "Common",
		Cost = 100,           -- ~5 small cash pickups, very accessible
		RarityChances = {
			Common    = 92,
			Rare      = 7,
			Legendary = 1,
		}
	},
	["Rare"] = {
		Name = "Rare",
		Cost = 500,           -- ~5 small cash pickups, very accessible
		RarityChances = {
			Common    = 80,
			Rare      = 15,
			Legendary = 4,
			Mythical  = 1,
		}
	},
	["Epic"] = {
		Name = "Epic",
		Cost = 5000,           -- ~3x Basic, noticeable step up
		RarityChances = {
			Common    = 60,
			Rare      = 28,
			Legendary = 9,    -- was 3% (WORSE than Basic), now properly better
			Mythical  = 3,
		}
	},
	["Mythical"] = {
		Name = "Mythical",
		Cost = 15000,          -- requires real grinding
		RarityChances = {
			Common    = 30,
			Rare      = 44,
			Legendary = 19,
			Mythical  = 7,
		}
	},
	["Rainbow"] = {
		Name = "Rainbow",
		Cost = 50000,          -- endgame crate, rare to buy
		RarityChances = {
			Common    = 15,
			Rare      = 35,
			Legendary = 40,
			Mythical  = 10,
		}
	},
	-- Premium "lucky" crates. Not purchasable with cash (no Cost keeps them
	-- out of the in-world cash stations); granted by the OPRoll / SuperOPRoll
	-- dev products (and their server-wide variants) via DataHandler receipts.
	["LuckyRoll"] = {
		Name = "Lucky Roll",
		PremiumOnly = true,
		RarityChances = {
			Common    = 10,
			Rare      = 30,
			Legendary = 45,
			Mythical  = 15,
		}
	},
	["SuperLuckyRoll"] = {
		Name = "Super Lucky Roll",
		PremiumOnly = true,
		RarityChances = {
			Rare      = 20,    -- never rolls Common
			Legendary = 50,
			Mythical  = 30,
		}
	},
}