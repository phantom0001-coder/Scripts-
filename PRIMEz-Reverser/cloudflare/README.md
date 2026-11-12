# 🌐 PRIMEz Reverser — Cloudflare Worker + Full Engine Backend

This Worker is the edge gateway for **PRIMEz Reverser**:
- Serves Discord Slash Commands (`/status`, `/detect`, `/deobf`) via Discord Interactions Webhooks.
- Instant edge fingerprinting in < 15ms.

## ⚠️ Important — two operating modes

**Edge-only mode (default):** `/deobf` runs a lightweight regex cleanup
(`string.char` decode, escape unrolling, concat folding). This is cosmetic
only and **cannot devirtualize VM obfuscators** (IronBrew, Luraph, PSU, …).
Outputs and embeds are honestly labeled as "Edge Cleanup Only".

**Full engine mode:** set `REVERSER_BACKEND_URL` (and the
`REVERSER_API_KEY` secret) to point at the Python engine host running
`server.py`. `/deobf` then submits the job to the REAL engine pipelines
(IronBrew 1/2/3, LuaObfuscator SSA lifter, Luraph sandbox, 3-tier cascade).
The worker ACKs Discord with a DEFERRED response, the backend runs the
engines (up to the DEOBF_TIMEOUT), then PATCHes the interaction followup
with the deobfuscated file — all within Discord's 15-minute window.

---

## 🚀 How to Deploy

### 1. Authenticate with Cloudflare
```bash
npx wrangler login
```

### 2. Configure Discord secrets
Inside the `cloudflare/` directory:
```bash
npx wrangler secret put DISCORD_PUBLIC_KEY
npx wrangler secret put DISCORD_APPLICATION_ID
npx wrangler secret put DISCORD_BOT_TOKEN
```

### 3. Run the full engine backend (server.py)

Pick ONE hosting option for the Python engines:

**Option A — your own PC (all engines, incl. Windows-only IB2 CLI):**
```bash
# in the PRIMEz-Reverser folder
pip install -r requirements.txt
set REVERSER_API_KEY=<your-secret>     # Windows (use export on Linux/Mac)
python server.py                      # listens on :8787
cloudflared tunnel --url http://localhost:8787   # gives you a https://...trycloudflare.com URL
```

**Option B — Render web service (Linux):**
- New Web Service → root dir `PRIMEz-Reverser/`
- Build command: `pip install -r requirements.txt`
- Start command: `python server.py`
- Env vars: `REVERSER_API_KEY=<your-secret>`
- Linux notes: IB3 + LuaObfuscator + static dumper are pure Python (always
  work); the Luraph sandbox uses the bundled `engines/luraph/bin/luau`
  binary; IB2 (C# CLI.exe) is Windows-only and is skipped on Linux.

### 4. Connect the worker to the backend
```bash
# in cloudflare/
npx wrangler secret put REVERSER_API_KEY        # same secret as server.py
# edit wrangler.toml [vars]: REVERSER_BACKEND_URL = "https://<your-backend-url>"
npx wrangler deploy
```

### 5. Discord wiring
Set your Discord Application's **Interactions Endpoint URL** to:
```
https://primez-reverser.<your-subdomain>.workers.dev/interactions
```

### 6. Verify
- `/status` must show: `Mode: full_engine_backend` and `Backend Health: 🟢 Connected`
- `GET https://<worker>/api/reverser/status` must show `"mode": "full_engine_backend"`
- `/deobf` with a known obfuscated script: the embed must show a real
  `Pipeline:` (e.g. `ib3`, `luaobf`, `luraph`) — not `edge_regex_only`.
- If the backend is down, `/deobf` returns a clearly-labeled warning embed
  ("Engine Backend Unreachable") with an `edgecleanup_` file — never a fake
  success.

---

## 🔌 HTTP API (worker)

| Endpoint | Description |
|---|---|
| `GET /api/reverser/status` | Honest mode + backend health report |
| `POST /api/reverser/detect` | `{source}` → fingerprint (backend DB when available) |
| `POST /api/reverser/deobf` | `{source, backend?}` → real engine deobf when backend configured; `mode` field says which |
| `POST /api/reverser/dump` | `{source}` → edge constant/string pool dump |
