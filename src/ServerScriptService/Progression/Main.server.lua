-- Liga o sistema de progressão (dados, XP, níveis, loja, conquistas).
-- Acha um filho pelo nome, ignorando espaços sobrando e maiúsculas/minúsculas
local function findChild(parent: Instance, name: string): Instance
	local target = name:lower()
	local started = os.clock()
	local warned = false
	while true do
		for _, child in ipairs(parent:GetChildren()) do
			local clean = child.Name:gsub("^%s+", ""):gsub("%s+$", "")
			if clean:lower() == target then
				return child
			end
		end
		if not warned and os.clock() - started > 5 then
			warned = true
			warn(("[Progression] Esperando '%s' dentro de %s... confira se ele existe e está no lugar certo."):format(name, parent:GetFullName()))
		end
		task.wait(0.1)
	end
end

local Progression = require(findChild(script.Parent, "ProgressionService"))
Progression.Init()
