--!strict

-- // Services
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- // Constants
local TAG = "ColourChangingElement"

-- // Types
type GuiComponent = {
	ColourSets: { [string]: { [number]: Color3 } },
	
	Init: (self: GuiComponent) -> (),
}

-- // Component
local GuiComponent = {} :: GuiComponent

-- // Configuration
GuiComponent.ColourSets = {
	Default = {
		BrickColor.new("Really red").Color,
		BrickColor.new("Neon orange").Color,
		BrickColor.new("New Yeller").Color,
		BrickColor.new("Lime green").Color,
		BrickColor.new("Electric blue").Color,
		BrickColor.new("Dark blue").Color,
		BrickColor.new("Royal purple").Color,
		BrickColor.new("Hot pink").Color,
	},

	Greyscale = {
		Color3.fromRGB(0, 0, 0),
		Color3.fromRGB(128, 128, 128),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(128, 128, 128),
	},

	Blue = {
		Color3.fromRGB(50, 150, 255),
		Color3.fromRGB(0, 0, 255),
		Color3.fromRGB(0, 200, 255),
		Color3.fromRGB(0, 255, 255),
	},
}

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

		local colourSetId = element:GetAttribute("ColourSet") or "Default"
		local colourSet = GuiComponent.ColourSets[colourSetId]

		if not colourSet then
			warn(TAG .. " - Unknown colour set: " .. tostring(colourSetId))
			continue
		end

		local speedAttr = element:GetAttribute("ColourChangeSpeed") or 1
		local clampedSpeed = math.clamp(speedAttr, 0.1, 10)
		local duration = 4 / clampedSpeed

		local index = (t % (duration / #colourSet)) / (duration / #colourSet)
		local n1 = math.floor((t / duration) * #colourSet) % #colourSet
		local n2 = (n1 + 1) > #colourSet and 1 or (n1 + 1)

		if n1 == 0 then n1 = #colourSet end

		local c1 = colourSet[n1]
		local c2 = colourSet[n2]
		local interpolated = c1:Lerp(c2, index)

		if element:IsA("Frame") or element:IsA("GuiButton") then
			element.BackgroundColor3 = interpolated
		elseif element:IsA("ImageLabel") then
			element.ImageColor3 = interpolated
		elseif element:IsA("TextLabel") then
			element.TextColor3 = interpolated
		elseif element:IsA("UIStroke") then
			element.Color = interpolated
		end
	end
end

-- ========== Life Cycle ========== --
function GuiComponent:Init()
	RunService:BindToRenderStep("ChangeElementColours", Enum.RenderPriority.Last.Value, update)
end

return GuiComponent