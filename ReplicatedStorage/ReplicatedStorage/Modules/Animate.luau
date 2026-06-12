local Animate = {}
local RunService = game:GetService("RunService")

local Easing = {}

Easing.Linear = function(t) return t end

Easing.InQuad = function(t) return t * t end
Easing.OutQuad = function(t) return t * (2 - t) end
Easing.InOutQuad = function(t) 
	return t < 0.5 and 2 * t * t or -1 + (4 - 2 * t) * t 
end

Easing.InCubic = function(t) return t * t * t end
Easing.OutCubic = function(t) return (t - 1) * (t - 1) * (t - 1) + 1 end
Easing.InOutCubic = function(t)
	return t < 0.5 and 4 * t * t * t or (t - 1) * (2 * t - 2) * (2 * t - 2) + 1
end

Easing.InQuart = function(t) return t * t * t * t end
Easing.OutQuart = function(t) return 1 - (t - 1) * (t - 1) * (t - 1) * (t - 1) end
Easing.InOutQuart = function(t)
	return t < 0.5 and 8 * t * t * t * t or 1 - 8 * (t - 1) * (t - 1) * (t - 1) * (t - 1)
end

Easing.InSine = function(t) return 1 - math.cos(t * math.pi / 2) end
Easing.OutSine = function(t) return math.sin(t * math.pi / 2) end
Easing.InOutSine = function(t) return -(math.cos(math.pi * t) - 1) / 2 end

Easing.InExpo = function(t) return t == 0 and 0 or math.pow(2, 10 * (t - 1)) end
Easing.OutExpo = function(t) return t == 1 and 1 or 1 - math.pow(2, -10 * t) end
Easing.InOutExpo = function(t)
	if t == 0 or t == 1 then return t end
	if t < 0.5 then
		return math.pow(2, 20 * t - 10) / 2
	else
		return (2 - math.pow(2, -20 * t + 10)) / 2
	end
end

Easing.InElastic = function(t)
	if t == 0 or t == 1 then return t end
	return -math.pow(2, 10 * t - 10) * math.sin((t * 10 - 10.75) * (2 * math.pi) / 3)
end
Easing.OutElastic = function(t)
	if t == 0 or t == 1 then return t end
	return math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi) / 3) + 1
end
Easing.InOutElastic = function(t)
	if t == 0 or t == 1 then return t end
	local c = (2 * math.pi) / 4.5
	if t < 0.5 then
		return -(math.pow(2, 20 * t - 10) * math.sin((20 * t - 11.125) * c)) / 2
	else
		return (math.pow(2, -20 * t + 10) * math.sin((20 * t - 11.125) * c)) / 2 + 1
	end
end

Easing.InBack = function(t)
	local c = 1.70158
	return t * t * ((c + 1) * t - c)
end
Easing.OutBack = function(t)
	local c = 1.70158
	return 1 + (t - 1) * (t - 1) * ((c + 1) * (t - 1) + c)
end
Easing.InOutBack = function(t)
	local c = 1.70158 * 1.525
	if t < 0.5 then
		return (2 * t) * (2 * t) * ((c + 1) * 2 * t - c) / 2
	else
		return ((2 * t - 2) * (2 * t - 2) * ((c + 1) * (2 * t - 2) + c) + 2) / 2
	end
end

Easing.OutBounce = function(t)
	if t < 1 / 2.75 then
		return 7.5625 * t * t
	elseif t < 2 / 2.75 then
		t = t - 1.5 / 2.75
		return 7.5625 * t * t + 0.75
	elseif t < 2.5 / 2.75 then
		t = t - 2.25 / 2.75
		return 7.5625 * t * t + 0.9375
	else
		t = t - 2.625 / 2.75
		return 7.5625 * t * t + 0.984375
	end
end
Easing.InBounce = function(t) return 1 - Easing.OutBounce(1 - t) end
Easing.InOutBounce = function(t)
	if t < 0.5 then
		return Easing.InBounce(t * 2) / 2
	else
		return Easing.OutBounce(t * 2 - 1) / 2 + 0.5
	end
end

Animate.Easing = Easing

local function setTransparency(obj, value)
	if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
		obj.TextTransparency = value
		obj.TextStrokeTransparency = value
	elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
		obj.ImageTransparency = value
	end
end

local function getTransparency(obj)
	if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
		return obj.TextTransparency
	elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
		return obj.ImageTransparency
	else
		return obj.BackgroundTransparency
	end
end

local function setTransparencyRecursive(parent, value)
	setTransparency(parent, value)
	for _, child in ipairs(parent:GetDescendants()) do
		setTransparency(child, value)
	end
end

