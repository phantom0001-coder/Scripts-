import os
import sys
from pathlib import Path

# Base Paths
BASE_DIR = Path(__file__).resolve().parent
ENGINES_DIR = BASE_DIR / "engines"
BIN_DIR = BASE_DIR / "bin"
DATA_DIR = BASE_DIR / "data"

# Automatically load local .env if present
_env_file = BASE_DIR / ".env"
if _env_file.exists():
    try:
        for line in _env_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip("'\""))
    except Exception:
        pass

# Discord Bot Configuration
DISCORD_TOKEN = os.getenv("DISCORD_TOKEN", "")
COMMAND_PREFIX = os.getenv("COMMAND_PREFIX", "!")
FALLBACK_CHANNEL_ID = int(os.getenv("FALLBACK_CHANNEL_ID", "0"))

# Execution Timeouts (seconds)
DEOBF_TIMEOUT = int(os.getenv("DEOBF_TIMEOUT", "180"))
MAX_INPUT_SIZE_MB = int(os.getenv("MAX_INPUT_SIZE_MB", "15"))

# Backend Paths (platform-aware)
# Windows ships the .exe builds in bin/. On Linux (e.g. Render), the bundled
# engines/luraph/bin/luau build is used instead. The IB2 C# CLI is
# Windows-only and simply fails (and gets skipped by the engine cascade) elsewhere.
if sys.platform == "win32":
    LUAU_BIN = BIN_DIR / "luau.exe"
    LUAU_AST_BIN = BIN_DIR / "luau-ast.exe"
else:
    LUAU_BIN = ENGINES_DIR / "luraph" / "bin" / "luau"
    LUAU_AST_BIN = LUAU_BIN  # no separate Linux luau-ast build is bundled

IB1_RUNNER = ENGINES_DIR / "ib1" / "runner.py"
IB2_CLI = ENGINES_DIR / "ib2" / "bin" / "CLI.exe"
LURAPH_CLI = ENGINES_DIR / "luraph" / "deob.py"

# Brand Colors (Hex / Int for Discord Embeds)
PRIMEZ_COLOR_PRIMARY = 0xFF204E   # Crimson Cyberpunk
PRIMEZ_COLOR_SUCCESS = 0x00FFA3   # Neon Mint
PRIMEZ_COLOR_INFO    = 0x00D2FF   # Cyber Blue
PRIMEZ_COLOR_WARNING = 0xFFA500  # Amber
PRIMEZ_COLOR_ERROR   = 0xFF0055   # Bright Red
