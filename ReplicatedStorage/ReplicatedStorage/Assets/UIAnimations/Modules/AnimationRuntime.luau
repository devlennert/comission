local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Runtime = {}

local function fixAnchorPointIfNeeded(obj)
	if not obj or not obj:IsA("GuiObject") or obj.AnchorPoint == Vector2.new(0.5, 0.5) then return end
	pcall(function()
		local oldAP, newAP = obj.AnchorPoint, Vector2.new(0.5, 0.5)
		local size = obj.AbsoluteSize
		local offsetDelta = Vector2.new((newAP.X - oldAP.X) * size.X, (newAP.Y - oldAP.Y) * size.Y)
		obj.AnchorPoint = newAP
		obj.Position = obj.Position + UDim2.fromOffset(offsetDelta.X, offsetDelta.Y)
	end)
end

local function isTextObject(obj) return obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") end

local function shouldScaleTextForThisAnim(name)
	if name == "Grow In" or name == "Zoom In" or name == "Pop Out" or name == "Zoom Out" or string.sub(name, 1, 10) == "Shrink Out" or string.find(name, "Unfold", 1, true) ~= nil or string.sub(name, 1, 4) == "Fold" then return true end
	return false
end

local function recordBaseline(obj)
	local baseline = {}
	pcall(function() baseline.Position = obj.Position end); pcall(function() baseline.Rotation = obj.Rotation end); pcall(function() baseline.Size = obj.Size end)
	pcall(function() baseline.Visible = obj.Visible end); pcall(function() baseline.AnchorPoint = obj.AnchorPoint end)
	if isTextObject(obj) then pcall(function() baseline.TextScaled = obj.TextScaled end); pcall(function() baseline.TextSize = obj.TextSize end) end
	return baseline
end

local function safeTween(target, info, props)
	local ok, tween = pcall(function() return TweenService:Create(target, info, props) end)
	if ok and tween then tween:Play(); return tween end; return nil
end

local function setTextScaledForSize(obj, on, animName)
	if isTextObject(obj) and shouldScaleTextForThisAnim(animName) then pcall(function() obj.TextScaled = on end) end
end

function Runtime.run(obj, config)
	if not obj or not obj.Parent or not config then return end
	if config.prop == "Size" or config.prop == "Rotation" then fixAnchorPointIfNeeded(obj) end
	local baseline = recordBaseline(obj)

	if config.event == "hover" then
		obj.MouseEnter:Connect(function()
			setTextScaledForSize(obj, true, config.name)
			safeTween(obj, TweenInfo.new(config.time or 0.2, Enum.EasingStyle[config.style or "Quad"]), {[config.prop] = config.val})
		end)
		obj.MouseLeave:Connect(function()
			local tw = safeTween(obj, TweenInfo.new(config.time or 0.2, Enum.EasingStyle[config.style or "Quad"]), {[config.prop] = baseline[config.prop]})
			if tw then pcall(function() tw.Completed:Wait() end) end
			if config.prop == "Size" and shouldScaleTextForThisAnim(config.name) then
				if baseline.TextScaled ~= nil then pcall(function() obj.TextScaled = baseline.TextScaled end) end
				if baseline.TextSize ~= nil and not baseline.TextScaled then pcall(function() obj.TextSize = baseline.TextSize end) end
			end
		end)
	elseif config.event == "click" then
		if config.prop == "Ripple" and obj:IsA("GuiButton") then
			obj.ClipsDescendants = true
			obj.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
				local ripple = Instance.new("Frame", {Size=UDim2.fromOffset(0,0), Position=UDim2.fromOffset(input.Position.X - obj.AbsolutePosition.X, input.Position.Y - obj.AbsolutePosition.Y), AnchorPoint=Vector2.new(0.5,0.5), BackgroundColor3=Color3.new(1,1,1), BackgroundTransparency=0.6, BorderSizePixel=0})
				Instance.new("UICorner", ripple).CornerRadius = UDim.new(1,0); ripple.Parent = obj
				local max = math.max(obj.AbsoluteSize.X, obj.AbsoluteSize.Y) * 2
				local tween = safeTween(ripple, TweenInfo.new(0.5, Enum.EasingStyle.Sine), {Size=UDim2.fromOffset(max,max), BackgroundTransparency=1})
				if tween then tween.Completed:Connect(function() ripple:Destroy() end) end
			end)
		elseif obj:IsA("GuiButton") then
			obj.MouseButton1Click:Connect(function()
				setTextScaledForSize(obj, true, config.name)
				safeTween(obj, TweenInfo.new(config.time or 0.1, Enum.EasingStyle[config.style or "Quad"]), {[config.prop] = config.val})
				if config.reset then
					task.wait(config.time or 0.1)
					local t = safeTween(obj, TweenInfo.new(config.resetTime or 0.2, Enum.EasingStyle[config.resetStyle or "Quad"]), {[config.prop] = baseline[config.prop]})
					if t then pcall(function() t.Completed:Wait() end) end
					if config.prop == "Size" and shouldScaleTextForThisAnim(config.name) then
						if baseline.TextScaled ~= nil then pcall(function() obj.TextScaled = baseline.TextScaled end) end
						if baseline.TextSize ~= nil and not baseline.TextScaled then pcall(function() obj.TextSize = baseline.TextSize end) end
					end
				end
			end)
		end
	elseif config.event == "loop" then
		if config.prop == "Size" then setTextScaledForSize(obj, true, config.name) end
		
		if config.permanent and config.to then
			task.spawn(function()
				if config.from then pcall(function() obj[config.prop] = config.from end) end
				local tw = safeTween(obj, TweenInfo.new(config.time or 0.5, Enum.EasingStyle[config.style or "Quad"]), {[config.prop] = config.to})
				if tw and config.prop == "Size" and shouldScaleTextForThisAnim(config.name) then
					tw.Completed:Wait()
					if baseline.TextScaled ~= nil then pcall(function() obj.TextScaled = baseline.TextScaled end) end
					if baseline.TextSize ~= nil and not baseline.TextScaled then pcall(function() obj.TextSize = baseline.TextSize end) end
				end
			end)
		else
			task.spawn(function()
				local function playOnce()
					if config.from then pcall(function() obj[config.prop] = config.from end) end
					local target = config.to or config.val or baseline[config.prop]
					local t = safeTween(obj, TweenInfo.new(config.time or 0.5, Enum.EasingStyle[config.style or "Quad"]), {[config.prop] = target})
					if t then pcall(function() t.Completed:Wait() end) end
					local bt = safeTween(obj, TweenInfo.new(config.time or 0.4, Enum.EasingStyle[config.style or "Quad"]), {[config.prop] = baseline[config.prop]})
					if bt then pcall(function() bt.Completed:Wait() end) end
				end
				
				local shouldLoop = config.looping == nil or config.looping == true
				if shouldLoop then
					while obj and obj.Parent do
						playOnce()
						task.wait(config.pause or 1)
					end
				else
					playOnce()
				end
			end)
		end
	end
end

return Runtime