function Animate.EaseUISize(uiElement, targetSize, duration, easingFunc, onComplete)
	if not targetSize then return end
	easingFunc = easingFunc or Easing.OutQuad
	local startTime = tick()
	local startSize = uiElement.Size
	local connection

	connection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local t = math.min(elapsed / duration, 1)
		local progress = easingFunc(t)

		local xScale = startSize.X.Scale + (targetSize.X.Scale - startSize.X.Scale) * progress
		local yScale = startSize.Y.Scale + (targetSize.Y.Scale - startSize.Y.Scale) * progress
		local xOffset = startSize.X.Offset + (targetSize.X.Offset - startSize.X.Offset) * progress
		local yOffset = startSize.Y.Offset + (targetSize.Y.Offset - startSize.Y.Offset) * progress

		uiElement.Size = UDim2.new(xScale, xOffset, yScale, yOffset)

		if t >= 1 then
			connection:Disconnect()
			if onComplete then onComplete() end
		end
	end)

	return connection
end

function Animate.EaseUIPosition(uiElement, targetPos, duration, easingFunc, onComplete)
	easingFunc = easingFunc or Easing.OutQuad
	local startTime = tick()
	local startPos = uiElement.Position
	local connection

	connection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local t = math.min(elapsed / duration, 1)
		local progress = easingFunc(t)

		local xScale = startPos.X.Scale + (targetPos.X.Scale - startPos.X.Scale) * progress
		local yScale = startPos.Y.Scale + (targetPos.Y.Scale - startPos.Y.Scale) * progress
		local xOffset = startPos.X.Offset + (targetPos.X.Offset - startPos.X.Offset) * progress
		local yOffset = startPos.Y.Offset + (targetPos.Y.Offset - startPos.Y.Offset) * progress

		uiElement.Position = UDim2.new(xScale, xOffset, yScale, yOffset)

		if t >= 1 then
			connection:Disconnect()
			if onComplete then onComplete() end
		end
	end)

	return connection
end

function Animate.EaseUIRotation(uiElement, targetRotation, duration, easingFunc, onComplete)
	easingFunc = easingFunc or Easing.OutQuad
	local startTime = tick()
	local startRotation = uiElement.Rotation
	local connection

	connection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local t = math.min(elapsed / duration, 1)
		local progress = easingFunc(t)

		uiElement.Rotation = startRotation + (targetRotation - startRotation) * progress

		if t >= 1 then
			connection:Disconnect()
			if onComplete then onComplete() end
		end
	end)

	return connection
end

function Animate.EaseTransparency(uiElement, targetTransparency, duration, easingFunc, recursive, onComplete)
	if type(recursive) == "function" then
		onComplete = recursive
		recursive = false
	end

	easingFunc = easingFunc or Easing.OutQuad
	recursive = recursive or false

	local startTime = tick()
	local startTransparency = getTransparency(uiElement)
	local connection

	connection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local t = math.min(elapsed / duration, 1)
		local progress = easingFunc(t)

		local currentTransparency = startTransparency + (targetTransparency - startTransparency) * progress

		if recursive then
			setTransparencyRecursive(uiElement, currentTransparency)
		else
			setTransparency(uiElement, currentTransparency)
		end

		if t >= 1 then
			connection:Disconnect()
			if onComplete then onComplete() end
		end
	end)

	return connection
end

function Animate.EaseColor(uiElement, targetColor, duration, easingFunc, onComplete)
	easingFunc = easingFunc or Easing.OutQuad
	local startTime = tick()

	local startColor
	if uiElement:IsA("ImageLabel") or uiElement:IsA("ImageButton") then
		startColor = uiElement.ImageColor3
	elseif uiElement:IsA("TextLabel") or uiElement:IsA("TextButton") or uiElement:IsA("TextBox") then
		startColor = uiElement.TextColor3
	else
		startColor = uiElement.BackgroundColor3
	end

	local connection

	connection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local t = math.min(elapsed / duration, 1)
		local progress = easingFunc(t)

		local r = startColor.R + (targetColor.R - startColor.R) * progress
		local g = startColor.G + (targetColor.G - startColor.G) * progress
		local b = startColor.B + (targetColor.B - startColor.B) * progress
		local newColor = Color3.new(r, g, b)

		if uiElement:IsA("ImageLabel") or uiElement:IsA("ImageButton") then
			uiElement.ImageColor3 = newColor
		elseif uiElement:IsA("TextLabel") or uiElement:IsA("TextButton") or uiElement:IsA("TextBox") then
			uiElement.TextColor3 = newColor
		else
			uiElement.BackgroundColor3 = newColor
		end

		if t >= 1 then
			connection:Disconnect()
			if onComplete then onComplete() end
		end
	end)

	return connection
end

