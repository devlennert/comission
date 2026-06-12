local module = {}
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local blur = Lighting.FrameBlur
local Correction = Lighting.FrameCorrection
local Player = game.Players.LocalPlayer
local playerGui = Player.PlayerGui
local UI = playerGui:WaitForChild("UI")
local cam = game.Workspace.Camera

local function changeFOV(fovtype)
	if fovtype == "Show" then
		local ShowInfo = TweenInfo.new(0.295,Enum.EasingStyle.Sine,Enum.EasingDirection.Out)
		local ShowTween = TweenService:Create(cam,ShowInfo,{FieldOfView = 107})
		ShowTween:Play()
	elseif fovtype == "Hide" then
		local HideInfo = TweenInfo.new(0.325,Enum.EasingStyle.Sine,Enum.EasingDirection.Out)
		local HideTween = TweenService:Create(cam,HideInfo,{FieldOfView = 70})
		HideTween:Play()
	end
end

local function HideButtons(button)
	local LeftButtons = UI.LeftButtons
	local SideInfo = TweenInfo.new(0.15,Enum.EasingStyle.Sine,Enum.EasingDirection.In)
	local SideTween = TweenService:Create(LeftButtons,SideInfo,{Position = UDim2.new(-0.3,0,LeftButtons.Position.Y.Scale,0)})
	SideTween:Play()
end

local function ShowButtons()
	local LeftButtons = UI.LeftButtons
	local SideInfo = TweenInfo.new(0.15,Enum.EasingStyle.Sine,Enum.EasingDirection.In)
	local SideTween = TweenService:Create(LeftButtons,SideInfo,{Position = UDim2.new(0.01,0,LeftButtons.Position.Y.Scale,0)})
	SideTween:Play()
end

local function showFrame(frame)
	local Original = frame:GetAttribute("Original")
	frame.Visible = true
	blur.Enabled = true
	Correction.Enabled = true
	UI.Bottom.Visible = true
	game:GetService("SoundService").Audio.Pop:Play()
	changeFOV("Show")
	local ShowInfo = TweenInfo.new(0.3,Enum.EasingStyle.Bounce,Enum.EasingDirection.Out)
	local ShowTween = TweenService:Create(frame,ShowInfo,{Size = Original})
	ShowTween:Play()
end

local function attachFrameSize(frame)
	frame:SetAttribute("Original",frame.Size)
end

local function closeFrame(frame)
	local HideInfo = TweenInfo.new(0.425,Enum.EasingStyle.Exponential,Enum.EasingDirection.InOut)
	local HideTween = TweenService:Create(frame,HideInfo,{Size = UDim2.new(0,0,0,0)})
	HideTween:Play()
	blur.Enabled = false
	Correction.Enabled = false
	UI.Bottom.Visible = false
	changeFOV("Hide")
	HideTween.Completed:Wait()
	frame.Visible = false
end

local function attachButtonToFrame(buttonF : Frame, frame : Frame?)
	local button
	if not buttonF:FindFirstChild("Btn") then
		button = buttonF
	else
		button = buttonF.Btn
	end
	local Exit : GuiButton = frame:FindFirstChild("Exit")
	attachFrameSize(frame)
	button.MouseButton1Click:Connect(function()
		task.wait(0.11)
		if frame.Visible == false then
			HideButtons(button)
			showFrame(frame)
		end
	end)
	if Exit then
		Exit.MouseButton1Click:Connect(function()
			ShowButtons()
			closeFrame(frame)
		end)
	end
	button.MouseButton1Click:Connect(function()
		if frame.Visible == true and not debounce then
			print("hi")
			ShowButtons()
			closeFrame(frame)
		end
	end)
end

attachButtonToFrame(UI.LeftButtons.Chairs,UI.Chairs)
attachButtonToFrame(UI.LeftButtons.Shop,UI.Shop)
attachButtonToFrame(UI.LeftButtons.Rebirth,UI.Rebirth)
attachButtonToFrame(UI.Right.Free,UI.FreeGift)
attachButtonToFrame(UI.LeftButtons.Rewards.Navigation.Daily,UI.DailyRewards)
attachButtonToFrame(UI.LeftButtons.Rewards.Navigation.Playtime,UI.PlaytimeFrame)
--attachButtonToFrame(UI.RightButtons.Items.Spin,UI.SpinTheWheel)
--attachButtonToFrame(UI.RightButtons.Items.free,UI.Freepet)
--attachButtonToFrame(UI.LeftButtons.Frame.Daily,UI.Daily)
--attachButtonToFrame(UI.RightButtons.Items.Gift,UI.Rewards)

-- Exposed for sibling scripts that need to close a frame or restore buttons
-- using the same animation/blur/FOV logic as the rest of the UI
module.CloseFrame  = closeFrame
module.ShowButtons = ShowButtons

return module