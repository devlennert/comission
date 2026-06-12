local module = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CaseInfo = require(ReplicatedStorage.Modules:WaitForChild("CaseInfo"))
local Network = require(ReplicatedStorage.Modules:WaitForChild("Network"))
local DataHandler = require(script.Parent.DataHandler)
-- Case-purchase stations for buying/rolling chairs. They live under
-- workspace.Map.Cases in this place; fall back to a top-level workspace.Cases
-- if they're ever moved there. Guarded so the module no-ops if absent.
local Cases = (workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Cases"))
	or workspace:FindFirstChild("Cases")
local CaseGradients = ReplicatedStorage.Assets:FindFirstChild("CaseGradients")

-- ── GRADIENT SETUP ────────────────────────────────────────────────────────────
local function applyGradients()
	for _, casePart in ipairs(Cases:GetChildren()) do
		local cashGui = casePart:FindFirstChild("CashGui")
		if not cashGui then continue end
		local caseName = cashGui:FindFirstChild("CaseName")
		local casePrice = cashGui:FindFirstChild("CasePrice")
		if caseName then
			if CaseGradients then
				local gradient = CaseGradients:FindFirstChild(casePart.Name)
				if gradient then
					for _, child in ipairs(caseName:GetChildren()) do
						if child:IsA("UIGradient") then child:Destroy() end
					end
					gradient:Clone().Parent = caseName
				end
			end
			caseName.Text = casePart.Name
		end
		if casePrice then
			local info = CaseInfo[casePart.Name]
			if info then
				casePrice.Text = "$" .. tostring(info.Cost)
			end
		end
	end
end

-- ── PURCHASE PROMPTS ──────────────────────────────────────────────────────────
local function setupPrompts()
	for _, casePart in ipairs(Cases:GetChildren()) do
		local prompt = casePart:FindFirstChild("PurchasePrompt")
		if not prompt then continue end

		prompt.Triggered:Connect(function(player)
			local caseData = CaseInfo[casePart.Name]
			if not caseData then
				warn("[CASES] No CaseInfo entry for:", casePart.Name)
				return
			end

			local profile = DataHandler.GetProfile(player)
			if not profile then return end

			-- FIX: Block the purchase entirely if the player is mid-roll.
			-- This prevents cash being deducted and a second case opening on top of the current one.
			if DataHandler.IsRollLocked(player.UserId) then
				Network.sendToClient(player, "Notify", "⏳ Finish your current roll first!", "Warning")
				return
			end

			-- Player can't afford it with in-game cash — try Robux product
			if player.leaderstats.Cash.Value < caseData.Cost then
				local CASE_PRODUCTS = {
					["Basic"]    = 3557510877,
					["Epic"]     = 3557512219,
					["Mythical"] = 3557512275,
					["Rainbow"]  = 3557512358,
				}
				local productId = CASE_PRODUCTS[casePart.Name]
				if productId then
					game:GetService("MarketplaceService"):PromptProductPurchase(player, productId)
				else
					Network.sendToClient(player, "Notify",
						"Not enough cash! This case costs $" .. tostring(caseData.Cost), "Warning")
				end
				return
			end

			-- FIX: Set the roll lock BEFORE deducting cash and firing OpenCase.
			-- This ensures any purchase that arrives in the same frame is queued, not double-fired.
			DataHandler.SetRollLocked(player.UserId, true)
			DataHandler.RemoveCurrency(player, caseData.Cost, "Cash")
			Network.sendToClient(player, "OpenCase", casePart.Name)
			Network.sendToClient(player, "Notify", "🎉 Opening " .. casePart.Name .. " case...", "Confirmation")
		end)
	end
end

if Cases then
	applyGradients()
	setupPrompts()
end
return module