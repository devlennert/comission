-- RiskClient  (LocalScript — place alongside CasesClient)
-- Handles all client-side UI for the Risk gamemode.
-- Uses existing MainUI elements:
--   MainUI.PickFrame          — 5 buttons: Case1-Case5
--     each button has: TextLabel, RightGradient, WrongGradient, UIStroke
--   MainUI.EarnedMoney        — TextLabel showing running bank
--   MainUI.DecisionFrame      — cash-out prompt
--     DecisionFrame.KeepGoing — TextLabel (rich text)
--     DecisionFrame.CashOut   — TextLabel (rich text)
--   MainUI.ReasonFrame        — final result (shared with CasesClient)
--     ReasonFrame.TextLabel
--
-- Camera / sound / timer remotes are already handled by CasesClient.

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RS           = game:GetService("ReplicatedStorage")

local player  = Players.LocalPlayer
local Network = require(RS:WaitForChild("Modules"):WaitForChild("Network"))

local mainUI = player.PlayerGui:WaitForChild("MainUI")

-- ─── ReasonFrame ─────────────────────────────────────────────────────────────
-- Shared with CasesClient.  CasesClient collapses it to 0,0 at startup.
-- We recover the true size by reading it before any collapse, OR fall back to a
-- constant — adjust REASON_FALLBACK_SIZE if the frame looks wrong in-game.

local REASON_FALLBACK_SIZE = UDim2.new(0.841, 0, 0.096, 0)

local reasonFrame = mainUI:WaitForChild("ReasonFrame")
local reasonLabel = reasonFrame:WaitForChild("TextLabel")

local function getReasonOrigSize()
	local s = reasonFrame.Size
	if s.X.Scale == 0 and s.X.Offset == 0 and s.Y.Scale == 0 and s.Y.Offset == 0 then
		return REASON_FALLBACK_SIZE
	end
	return s
end

-- ─── EarnedMoney ─────────────────────────────────────────────────────────────

local earnedMoneyLabel = mainUI:WaitForChild("EarnedMoney")
earnedMoneyLabel.Visible = false

-- ─── PickFrame + Case buttons ─────────────────────────────────────────────────

local pickFrame = mainUI:WaitForChild("PickFrame")
pickFrame.Visible = false

local NORMAL_STROKE_COLOR = Color3.fromRGB(39, 149, 0)
local HOVER_STROKE_COLOR  = Color3.fromRGB(240, 255, 233)
local OPENED_STROKE_COLOR = Color3.fromRGB(200, 40, 40)

local caseButtons = {}
for i = 1, 5 do
	local btn = pickFrame:WaitForChild("Case" .. i)
	caseButtons[i] = {
		btn           = btn,
		textLabel     = btn:WaitForChild("TextLabel"),
		rightGradient = btn:WaitForChild("RightGradient"),
		wrongGradient = btn:WaitForChild("WrongGradient"),
		uiStroke      = btn:WaitForChild("UIStroke"),
	}
end

-- ─── DecisionFrame ───────────────────────────────────────────────────────────

local decisionFrame  = mainUI:WaitForChild("DecisionFrame")
local keepGoingBtn   = decisionFrame:WaitForChild("KeepGoing")
local cashOutBtn     = decisionFrame:WaitForChild("CashOut")
local keepGoingLabel = keepGoingBtn:WaitForChild("TextLabel")
local cashOutLabel   = cashOutBtn:WaitForChild("TextLabel")
decisionFrame.Visible = false

-- ─── Workspace highlight ─────────────────────────────────────────────────────

local activeHighlight = nil

local function setHighlight(caseName)
	if activeHighlight then activeHighlight:Destroy(); activeHighlight = nil end
	local m = workspace:FindFirstChild(caseName)
	if not m then return end
	local hl                = Instance.new("Highlight")
	hl.FillColor            = Color3.fromRGB(255, 200, 0)
	hl.FillTransparency     = 0.7
	hl.OutlineColor         = Color3.fromRGB(255, 215, 0)
	hl.OutlineTransparency  = 0
	hl.DepthMode            = Enum.HighlightDepthMode.Occluded
	hl.Adornee              = m
	hl.Parent               = workspace
	activeHighlight         = hl
end

local function clearHighlight()
	if not activeHighlight then return end
	local hl       = activeHighlight
	activeHighlight = nil
	local tw = TweenService:Create(hl,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = 1, OutlineTransparency = 1 })
	tw:Play()
	tw.Completed:Connect(function() hl:Destroy() end)
end

-- ─── ReasonFrame animation ───────────────────────────────────────────────────

local reasonThread = nil

local function showRiskResult(text)
	if reasonThread then task.cancel(reasonThread); reasonThread = nil end

	local origSize       = getReasonOrigSize()
	reasonLabel.Text     = text
	reasonFrame.Size     = UDim2.new(0, 0, 0, 0)
	reasonFrame.Visible  = true

	TweenService:Create(reasonFrame,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = origSize }):Play()

	reasonThread = task.spawn(function()
		task.wait(4)
		local tw = TweenService:Create(reasonFrame,
			TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut),
			{ Size = UDim2.new(0, 0, 0, 0) })
		tw:Play()
		tw.Completed:Wait()
		reasonFrame.Visible = false
		reasonThread        = nil
	end)
