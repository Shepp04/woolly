--!strict

--// Services
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

--// Constants
local TAG = "RotatingElement"
local APPLIED_TAG = TAG .. "_Applied"

--// Types
type GuiComponent = {
	Init: (self: GuiComponent) -> (),
}

--// Component
local GuiComponent = {} :: GuiComponent

--// Render Update
local function update()
	local elements = CollectionService:GetTagged(TAG)
	if #elements == 0 then return end

	local t = tick()

	for _, element in elements do
		if not element:IsDescendantOf(game.Players) then continue end
		if not CollectionService:HasTag(element, APPLIED_TAG) then
			CollectionService:AddTag(element, APPLIED_TAG)
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