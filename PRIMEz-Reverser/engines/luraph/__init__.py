import asyncio
import sys
import tempfile
from pathlib import Path
from config import LURAPH_CLI, DEOBF_TIMEOUT

_LURAPH_DIR = Path(__file__).resolve().parent

async def run_luraph(source: str, engine_name: str | None = None) -> str:
    """Executes the Luraph / generic Luau behavioral sandbox tracer."""
    if not LURAPH_CLI.exists():
        raise FileNotFoundError(f"Missing Luraph engine: {LURAPH_CLI}")
        
    with tempfile.TemporaryDirectory(prefix="primez_luraph_") as td:
        temp = Path(td)
        inp = temp / "input.lua"
        out = temp / "deobfuscated.lua"
        inp.write_text(source, encoding="utf-8", errors="replace")
        
        cmd = [
            sys.executable,
            str(LURAPH_CLI),
            str(inp),
            "-o",
            str(out),
            "--timeout",
            str(min(DEOBF_TIMEOUT, 90))
        ]
        
        if engine_name and engine_name not in ("auto", "luraph"):
            cmd.extend(["--obfuscator", engine_name])
            
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=str(_LURAPH_DIR)
        )
        
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=DEOBF_TIMEOUT)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.communicate()
            raise RuntimeError("Luraph sandbox execution timed out.")
            
        so = stdout.decode("utf-8", errors="replace")
        se = stderr.decode("utf-8", errors="replace")
        
        if out.exists():
            return out.read_text(encoding="utf-8", errors="replace")
            
        if proc.returncode != 0:
            raise RuntimeError(f"Luraph engine failed (code {proc.returncode}):\n{se.strip() or so.strip()}")
            
        raise RuntimeError("Luraph engine completed without producing output.")
