import asyncio
import os
import sys
import tempfile
from pathlib import Path
from config import LUAU_BIN, DEOBF_TIMEOUT

_IB1_DIR = Path(__file__).resolve().parent

async def run_ib1(source: str) -> str:
    """Devirtualizes IronBrew 1 scripts into canonical IR and reconstructed Lua."""
    runner_script = _IB1_DIR / "runner.py"
    
    with tempfile.TemporaryDirectory(prefix="primez_ib1_") as td:
        temp = Path(td)
        inp = temp / "input.lua"
        out_dir = temp / "output"
        out_file = out_dir / "readable_deobfuscated.lua"
        
        inp.write_text(source, encoding="utf-8", errors="replace")
        
        env = os.environ.copy()
        # Add bin directory to PATH so luau.exe is automatically resolved
        bin_dir = str(LUAU_BIN.parent)
        env["PATH"] = bin_dir + os.pathsep + env.get("PATH", "")
        
        cmd = [
            sys.executable,
            str(runner_script),
            str(inp),
            "--outdir",
            str(out_dir),
            "--luau",
            str(LUAU_BIN),
            "--timeout",
            str(min(DEOBF_TIMEOUT, 90))
        ]
        
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=str(_IB1_DIR),
            env=env
        )
        
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=DEOBF_TIMEOUT)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.communicate()
            raise RuntimeError("IronBrew 1 devirtualization timed out.")
            
        so = stdout.decode("utf-8", errors="replace")
        se = stderr.decode("utf-8", errors="replace")
        
        if out_file.exists():
            return out_file.read_text(encoding="utf-8", errors="replace")
        elif proc.returncode != 0:
            raise RuntimeError(f"IronBrew 1 engine failed:\n{se.strip() or so.strip()}")
        else:
            raise RuntimeError("IronBrew 1 completed without output file.")
