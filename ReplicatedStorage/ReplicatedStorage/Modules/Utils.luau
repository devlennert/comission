local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local DeveloperProducts = require(ReplicatedStorage.Modules.DevProducts)

local module = {}
local TweeningModels = {}

function module.GetFriendCount(Player : Player)
	local Count = 0

	for _, v in Players:GetPlayers() do
		if Player and Player.Parent and Player.UserId and v ~= Player and v:IsFriendsWith(Player.UserId) then
			Count += 1
		end
	end

	return Count
end


function module.GetProductNameById(Id : number)
	for ItemName, ItemData in DeveloperProducts do
		if ItemData.ID == Id then
			return ItemName, ItemData.Type
		end
	end
end

function module.formatWithKomma(number)
	local formatted = tostring(number)
	local result = formatted:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	-- Remove a dot at the start if it exists
	if result:sub(1, 1) == "," then
		result = result:sub(2)
	end
	return result
end

function module.formatWithDots(number)
	local formatted = tostring(number)
	local result = formatted:reverse():gsub("(%d%d%d)", "%1."):reverse()
	-- Remove a dot at the start if it exists
	if result:sub(1, 1) == "." then
		result = result:sub(2)
	end
	return result
end

function module.tweenScale(startScale : number, endScale : number, tweenInfo : TweenInfo, model : Model)
	local elapsed = 0
	local scale = 0
	local tweenConnection

	local function onStep(deltaTime : number)
		elapsed = math.min(elapsed + deltaTime, tweenInfo.Time)

		local alpha = TweenService:GetValue(elapsed / tweenInfo.Time, tweenInfo.EasingStyle, tweenInfo.EasingDirection)

		scale = startScale + alpha * (endScale - startScale)

		model:ScaleTo(scale)

		if elapsed == tweenInfo.Time then
			tweenConnection:Disconnect()
		end
	end

	tweenConnection = RunService.Heartbeat:Connect(onStep)
end

function module.MakeModelCanCollide(Model : Model, CanCollide : boolean)
	for _, Part in Model:GetDescendants() do
		if Part:IsA("BasePart") or Part:IsA("MeshPart") then
			Part.CanCollide = CanCollide	
		end
	end
end

function module.GetRandomSize(weightArray : {})
	local total = 0

	for _, entry in ipairs(weightArray) do
		total += entry.Weight
	end

	local roll = math.random() * total
	local cumulative = 0

	for _, entry in ipairs(weightArray) do
		cumulative += entry.Weight
		if roll <= cumulative then
			return math.random() * (entry.Max - entry.Min) + entry.Min
		end
	end

	-- fallback
	local last = weightArray[#weightArray]
	return math.random() * (last.Max - last.Min) + last.Min
end

function module.formatDigitalTime(seconds)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60

	if hours > 0 then
		return string.format("%02d:%02d:%02d", hours, minutes, secs)
	else
		return string.format("%d:%02d", minutes, secs)
	end
end


function module.TweenModel(Model: Model, CFrameTweenInfo: TweenInfo, TargetCFrame: CFrame, Interval: number?): Tween
	local PreviousTween = TweeningModels[Model]
	if PreviousTween then
		if PreviousTween.Goal ~= TargetCFrame then
			TweeningModels[Model].Tween:Cancel()
		end
	end

	local CFrameValue = Instance.new("CFrameValue")
	CFrameValue.Value = Model:GetPivot()

	local Tween = game:GetService("TweenService"):Create(CFrameValue, CFrameTweenInfo, {Value = TargetCFrame})
	TweeningModels[Model] = {Tween = Tween, Goal = TargetCFrame}
	Tween:Play()
	Tween.Completed:Once(function()
		TweeningModels[Model] = nil
	end)

	task.spawn(function()
		while Tween.PlaybackState == Enum.PlaybackState.Playing and Model:IsDescendantOf(game) do
			Model:PivotTo(CFrameValue.Value)
			task.wait(Interval)
		end

		if not Model:IsDescendantOf(game) then
			Tween:Cancel()
		elseif Tween.PlaybackState ~= Enum.PlaybackState.Cancelled then
			Model:PivotTo(TargetCFrame)
		end
	end)

	return Tween
end

return module
