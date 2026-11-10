import asyncio
import io
import os
import sys
from pathlib import Path

# Add project root and bot dir to sys.path
PROJECT_ROOT = Path(__file__).resolve().parent.parent
BOT_DIR = Path(__file__).resolve().parent

for p in [PROJECT_ROOT, BOT_DIR]:
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))

import discord
from discord import app_commands
from discord.ext import commands

from config import (
    DISCORD_TOKEN,
    COMMAND_PREFIX,
    PRIMEZ_COLOR_PRIMARY,
    PRIMEZ_COLOR_SUCCESS,
    PRIMEZ_COLOR_ERROR,
    PRIMEZ_COLOR_INFO,
    LUAU_BIN,
    IB2_CLI,
    LURAPH_CLI
)
from core.engine import deobfuscate
from core.detector import detect_obfuscator
from core.dumper import dump_bytecode_and_constants
from core.io_resolver import resolve_input

try:
    from bot.ui import make_primez_embed, DeobfActionView
except (ModuleNotFoundError, ImportError):
    from ui import make_primez_embed, DeobfActionView

intents = discord.Intents.default()
# Slash commands work without privileged message_content intent
intents.message_content = False

bot = commands.Bot(command_prefix=COMMAND_PREFIX, intents=intents)

@bot.event
async def on_ready():
    print(f"[+] PrimeZ R.E.L Bot logged in as {bot.user} (ID: {bot.user.id})")
    try:
        synced = await bot.tree.sync()
        print(f"[+] Synchronized {len(synced)} slash commands.")
    except Exception as e:
        print(f"[-] Failed to sync commands: {e}")

@bot.tree.command(name="status", description="Check PrimeZ R.E.L engine & binary health")
async def status_command(interaction: discord.Interaction):
    embed = make_primez_embed("PrimeZ R.E.L — Health Diagnostics", color=PRIMEZ_COLOR_INFO)
    
    ib3_ok = "✅ Operational (Built-in)"
    luaobf_ok = "✅ Operational (Python SSA)"
    ib1_ok = f"{'✅ Available' if LUAU_BIN.exists() else '⚠️ Missing luau.exe'}"
    ib2_ok = f"{'✅ Available' if IB2_CLI.exists() else '⚠️ Missing CLI.exe'}"
    luraph_ok = f"{'✅ Available' if LURAPH_CLI.exists() else '⚠️ Missing deob.py'}"
    
    embed.add_field(name="IronBrew 3 Lifter & Dumper", value=ib3_ok, inline=True)
    embed.add_field(name="LuaObfuscator Deflattener", value=luaobf_ok, inline=True)
    embed.add_field(name="IronBrew 1 Hook Engine", value=ib1_ok, inline=True)
    embed.add_field(name="IronBrew 2 / Aztup CLI", value=ib2_ok, inline=True)
    embed.add_field(name="Luraph Sandbox Tracer", value=luraph_ok, inline=True)
    embed.add_field(name="Luau Engine Core", value="v0.624+ Ready", inline=True)
    
    await interaction.response.send_message(embed=embed)

@bot.tree.command(name="detect", description="Inspect and fingerprint an obfuscated script")
@app_commands.describe(
    file="Upload an obfuscated script file (.lua / .luau / .txt)",
    code="Paste script code directly",
    url="Provide a direct URL to raw script"
)
async def detect_command(
    interaction: discord.Interaction,
    file: discord.Attachment | None = None,
    code: str | None = None,
    url: str | None = None
):
    await interaction.response.defer()
    
    raw_source = ""
    if file:
        data = await file.read()
        raw_source = data.decode("utf-8", errors="replace")
    elif url:
        raw_source = await resolve_input(url)
    elif code:
        raw_source = await resolve_input(code)
    else:
        await interaction.followup.send("❌ Please provide a file, code, or a URL to analyze.")
        return
        
    if not raw_source.strip():
        await interaction.followup.send("❌ Input is empty.")
        return
        
    det = detect_obfuscator(raw_source)
    embed = make_primez_embed("Obfuscator Fingerprint Detection", color=PRIMEZ_COLOR_INFO)
    embed.add_field(name="Identified Obfuscator", value=f"**{det.name}**", inline=False)
    embed.add_field(name="Engine Code", value=f"`{det.kind}`", inline=True)
    embed.add_field(name="Confidence Score", value=f"`{det.confidence * 100:.1f}%`", inline=True)
    embed.add_field(name="Direct Support", value="✅ Yes" if det.supported else "❌ Experimental/No", inline=True)
    embed.add_field(name="Detection Heuristic", value=det.reason, inline=False)
    
    await interaction.followup.send(embed=embed)

