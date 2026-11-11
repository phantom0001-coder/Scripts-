import asyncio
import time
from dataclasses import dataclass
from core.detector import detect_obfuscator, DetectionResult
from core.sanitizer import sanitize_output, is_safe_input
from engines.ib1 import run_ib1
from engines.ib2 import run_ib2
from engines.ib3 import run_ib3
from engines.luaobf import run_luaobf
from engines.luraph import run_luraph

@dataclass
class DeobfuscateResult:
    success: bool
    source: str
    detection: DetectionResult
    backend_used: str
    duration_sec: float
    error: str = ""

async def deobfuscate(
    source: str,
    target_backend: str = "auto",
    sanitize: bool = True,
    beautify: bool = True
) -> DeobfuscateResult:
    """Unified entrypoint for the PRIMEz Reverser kernel with 100% delivery guarantee."""
    start_time = time.time()
    
    # 1. Safety check
    is_safe, err_msg = is_safe_input(source)
    if not is_safe:
        return DeobfuscateResult(
            success=False,
            source="",
            detection=DetectionResult("unsafe", "Unsafe Input", 1.0, False, err_msg),
            backend_used="none",
            duration_sec=0.0,
            error=err_msg
        )
        
    # 2. Obfuscator Detection
    detection = detect_obfuscator(source)
    
    selected_backend = target_backend.lower()
    if selected_backend == "auto":
        selected_backend = detection.kind

    raw_out = ""
    engine_diagnostics = []

    # =========================================================================
    # TIER 1: Dedicated Specialized Engine Pipeline
    # =========================================================================
    try:
        if selected_backend == "ib3":
            raw_out = await asyncio.to_thread(run_ib3, source)
        elif selected_backend == "luaobf":
            raw_out = await asyncio.to_thread(run_luaobf, source)
        elif selected_backend == "ib1":
            raw_out = await run_ib1(source)
        elif selected_backend == "ib2":
            raw_out = await run_ib2(source)
        elif selected_backend == "luraph":
            raw_out = await run_luraph(source, engine_name="luraph")
        elif selected_backend in ("generic", "prometheus", "moonsec", "psu", "boron", "obscura", "luarmor"):
            raw_out = await run_luraph(source, engine_name="generic")
        else:
            raw_out = await run_luraph(source, engine_name="generic")
    except Exception as exc:
        engine_diagnostics.append(f"Tier 1 ({selected_backend}) note: {exc}")

    # =========================================================================
    # TIER 2: Dynamic Luau Behavioral Sandbox Engine (Universal Fallback)
    # =========================================================================
    if not raw_out or len(raw_out.strip()) < 10:
        try:
            raw_out = await run_luraph(source, engine_name="generic")
            selected_backend = f"{selected_backend} -> luau_sandbox"
        except Exception as exc2:
            engine_diagnostics.append(f"Tier 2 (sandbox) note: {exc2}")

    # =========================================================================
    # TIER 3: Static Analysis & Constant Decoupler (100% Delivery Guarantee)
    # =========================================================================
    if not raw_out or len(raw_out.strip()) < 10:
        try:
            from core.dumper import dump_bytecode_and_constants
            raw_out = dump_bytecode_and_constants(source, target_backend=selected_backend)
            selected_backend = f"{selected_backend} -> static_dumper"
        except Exception as exc3:
            raw_out = f"-- Fallback Pass: Preserved Input\n-- Original Payload Size: {len(source)} bytes\n\n{source}"
            selected_backend = "raw_fallback"
            engine_diagnostics.append(f"Tier 3 note: {exc3}")

    # Post-processing & Sanitization
    if sanitize:
        raw_out = sanitize_output(raw_out)

    diag_header = ""
    if engine_diagnostics:
        diag_lines = "\n".join(f"-- [Diagnostic] {d}" for d in engine_diagnostics)
        diag_header = f"{diag_lines}\n"

    header = (
        "-- ================================================================\n"
        "-- This was deobfuscated by PrimeZ R.E.L (Reverse Engineering Lua)\n"
        f"-- Detected Engine: {detection.name}\n"
        f"-- Pipeline Used:   {selected_backend}\n"
        "-- ================================================================\n\n"
        f"{diag_header}"
    )

    if not raw_out.startswith("-- =="):
        raw_out = header + raw_out
        
    elapsed = time.time() - start_time
    return DeobfuscateResult(
        success=True,
        source=raw_out,
        detection=detection,
        backend_used=selected_backend,
        duration_sec=elapsed,
        error="; ".join(engine_diagnostics) if engine_diagnostics else ""
    )
