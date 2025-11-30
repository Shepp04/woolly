--!strict

-- // Services
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- // Constants
local TAG = "SwingingElement"

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

		local maxAngle = element:GetAttribute("MaxSwingAngle") or 30
		local offset = element:GetAttribute("SwingOffset") or 0
		local speed = element:GetAttribute("SwingSpeed") or 1
		local func = element:GetAttribute("SwingFunction") or "Default"

		local rot : number
		if (func == "Default") then
			rot = (math.sin(speed * t * 1.5) * math.cos(speed * 0.1 * t)) * maxAngle
		elseif (func == "Tan") then
			rot = (math.sin(speed * 0.25 * t) / math.cos(speed * 1 * t)) * maxAngle
		end

		element.Rotation = rot + offset
	end
end

-- ========== Life Cycle ========== --
function GuiComponent:Init()
	RunService:BindToRenderStep("SwingUIElements", Enum.RenderPriority.Last.Value, update)
end

return GuiComponent