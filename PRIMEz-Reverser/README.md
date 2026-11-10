# ⚡ PRIMEz Reverser

> **Autonomous Lua & Luau Reverse Engineering Engine and Discord Bot**  
> Developed for the **PRIMEz Suite** to deobfuscate, analyze, and devirtualize protected Roblox / Lua scripts.

---

## 🌟 Key Features

- **Multi-Engine Reverse Engineering Architecture**:
  - **IronBrew 3 (IB3)**: Pure-Python varint stream decoder and prototype lifter.
  - **LuaObfuscator (Ferib VM)**: SSA-style IR lifter, control-flow deflattener, dead-code eliminator, and constant folder.
  - **IronBrew 1 (IB1)**: Dynamic Luau memory hook capture and CFG reconstructor.
  - **IronBrew 2 / AztupBrew (IB2)**: Native C# bytecode disassembler bridge.
  - **Luraph (v14.7 - v15)**: Behavioral Luau sandbox (`envlog.luau`) and symbolic tracer.
  - **Generic Sandbox**: Automated trace capture for unknown or novel obfuscators.
- **Smart Signature Fingerprinting**:
  - Exact signature matchers + Jaccard similarity scoring across structural feature vectors.
- **Security & Privacy Shield**:
  - Automatically redacts Discord Webhook URLs and bot tokens from decompiled source to protect secrets.
- **Dual Interface**:
  - **Interactive Discord Bot** with modern Slash Commands (`/deobf`, `/detect`, `/status`).
  - **High-Speed Standalone CLI** (`primez_cli.py`) for automated and headless workflows.
- **Ultra-Lightweight**:
  - Refactored and pruned from over **1.18 GB** of bloat down to **~21 MB** clean.

---

## 🚀 Quick Start (CLI)

### 1. Installation
Ensure Python 3.10+ is installed:
```bash
pip install -r requirements.txt
```

### 2. Deobfuscate a File
```bash
# Auto-detect obfuscator and save output
python primez_cli.py obfuscated.lua -o clean.lua

# Force a specific engine
python primez_cli.py script.lua -o clean.lua --backend luaobf
```

### 3. Fingerprint Analysis
```bash
python primez_cli.py --detect script.lua
```

---

## 🤖 Discord Bot Setup

1. Copy `.env.example` to `.env` or edit `config.py`:
   ```env
   DISCORD_TOKEN=your_bot_token_here
   COMMAND_PREFIX=!
   ```
2. Launch the bot:
   ```bash
   python bot/bot.py
   ```
3. Use slash commands inside Discord:
   - `/deobf` — Upload an attachment, paste code, or supply a raw URL.
   - `/detect` — Quick fingerprint breakdown.
   - `/status` — Live diagnostics of available backends and binaries.

---

## 📁 Repository Layout

```text
PRIMEz-Reverser/
├── bin/                 # Luau execution & AST binaries
├── bot/                 # Discord Bot, UI components & slash commands
├── core/                # Central engine, detector & security sanitizer
├── data/                # Structural fingerprint database
├── engines/             # Modular deobfuscation engines (IB1, IB2, IB3, LuaObf, Luraph)
├── config.py            # Global paths & settings
├── primez_cli.py        # Standalone terminal runner
└── requirements.txt     # Python dependencies
```

---

## 🛡️ License & Attribution
Part of the **PRIMEz** ecosystem.
