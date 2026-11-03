--[[
	Config — tudo que você quer ajustar no jogo fica aqui.
	Fica no ReplicatedStorage porque o cliente também lê (loja, conquistas, níveis).
]]

local Config = {}

---------------------------------------------------------------------
-- DADOS
---------------------------------------------------------------------
-- Mudar o nome do DataStore "zera" o progresso de todo mundo (útil para testes).
Config.DataStoreName = "DoomspireProgress_v1"
Config.AutosaveInterval = 120 -- segundos

Config.StartingCoins = 100

---------------------------------------------------------------------
-- RECOMPENSAS
---------------------------------------------------------------------
Config.Rewards = {
	Kill = { XP = 25, Coins = 10 },
	Win = { XP = 120, Coins = 60 },
	-- A partir de 3 kills seguidas sem morrer, cada kill extra dá esse bônus de moedas
	StreakBonusFrom = 3,
	StreakBonusCoins = 5,
}

---------------------------------------------------------------------
-- NÍVEIS
---------------------------------------------------------------------
Config.MaxLevel = 100

-- XP necessário para sair do nível `level` e ir para o próximo
function Config.XPForLevel(level: number): number
	return math.floor(100 * level ^ 1.35)
end

-- Títulos que aparecem em cima da cabeça (o maior nível alcançado vale)
Config.Titles = {
	{ Level = 1, Title = "Novato" },
	{ Level = 5, Title = "Construtor" },
	{ Level = 10, Title = "Demolidor" },
	{ Level = 20, Title = "Bombardeiro" },
	{ Level = 35, Title = "Mestre dos Tijolos" },
	{ Level = 50, Title = "Lenda de Doomspire" },
	{ Level = 75, Title = "Destruidor de Torres" },
	{ Level = 100, Title = "Imortal" },
}

function Config.GetTitle(level: number): string
	local title = Config.Titles[1].Title
	for _, entry in ipairs(Config.Titles) do
		if level >= entry.Level then
			title = entry.Title
		end
	end
	return title
end

---------------------------------------------------------------------
-- LOJA DE GEARS
---------------------------------------------------------------------
--[[
	Cada item pode vir de dois lugares (o primeiro que existir é usado):

	1) Um Tool dentro de ServerStorage > ShopItems com o MESMO nome do `Id`
	   (ex.: ServerStorage.ShopItems.PeriAlpha). Pegue o gear pela Toolbox,
	   jogue lá dentro e renomeie. É o jeito mais confiável.

	2) `AssetId`: o número do gear no catálogo do Roblox
	   (roblox.com/catalog/<NUMERO>/nome-do-gear). O servidor carrega com
	   InsertService. Só funciona com gears feitos pelo próprio Roblox
	   (as Periastrons são) ou por você. Deixe 0 para não usar.

	`Color` é só a cor do card na loja.
]]
Config.ShopItems = {
	-- Periastrons (espadas com habilidade especial)
	{ Id = "PeriAlpha",   Name = "Periastron Alpha",   Price = 1500,  MinLevel = 3,  AssetId = 0, Color = Color3.fromRGB(255, 70, 70) },
	{ Id = "PeriBeta",    Name = "Periastron Beta",    Price = 2500,  MinLevel = 6,  AssetId = 0, Color = Color3.fromRGB(80, 220, 110) },
	{ Id = "PeriGamma",   Name = "Periastron Gamma",   Price = 4000,  MinLevel = 10, AssetId = 0, Color = Color3.fromRGB(70, 140, 255) },
	{ Id = "PeriDelta",   Name = "Periastron Delta",   Price = 6000,  MinLevel = 15, AssetId = 0, Color = Color3.fromRGB(240, 240, 255) },
	{ Id = "PeriEpsilon", Name = "Periastron Epsilon", Price = 9000,  MinLevel = 22, AssetId = 0, Color = Color3.fromRGB(220, 80, 255) },
	{ Id = "PeriOmega",   Name = "Periastron Omega",   Price = 25000, MinLevel = 50, AssetId = 0, Color = Color3.fromRGB(255, 200, 40), Rainbow = true },

	-- Outras espadas clássicas
	{ Id = "Illumina",    Name = "Illumina",           Price = 3000,  MinLevel = 8,  AssetId = 0, Color = Color3.fromRGB(255, 245, 170) },
	{ Id = "Darkheart",   Name = "Darkheart",          Price = 3000,  MinLevel = 8,  AssetId = 0, Color = Color3.fromRGB(110, 60, 150) },
	{ Id = "Venomshank",  Name = "Venomshank",         Price = 2000,  MinLevel = 5,  AssetId = 0, Color = Color3.fromRGB(150, 255, 60) },
	{ Id = "Firebrand",   Name = "Firebrand",          Price = 2000,  MinLevel = 5,  AssetId = 0, Color = Color3.fromRGB(255, 130, 30) },
}

function Config.GetShopItem(id: string)
	for _, item in ipairs(Config.ShopItems) do
		if item.Id == id then
			return item
		end
	end
	return nil
end

---------------------------------------------------------------------
-- CONQUISTAS
---------------------------------------------------------------------
--[[
	Stat: qual número é olhado ("Kills", "Wins", "BestStreak", "Level", "OwnedCount")
	Goal: valor para desbloquear
	Coins: recompensa
	BadgeId: id de uma badge do Roblox para dar junto (0 = nenhuma)
]]
Config.Achievements = {
	{ Id = "FirstBlood", Name = "Primeiro Sangue",    Description = "Consiga sua primeira kill",        Stat = "Kills",      Goal = 1,   Coins = 50,   BadgeId = 0 },
	{ Id = "Kills100",   Name = "Exterminador",       Description = "Consiga 100 kills",                Stat = "Kills",      Goal = 100, Coins = 500,  BadgeId = 0 },
	{ Id = "Kills1000",  Name = "Máquina de Guerra",  Description = "Consiga 1000 kills",               Stat = "Kills",      Goal = 1000,Coins = 3000, BadgeId = 0 },
	{ Id = "FirstWin",   Name = "Torre de Pé",        Description = "Vença sua primeira partida",       Stat = "Wins",       Goal = 1,   Coins = 100,  BadgeId = 0 },
	{ Id = "Wins25",     Name = "Conquistador",       Description = "Vença 25 partidas",                Stat = "Wins",       Goal = 25,  Coins = 1000, BadgeId = 0 },
	{ Id = "Streak5",    Name = "Imparável",          Description = "Faça 5 kills seguidas sem morrer", Stat = "BestStreak", Goal = 5,   Coins = 250,  BadgeId = 0 },
	{ Id = "Streak10",   Name = "Lenda Viva",         Description = "Faça 10 kills seguidas sem morrer",Stat = "BestStreak", Goal = 10,  Coins = 750,  BadgeId = 0 },
	{ Id = "Level10",    Name = "Subindo",            Description = "Chegue ao nível 10",               Stat = "Level",      Goal = 10,  Coins = 300,  BadgeId = 0 },
	{ Id = "Level50",    Name = "Veterano",           Description = "Chegue ao nível 50",               Stat = "Level",      Goal = 50,  Coins = 2500, BadgeId = 0 },
	{ Id = "Collector",  Name = "Colecionador",       Description = "Tenha 3 gears da loja",            Stat = "OwnedCount", Goal = 3,   Coins = 500,  BadgeId = 0 },
}

return Config
