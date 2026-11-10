#!/usr/bin/env python3
"""
PrimeZ R.E.L — Command Line Interface
Reverse Engineering Layer (Deobfuscator & Memory/Bytecode Dumper) for Lua and Luau.
"""

import argparse
import asyncio
import json
import sys
from pathlib import Path

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

from core.engine import deobfuscate
from core.detector import detect_obfuscator
from core.dumper import dump_bytecode_and_constants

BANNER = r"""
  ____       _                 _____     ____      _____   _     
 |  _ \ _ __(_)_ __ ___   ___ |__  /    |  _ \    | ____| | |    
 | |_) | '__| | '_ ` _ \ / _ \  / /     | |_) |   |  _|   | |    
 |  __/|  _ < | || |  | | |___    |  _ <  __/\ V /  __/ |  \__ \  __/ |   
 |_|   |_| \_\___|_|  |_|_____|___|_| \_\___| \_/ \___|_|  |___/\___|_|   
                                   |_____|                       
       Reverse Engineering Layer (R.E.L) — Deobfuscator & Dumper v1.0
"""

def parse_args():
    parser = argparse.ArgumentParser(description="PrimeZ R.E.L — Deobfuscator & Bytecode Dumper")
    parser.add_argument("input", help="Path to obfuscated input file or raw string")
    parser.add_argument("-o", "--output", help="Path to write output")
    parser.add_argument(
        "--backend",
        choices=["auto", "ib1", "ib2", "ib3", "luaobf", "luraph", "generic"],
        default="auto",
        help="Select deobfuscation backend (default: auto)"
    )
    parser.add_argument("--detect", action="store_true", help="Only detect the obfuscator and exit")
    parser.add_argument("--dump", action="store_true", help="Dump constants pool, string table, and disassembled bytecode")
    parser.add_argument("--no-sanitize", action="store_true", help="Disable webhook and token sanitization")
    parser.add_argument("--json", action="store_true", help="Output machine-readable JSON result")
    return parser.parse_args()

async def main():
    args = parse_args()
    if not args.json:
        print(BANNER)
        
    input_path = Path(args.input)
    if input_path.exists():
        source = input_path.read_text(encoding="utf-8", errors="replace")
    else:
        source = args.input
        
    if args.detect:
        det = detect_obfuscator(source)
        if args.json:
            print(json.dumps({
                "kind": det.kind,
                "name": det.name,
                "confidence": round(det.confidence * 100, 1),
                "supported": det.supported,
                "reason": det.reason
            }))
            return
        print(f"[*] Obfuscator:  {det.name} ({det.kind})")
        print(f"[*] Confidence:  {det.confidence * 100:.1f}%")
        print(f"[*] Supported:   {'Yes' if det.supported else 'No'}")
        print(f"[*] Reason:      {det.reason}")
        return

    if args.dump:
        if not args.json:
            print(f"[*] Extracting constants and dumping bytecode ({len(source)} bytes)...")
        dump_res = dump_bytecode_and_constants(source, args.backend)
        if args.json:
            print(json.dumps({
                "success": True,
                "mode": "dump",
                "source": dump_res
            }))
            return
        if args.output:
            Path(args.output).write_text(dump_res, encoding="utf-8")
            print(f"[+] Dump saved to: {args.output}")
        else:
            print(dump_res)
        return
        
    if not args.json:
        print(f"[*] Analyzing & deobfuscating input ({len(source)} bytes)...")
        
    res = await deobfuscate(
        source=source,
        target_backend=args.backend,
        sanitize=not args.no_sanitize
    )
    
    if args.json:
        print(json.dumps({
            "success": res.success,
            "mode": "deobfuscate",
            "source": res.source,
            "detection": {
                "kind": res.detection.kind,
                "name": res.detection.name,
                "confidence": round(res.detection.confidence * 100, 1),
                "supported": res.detection.supported,
                "reason": res.detection.reason
            },
            "backend_used": res.backend_used,
            "duration_sec": round(res.duration_sec, 3),
            "error": res.error
        }))
        return
        
    if not res.success:
        print(f"\n[-] Deobfuscation failed in {res.duration_sec:.2f}s:")
        print(f"    {res.error}")
        sys.exit(1)
        
    print(f"[+] Successfully deobfuscated via [{res.backend_used}] in {res.duration_sec:.2f}s!")
    
    if args.output:
        out_path = Path(args.output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(res.source, encoding="utf-8")
        print(f"[+] Saved result to: {out_path.resolve()}")
    else:
        print("\n--- BEGIN DEOBFUSCATED CODE ---")
        print(res.source[:2000])
        if len(res.source) > 2000:
            print(f"\n... [Output truncated. {len(res.source) - 2000} bytes remaining. Use -o to save]")
        print("--- END DEOBFUSCATED CODE ---")

if __name__ == "__main__":
    asyncio.run(main())
