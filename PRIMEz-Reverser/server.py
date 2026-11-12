"""
PrimeZ R.E.L - Full Engine Backend (HTTP API)

Wraps the real Python deobfuscation kernel (core.engine) so the Cloudflare
Worker edge gateway can run actual engine pipelines remotely.

Run:
    REVERSER_API_KEY=<secret> python server.py

Endpoints (auth: X-API-Key header, required when REVERSER_API_KEY is set):
    GET  /api/reverser/status      -> health + engine availability
    POST /api/reverser/detect      -> {source}                -> fingerprint
    POST /api/reverser/deobf       -> {source, backend?}       -> sync deobfuscation
    POST /api/reverser/deobf_job   -> {source, backend?, interaction_token,
                                      application_id, filename?}
          Async Discord job: runs the engines, then PATCHes the deferred
          interaction followup with the result file (within 15 min).
    POST /api/reverser/dump        -> {source, backend?}       -> constant/bytecode dump
"""

import asyncio
import json
import os
import sys
import time
from dataclasses import asdict
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from aiohttp import ClientSession, FormData, web

from config import DEOBF_TIMEOUT, LUAU_BIN, IB2_CLI, LURAPH_CLI, MAX_INPUT_SIZE_MB
from core.engine import deobfuscate
from core.detector import detect_obfuscator
from core.dumper import dump_bytecode_and_constants

API_KEY = os.getenv("REVERSER_API_KEY", "").strip()
PORT = int(os.getenv("PORT", "8787"))
MAX_BODY_BYTES = MAX_INPUT_SIZE_MB * 1024 * 1024
DISCORD_API = "https://discord.com/api/v10"

# Brand colors (match the bot)
COLOR_SUCCESS = 0x00FFA3
COLOR_WARNING = 0xFFA500
COLOR_ERROR = 0xFF0055


def _authorized(request) -> bool:
    if not API_KEY:
        return True
    return request.headers.get("X-API-Key", "") == API_KEY


def _unauthorized():
    return web.json_response({"success": False, "error": "API key required."}, status=401)


def _bad_request(msg: str):
    return web.json_response({"success": False, "error": msg}, status=400)


def engine_availability() -> dict:
    """Which engine pipelines can actually run on this host."""
    return {
        "ib3": True,                                   # pure Python
        "luaobf": True,                                # pure Python
        "ib1": Path(LUAU_BIN).exists(),                # needs the Luau VM
        "ib2": Path(IB2_CLI).exists() and sys.platform == "win32",  # Windows CLI
        "luraph": Path(LURAPH_CLI).exists(),
        "static_dumper": True,
    }


async def handle_status(request):
    if not _authorized(request):
        return _unauthorized()
    return web.json_response({
        "success": True,
        "service": "primez-rel-backend",
        "version": "1.0",
        "engines": engine_availability(),
        "deobf_timeout_sec": DEOBF_TIMEOUT,
        "auth_required": bool(API_KEY),
        "timestamp": time.time(),
    })


async def handle_detect(request):
    if not _authorized(request):
        return _unauthorized()
    try:
        body = await request.json()
        source = (body or {}).get("source", "")
        if not source or not source.strip():
            return _bad_request("No source provided.")
        det = detect_obfuscator(source)
        return web.json_response({"success": True, "detection": asdict(det)})
    except Exception as e:
        return _bad_request(str(e))


async def handle_deobf(request):
    """Synchronous deobfuscation (HTTP API consumers)."""
    if not _authorized(request):
        return _unauthorized()
    try:
        body = await request.json()
        source = (body or {}).get("source", "")
        backend = (body or {}).get("backend") or "auto"
        if not source or not source.strip():
            return _bad_request("No source provided.")
        if len(source.encode("utf-8", "replace")) > MAX_BODY_BYTES:
            return web.json_response(
                {"success": False, "error": f"Source exceeds {MAX_INPUT_SIZE_MB} MB limit."},
                status=413,
            )
        res = await deobfuscate(source, target_backend=backend)
        return web.json_response({
            "success": bool(res.success),
            "source": res.source,
            "detection": asdict(res.detection),
            "backend_used": res.backend_used,
            "duration_sec": res.duration_sec,
            "error": res.error,
        })
    except Exception as e:
        return web.json_response({"success": False, "error": str(e)}, status=500)


async def handle_deobf_job(request):
    """Async Discord job: queue the work, PATCH the deferred interaction later."""
    if not _authorized(request):
        return _unauthorized()
    try:
        body = await request.json()
        source = (body or {}).get("source", "")
        backend = (body or {}).get("backend") or "auto"
        interaction_token = (body or {}).get("interaction_token", "")
        application_id = (body or {}).get("application_id", "")
        filename = (body or {}).get("filename") or "script.lua"

        if not source or not source.strip():
            return _bad_request("No source provided.")
        if not interaction_token or not application_id:
            return _bad_request("interaction_token and application_id are required.")
        if len(source.encode("utf-8", "replace")) > MAX_BODY_BYTES:
            return web.json_response(
                {"success": False, "error": f"Source exceeds {MAX_INPUT_SIZE_MB} MB limit."},
                status=413,
            )

        asyncio.create_task(_run_job_and_report(
            source, backend, application_id, interaction_token, filename
        ))
        return web.json_response({
            "success": True,
            "queued": True,
            "timeout_sec": DEOBF_TIMEOUT,
        })
    except Exception as e:
        return _bad_request(str(e))


