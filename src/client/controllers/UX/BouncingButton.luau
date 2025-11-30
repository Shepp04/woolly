--!strict

-- // Services
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

-- // Constants
local TAG = "BouncingButton"

-- // Types
type GuiComponent = {
	Create: (self: GuiComponent, button: Frame) -> (),
	Init: (self: GuiComponent) -> (),
}

-- // Component
local GuiComponent = {} :: GuiComponent

-- // Internal State
local appliedInstances: { [Instance]: boolean } = {}

-- ========== Public API ========== --
function GuiComponent:Create(button: Frame): nil
	-- Prevent re-application
	if appliedInstances[button] then
		return
	end
	appliedInstances[button] = true

	local selectButton = button:FindFirstChild("Select")
	if not selectButton or not selectButton:IsA("TextButton") then
		warn(TAG, "Error: '" .. button:GetFullName() .. "' has no child 'Select' (TextButton)")
		return
	end

	local childFrame = button:FindFirstChild("Button")
	if not childFrame or not childFrame:IsA("Frame") then
		warn(TAG, "Error: '" .. button:GetFullName() .. "' has no child 'Button' (Frame)")
		return
	end

	local originalSize = childFrame.Size

	-- Create tweens
	local inTweens = {} :: { [string]: Tween }
	local outTweens = {} :: { [string]: Tween }
 
	local imageLabel = childFrame:FindFirstChild("ImageLabel")
	if (imageLabel) then
		inTweens.Image = TweenService:Create(
			imageLabel, TweenInfo.new(0.5, Enum.EasingStyle.Quart), {Rotation = 30}
		)
		outTweens.Image = TweenService:Create(
			imageLabel, TweenInfo.new(0.5, Enum.EasingStyle.Quart), {Rotation = 0}
		)
	end

	local gradientFrame = childFrame:FindFirstChild("GradientFrame") :: Frame
	if gradientFrame then
		gradientFrame.Transparency = 1
		gradientFrame.Visible = true
		inTweens.Gradient = TweenService:Create(
			gradientFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quart), {Transparency = 0.8}
		)
		outTweens.Gradient = TweenService:Create(
			gradientFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quart), {Transparency = 1}
		)
	end

	inTweens.Frame = TweenService:Create(
		childFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quart),
		{Position = UDim2.new(childFrame.Position.X.Scale, childFrame.Position.X.Offset, 0.5, -5)}
	)
	outTweens.Frame = TweenService:Create(
		childFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quart),
		{Position = childFrame.Position}
	)

	selectButton.MouseEnter:Connect(function()
		for _, tween in inTweens do
			tween:Play()
		end

		selectButton.MouseLeave:Wait()

		for _, tween in outTweens do
			tween:Play()
		end
	end)
end

-- ========== Life Cycle ========== --
function GuiComponent:Init()
	for _, instance in CollectionService:GetTagged(TAG) do
		GuiComponent:Create(instance)
	end

	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance)
		GuiComponent:Create(instance)
	end)
end

return GuiComponent