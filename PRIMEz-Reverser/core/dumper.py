import json
import re
from core.detector import detect_obfuscator
from engines.ib3.deserializer import parse_ib3, find_root

def dump_strings_and_urls(src: str) -> list[str]:
    """Extract all printable string literals and URLs found in the code."""
    strings = []
    # Match double or single quoted strings
    for m in re.finditer(r'["\']([^"\'\\]*(?:\\.[^"\'\\]*)*)["\']', src):
        val = m.group(1)
        if len(val) >= 3 and not re.match(r'^[0-9a-fA-F]{64,}$', val):
            strings.append(val)
    return sorted(list(set(strings)))

def dump_bytecode_and_constants(source: str, target_backend: str = "auto") -> str:
    """Extracts raw constants, decoded bytecode, and opcode handlers."""
    det = detect_obfuscator(source)
    backend = target_backend.lower()
    if backend == "auto":
        backend = det.kind

    output = [
        "-- ================================================================",
        "-- This was dumped by PrimeZ R.E.L (Reverse Engineering Lua)",
        f"-- Detected Obfuscator: {det.name} ({det.kind})",
        f"-- Confidence:          {det.confidence * 100:.1f}%",
        "-- ================================================================\n"
    ]

    # 1. IB3 specialized dumper
    if backend == "ib3" or "--ironbrew3" in source.lower():
        try:
            parsed = parse_ib3(source)
            root = find_root(parsed.prototypes)
            output.append(f"[+] IronBrew 3 Profile: {parsed.profile}")
            output.append(f"[+] Total Prototypes:  {len(parsed.prototypes)}")
            output.append(f"[+] Total Constants:   {len(parsed.constants)}\n")
            
            output.append("─── [1/3] EXTRACTED CONSTANTS TABLE ───")
            for idx, c in enumerate(parsed.constants):
                output.append(f"  [{idx:03d}] ({type(c).__name__}) = {repr(c)}")
            output.append("")

            output.append("─── [2/3] DISASSEMBLED PROTOTYPES & OPCODES ───")
            for idx, proto in enumerate(parsed.prototypes):
                is_root = " (ROOT ENTRYPOINT)" if idx == root else ""
                output.append(f"Prototype #{idx}{is_root} — Parameters: {proto.params}, Instructions: {len(proto.instructions)}")
                for pc, ins in enumerate(proto.instructions, 1):
                    extra_str = f" extra={ins.extra}" if ins.extra else ""
                    output.append(f"    [{pc:03d}] opcode={ins.opcode:<3} a={ins.a:<3} b={ins.b:<3} c={ins.c:<3} jump={ins.jump}{extra_str}")
                output.append("")
                
            output.append("─── [3/3] RAW RECOVERED STRINGS ───")
            recovered_strings = [str(c) for c in parsed.constants if isinstance(c, str) and len(str(c)) > 2]
            for s in sorted(list(set(recovered_strings))):
                output.append(f"  • {s}")
            return "\n".join(output)
        except Exception as e:
            output.append(f"[!] IB3 specific constant extraction error: {e}")

    # 2. General string and literal extraction fallback
    output.append("─── EXTRACTED STRING POOL & API LITERALS ───")
    extracted = dump_strings_and_urls(source)
    if extracted:
        for s in extracted[:500]:
            output.append(f"  • {s}")
        if len(extracted) > 500:
            output.append(f"\n  ... [{len(extracted) - 500} more strings truncated]")
    else:
        output.append("  (No printable plaintext strings found. Bytecode may be fully masked)")

    # 3. Discovered Hexadecimal Blocks
    hex_blocks = re.findall(r'["\']([0-9a-fA-F]{64,})["\']', source)
    if hex_blocks:
        output.append("\n─── SERIALIZED BYTECODE PAYLOADS (HEX) ───")
        for idx, h in enumerate(hex_blocks):
            output.append(f"  Block #{idx+1}: {len(h)} chars ({len(h)//2} bytes)")
            output.append(f"    Preview: {h[:80]}...\n")

    return "\n".join(output)