@bot.tree.command(name="dump", description="Dump constants pool, string table & bytecode instructions")
@app_commands.describe(
    file="Upload an obfuscated script (.lua / .luau / .txt)",
    code="Paste script code directly",
    url="Provide a direct URL to raw script",
    backend="Force a specific engine (default: auto)",
    ephemeral="Hide output from others (private session)"
)
@app_commands.choices(backend=[
    app_commands.Choice(name="Auto-Detect (Recommended)", value="auto"),
    app_commands.Choice(name="IronBrew 3", value="ib3"),
    app_commands.Choice(name="IronBrew 2 / AztupBrew", value="ib2"),
    app_commands.Choice(name="IronBrew 1", value="ib1"),
    app_commands.Choice(name="LuaObfuscator", value="luaobf"),
    app_commands.Choice(name="Luraph v14/v15", value="luraph"),
])
async def dump_command(
    interaction: discord.Interaction,
    file: discord.Attachment | None = None,
    code: str | None = None,
    url: str | None = None,
    backend: str = "auto",
    ephemeral: bool = False
):
    await interaction.response.defer(ephemeral=ephemeral)
    
    raw_source = ""
    filename = "primez_memory_dump.txt"
    if file:
        data = await file.read()
        raw_source = data.decode("utf-8", errors="replace")
        filename = f"dump_{file.filename}.txt"
    elif url:
        raw_source = await resolve_input(url)
    elif code:
        raw_source = await resolve_input(code)
    else:
        await interaction.followup.send("❌ Please provide a file, code, or a URL to dump.")
        return
        
    if not raw_source.strip():
        await interaction.followup.send("❌ Input is empty.")
        return

    dump_text = dump_bytecode_and_constants(raw_source, target_backend=backend)
    
    succ_embed = make_primez_embed("PrimeZ R.E.L — Bytecode & Constant Dump", color=PRIMEZ_COLOR_INFO)
    succ_embed.add_field(name="Mode", value="📦 Memory & Bytecode Extraction", inline=True)
    succ_embed.add_field(name="Dump Size", value=f"`{len(dump_text):,} bytes`", inline=True)
    
    file_bytes = dump_text.encode("utf-8")
    discord_file = discord.File(io.BytesIO(file_bytes), filename=filename)
    
    if len(dump_text) <= 1200:
        succ_embed.description = f"```\n{dump_text}\n```"
        
    await interaction.followup.send(embed=succ_embed, file=discord_file)

@bot.tree.command(name="deobf", description="Deobfuscate a protected Lua or Luau script")
@app_commands.describe(
    file="Upload an obfuscated script file (.lua / .luau / .txt)",
    code="Paste script code directly",
    url="Provide a direct URL (GitHub raw, Pastebin, etc.)",
    backend="Select backend to run (default: auto)",
    ephemeral="Hide output from others (private session)"
)
@app_commands.choices(backend=[
    app_commands.Choice(name="Auto-Detect (Recommended)", value="auto"),
    app_commands.Choice(name="IronBrew 1", value="ib1"),
    app_commands.Choice(name="IronBrew 2 / AztupBrew", value="ib2"),
    app_commands.Choice(name="IronBrew 3", value="ib3"),
    app_commands.Choice(name="LuaObfuscator", value="luaobf"),
    app_commands.Choice(name="Luraph v14/v15", value="luraph"),
])
async def deobf_command(
    interaction: discord.Interaction,
    file: discord.Attachment | None = None,
    code: str | None = None,
    url: str | None = None,
    backend: str = "auto",
    ephemeral: bool = False
):
    await interaction.response.defer(ephemeral=ephemeral)
    
    raw_source = ""
    filename = "deobfuscated.lua"
    if file:
        data = await file.read()
        raw_source = data.decode("utf-8", errors="replace")
        filename = f"primez_{file.filename}"
    elif url:
        raw_source = await resolve_input(url)
    elif code:
        raw_source = await resolve_input(code)
    else:
        await interaction.followup.send("❌ Please provide a file, code, or a URL to deobfuscate.")
        return
        
    if not raw_source.strip():
        await interaction.followup.send("❌ Input script is empty.")
        return
        
    res = await deobfuscate(raw_source, target_backend=backend)
    
    if not res.success:
        err_embed = make_primez_embed("Deobfuscation Failed", color=PRIMEZ_COLOR_ERROR)
        err_embed.description = f"**Engine**: `{res.backend_used}`\n**Error Details**:\n```\n{res.error[:1500]}\n```"
        await interaction.followup.send(embed=err_embed)
        return
        
    succ_embed = make_primez_embed("Deobfuscation Completed Successfully", color=PRIMEZ_COLOR_SUCCESS)
    succ_embed.add_field(name="Detected Type", value=res.detection.name, inline=True)
    succ_embed.add_field(name="Engine Executed", value=f"`{res.backend_used}`", inline=True)
    succ_embed.add_field(name="Duration", value=f"`{res.duration_sec:.2f}s`", inline=True)
    succ_embed.add_field(name="Decompiled Size", value=f"`{len(res.source):,} bytes`", inline=True)
    
    # Attach as file
    file_bytes = res.source.encode("utf-8")
    discord_file = discord.File(io.BytesIO(file_bytes), filename=filename)
    
    # If small enough, provide preview snippet
    if len(res.source) <= 1200:
        succ_embed.description = f"```lua\n{res.source}\n```"
        
    await interaction.followup.send(embed=succ_embed, file=discord_file)

def run():
    token = DISCORD_TOKEN or os.getenv("DISCORD_TOKEN")
    if not token:
        print("[!] No DISCORD_TOKEN set. Specify it in config.py or .env to start the bot.")
        print("[*] Standalone CLI is ready: python primez_cli.py --help")
        return
    bot.run(token)

if __name__ == "__main__":
    run()
