import sys
from pathlib import Path

# Ensure local imports inside luaobf work cleanly
_LUAOBF_DIR = Path(__file__).resolve().parent
if str(_LUAOBF_DIR) not in sys.path:
    sys.path.insert(0, str(_LUAOBF_DIR))

from .deobfuscate import reconstruct

def run_luaobf(source: str, raw: bool = False, verbose: bool = False) -> str:
    """Symbolically lifts, deflattens, folds constants, and emits clean Lua from LuaObfuscator."""
    logs = []
    def _logger(msg):
        if verbose:
            print(f"[LuaObf] {msg}")
        logs.append(msg)
        
    result = reconstruct(source, log=_logger, raw=raw)
    return result
