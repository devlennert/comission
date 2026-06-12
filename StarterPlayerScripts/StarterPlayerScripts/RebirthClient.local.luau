-- RebirthClient (LocalScript)
local Players             = game:GetService("Players")
local TweenService        = game:GetService("TweenService")
local MarketplaceService  = game:GetService("MarketplaceService")
local RS                  = game:GetService("ReplicatedStorage")

local player      = Players.LocalPlayer
local Network     = require(RS:WaitForChild("Modules"):WaitForChild("Network"))
local DevProducts = require(RS:WaitForChild("Modules"):WaitForChild("DevProducts"))

print("[REBIRTH CLIENT] Starting up...")

local ui           = player.PlayerGui:WaitForChild("UI")
local rebirthFrame = ui:WaitForChild("Rebirth")
local frame        = rebirthFrame:WaitForChild("Frame")

local bar      = frame:WaitForChild("Bar")
local barJuice = bar:WaitForChild("BarJuice")
local barText  = bar:WaitForChild("Text")

local Statss      = frame:WaitForChild("Stats")
local beforeFrame = Statss:WaitForChild("Before")
local afterFrame  = Statss:WaitForChild("After")
local beforeText  = beforeFrame:WaitForChild("Text")
local beforeMoney = beforeFrame:WaitForChild("Money"):WaitForChild("Text")
local afterText   = afterFrame:WaitForChild("Text")
local afterMoney  = afterFrame:WaitForChild("Money"):WaitForChild("Text")

rebirthFrame.Visible = false

local rebirthBtn = rebirthFrame:WaitForChild("Rebirth")
local skipBtn    = rebirthFrame:WaitForChild("Skip")

print("[REBIRTH CLIENT] All UI elements found")

local function formatCash(n)
	if n >= 1e9 then      return "$" .. math.floor(n / 1e8) / 10 .. "B"
	elseif n >= 1e6 then  return "$" .. math.floor(n / 1e5) / 10 .. "M"
	elseif n >= 1000 then return "$" .. math.floor(n / 100) / 10 .. "K"
	end
	return "$" .. n
end

local function getRequirement(level)
	return math.floor(450 * (1.75 ^ level))
end

local function updateUI()
	local rebirthVal = player:FindFirstChild("RebirthLevel")
	local ls         = player:FindFirstChild("leaderstats")
	local cashVal    = ls and ls:FindFirstChild("Cash")

	local rebirthLevel = rebirthVal and rebirthVal.Value or 0
	local cash         = cashVal    and cashVal.Value    or 0
	local required     = getRequirement(rebirthLevel)

	local currentMult = string.format("%.2f", 1 + rebirthLevel * 0.25)
	local nextMult    = string.format("%.2f", 1 + (rebirthLevel + 1) * 0.25)

	print("[REBIRTH CLIENT] updateUI — level:", rebirthLevel, "| cash:", cash, "| required:", required)

	beforeText.Text  = "Rebirth " .. rebirthLevel
	beforeMoney.Text = currentMult .. "x Cash"
	afterText.Text   = "Rebirth " .. (rebirthLevel + 1)
	afterMoney.Text  = nextMult .. "x Cash"

	barText.Text = formatCash(cash) .. " / " .. formatCash(required)

	local progress = math.clamp(cash / required, 0, 1)
	TweenService:Create(barJuice,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(progress, 0, 1, 0) }):Play()

	local canRebirth = cash >= required
	rebirthBtn.AutoButtonColor        = canRebirth
	rebirthBtn.Active                  = canRebirth
	rebirthBtn.BackgroundTransparency  = canRebirth and 0 or 0.45

	print("[REBIRTH CLIENT] progress:", progress, "| canRebirth:", canRebirth)
end

local function openUI()
	print("[REBIRTH CLIENT] Opening rebirth UI")
	updateUI()
	rebirthFrame.Visible = true
end

-- ── CLOSE / SKIP ──────────────────────────────────────────────────────────

skipBtn.MouseButton1Click:Connect(function()
	print("[REBIRTH CLIENT] Skip pressed — prompting SkipRebirth purchase")
	local productId = DevProducts.SkipRebirth.ID
	MarketplaceService:PromptProductPurchase(player, productId)
end)

local function hookClose(parent)
	for _, name in ipairs({"Close", "X", "CloseBtn", "Exit"}) do
		local btn = parent:FindFirstChild(name)
		if btn and btn:IsA("GuiButton") then
			btn.MouseButton1Click:Connect(function()
				print("[REBIRTH CLIENT] Close button pressed")
				rebirthFrame.Visible = false
			end)
			print("[REBIRTH CLIENT] Close button found:", btn:GetFullName())
			return
		end
	end
end
hookClose(rebirthFrame)
hookClose(frame)

-- ── REBIRTH BUTTON ────────────────────────────────────────────────────────

rebirthBtn.MouseButton1Click:Connect(function()
	print("[REBIRTH CLIENT] Rebirth button clicked")
	local rebirthVal = player:FindFirstChild("RebirthLevel")
	local ls         = player:FindFirstChild("leaderstats")
	local cashVal    = ls and ls:FindFirstChild("Cash")
	local level      = rebirthVal and rebirthVal.Value or 0
	local cash       = cashVal    and cashVal.Value    or 0
	local required   = getRequirement(level)

	print("[REBIRTH CLIENT] level:", level, "| cash:", cash, "| required:", required)

	if cash < required then
		print("[REBIRTH CLIENT] Not enough cash — aborting")
		return
	end

	print("[REBIRTH CLIENT] Sending Rebirth_Request to server")
	Network.send("Rebirth_Request")
end)

Network.onClient("Rebirth_Result", function(success, msg)
	print("[REBIRTH CLIENT] Got Rebirth_Result — success:", success, "| msg:", msg)
	if success then
		updateUI()
	end
end)

Network.onClient("Rebirth_Show", function()
	print("[REBIRTH CLIENT] Got Rebirth_Show")
	openUI()
end)

-- ── WATCH VALUES ──────────────────────────────────────────────────────────
task.spawn(function()
	local ls   = player:WaitForChild("leaderstats")
	local cash = ls:WaitForChild("Cash")
	local rl   = player:WaitForChild("RebirthLevel")

	print("[REBIRTH CLIENT] Watching Cash and RebirthLevel for changes")

	updateUI()

	cash.Changed:Connect(function()
		updateUI()
	end)

	rl.Changed:Connect(function()
		print("[REBIRTH CLIENT] RebirthLevel changed to:", rl.Value)
		updateUI()
	end)
end)

print("[REBIRTH CLIENT] Fully loaded")