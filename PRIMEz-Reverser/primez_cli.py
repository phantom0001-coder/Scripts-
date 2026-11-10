#!/usr/bin/env python3
"""
PRIMEz Reverser — Command Line Interface
High-performance deobfuscation and analysis suite for Lua and Luau.
"""

import argparse
import asyncio
import sys
from pathlib import Path
from core.engine import deobfuscate
from core.detector import detect_obfuscator

BANNER = r"""
  ____  ____  ___ __  __ _____     ____                                    
 |  _ \|  _ \|_ _|  \/  | ____|   |  _ \ _____   _____ _ __ ___  ___ _ __ 
 | |_) | |_) || || |\/| |  _|     | |_) / _ \ \ / / _ \ '__/ __|/ _ \ '__|
 |  __/|  _ < | || |  | | |___    |  _ <  __/\ V /  __/ |  \__ \  __/ |   
 |_|   |_| \_\___|_|  |_|_____|___|_| \_\___| \_/ \___|_|  |___/\___|_|   
                             |_____|                                      
                   Reverse Engineering Engine v1.0
"""

def parse_args():
    parser = argparse.ArgumentParser(description="PRIMEz Reverser — Advanced Lua/Luau Deobfuscator")
    parser.add_argument("input", help="Path to obfuscated input file or raw string")
    parser.add_argument("-o", "--output", help="Path to write deobfuscated Lua output")
    parser.add_argument(
        "--backend",
        choices=["auto", "ib1", "ib2", "ib3", "luaobf", "luraph", "generic"],
        default="auto",
        help="Select deobfuscation backend (default: auto)"
    )
    parser.add_argument("--detect", action="store_true", help="Only detect the obfuscator and exit")
    parser.add_argument("--no-sanitize", action="store_true", help="Disable webhook and token sanitization")
    return parser.parse_args()

async def main():
    print(BANNER)
    args = parse_args()
    
    input_path = Path(args.input)
    if input_path.exists():
        source = input_path.read_text(encoding="utf-8", errors="replace")
    else:
        source = args.input
        
    if args.detect:
        det = detect_obfuscator(source)
        print(f"[*] Obfuscator:  {det.name} ({det.kind})")
        print(f"[*] Confidence:  {det.confidence * 100:.1f}%")
        print(f"[*] Supported:   {'Yes' if det.supported else 'No'}")
        print(f"[*] Reason:      {det.reason}")
        return
        
    print(f"[*] Analyzing input ({len(source)} bytes)...")
    res = await deobfuscate(
        source=source,
        target_backend=args.backend,
        sanitize=not args.no_sanitize
    )
    
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
