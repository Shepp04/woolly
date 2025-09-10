--!strict

-- // Paths
local Packages = {
    Sounds = require(script.Sounds),
    -- UI = require(script.UI),
    Remotes = require(script.Remotes),
    Bindables = require(script.Bindables),
    -- Debounce = require(script.Debounce),
    ReplicatedData = require(script.ReplicatedData),
    -- Collectables = require(script.Collectables),
    -- FriendStatus = require(script.FriendStatus),
}

-- Auto-loader
for _, child in ipairs(script:GetChildren()) do
    if child:IsA("ModuleScript") and Packages[child.Name] == nil then
        local ok, mod = pcall(require, child)
        if ok then Packages[child.Name] = mod end
    end
end

return Packages