async def _run_job_and_report(source, backend, application_id, interaction_token, filename):
    """Run the real engines, then PATCH the Discord deferred followup with the file."""
    url = f"{DISCORD_API}/webhooks/{application_id}/{interaction_token}/messages/@original"
    try:
        res = await deobfuscate(source, target_backend=backend)
    except Exception as e:
        embed = {
            "title": "PrimeZ R.E.L - Deobfuscation Failed",
            "description": f"Engine kernel raised an exception:\n```\n{str(e)[:1500]}\n```",
            "color": COLOR_ERROR,
        }
        await _patch_discord(url, embed, None, None)
        return

    raw_fallback = "raw_fallback" in (res.backend_used or "")
    if raw_fallback:
        embed = {
            "title": "PrimeZ R.E.L - Engines Failed (Preserved Input)",
            "description": (
                "All deobfuscation engines failed, so the attached file is your "
                "**original input preserved**. Check the `-- [Diagnostic]` header "
                "lines in the file for the failure reasons."
            ),
            "color": COLOR_WARNING,
            "fields": [
                {"name": "Detected Type", "value": str(res.detection.name), "inline": True},
                {"name": "Pipeline", "value": f"`{res.backend_used}`", "inline": True},
                {"name": "Duration", "value": f"`{res.duration_sec:.2f}s`", "inline": True},
                {"name": "Output Size", "value": f"`{len(res.source):,} bytes`", "inline": True},
            ],
            "footer": {"text": "PrimeZ R.E.L Full Engine Backend"},
        }
    else:
        embed = {
            "title": "PrimeZ R.E.L - Deobfuscation Complete",
            "description": (
                f"Deobfuscated on the **full engine backend** "
                f"(pipeline: `{res.backend_used}`). Result file attached below."
            ),
            "color": COLOR_SUCCESS,
            "fields": [
                {"name": "Detected Type", "value": str(res.detection.name), "inline": True},
                {"name": "Pipeline", "value": f"`{res.backend_used}`", "inline": True},
                {"name": "Duration", "value": f"`{res.duration_sec:.2f}s`", "inline": True},
                {"name": "Output Size", "value": f"`{len(res.source):,} bytes`", "inline": True},
            ],
            "footer": {"text": "PrimeZ R.E.L Full Engine Backend"},
        }

    safe_name = (filename or "script.lua").replace("\\", "_").replace("/", "_")
    out_filename = f"deobfuscated_{safe_name}"
    await _patch_discord(url, embed, res.source, out_filename)


async def _patch_discord(url, embed, file_text, out_filename):
    """PATCH the deferred interaction followup, with an optional file attachment."""
    payload = {"embeds": [embed]}
    form = FormData()
    if file_text is not None:
        payload["attachments"] = [{"id": 0, "filename": out_filename, "description": "PrimeZ R.E.L Result"}]
    form.add_field("payload_json", json.dumps(payload), content_type="application/json")
    if file_text is not None:
        form.add_field(
            "files[0]",
            file_text.encode("utf-8", "replace"),
            filename=out_filename,
            content_type="text/plain",
        )
    try:
        async with ClientSession() as sess:
            async with sess.patch(url, data=form) as resp:
                if resp.status not in (200, 204):
                    body = await resp.text()
                    print(f"[!] Discord followup failed: HTTP {resp.status}: {body[:500]}")
                else:
                    print("[+] Discord followup delivered.")
    except Exception as e:
        print(f"[!] Discord followup error: {e}")


async def handle_dump(request):
    if not _authorized(request):
        return _unauthorized()
    try:
        body = await request.json()
        source = (body or {}).get("source", "")
        backend = (body or {}).get("backend") or "auto"
        if not source or not source.strip():
            return _bad_request("No source provided.")
        dump_text = dump_bytecode_and_constants(source, target_backend=backend)
        det = detect_obfuscator(source)
        return web.json_response({
            "success": True,
            "source": dump_text,
            "detection": asdict(det),
        })
    except Exception as e:
        return web.json_response({"success": False, "error": str(e)}, status=500)


def make_app():
    app = web.Application(client_max_size=MAX_BODY_BYTES + 1024 * 1024)
    app.router.add_get("/api/reverser/status", handle_status)
    app.router.add_post("/api/reverser/detect", handle_detect)
    app.router.add_post("/api/reverser/deobf", handle_deobf)
    app.router.add_post("/api/reverser/deobf_job", handle_deobf_job)
    app.router.add_post("/api/reverser/dump", handle_dump)
    return app


if __name__ == "__main__":
    print(f"[+] PrimeZ R.E.L full engine backend listening on 0.0.0.0:{PORT}")
    print(f"[+] API key auth: {'ENABLED' if API_KEY else 'DISABLED (open!) - set REVERSER_API_KEY'}")
    print(f"[+] Engine availability: {engine_availability()}")
    web.run_app(make_app(), host="0.0.0.0", port=PORT)
