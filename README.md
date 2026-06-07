# Crafting Cooldowns

A World of Warcraft addon for **Project Epoch** (WotLK 3.3.5a) that tracks crafting profession cooldowns across all your characters in a single clean UI — so you never forget to craft your weekly Mooncloth or Arcanite Transmute again.

![UI Preview](screenshots/preview.png)

---

## Features

- Tracks all profession crafting cooldowns across every character on your account
- Supports **Tailoring**, **Leatherworking**, and **Alchemy** — including both spell-based and item-based cooldowns
- ElvUI-inspired dark UI, toggleable with a slash command
- Chat notification when a cooldown becomes ready, with a clickable **Don't remind me** link per character
- Cross-account sync via the companion **CraftingSync** tool — share cooldown data between two separate WoW accounts without both needing to be online at the same time

---

## Supported Cooldowns

| Profession | Cooldown | Type |
|---|---|---|
| Tailoring | Mooncloth | Spell |
| Tailoring | Mooncloth BRD Ring | Item |
| Leatherworking | Salt Shaker | Item |
| Leatherworking | Masterwork Saltshaker | Item |
| Alchemy | Arcanite Transmute | Spell |
| Alchemy | Arcanite UBRS Ring | Item |

> Project Epoch uses custom item IDs for some Leatherworking cooldowns. These are already configured for the server — no manual setup needed.

---

## Installation

1. Download the latest release from the ([Main](https://github.com/Parsemonke/CraftingCooldowns/archive/refs/heads/main.zip)) 
2. Extract the `CraftingCooldowns-main` folder and rename to `CraftingCooldowns`.
3. Place it in your addons directory:
   ```
   World of Warcraft/Interface/AddOns/CraftingCooldowns/
   ```
4. Launch WoW and enable the addon in the character select screen

---

## Usage

| Command | Description |
|---|---|
| `/cd` | Toggle the cooldown window |
| `/ccd` | Toggle the cooldown window |
| `/craftingcd` | Toggle the cooldown window |

The window shows all characters on your account with their profession cooldowns, remaining time, and ready status. It updates automatically when you log in, cast a crafting spell, or open your bags.

---

## Chat Notifications

When a tracked cooldown becomes ready while you are logged in, you will see a message in chat:

```
[CraftingCooldowns] Mooncloth is ready on Mage!  [Don't remind me]
```

Clicking **Don't remind me** suppresses the notification for 1 hour. Suppression is per-character — silencing one alt does not affect others.

---

## Cross-Account Sync (CraftingSync)

By default the addon tracks all characters on a **single WoW account** automatically via shared SavedVariables. If you play on **two separate accounts**, the companion CraftingSync tool lets you merge both databases without needing both accounts online at the same time.

### How it works

CraftingSync is a small standalone `.exe` you run **instead of launching WoW directly**. It:

1. Reads the SavedVariables file from each configured account
2. Merges character cooldown data (most recently scanned copy of each character wins)
3. Writes the merged result back to all accounts
4. Launches WoW automatically

Each account will see all characters from both accounts in the cooldown UI on their next login — no extra in-game setup needed.

### Setup

1. Open `AccountSyncGuide` Filder
2. Place `CraftingSync.exe` and `config.json` anywhere on your PC
3. Edit `config.json`:

```json
{
    "wow_executable": "C:/WoW/WoW.exe",
    "savedvariables_paths": [
        "C:/WoW/WTF/Account/ACCOUNT1/SavedVariables/CraftingCooldowns.lua",
        "C:/WoW/WTF/Account/ACCOUNT2/SavedVariables/CraftingCooldowns.lua"
    ],
    "addon_db_key": "CraftingCooldownsDB",
    "launch_wow": true,
    "backup_before_merge": true
}
```

4. Double-click `CraftingSync.exe` instead of WoW from now on

Your account name folders can be found at:
```
World of Warcraft/WTF/Account/<ACCOUNT_NAME>/SavedVariables/
```

> `backup_before_merge: true` keeps a timestamped `.bak` copy of your SavedVariables before every merge. Recommended to leave this on.

### Building CraftingSync yourself

If you prefer to build from source rather than run a downloaded executable:

1. Install [Python 3.10+](https://www.python.org/downloads/) — tick **Add Python to PATH**
2. Place `CraftingSync.py`, `config.json`, and `build.bat` in the same folder
3. Double-click `build.bat`

The script installs all dependencies automatically and outputs `dist/CraftingSync.exe`. No Python installation required on the machine that runs the final exe.

---

## Screenshots

| Cooldown window | Chat notification |
|---|---|
| ![Notification](screenshots/notification.png) |

---

## Compatibility

- **Server:** Project Epoch (WotLK 3.3.5a)
- **Client patch:** 3.3.5a (12340)
- Uses only 3.3.5a-compatible APIs — no `C_Spell`, `C_Item`, `C_Timer`, or any Cataclysm+ APIs

---

## Contributing

Pull requests are welcome. If you play on a 3.3.5a server with different custom item IDs for Leatherworking cooldowns, open an issue with the correct IDs and the server name and I'll add a config entry for it.

---

## License

MIT — do whatever you want with it.

```
Copyright (c) 2025 Parsemonke
https://github.com/Parsemonke

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