end

-- ─── Pick connections ─────────────────────────────────────────────────────────

local pickConns = {}

local function clearPickConns()
	for _, c in ipairs(pickConns) do c:Disconnect() end
	pickConns = {}
end

-- ─── Network handlers ────────────────────────────────────────────────────────

-- Show the PickFrame.
-- `available` = array of case indices the player can still pick, e.g. {1, 3, 5}.
-- Any case NOT in available is treated as already opened (cash).
Network.onClient("Risk_ShowCasePick", function(available)
	clearPickConns()
	clearHighlight()

	local availableSet = {}
	for _, idx in ipairs(available) do availableSet[idx] = true end

	for i = 1, 5 do
		local data     = caseButtons[i]
		local caseName = "RiskCase_" .. i .. "_" .. player.UserId

		if availableSet[i] then
			-- ── Available: right gradient on, correct stroke, clickable ──────
			data.rightGradient.Enabled = true
			data.wrongGradient.Enabled = false
			data.uiStroke.Color        = NORMAL_STROKE_COLOR
			data.textLabel.Text        = "Case " .. i
			data.btn.Active            = true

			table.insert(pickConns, data.btn.MouseButton1Click:Connect(function()
				clearPickConns()
				clearHighlight()
				pickFrame.Visible = false
				Network.send("Risk_CasePicked", i)
			end))

			table.insert(pickConns, data.btn.MouseEnter:Connect(function()
				setHighlight(caseName)
				data.uiStroke.Color = HOVER_STROKE_COLOR
			end))

			table.insert(pickConns, data.btn.MouseLeave:Connect(function()
				clearHighlight()
				data.uiStroke.Color = NORMAL_STROKE_COLOR
			end))
		else
			-- ── Already opened (cash): wrong gradient, red stroke, dimmed ────
			data.rightGradient.Enabled = false
			data.wrongGradient.Enabled = true
			data.uiStroke.Color        = OPENED_STROKE_COLOR
			data.textLabel.Text        = "OPENED"
			data.btn.Active            = false
		end
	end

	pickFrame.Visible = true
end)

Network.onClient("Risk_HideCasePick", function()
	clearPickConns()
	clearHighlight()
	pickFrame.Visible = false
end)

-- Show the DecisionFrame after a cash find.
-- `remaining` = cases left INCLUDING the 1 empty case.
Network.onClient("Risk_ShowCashOut", function(foundAmount, bankTotal, remaining)
	pickFrame.Visible = false

	-- Success % = how many cash cases remain out of total remaining
	local cashLeft   = remaining - 1
	local successPct = math.floor((cashLeft / remaining) * 100)

	-- KeepGoing label: rich text with red success %
	keepGoingLabel.Text = string.format(
		'Keep Going  <font color="#FF3333"><b>%d%% Success</b></font>',
		successPct)

	-- CashOut label: rich text with red bank amount
	cashOutLabel.Text = string.format(
		'Cash Out  <font color="#33DD33"><b>$%s</b></font>',
		tostring(bankTotal))

	decisionFrame.Visible = true
end)

Network.onClient("Risk_HideCashOut", function()
	decisionFrame.Visible = false
end)

-- Update the running total shown at the top of the screen.
Network.onClient("Risk_UpdateBank", function(bankTotal)
	earnedMoneyLabel.Text    = "Earned Money: $" .. tostring(bankTotal)
	earnedMoneyLabel.Visible = true
end)

-- Show the final result card using ReasonFrame.
-- `amount` on a win  = the bank total cashed out / swept.
-- `amount` on a loss = whatever was in the bank before busting (may be 0).
Network.onClient("Risk_ShowResult", function(won, amount)
	pickFrame.Visible        = false
	decisionFrame.Visible    = false
	earnedMoneyLabel.Visible = false   -- hide immediately so ReasonFrame is unobstructed

	local text
	if won then
		if amount > 0 then
			text = string.format(
				'<font color="#00CC44"><b>You Cashed Out!</b></font>  💰 Banked <b>$%s</b>!',
				tostring(amount))
		else
			text = '<font color="#00CC44"><b>You Won!</b></font>  Well played!'
		end
	else
		if amount > 0 then
			-- Had money in the bank but kept going and hit empty
			text = string.format(
				'You opened the <font color="#FF3333"><b>EMPTY</b></font> Case!  You lost your <b>$%s</b>...',
				tostring(amount))
		else
			-- Busted on the very first pick with nothing banked
			text = 'You opened the <font color="#FF3333"><b>EMPTY</b></font> Case!  Better luck next time...'
		end
	end

	showRiskResult(text)
end)

-- ─── Decision buttons ─────────────────────────────────────────────────────────

keepGoingBtn.MouseButton1Click:Connect(function()
	if not decisionFrame.Visible then return end
	decisionFrame.Visible = false
	Network.send("Risk_CashOutDecision", "keepgoing")
end)

cashOutBtn.MouseButton1Click:Connect(function()
	if not decisionFrame.Visible then return end
	decisionFrame.Visible = false
	Network.send("Risk_CashOutDecision", "cashout")
end)