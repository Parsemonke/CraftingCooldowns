# CraftingSync

Merges your CraftingCooldowns addon database across multiple WoW accounts,
then launches WoW automatically. No background process, no server, no Python
required on the end user's machine.

---

## For end users (you received the .exe)

You need two files in the same folder:

```
CraftingSync.exe
config.json
```

### 1. Edit config.json

Open `config.json` in Notepad and fill in your paths:

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

**wow_executable**
  Path to WoW.exe (or your server launcher). Use forward slashes.

**savedvariables_paths**
  One path per account. You can add as many accounts as you like.
  To find the right path, look in:
  `C:\WoW\WTF\Account\<YOUR_ACCOUNT_NAME>\SavedVariables\`
  The account name folder is usually your login name in ALL CAPS.

**addon_db_key**
  The Lua global the addon uses for its database. Default is
  CraftingCooldownsDB — only change this if you know it differs.

**launch_wow**
  Set to false if you only want the merge without launching WoW.

**backup_before_merge**
  Set to true (recommended) to keep timestamped .bak copies of your
  SV files before every merge, in case something goes wrong.

### 2. Use it

Double-click `CraftingSync.exe` instead of WoW from now on.

It will:
1. Read all SavedVariables files listed in config.json
2. Merge character data (newest lastScanAt per character wins)
3. Write the merged result back to all SV files
4. Launch WoW

Each character's cooldowns will be visible to all accounts on login.

---

## How the merge works

Each character is stored under a unique `"CharName-RealmName"` key.
The merge keeps the most recently scanned copy of each character across
all accounts. No data is ever lost — if Account 1 has Mage data and
Account 2 has Druid data, the merged result contains both.

If the same character appears in multiple SV files (e.g. you logged
both accounts at the same time), the copy with the higher `lastScanAt`
timestamp wins.

Backups are saved next to the original file as:
`CraftingCooldowns.bak_YYYYMMDD_HHMMSS`

---

## For developers (building the .exe yourself)

Requirements: Python 3.10+ with internet access for first build.

```
build.bat
```

That's it. The script installs lupa and PyInstaller automatically,
builds a standalone exe, and puts the result in the `dist/` folder.

Output:
```
dist/
  CraftingSync.exe    <- share this
  dist/config.json    <- user edits this once
```

The exe bundles lupa (Lua runtime) so the end user needs nothing installed.

---

## Troubleshooting

**"Key 'CraftingCooldownsDB' not found"**
  Your addon may use a different global name. Open the SV file in
  Notepad — the first line will be something like `MyAddonDB = {`.
  Put that name in config.json under addon_db_key.

**"WoW executable not found"**
  Update wow_executable in config.json with the correct path.
  Right-click your WoW shortcut → Properties → Target to find it.

**Cooldowns not showing for other account's characters**
  Make sure both accounts have logged out cleanly before running
  CraftingSync — WoW only writes SavedVariables on logout/reload.
  The safest workflow: log out on Account 1, run CraftingSync, log in
  on Account 2.

**I want to add a third account**
  Just add a third path to savedvariables_paths in config.json.
  No limit on the number of accounts.