function Animate.ShakeCamera(camera, intensity, duration, onComplete)
	intensity = intensity or 0.5
	local startTime = tick()
	local originalCFrame = camera.CFrame
	local connection

	connection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local t = elapsed / duration

		if t >= 1 then
			camera.CFrame = originalCFrame
			connection:Disconnect()
			if onComplete then onComplete() end
			return
		end

		local currentIntensity = intensity * (1 - t)
		local offsetX = (math.random() - 0.5) * 2 * currentIntensity
		local offsetY = (math.random() - 0.5) * 2 * currentIntensity
		local offsetZ = (math.random() - 0.5) * 2 * currentIntensity

		camera.CFrame = originalCFrame * CFrame.Angles(
			math.rad(offsetX),
			math.rad(offsetY),
			math.rad(offsetZ)
		)
	end)

	return connection
end

function Animate.CharacterJump(character, power, onComplete)
	power = power or 50
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if humanoid and rootPart then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		rootPart.AssemblyLinearVelocity = Vector3.new(
			rootPart.AssemblyLinearVelocity.X,
			power,
			rootPart.AssemblyLinearVelocity.Z
		)

		if onComplete then
			task.spawn(function()
				repeat task.wait() until humanoid:GetState() ~= Enum.HumanoidStateType.Jumping
				onComplete()
			end)
		end
	end
end

function Animate.Shake(target, intensity, duration, onComplete)
	intensity = intensity or 10

	if target:IsA("Camera") then
		return Animate.ShakeCamera(target, intensity, duration, onComplete)
	end

	local startPos = target.Position
	local startTime = tick()
	local connection

	connection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local t = elapsed / duration

		if t >= 1 then
			target.Position = startPos
			connection:Disconnect()
			if onComplete then onComplete() end
			return
		end

		local currentIntensity = intensity * (1 - t)
		local offsetX = (math.random() - 0.5) * currentIntensity
		local offsetY = (math.random() - 0.5) * currentIntensity

		target.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + offsetX,
			startPos.Y.Scale,
			startPos.Y.Offset + offsetY
		)
	end)

	return connection
end

function Animate.Pulse(uiElement, scaleAmount, duration, pulseCount, onComplete)
	scaleAmount = scaleAmount or 0.1
	pulseCount = pulseCount or 3
	local originalSize = uiElement.Size
	local pulses = 0

	local function doPulse()
		pulses = pulses + 1

		Animate.EaseUISize(
			uiElement,
			UDim2.new(
				originalSize.X.Scale * (1 + scaleAmount),
				originalSize.X.Offset,
				originalSize.Y.Scale * (1 + scaleAmount),
				originalSize.Y.Offset
			),
			duration / 2,
			Easing.OutQuad,
			function()
				Animate.EaseUISize(
					uiElement,
					originalSize,
					duration / 2,
					Easing.InQuad,
					function()
						if pulses < pulseCount then
							doPulse()
						elseif onComplete then
							onComplete()
						end
					end
				)
			end
		)
	end

	doPulse()
end

-- FIXED: Store target position separately to prevent issues
function Animate.SlideIn(uiElement, direction, duration, easingFunc, onComplete, customTargetPos)
	direction = direction or "Left"
	easingFunc = easingFunc or Easing.OutBack

	-- Use custom target or current position as target
	local targetPos = customTargetPos or uiElement.Position
	local startPos

	if direction == "Left" then
		startPos = UDim2.new(-1, targetPos.X.Offset, targetPos.Y.Scale, targetPos.Y.Offset)
	elseif direction == "Right" then
		startPos = UDim2.new(2, targetPos.X.Offset, targetPos.Y.Scale, targetPos.Y.Offset)
	elseif direction == "Top" then
		startPos = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, -1, targetPos.Y.Offset)
	else
		startPos = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, 2, targetPos.Y.Offset)
	end

	if game:GetService("SoundService").Audio:FindFirstChild("Slide") then
		game:GetService("SoundService").Audio.Slide:Play()
	end

	uiElement.Position = startPos
	return Animate.EaseUIPosition(uiElement, targetPos, duration, easingFunc, onComplete)
end

function Animate.SlideOut(uiElement, direction, duration, easingFunc, onComplete)
	direction = direction or "Right"
	easingFunc = easingFunc or Easing.InBack

	local targetPos
	local currentPos = uiElement.Position

	if direction == "Left" then
		targetPos = UDim2.new(-1, currentPos.X.Offset, currentPos.Y.Scale, currentPos.Y.Offset)
	elseif direction == "Right" then
		targetPos = UDim2.new(2, currentPos.X.Offset, currentPos.Y.Scale, currentPos.Y.Offset)
	elseif direction == "Top" then
		targetPos = UDim2.new(currentPos.X.Scale, currentPos.X.Offset, -1, currentPos.Y.Offset)
	else
		targetPos = UDim2.new(currentPos.X.Scale, currentPos.X.Offset, 2, currentPos.Y.Offset)
	end

	if game:GetService("SoundService").Audio:FindFirstChild("Slide") then
		game:GetService("SoundService").Audio.Slide:Play()
	end

	return Animate.EaseUIPosition(uiElement, targetPos, duration, easingFunc, onComplete)
