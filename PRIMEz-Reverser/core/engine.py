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
    """Unified entrypoint for the PRIMEz Reverser kernel."""
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
        
    if not detection.supported and target_backend == "auto":
        return DeobfuscateResult(
            success=False,
            source="",
            detection=detection,
            backend_used=selected_backend,
            duration_sec=time.time() - start_time,
            error=f"Detected {detection.name}, but automatic deobfuscation is currently not supported for this obfuscator."
        )

    # 3. Route to designated engine
    try:
        if selected_backend == "ib3":
            raw_out = await asyncio.to_thread(run_ib3, source)
        elif selected_backend == "luaobf":
            raw_out = await asyncio.to_thread(run_luaobf, source)
        elif selected_backend == "ib1":
            raw_out = await run_ib1(source)
        elif selected_backend == "ib2":
            raw_out = await run_ib2(source)
        elif selected_backend in ("luraph", "generic"):
            raw_out = await run_luraph(source, engine_name=selected_backend)
        else:
            # Fallback to Luraph behavioral sandbox tracer
            raw_out = await run_luraph(source, engine_name="generic")
            selected_backend = "sandbox"
            
        # 4. Post-processing & Sanitization
        if sanitize:
            raw_out = sanitize_output(raw_out)
            
        elapsed = time.time() - start_time
        return DeobfuscateResult(
            success=True,
            source=raw_out,
            detection=detection,
            backend_used=selected_backend,
            duration_sec=elapsed
        )
        
    except Exception as exc:
        elapsed = time.time() - start_time
        return DeobfuscateResult(
            success=False,
            source="",
            detection=detection,
            backend_used=selected_backend,
            duration_sec=elapsed,
            error=str(exc)
        )
