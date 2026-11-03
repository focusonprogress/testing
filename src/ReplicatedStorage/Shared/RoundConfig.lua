--[[
	RoundConfig — tempos, modos e eventos do sistema de rodadas.
	Fica no ReplicatedStorage porque a interface também usa os nomes/emojis.
]]

local RoundConfig = {}

---------------------------------------------------------------------
-- MAPA
---------------------------------------------------------------------
--[[
	Se o seu mapa (torres + chão) estiver dentro de um Model/Folder no
	Workspace, coloque o nome dele aqui (ex.: "Map"). O sistema guarda uma
	cópia no começo do servidor e reconstrói o mapa a cada rodada.

	Se deixar "" (ou não achar), ele usa TUDO que está no Workspace,
	menos Terrain, câmera e personagens.
]]
RoundConfig.MapName = ""

-- Coisas do Workspace que NUNCA devem ser apagadas/reconstruídas
RoundConfig.IgnoreInWorkspace = { "Camera", "Terrain" }

-- Se o SpawnLocation de um time cair mais que isso (studs), a torre "caiu"
RoundConfig.SpawnFallTolerance = 15

---------------------------------------------------------------------
-- TEMPOS (segundos)
---------------------------------------------------------------------
RoundConfig.MinPlayers = 2 -- no Studio é sempre 1 (pra você testar sozinho)
RoundConfig.IntermissionTime = 20
RoundConfig.EndingTime = 8
RoundConfig.RespawnTime = 3

RoundConfig.ShrinkStartsAt = 90 -- quando começa o evento que encolhe o mapa
RoundConfig.FirstRandomEventAt = 40
RoundConfig.SuddenDeathAt = 360 -- 6 min: sem respawn, tudo mais rápido
RoundConfig.MaxRoundTime = 600 -- 10 min: acaba por tempo

---------------------------------------------------------------------
-- RECOMPENSAS (usa o sistema de progressão)
---------------------------------------------------------------------
RoundConfig.MVPReward = { XP = 60, Coins = 30 }
RoundConfig.KingKillReward = { XP = 75, Coins = 50 }
RoundConfig.KingSurviveReward = { XP = 75, Coins = 50 }
RoundConfig.GoldenBrickReward = { XP = 40, Coins = 100 }

---------------------------------------------------------------------
-- MODOS (votados na intermissão)
---------------------------------------------------------------------
RoundConfig.Modes = {
	{
		Id = "Classic",
		Name = "Clássico",
		Emoji = "🏰",
		Description = "Derrube as torres inimigas! Sem torre, sem respawn.",
		Teams = true,
		EventInterval = 55,
		EventDuration = 25,
	},
	{
		Id = "FFA",
		Name = "Todos contra todos",
		Emoji = "💥",
		Description = "Cada um por si. 3 vidas!",
		Teams = false,
		Lives = 3,
		EventInterval = 55,
		EventDuration = 25,
	},
	{
		Id = "Swords",
		Name = "Só espadas",
		Emoji = "🗡️",
		Description = "Nada de foguete ou bomba. Só lâmina!",
		Teams = true,
		SwordsOnly = true,
		EventInterval = 55,
		EventDuration = 25,
	},
	{
		Id = "Chaos",
		Name = "Caos",
		Emoji = "🌪️",
		Description = "Um evento atrás do outro!",
		Teams = true,
		EventInterval = 20,
		EventDuration = 15,
	},
}

function RoundConfig.GetMode(id: string)
	for _, mode in ipairs(RoundConfig.Modes) do
		if mode.Id == id then
			return mode
		end
	end
	return RoundConfig.Modes[1]
end

-- Nomes que contam como "espada" (modo/evento só espadas). Gears da loja contam sempre.
RoundConfig.SwordKeywords = { "sword", "espada", "blade", "periastron", "illumina", "darkheart", "venomshank", "firebrand", "katana" }

---------------------------------------------------------------------
-- EVENTOS
---------------------------------------------------------------------
-- Eventos que encolhem o mapa (um por rodada, sorteado)
RoundConfig.ShrinkEvents = {
	{ Id = "Lava", Emoji = "🌋", Name = "A LAVA ESTÁ SUBINDO!", Description = "Suba nas torres!" },
	{ Id = "Melt", Emoji = "🏚️", Name = "AS TORRES ESTÃO DERRETENDO!", Description = "Os andares de baixo vão sumir..." },
	{ Id = "Edge", Emoji = "⬛", Name = "O MAPA ESTÁ DESMORONANDO!", Description = "As bordas estão caindo, vá pro centro!" },
	{ Id = "Zone", Emoji = "☁️", Name = "NUVEM TÓXICA!", Description = "Fique dentro da zona segura!" },
}

-- Eventos aleatórios (duram EventDuration do modo)
RoundConfig.RandomEvents = {
	{ Id = "Meteors", Emoji = "☄️", Name = "CHUVA DE METEOROS!", Description = "Olhe pro céu!" },
	{ Id = "Bombs", Emoji = "💣", Name = "CHUVA DE BOMBAS!", Description = "Corra quando ouvir o tique-taque!" },
	{ Id = "LowGravity", Emoji = "🌙", Name = "GRAVIDADE BAIXA!", Description = "Pulos gigantes!" },
	{ Id = "Speed", Emoji = "⚡", Name = "SUPER VELOCIDADE!", Description = "Todo mundo 2x mais rápido!" },
	{ Id = "Blackout", Emoji = "🌑", Name = "APAGÃO!", Description = "Ficou de noite..." },
	{ Id = "SwordDuel", Emoji = "🗡️", Name = "DUELO DE ESPADAS!", Description = "Só espadas por um tempo!" },
	{ Id = "GoldenBrick", Emoji = "💎", Name = "TIJOLO DOURADO!", Description = "Quem pegar primeiro ganha moedas!" },
	{ Id = "KingHunt", Emoji = "👑", Name = "CAÇA AO REI!", Description = "Derrube o rei pra ganhar bônus!" },
}

RoundConfig.Events = {}
for _, list in ipairs({ RoundConfig.ShrinkEvents, RoundConfig.RandomEvents }) do
	for _, event in ipairs(list) do
		RoundConfig.Events[event.Id] = event
	end
end

-- Ajustes finos dos eventos
RoundConfig.Tuning = {
	LavaRiseTime = 200, -- segundos pra lava ir do chão até o topo das torres
	LavaDamagePerSecond = 60,
	MeltTime = 200, -- segundos pra "derreter" até o topo
	MeltIgnoreBiggerThan = 120, -- peças maiores que isso (ex.: chão gigante) não derretem
	EdgeShrinkTime = 180,
	EdgeMinRadius = 30,
	ZoneShrinkTime = 180,
	ZoneMinRadius = 25,
	ZoneDamagePerSecond = 15,
	MeteorEvery = 0.5,
	BombEvery = 0.8,
	LowGravity = 50,
	SpeedWalkSpeed = 32,
	SuddenDeathSpeedMultiplier = 2,
}

return RoundConfig
