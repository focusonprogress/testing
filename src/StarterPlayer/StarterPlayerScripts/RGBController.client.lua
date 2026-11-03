-- Anima todos os textos marcados como RGB (interface, títulos em cima da cabeça etc.)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RGB = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RGB"))

RGB.Start()
