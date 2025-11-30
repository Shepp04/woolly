--!strict

-- // Services
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- // Constants
local TAG = "RotatingElement"

-- // Types
type GuiComponent = {
	Init: (self: GuiComponent) -> (),
}

-- // Component
local GuiComponent = {} :: GuiComponent

-- // Internal State
local appliedInstances: { [Instance]: boolean } = {}

-- // Render Update
local function update()
	local elements = CollectionService:GetTagged(TAG)
	if #elements == 0 then return end

	local t = tick()

	for _, element in elements do
		if not element:IsDescendantOf(game.Players) then continue end
		if not appliedInstances[element] then
			appliedInstances[element] = true
		end

		local speed = element:GetAttribute("RotateSpeed") or 1
		element.Rotation += speed
	end
end

-- ========== Life Cycle ========== --
function GuiComponent:Init()
	RunService:BindToRenderStep("RotateUIElements", Enum.RenderPriority.Last.Value, update)
end

return GuiComponent