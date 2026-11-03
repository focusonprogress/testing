-- Liga o sistema de rodadas (intermissão, votação, eventos, vitória).
-- Desligue (Disabled) outros scripts que fazem rodada/respawn/regen, como GameControl e RegenControl.

local function findChild(parent: Instance, name: string): Instance
	local target = name:lower()
	while true do
		for _, child in ipairs(parent:GetChildren()) do
			local clean = child.Name:gsub("^%s+", ""):gsub("%s+$", "")
			if clean:lower() == target then
				return child
			end
		end
		task.wait(0.1)
	end
end

local RoundService = require(findChild(script.Parent, "RoundService"))
RoundService.Init()
