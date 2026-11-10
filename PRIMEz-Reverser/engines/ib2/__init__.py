import asyncio
import tempfile
import uuid
from pathlib import Path
from config import IB2_CLI, DEOBF_TIMEOUT

_IB2_DIR = Path(__file__).resolve().parent
_BIN_DIR = _IB2_DIR / "bin"

async def run_ib2(source: str) -> str:
    """Runs the IronBrew 2 & AztupBrew native CLI disassembler."""
    if not IB2_CLI.exists():
        raise FileNotFoundError(f"Missing IronBrew 2 CLI binary: {IB2_CLI}")
        
    tasks_dir = _BIN_DIR / "tasks"
    tasks_dir.mkdir(parents=True, exist_ok=True)
    
    with tempfile.TemporaryDirectory(prefix="primez_ib2_") as td:
        temp = Path(td)
        input_path = temp / f"primez_{uuid.uuid4().hex[:8]}.lua"
        input_path.write_text(source, encoding="utf-8", errors="replace")
        
        old_outputs = {}
        for output in tasks_dir.rglob("deobfuscated.lua"):
            try:
                old_outputs[output.resolve()] = output.stat().st_mtime_ns
            except OSError:
                pass
                
        proc = await asyncio.create_subprocess_exec(
            str(IB2_CLI),
            str(input_path),
            cwd=str(_BIN_DIR),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=DEOBF_TIMEOUT)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.communicate()
            raise RuntimeError("IronBrew 2 backend timed out.")
            
        so = stdout.decode("utf-8", errors="replace")
        se = stderr.decode("utf-8", errors="replace")
        
        candidates = []
        for output in tasks_dir.rglob("deobfuscated.lua"):
            try:
                new_time = output.stat().st_mtime_ns
                old_time = old_outputs.get(output.resolve())
                if old_time is None or new_time != old_time:
                    candidates.append(output)
            except OSError:
                pass
                
        candidates.sort(key=lambda p: p.stat().st_mtime_ns, reverse=True)
        
        if candidates:
            res = candidates[0].read_text(encoding="utf-8", errors="replace")
            # Clean up task output file
            try:
                candidates[0].unlink(missing_ok=True)
            except Exception:
                pass
            return res
            
        if proc.returncode != 0:
            raise RuntimeError(f"IronBrew 2 engine error:\n{se.strip() or so.strip()}")
            
        raise RuntimeError("IronBrew 2 finished but generated no deobfuscated output.")
