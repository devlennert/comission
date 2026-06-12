-- CashConfig: maps each Cash model name → amount (in-game cash) and weight (probability)
-- Percentage shown on billboard = weight / totalWeight * 100 (auto-calculated)
-- Models are named 1–16 in ReplicatedStorage.Cash

return {
	["1"]  = { amount = 50,          weight = 1250, display = "$50"         },
	["2"]  = { amount = 100,         weight = 1300, display = "$100"        },
	["3"]  = { amount = 500,         weight = 1350, display = "$500"        },
	["4"]  = { amount = 1000,        weight = 1200, display = "$1,000"      },
	["5"]  = { amount = 5000,        weight = 1100,  display = "$5,000"      },
	["6"]  = { amount = 10000,       weight = 750,  display = "$10,000"     },
	["7"]  = { amount = 20000,       weight = 480,  display = "$20,000"     },

	-- rebalanced starts here
	["8"]  = { amount = 25000,       weight = 150,  display = "$25,000"     },
	["9"]  = { amount = 50000,       weight = 80,   display = "$50,000"     },
	["10"] = { amount = 100000,      weight = 55,   display = "$100,000"    },
	["11"] = { amount = 250000,      weight = 35,   display = "$250,000"    },
	["12"] = { amount = 500000,      weight = 20,   display = "$500,000"    },
	["13"] = { amount = 1000000,     weight = 10,   display = "$1,000,000"  },
	["14"] = { amount = 2500000,     weight = 5,    display = "$2,500,000"  },
	["15"] = { amount = 5000000,     weight = 3,    display = "$5,000,000"  },
	["16"] = { amount = 10000000,    weight = 0.5,    display = "$10,000,000" },
}