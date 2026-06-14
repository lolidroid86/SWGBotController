# SWGBotController

PowerShell bot launcher for SWGEmu Pre-CU LAN servers. Launches multiple SWGEmu clients simultaneously with per-bot auto-login, arranged in a grid layout.

## How It Works

SWGEmu normally blocks multiple instances via a Windows named mutex (`SwgClientInstanceRunning`). The fix is a single line in the game config:

```ini
[SwgClient]
allowMultipleInstances=1
```

> **Critical:** This must be in `[SwgClient]`, not `[ClientGame]`. Source confirmed in `ClientMain.cpp`:
> `ConfigFile::getKeyBool("SwgClient", "allowMultipleInstances", false)`

The launcher uses `user.cfg` as a per-launch override file. It writes each bot's credentials before launching, waits for the process to read the config, then overwrites for the next bot. After all bots are launched, `user.cfg` is deleted so normal play is unaffected.

## Usage

```powershell
# Launch all 15 bots (bots.json)
.\launch_bots.ps1

# Launch 2-bot test config
.\launch_bots.ps1 -ConfigFile bots_test.json

# Launch a single bot manually (e.g. after crash)
$swgDir = "F:\mmo emulators\SWGEmu\StarWarsGalaxies"
$cfg = "[SwgClient]`r`nallowMultipleInstances=1`r`n`r`n[ClientGame]`r`nloginClientID=bot_doctor`r`nloginClientPassword=botpass1`r`nautoConnectToLoginServer=1`r`n`r`n[ClientGraphics]`r`nscreenWidth=1024`r`nscreenHeight=768`r`nwindowed=1`r`n"
[System.IO.File]::WriteAllText("$swgDir\user.cfg", $cfg, [System.Text.Encoding]::ASCII)
Start-Process "$swgDir\SWGEmu.exe" -WorkingDirectory $swgDir
Start-Sleep 8
Remove-Item "$swgDir\user.cfg"
```

## Config Format

```json
{
  "swgDir": "F:\\path\\to\\StarWarsGalaxies",
  "startupDelaySec": 6,
  "layout": {
    "columns": 2,
    "windowWidth": 640,
    "windowHeight": 480
  },
  "bots": [
    { "username": "bot_doctor",     "password": "botpass1" },
    { "username": "bot_entertainer","password": "botpass2" }
  ]
}
```

| Field | Description |
|---|---|
| `swgDir` | Path to the SWGEmu game client directory |
| `startupDelaySec` | Seconds to wait between launches for config to be read (6–8s) |
| `layout.columns` | Number of columns in the window grid |
| `layout.windowWidth/Height` | Size of each bot window in pixels |

### Window size notes
- `640x480` — minimum usable; travel terminal UI gets clipped
- `1024x768` — comfortable for interacting with in-game UIs
- `480x270` — use for 15-bot full grid (4 columns), minimized-only bots

## Server Setup (SWGEmu Pre-CU Docker)

### Docker container
```bash
docker start swgemu-core3
docker exec -it swgemu-core3 bash
```

### Starting the server
```bash
service mariadb start
sleep 8
cd /home/swgemu/workspace/Core3/MMOCoreORB/build/unix/src
./core3
```

> MariaDB runs **inside** the container. Always start it before core3 or you'll get "Can't connect to server on 127.0.0.1".

### Creating bot accounts (MySQL)
```sql
INSERT INTO accounts (username, password, admin_level) VALUES ('bot_doctor', SHA1('botpass1'), 0);
INSERT INTO accounts (username, password, admin_level) VALUES ('bot_entertainer', SHA1('botpass2'), 0);
```

### Admin accounts
Set `admin_level = 15` for your main account to get full admin at login:
```sql
UPDATE accounts SET admin_level = 15 WHERE username = 'hissash';
```

> **Note:** Admin skills (`admin_general_admin_02`, `admin_base`) are only applied at **character creation**, not login. They are granted via `PlayerCreationManager.cpp` when `accountPermissionLevel > 0`. For a newly created character to receive admin, the account must already have `admin_level = 15` **before** character creation.

### freeGodMode — all new chars get admin
In `bin/scripts/managers/player_creation_manager.lua`:
```lua
freeGodMode = 1          -- was 0; grants full admin to every new character
startingCash = 100000
startingBank = 1000000
```

### Key admin commands (in-game chat)
| Command | Effect |
|---|---|
| `/teleportTarget <name>` | Pull named player to you |
| `/teleportTo <name>` | Teleport yourself to named player |
| `/waypoint <x> <y>` | Set navigation waypoint |

## Bot Characters

| Account | Character | Professions |
|---|---|---|
| bot_entertainer | Siri Toni | Master Dancer, Master Entertainer, Master Image Designer |
| bot_doctor | Dibe Smeasa | Master Combat Medic, Master Doctor, Master Medic, Master Bio-Engineer, Master Creature Handler |

## Yavin IV Travel Points

If a character gets stranded on Yavin IV (e.g. via the Dark Jedi quest teleport), the two usable departure shuttles are:

| Location | X | Y | Notes |
|---|---|---|---|
| Mining Outpost | -267 | 4896 | Closest to Dark Jedi Enclave (~7000 units) |
| Labor Outpost | -6921 | -5726 | Farther option |

Imperial Outpost has `incomingTravelAllowed = 0` — you cannot depart from there.

Set a waypoint: `/waypoint -267 4896`

## Known Limitations

- **No programmatic keyboard input**: SWG uses DirectInput, not the Windows message queue. `PostMessage`, `SendInput`, `SendKeys`, and AutoHotkey WM_CHAR all fail for in-game text. Commands must be typed manually.
- **Travel terminal UI requires ≥1024px width**: The 640×480 bot default clips the terminal. Resize the window before buying tickets.
- **Admin skills require a fresh character**: `updatePermissionLevel` is not called on login for existing characters. See `SelectCharacterCallback.h` / `PlayerCreationManager.cpp`.

## Phase 2 (Planned)

Automated command input via a separate SKSE/DirectInput injection mechanism or server-side Lua command scheduling.
