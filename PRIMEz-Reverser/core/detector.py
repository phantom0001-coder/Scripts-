from dataclasses import dataclass
from pathlib import Path
import json
import re
from config import DATA_DIR

@dataclass
class DetectionResult:
    kind: str
    name: str
    confidence: float
    supported: bool = True
    reason: str = ""

FINGERPRINTS_FILE = DATA_DIR / "fingerprints.json"

def extract_features(src: str) -> set[str]:
    s = src.lower()
    f = set()
    
    literals = [
        "--ironbrew3", "ironbrew3", "ironbrew", "aztupbrew",
        "luaobfuscator", "luraph", "lph_", "moonsec", "moonveil",
        "prometheus", "getfenv", "setfenv", "loadstring",
        "string.char", "string.byte", "bit32", "bit.bxor",
        "coroutine.wrap", "coroutine.create", "table.concat",
        "math.floor", "return(function", "while true do",
        "vykus", "primez protector"
    ]
    for x in literals:
        if x in s:
            f.add(f"lit:{x}")
            
    if re.search(r'["\'][0-9a-fA-F]{512,}["\']', src):
        f.add("shape:large_hex_string")
    if len(re.findall(r"\bfunction\b", src)) > 50:
        f.add("shape:many_functions")
    if len(re.findall(r"\bwhile\b|\brepeat\b", src)) > 20:
        f.add("shape:many_loops")
    if len(re.findall(r"\bbit32\b|\bbit\.", src)) > 5:
        f.add("shape:bit_heavy")
    if len(re.findall(r"\[[^\]]+\]\s*=", src)) > 50:
        f.add("shape:table_dispatch")
    if "return(function" in s and "string.byte" in s and "math.floor" in s:
        f.add("shape:lua_vm_wrapper")
        
    return f

def jaccard_similarity(a: set[str], b: set[str]) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)

def map_fingerprint_folder(name: str) -> tuple[str, str, bool]:
    l = name.lower()
    if "ironbrew3" in l or l == "ib3":
        return "ib3", "IronBrew 3", True
    if "ironbrew2" in l or "aztup" in l or l == "ib2":
        return "ib2", "IronBrew 2 / AztupBrew", True
    if "ironbrew1" in l or l == "ib1":
        return "ib1", "IronBrew 1", True
    if "luaobfuscator" in l:
        return "luaobf", "LuaObfuscator", True
    if "luraph" in l:
        return "luraph", "Luraph", True
    if "moonsec" in l:
        return "unsupported", "MoonSec", False
    if "prometheus" in l:
        return "unsupported", "Prometheus", False
    return "unknown", name, False

def detect_obfuscator(src: str) -> DetectionResult:
    s = src.lower()
    feats = extract_features(src)
    
    # Direct high-priority signatures
    if "--ironbrew3" in s or "ironbrew3:" in s:
        return DetectionResult("ib3", "IronBrew 3", 0.99, True, "Direct signature")
    if "aztupbrew" in s:
        return DetectionResult("ib2", "AztupBrew", 0.99, True, "Direct signature")
    if "luaobfuscator" in s:
        return DetectionResult("luaobf", "LuaObfuscator", 0.99, True, "Direct signature")
    if "luraph" in s:
        version = "v15"
        if "14.9" in s: version = "v14.9"
        elif "14.8" in s: version = "v14.8"
        elif "14.7" in s: version = "v14.7"
        return DetectionResult("luraph", f"Luraph {version}", 0.98, True, "Luraph header")
    if "lph_" in s:
        return DetectionResult("luraph", "Luraph Candidate", 0.85, True, "Luraph prefix")
    if "vykus" in s or "primez protector" in s:
        return DetectionResult("unsupported", "PRIMEz / Vykus Protected", 0.99, False, "PRIMEz Core signature")

    # Match database fingerprints
    if FINGERPRINTS_FILE.exists():
        try:
            db = json.loads(FINGERPRINTS_FILE.read_text(encoding="utf-8"))
            best_score = 0.0
            best_folder = None
            for folder, item in db.items():
                ref_features = set(item.get("features", []))
                sc = jaccard_similarity(feats, ref_features)
                if sc > best_score:
                    best_score = sc
                    best_folder = folder
            
            if best_folder and best_score >= 0.20:
                k, n, sup = map_fingerprint_folder(best_folder)
                if k != "unknown":
                    return DetectionResult(k, n, min(0.95, max(0.50, best_score)), sup, f"Matched fingerprint: {best_folder}")
        except Exception:
            pass

    # Structural fallbacks
    if "ironbrew" in s:
        return DetectionResult("ib2", "IronBrew 2 / Legacy VM", 0.75, True, "Weak keyword match")
    if {"shape:large_hex_string", "shape:lua_vm_wrapper"} <= feats:
        return DetectionResult("ib3", "IronBrew 3 Candidate", 0.65, True, "Structural payload analysis")
    if "shape:lua_vm_wrapper" in feats:
        return DetectionResult("ib1", "IronBrew 1 Candidate", 0.55, True, "Wrapper pattern analysis")

    return DetectionResult("generic", "Generic / Unrecognized Obfuscator", 0.30, True, "Behavioral heuristic")
