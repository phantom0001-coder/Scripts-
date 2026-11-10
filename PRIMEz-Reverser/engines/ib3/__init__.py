from .deserializer import parse_ib3, find_root

def run_ib3(source: str) -> str:
    """Disassembles and formats IronBrew 3 bytecode and constants into readable Lua structure."""
    parsed = parse_ib3(source)
    root = find_root(parsed.prototypes)
    
    out = [
        "-- [PRIMEz Reverser] IronBrew 3 Decoded VM",
        f"-- Profile: {parsed.profile}",
        f"-- Recovered Constants: {len(parsed.constants)}",
        f"-- Recovered Prototypes: {len(parsed.prototypes)}",
        "",
        "-- Constants Table:",
        "local CONSTANTS = {"
    ]
    for idx, c in enumerate(parsed.constants):
        out.append(f"    [{idx}] = {repr(c)},")
    out.append("}")
    out.append("")
    
    for idx, proto in enumerate(parsed.prototypes):
        out.append(f"local function proto_{idx}(...)")
        out.append(f"    -- Params: {proto.params}")
        for pc, ins in enumerate(proto.instructions, 1):
            out.append(f"    -- [{pc:03d}] opcode={ins.opcode} a={ins.a} b={ins.b} c={ins.c} jump={ins.jump}")
        out.append("end")
        out.append("")
        
    out.append(f"return proto_{root}(...)")
    return "\n".join(out)
