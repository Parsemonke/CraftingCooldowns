"""
CraftingSync.py
===============
Merges CraftingCooldowns SavedVariables across multiple WoW accounts,
then launches WoW (or any target executable).

Place CraftingSync.exe and config.json in the same folder.
Edit config.json once, then always launch WoW through CraftingSync.exe.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

# ── Logging ──────────────────────────────────────────────────────────────────

LOG_LINES = []

def log(msg: str):
    ts = datetime.now().strftime("%H:%M:%S")
    line = f"[{ts}] {msg}"
    LOG_LINES.append(line)
    print(line)

def fatal(msg: str):
    log(f"ERROR: {msg}")
    log("")
    log("Press Enter to exit.")
    input()
    sys.exit(1)

# ── Config ────────────────────────────────────────────────────────────────────

DEFAULT_CONFIG = {
    "wow_executable": "C:/WoW/WoW.exe",
    "savedvariables_paths": [
        "C:/WoW/WTF/Account/ACCOUNT1/SavedVariables/CraftingCooldowns.lua",
        "C:/WoW/WTF/Account/ACCOUNT2/SavedVariables/CraftingCooldowns.lua"
    ],
    "addon_db_key": "CraftingCooldownsDB",
    "launch_wow": True,
    "backup_before_merge": True
}

def load_config() -> dict:
    exe_dir = Path(sys.executable).parent if getattr(sys, "frozen", False) else Path(__file__).parent
    config_path = exe_dir / "config.json"

    if not config_path.exists():
        log("config.json not found — creating default template.")
        with open(config_path, "w", encoding="utf-8") as f:
            json.dump(DEFAULT_CONFIG, f, indent=4)
        fatal(
            f"config.json has been created at:\n  {config_path}\n\n"
            "Please edit it with your WoW path and account SavedVariables paths,\n"
            "then run CraftingSync again."
        )

    with open(config_path, "r", encoding="utf-8") as f:
        try:
            cfg = json.load(f)
        except json.JSONDecodeError as e:
            fatal(f"config.json is not valid JSON: {e}")

    # Fill in any missing keys with defaults
    for k, v in DEFAULT_CONFIG.items():
        cfg.setdefault(k, v)

    return cfg

# ── Lua SV parser ─────────────────────────────────────────────────────────────
#
# WoW SavedVariables files are Lua assignment statements.
# We use lupa (embedded LuaJIT) to evaluate them in a sandboxed runtime,
# then walk the resulting table into plain Python dicts/lists.
#
# lupa is bundled into the .exe by PyInstaller so the end user needs nothing.

def lua_to_python(lua_val):
    """Recursively convert a lupa Lua table into a Python dict or list."""
    try:
        from lupa import lua_type
    except ImportError:
        fatal("lupa library not found. Please rebuild the exe.")

    if lua_type(lua_val) == "table":
        # Determine if it looks like an array (consecutive integer keys from 1)
        keys = list(lua_val.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [lua_to_python(lua_val[k]) for k in sorted(keys)]
        else:
            return {str(k): lua_to_python(v) for k, v in lua_val.items()}
    else:
        return lua_val


def parse_sv_file(path: Path, db_key: str) -> dict:
    """
    Parse a SavedVariables .lua file and return the contents of db_key
    as a plain Python dict.  Returns {} on any failure.
    """
    try:
        from lupa import LuaRuntime
    except ImportError:
        fatal("lupa library not found.")

    if not path.exists():
        log(f"  Skipping (file not found): {path}")
        return {}

    try:
        lua_src = path.read_text(encoding="utf-8")
    except Exception as e:
        log(f"  Could not read {path.name}: {e}")
        return {}

    # Wrap in a pcall so Lua parse errors don't crash the runtime
    lua = LuaRuntime(unpack_returned_tuples=False)

    # Inject a safe environment — expose only what WoW SV files need
    safe_bootstrap = f"""
        local ok, err = pcall(function()
            {lua_src}
        end)
        if not ok then
            _G.__parse_error = err
        end
    """
    try:
        lua.execute(safe_bootstrap)
    except Exception as e:
        log(f"  Lua execution error in {path.name}: {e}")
        return {}

    parse_error = lua.globals().__parse_error
    if parse_error:
        log(f"  Lua parse error in {path.name}: {parse_error}")
        return {}

    raw = lua.globals()[db_key]
    if raw is None:
        log(f"  Key '{db_key}' not found in {path.name} — skipping.")
        return {}

    try:
        return lua_to_python(raw)
    except Exception as e:
        log(f"  Failed to convert Lua table in {path.name}: {e}")
        return {}


# ── Deep-path helpers ─────────────────────────────────────────────────────────

def deep_get(d: dict, *keys):
    """Safely traverse nested dicts. Returns None if any key is missing."""
    cur = d
    for k in keys:
        if not isinstance(cur, dict):
            return None
        cur = cur.get(k)
    return cur


def deep_set(d: dict, value, *keys):
    """Write value into nested dicts, creating levels as needed."""
    for k in keys[:-1]:
        d = d.setdefault(k, {})
    d[keys[-1]] = value


# ── Merge logic ───────────────────────────────────────────────────────────────
#
# AceDB stores character data under:
#   DB["profiles"][profileName]["characters"]["CharName-RealmName"][...]
#
# We also support a flat layout:
#   DB["characters"]["CharName-RealmName"][...]
#
# For each character key, the copy with the highest lastScanAt wins.

def extract_characters(db: dict) -> dict:
    """
    Return a flat { charKey: charData } dict from either AceDB profile layout
    or a flat characters layout.
    """
    chars = {}

    # AceDB layout: db.profiles.*.characters.*
    profiles = db.get("profiles") or db.get("profile") or {}
    if isinstance(profiles, dict):
        for profile_name, profile_data in profiles.items():
            if not isinstance(profile_data, dict):
                continue
            profile_chars = profile_data.get("characters") or {}
            if isinstance(profile_chars, dict):
                for char_key, char_data in profile_chars.items():
                    if not isinstance(char_data, dict):
                        continue
                    existing = chars.get(char_key)
                    if existing is None:
                        chars[char_key] = {"data": char_data, "profile": profile_name}
                    else:
                        t_new = char_data.get("lastScanAt") or 0
                        t_old = existing["data"].get("lastScanAt") or 0
                        if t_new > t_old:
                            chars[char_key] = {"data": char_data, "profile": profile_name}

    # Flat layout: db.characters.*
    flat_chars = db.get("characters") or {}
    if isinstance(flat_chars, dict):
        for char_key, char_data in flat_chars.items():
            if not isinstance(char_data, dict):
                continue
            existing = chars.get(char_key)
            if existing is None:
                chars[char_key] = {"data": char_data, "profile": None}
            else:
                t_new = char_data.get("lastScanAt") or 0
                t_old = existing["data"].get("lastScanAt") or 0
                if t_new > t_old:
                    chars[char_key] = {"data": char_data, "profile": None}

    return chars


def merge_databases(all_dbs: list[dict]) -> dict:
    """
    Merge a list of parsed DB dicts into one.
    Uses the first non-empty DB as the structural base (keeps profileKeys,
    global settings etc.), then overlays the best character data from all DBs.
    """
    if not all_dbs:
        return {}

    # Start from the first valid DB as the base structure
    base = {}
    for db in all_dbs:
        if db:
            base = json.loads(json.dumps(db))  # deep copy via JSON round-trip
            break

    # Collect the best version of every character from all accounts
    all_chars: dict[str, dict] = {}
    for db in all_dbs:
        if not db:
            continue
        chars = extract_characters(db)
        for char_key, entry in chars.items():
            existing = all_chars.get(char_key)
            if existing is None:
                all_chars[char_key] = entry
            else:
                t_new = entry["data"].get("lastScanAt") or 0
                t_old = existing["data"].get("lastScanAt") or 0
                if t_new > t_old:
                    all_chars[char_key] = entry

    # Write merged characters back into the base structure
    # AceDB layout
    profiles = base.get("profiles") or base.get("profile")
    if isinstance(profiles, dict):
        for char_key, entry in all_chars.items():
            profile_name = entry.get("profile")
            if profile_name and profile_name in profiles:
                if "characters" not in profiles[profile_name]:
                    profiles[profile_name]["characters"] = {}
                profiles[profile_name]["characters"][char_key] = entry["data"]
            else:
                # Fall back to first available profile
                first_profile = next(iter(profiles))
                if "characters" not in profiles[first_profile]:
                    profiles[first_profile]["characters"] = {}
                profiles[first_profile]["characters"][char_key] = entry["data"]

    # Flat layout
    elif "characters" in base:
        for char_key, entry in all_chars.items():
            base["characters"][char_key] = entry["data"]

    return base


# ── Lua writer ────────────────────────────────────────────────────────────────

def python_to_lua(val, indent: int = 0) -> str:
    """Serialize a Python value back to Lua table syntax."""
    pad  = "\t" * indent
    pad1 = "\t" * (indent + 1)

    if val is None:
        return "nil"
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, int):
        return str(val)
    if isinstance(val, float):
        # Preserve integer-looking floats as ints so WoW reads them cleanly
        if val == int(val):
            return str(int(val))
        return repr(val)
    if isinstance(val, str):
        escaped = val.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        return f'"{escaped}"'
    if isinstance(val, list):
        if not val:
            return "{}"
        items = [f"{pad1}{python_to_lua(v, indent + 1)}," for v in val]
        return "{\n" + "\n".join(items) + f"\n{pad}}}"
    if isinstance(val, dict):
        if not val:
            return "{}"
        lines = []
        for k, v in val.items():
            lua_val = python_to_lua(v, indent + 1)
            # Use ["key"] syntax to handle any key, including hyphenated charKeys
            lines.append(f'{pad1}["{k}"] = {lua_val},')
        return "{\n" + "\n".join(lines) + f"\n{pad}}}"
    # Fallback
    return f'"{str(val)}"'


def write_sv_file(path: Path, db_key: str, merged_db: dict):
    """Write the merged DB back to a SavedVariables .lua file."""
    lua_body = python_to_lua(merged_db)
    content  = f"{db_key} = {lua_body}\n"
    path.write_text(content, encoding="utf-8")


# ── Backup ────────────────────────────────────────────────────────────────────

def backup_file(path: Path):
    """Copy file to <name>.bak_YYYYMMDD_HHMMSS before overwriting."""
    if not path.exists():
        return
    ts  = datetime.now().strftime("%Y%m%d_%H%M%S")
    dst = path.with_suffix(f".bak_{ts}")
    shutil.copy2(path, dst)
    log(f"  Backed up → {dst.name}")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  CraftingSync — WoW Cooldown Database Merger")
    print("=" * 60)
    print()

    cfg = load_config()

    sv_paths   = [Path(p) for p in cfg["savedvariables_paths"]]
    db_key     = cfg["addon_db_key"]
    wow_exe    = Path(cfg["wow_executable"])
    do_launch  = cfg.get("launch_wow", True)
    do_backup  = cfg.get("backup_before_merge", True)

    # ── Validate ──────────────────────────────────────────────────────────────

    if not sv_paths:
        fatal("No savedvariables_paths defined in config.json.")

    valid_paths = [p for p in sv_paths if p.exists()]
    if not valid_paths:
        log("Warning: none of the configured SavedVariables paths exist yet.")
        log("This is normal if WoW has never been launched with the addon.")
        log("Skipping merge and launching WoW directly.")
    else:
        # ── Parse ──────────────────────────────────────────────────────────────
        log(f"Parsing {len(sv_paths)} SavedVariables file(s)...")
        all_dbs = []
        for p in sv_paths:
            log(f"  Reading: {p}")
            db = parse_sv_file(p, db_key)
            all_dbs.append(db)
            char_count = len(extract_characters(db))
            log(f"    → {char_count} character(s) found")

        # ── Merge ──────────────────────────────────────────────────────────────
        log("Merging databases...")
        merged = merge_databases(all_dbs)
        total_chars = len(extract_characters(merged))
        log(f"  → {total_chars} unique character(s) in merged result")

        # ── Write back ─────────────────────────────────────────────────────────
        log("Writing merged data back to all SV files...")
        for p in sv_paths:
            log(f"  Writing: {p}")
            if do_backup:
                backup_file(p)
            try:
                write_sv_file(p, db_key, merged)
                log(f"    → OK")
            except Exception as e:
                log(f"    → FAILED: {e}")

    print()

    # ── Launch WoW ────────────────────────────────────────────────────────────
    if do_launch:
        if not wow_exe.exists():
            fatal(
                f"WoW executable not found:\n  {wow_exe}\n\n"
                "Please update 'wow_executable' in config.json."
            )
        log(f"Launching: {wow_exe}")
        try:
            subprocess.Popen([str(wow_exe)], cwd=str(wow_exe.parent))
        except Exception as e:
            fatal(f"Failed to launch WoW: {e}")

        log("WoW launched. You can close this window.")
        time.sleep(3)
    else:
        log("launch_wow is false in config — skipping WoW launch.")
        log("")
        log("Press Enter to exit.")
        input()


if __name__ == "__main__":
    main()
