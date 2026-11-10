import os
from pathlib import Path

# Base Paths
BASE_DIR = Path(__file__).resolve().parent
ENGINES_DIR = BASE_DIR / "engines"
BIN_DIR = BASE_DIR / "bin"
DATA_DIR = BASE_DIR / "data"

# Discord Bot Configuration
DISCORD_TOKEN = os.getenv("DISCORD_TOKEN", "")
COMMAND_PREFIX = os.getenv("COMMAND_PREFIX", "!")
FALLBACK_CHANNEL_ID = int(os.getenv("FALLBACK_CHANNEL_ID", "0"))

# Execution Timeouts (seconds)
DEOBF_TIMEOUT = int(os.getenv("DEOBF_TIMEOUT", "180"))
MAX_INPUT_SIZE_MB = int(os.getenv("MAX_INPUT_SIZE_MB", "15"))

# Backend Paths
LUAU_BIN = BIN_DIR / "luau.exe"
LUAU_AST_BIN = BIN_DIR / "luau-ast.exe"

IB1_RUNNER = ENGINES_DIR / "ib1" / "runner.py"
IB2_CLI = ENGINES_DIR / "ib2" / "bin" / "CLI.exe"
LURAPH_CLI = ENGINES_DIR / "luraph" / "deob.py"

# Brand Colors (Hex / Int for Discord Embeds)
PRIMEZ_COLOR_PRIMARY = 0xFF204E   # Crimson Cyberpunk
PRIMEZ_COLOR_SUCCESS = 0x00FFA3   # Neon Mint
PRIMEZ_COLOR_INFO    = 0x00D2FF   # Cyber Blue
PRIMEZ_COLOR_WARNING = 0xFFA500   # Amber
PRIMEZ_COLOR_ERROR   = 0xFF0055   # Bright Red
