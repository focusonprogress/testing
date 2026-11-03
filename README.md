# Doomspire Brickbattle: sistemas

## Progressão + interface RGB 🌈

- **Dados salvos** (DataStore): moedas, XP, nível, kills, mortes, vitórias, melhor sequência, itens e conquistas. Autosave a cada 2 min e ao fechar o servidor.
- **XP e níveis** (1 a 100) com **títulos** em cima da cabeça. O nome fica em RGB com contorno na cor do time.
- **Moedas** por kill, por sequência de kills e por vitória.
- **Loja de gears** (Periastrons e outras espadas clássicas) com compra, equipar e desequipar. O gear vem sozinho toda vez que você nasce.
- **Conquistas**, com badges do Roblox opcionais, mais um painel de estatísticas (K/D etc.).
- **Interface**: HUD de nível, barra de XP e moedas; janelas da loja e das conquistas com blur; "+XP" flutuando; LEVEL UP gigante; avisos de conquista. Tudo com texto RGB.
- **Leaderboard** do Roblox com Nível, Kills e Vitórias.

## Instalação rápida (recomendado)

Baixe os 3 arquivos da pasta [`build/`](build). No Studio, clique com o botão direito no lugar indicado → **Insert from File...** e escolha o arquivo:

| Arquivo | Clique com o botão direito em |
|---|---|
| `1_Shared_ReplicatedStorage.rbxmx` | **ReplicatedStorage** |
| `2_Progression_ServerScriptService.rbxmx` | **ServerScriptService** |
| `3_Progression_StarterPlayerScripts.rbxmx` | **StarterPlayer > StarterPlayerScripts** |
| `4_Rounds_ServerScriptService.rbxmx` | **ServerScriptService** |
| `5_RoundUI_StarterPlayerScripts.rbxmx` | **StarterPlayer > StarterPlayerScripts** |

Antes de importar, apague as versões antigas (pastas `Shared` e `Progression`, e os LocalScripts `ProgressionUI` e `RGBController`).

Para regerar os arquivos depois de mudar o código: `python3 tools/build_rbxmx.py`.

## Onde fica cada coisa no Studio (instalação manual)

| Arquivo | Tipo | Onde colocar |
|---|---|---|
| `src/ReplicatedStorage/Shared/Config.lua` | ModuleScript `Config` | ReplicatedStorage > Folder `Shared` |
| `src/ReplicatedStorage/Shared/RGB.lua` | ModuleScript `RGB` | ReplicatedStorage > Folder `Shared` |
| `src/ReplicatedStorage/Shared/UIKit.lua` | ModuleScript `UIKit` | ReplicatedStorage > Folder `Shared` |
| `src/ServerScriptService/Progression/DataService.lua` | ModuleScript `DataService` | ServerScriptService > Folder `Progression` |
| `src/ServerScriptService/Progression/GearService.lua` | ModuleScript `GearService` | ServerScriptService > Folder `Progression` |
| `src/ServerScriptService/Progression/ProgressionService.lua` | ModuleScript `ProgressionService` | ServerScriptService > Folder `Progression` |
| `src/ServerScriptService/Progression/Main.server.lua` | **Script** `Main` | ServerScriptService > Folder `Progression` |
| `src/StarterPlayer/StarterPlayerScripts/RGBController.client.lua` | **LocalScript** `RGBController` | StarterPlayer > StarterPlayerScripts |
| `src/StarterPlayer/StarterPlayerScripts/ProgressionUI.client.lua` | **LocalScript** `ProgressionUI` | StarterPlayer > StarterPlayerScripts |

Ou use o [Rojo](https://rojo.space): `rojo serve` nesta pasta e conecte pelo plugin.

**Importante:** em *Game Settings > Security*, ligue **Enable Studio Access to API Services** para salvar no Studio.

## Colocando as Periastrons na loja

As Periastrons, a Illumina e a Darkheart já vêm com `AssetId` preenchido: o servidor baixa o gear oficial sozinho, sem precisar da Toolbox. Se algum não carregar, aparece um aviso `[GearService]` no Output. Aí é só corrigir o número em `Config.lua`.

Os itens ficam em `Config.ShopItems`. Para cada um, escolha **uma** destas opções:

1. **Pela Toolbox (mais confiável):** crie a pasta `ServerStorage > ShopItems`, coloque o Tool do gear lá dentro e renomeie com o `Id` do item (ex.: `PeriAlpha`).
2. **Pelo ID do catálogo:** pegue o número na URL do gear (`roblox.com/catalog/NUMERO/...`) e coloque em `AssetId`. O servidor carrega com InsertService. Isso só funciona para gears feitos pelo próprio Roblox (como as Periastrons) ou por você.

Item sem Tool configurado aparece como **"EM BREVE"** na loja e ninguém consegue comprar. Assim, ninguém gasta moedas à toa.

## Usando no sistema de rodadas

```lua
local Progression = require(game.ServerScriptService.Progression.ProgressionService)

-- quando um time vencer:
for _, player in ipairs(timeVencedor:GetPlayers()) do
	Progression.AddWin(player)
end

-- recompensa qualquer coisa:
Progression.Reward(player, 50, 20, "Destruiu uma torre!") -- XP, moedas, motivo
```

As kills já contam sozinhas pela tag `creator` que as armas clássicas colocam.

## Texto RGB em qualquer lugar

```lua
local RGB = require(game.ReplicatedStorage.Shared.RGB)
RGB.Apply(meuTextLabel)                -- gradiente arco-íris andando
RGB.Apply(meuTextLabel, "Rainbow")     -- cor única trocando
RGB.Apply(meuUIStroke, "Rainbow", 0.5) -- borda RGB mais rápida
```

Sem código: coloque a tag `RGBText` (Tag Editor) em qualquer TextLabel, TextButton, UIStroke ou Frame.

## Rodadas e eventos 🌋

**Ciclo:** Aguardando jogadores → Intermissão (20s: mapa reconstruído, sem armas, votação de modo) → Partida → Fim (vencedor, MVP, recompensas).

- **Times e torres:** cada time é ligado à sua torre pelo SpawnLocation com o mesmo TeamColor. Se o spawn cair (ou for destruído), o time não renasce mais. O time perde quando não sobra ninguém vivo.
- **Modos (votados):** Clássico, Todos contra todos (3 vidas), Só espadas e Caos (um evento atrás do outro).
- **Encolhimento (um por rodada, aos 1:30):** lava subindo, torres derretendo, bordas desmoronando ou nuvem tóxica.
- **Eventos aleatórios:** meteoros, bombas, gravidade baixa, super velocidade, apagão, duelo de espadas, tijolo dourado e caça ao rei.
- **Morte súbita (6:00):** sem respawn e tudo 2x mais rápido. Aos 10:00 acaba por tempo.
- **Interface RGB:** barra do topo (fase, tempo, times vivos, eventos), anúncios, votação, killfeed e tela de vitória.

**Importante:** o sistema controla o respawn sozinho (`CharacterAutoLoads = false`). Desligue os scripts do jogo que fazem rodada, regen ou respawn (ex.: `GameControl` e `RegenControl`): selecione o script → Properties → marque **Disabled** (ou **Enabled** desmarcado).

Tudo se ajusta em `Shared > RoundConfig` (tempos, modos, eventos, dano da lava...). Se o mapa estiver dentro de um Model, coloque o nome dele em `RoundConfig.MapName`. Se não estiver, o sistema reconstrói o Workspace inteiro.