end

function Animate.FadeIn(uiElement, duration, easingFunc, recursive, onComplete)
	if type(recursive) == "function" then
		onComplete = recursive
		recursive = false
	end
	return Animate.EaseTransparency(uiElement, 0, duration, easingFunc, recursive, onComplete)
end

function Animate.FadeOut(uiElement, duration, easingFunc, recursive, onComplete)
	if type(recursive) == "function" then
		onComplete = recursive
		recursive = false
	end
	return Animate.EaseTransparency(uiElement, 1, duration, easingFunc, recursive, onComplete)
end

-- FIX: Added optional targetSize parameter so callers can supply the intended size
-- when the element may already be at 0,0,0,0 from a previous PopOut.
-- Argument order:  uiElement, duration, easingFunc, targetSize, onComplete
-- targetSize and onComplete are both optional; if targetSize is a function it is
-- treated as onComplete (backwards-compatible with old call sites).
function Animate.PopIn(uiElement, duration, easingFunc, targetSize, onComplete)
	-- Handle backwards-compatible call where targetSize is omitted and onComplete is 3rd or 4th arg
	-- Only treat easingFunc as onComplete if it's NOT a known easing style
	local knownEasings = {}
	for _, v in pairs(Easing) do knownEasings[v] = true end
	if type(easingFunc) == "function" and not knownEasings[easingFunc] then
		onComplete  = easingFunc
		easingFunc  = nil
		targetSize  = nil
	elseif type(targetSize) == "function" then
		onComplete = targetSize
		targetSize = nil
	end

	easingFunc = easingFunc or Easing.OutElastic

	-- If no explicit targetSize was provided, use the element's current size.
	-- Guard: if that size is zero (element was left at 0,0,0,0 by PopOut),
	-- fall back to a sensible scale-based default so the element actually appears.
	local finalSize = targetSize or uiElement.Size
	local isZeroSize = (
		finalSize.X.Scale  == 0 and finalSize.X.Offset == 0 and
			finalSize.Y.Scale  == 0 and finalSize.Y.Offset == 0
	)
	if isZeroSize then
		-- Default fallback; callers should ideally supply origSize to avoid this
		finalSize = UDim2.new(0.1, 0, 0.1, 0)
		warn("[Animate.PopIn] targetSize was 0,0,0,0 — using fallback. Pass origSize explicitly.")
	end

	uiElement.Size = UDim2.new(0, 0, 0, 0)
	return Animate.EaseUISize(uiElement, finalSize, duration, easingFunc, onComplete)
end

function Animate.PopOut(uiElement, duration, easingFunc, onComplete)
	easingFunc = easingFunc or Easing.InBack
	return Animate.EaseUISize(uiElement, UDim2.new(0, 0, 0, 0), duration, easingFunc, onComplete)
end

function Animate.Spin(uiElement, rotations, duration, easingFunc, onComplete)
	rotations = rotations or 1
	easingFunc = easingFunc or Easing.InOutQuad
	local targetRotation = uiElement.Rotation + (360 * rotations)
	return Animate.EaseUIRotation(uiElement, targetRotation, duration, easingFunc, onComplete)
end

function Animate.Wobble(uiElement, intensity, duration, wobbleCount, onComplete)
	intensity = intensity or 15
	wobbleCount = wobbleCount or 3
	local originalRotation = uiElement.Rotation
	local wobbles = 0

	local function doWobble()
		wobbles = wobbles + 1

		Animate.EaseUIRotation(
			uiElement,
			originalRotation + intensity,
			duration / (wobbleCount * 2),
			Easing.InOutQuad,
			function()
				Animate.EaseUIRotation(
					uiElement,
					originalRotation - intensity,
					duration / (wobbleCount * 2),
					Easing.InOutQuad,
					function()
						if wobbles < wobbleCount then
							doWobble()
						else
							Animate.EaseUIRotation(
								uiElement,
								originalRotation,
								duration / (wobbleCount * 2),
								Easing.InOutQuad,
								onComplete
							)
						end
					end
				)
			end
		)
	end

	doWobble()
end

Animate.SpringPresets = {
	Smooth  = {dampingRatio = 1,   frequency = 1  },
	Snappy  = {dampingRatio = 1,   frequency = 2  },
	Bouncy  = {dampingRatio = 0.6, frequency = 1.5},
	Playful = {dampingRatio = 0.5, frequency = 1.2},
	Elastic = {dampingRatio = 0.3, frequency = 1  },
	Gentle  = {dampingRatio = 1,   frequency = 0.5},
	Wobbly  = {dampingRatio = 0.4, frequency = 0.8},
}

return Animate