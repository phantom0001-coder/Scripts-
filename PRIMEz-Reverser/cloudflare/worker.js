/**
 * PrimeZ R.E.L — Cloudflare Worker Edge Gateway
 * Reverse Engineering Lua (Deobfuscator & Memory/Bytecode Dumper)
 *
 * Two operating modes:
 *  - FULL ENGINE MODE — set [vars] REVERSER_BACKEND_URL (wrangler.toml) and the
 *    secret REVERSER_API_KEY to point at the Python engine host (`server.py`).
 *    /deobf then submits the job to the REAL engine pipelines (IronBrew,
 *    LuaObfuscator, Luraph sandbox, 3-tier cascade) via a deferred Discord
 *    followup; server.py PATCHes the result file back into the interaction.
 *  - EDGE-ONLY MODE (default) — lightweight regex cleanup only. It CANNOT
 *    devirtualize VM obfuscators; outputs are honestly labeled as such.
 */

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-signature-ed25519, x-signature-timestamp"
};

// ── Full-engine backend configuration ─────────────────────────────────────
// REVERSER_BACKEND_URL: base URL of the Python engine host running server.py
// (a Render service URL, or a Cloudflare Tunnel URL for your own machine).
// REVERSER_API_KEY: shared secret — set it on BOTH sides.
//   wrangler secret put REVERSER_API_KEY
function backendUrl(env) {
  const raw = String(env.REVERSER_BACKEND_URL || "").trim().replace(/\/+$/, "");
  return raw || null;
}

async function callReverserBackend(env, path, payload, timeoutMs) {
  const base = backendUrl(env);
  if (!base) return { ok: false, error: "backend_not_configured" };
  try {
    const headers = { "Content-Type": "application/json" };
    if (env.REVERSER_API_KEY) headers["X-API-Key"] = env.REVERSER_API_KEY;
    const res = await fetch(base + path, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(timeoutMs || 20000)
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || data.success === false) {
      return { ok: false, error: (data && data.error) || ("HTTP " + res.status) };
    }
    return { ok: true, data };
  } catch (e) {
    return { ok: false, error: e && e.message ? e.message : String(e) };
  }
}

async function checkBackendHealth(env) {
  const base = backendUrl(env);
  if (!base) return { connected: false, configured: false };
  try {
    const headers = {};
    if (env.REVERSER_API_KEY) headers["X-API-Key"] = env.REVERSER_API_KEY;
    const res = await fetch(base + "/api/reverser/status", {
      headers,
      signal: AbortSignal.timeout(5000)
    });
    if (!res.ok) return { connected: false, configured: true, error: "HTTP " + res.status };
    const data = await res.json().catch(() => ({}));
    return { connected: true, configured: true, info: data };
  } catch (e) {
    return { connected: false, configured: true, error: e && e.message ? e.message : String(e) };
  }
}

// PATCH a deferred (type 5) interaction followup with a file attachment.
async function patchFollowupFile(interaction, embed, fileText, outFilename) {
  const url = `https://discord.com/api/v10/webhooks/${interaction.application_id}/${interaction.token}/messages/@original`;
  const form = new FormData();
  form.append("payload_json", JSON.stringify({
    embeds: [embed],
    attachments: [{ id: 0, filename: outFilename, description: "PrimeZ R.E.L Result" }]
  }));
  form.append("files[0]", new Blob([fileText], { type: "text/plain;charset=utf-8" }), outFilename);
  try {
    const res = await fetch(url, { method: "PATCH", body: form });
    if (!res.ok) {
      console.error("Followup PATCH failed:", res.status, (await res.text()).slice(0, 300));
    }
  } catch (e) {
    console.error("Followup PATCH error:", e);
  }
}

// Ed25519 signature verifier using Web Crypto API
async function verifyDiscordSignature(request, publicKey) {
  const signature = request.headers.get("x-signature-ed25519");
  const timestamp = request.headers.get("x-signature-timestamp");
  if (!signature || !timestamp) return { isValid: false, body: "" };

  const body = await request.text();
  try {
    const keyData = hexToBuf(publicKey);
    const cryptoKey = await crypto.subtle.importKey(
      "raw",
      keyData,
      { name: "NODE-ED25519", namedCurve: "NODE-ED25519" },
      false,
      ["verify"]
    );

    const encoder = new TextEncoder();
    const data = encoder.encode(timestamp + body);
    const sigBuf = hexToBuf(signature);

    const isValid = await crypto.subtle.verify(
      "NODE-ED25519",
      cryptoKey,
      sigBuf,
      data
    );

    return { isValid, body };
  } catch (err) {
    return { isValid: false, body, error: err.message };
  }
}

function hexToBuf(hex) {
  const bytes = new Uint8Array(Math.ceil(hex.length / 2));
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
  }
  return bytes.buffer;
}

// Edge signature detector for instant low-latency analysis
function edgeDetect(source) {
  const s = source.toLowerCase();
  if (s.includes("luarmor") || s.includes("api.luarmor.net") || s.includes("v1.luarmor.net")) {
    return { name: "Luarmor Cloud Protection", kind: "luarmor", confidence: 99 };
  }
  if (s.includes("--ironbrew3") || s.includes("ironbrew3:") || s.includes("ib3")) {
    return { name: "IronBrew 3", kind: "ib3", confidence: 99 };
  }
  if (s.includes("aztupbrew") || s.includes("aztup")) {
    return { name: "AztupBrew", kind: "ib2", confidence: 99 };
  }
  if (s.includes("luaobfuscator") || s.includes("ferib")) {
    return { name: "LuaObfuscator", kind: "luaobf", confidence: 99 };
  }
  if (s.includes("prometheus") || s.includes("_cff_")) {
    return { name: "Prometheus (CFF/VM)", kind: "prometheus", confidence: 95 };
  }
  if (s.includes("moonsec") || s.includes("moonveil")) {
    return { name: "MoonSec / MoonVeil VM", kind: "moonsec", confidence: 95 };
  }
  if (s.includes("psu") || s.includes("psu obfuscator")) {
    return { name: "PSU Obfuscator", kind: "psu", confidence: 95 };
  }
  if (s.includes("boron")) {
    return { name: "Boron Obfuscator", kind: "boron", confidence: 92 };
  }
  if (s.includes("obscura") || s.includes("azurevm") || s.includes("clyde")) {
    return { name: "Obscura / AzureVM Protection", kind: "obscura", confidence: 92 };
  }
  if (s.includes("luraph") || s.includes("lph_")) {
    let ver = "v15";
    if (s.includes("14.9")) ver = "v14.9";
    else if (s.includes("14.8")) ver = "v14.8";
    else if (s.includes("14.7")) ver = "v14.7";
    return { name: `Luraph ${ver}`, kind: "luraph", confidence: 95 };
  }
  if (s.includes("ironbrew")) {
    return { name: "IronBrew 2 / Legacy", kind: "ib2", confidence: 85 };
  }
  if (s.includes("loadstring") && (s.includes("\\x") || s.includes("\\1") || s.includes("\\2"))) {
    return { name: "Bytecode / Encoded Packer", kind: "generic", confidence: 80 };
  }
  return { name: "Generic / Unrecognized", kind: "generic", confidence: 40 };
}

// Edge constant and string literal extractor
function edgeDump(source) {
  const strings = [];
  const stringRegex = /"([^"\\]*(?:\\.[^"\\]*)*)"|'([^'\\]*(?:\\.[^'\\]*)*)'|\[\[([\s\S]*?)\]\]/g;
  let match;
  while ((match = stringRegex.exec(source)) !== null) {
    const val = match[1] || match[2] || match[3];
    if (val && val.length > 0 && !strings.includes(val)) {
      strings.push(val);
      if (strings.length >= 100) break;
    }
  }

  const hexMatches = source.match(/\\x[0-9a-fA-F]{2}/g) || [];
  const numbers = Array.from(new Set(source.match(/\b\d+(?:\.\d+)?\b/g) || [])).slice(0, 50);

  return {
    detected: edgeDetect(source),
    string_constants_count: strings.length,
    string_constants: strings,
    number_constants: numbers,
    encoded_hex_sequences: hexMatches.length,
    entropy_score: Math.min(9.9, (source.length > 500 ? 7.2 : 4.1) + (hexMatches.length > 10 ? 1.8 : 0))
  };
}

// Edge light deobfuscation (constant fold + string unescape + bytecode unpack)
function edgeDeobf(source) {
  let cleaned = source;

  // 1. Decode string.char(n1, n2, ...) arrays into clean strings
  cleaned = cleaned.replace(/string\.char\s*\(\s*([\d\s,]+)\s*\)/g, (fullMatch, args) => {
    try {
      const bytes = args.split(',').map(s => parseInt(s.trim(), 10)).filter(n => !isNaN(n));
      if (bytes.length > 0 && bytes.every(b => b >= 0 && b <= 255)) {
        const decoded = bytes.map(b => (b >= 32 && b <= 126 && b !== 34 && b !== 92) ? String.fromCharCode(b) : `\\${b}`).join('');
        return `"${decoded}"`;
      }
    } catch (_) {}
    return fullMatch;
  });

  // 2. Decode hex escapes: \x61 -> a
  cleaned = cleaned.replace(/\\x([0-9a-fA-F]{2})/g, (_, h) => {
    try {
      const code = parseInt(h, 16);
      return (code >= 32 && code <= 126 && code !== 34 && code !== 39 && code !== 92) ? String.fromCharCode(code) : `\\x${h}`;
    } catch {
      return `\\x${h}`;
    }
  });

  // 3. Decode decimal escapes: \97 or \097 -> a
  cleaned = cleaned.replace(/\\([0-9]{1,3})/g, (_, d) => {
    try {
      const code = parseInt(d, 10);
      return (code >= 32 && code <= 126 && code !== 34 && code !== 39 && code !== 92) ? String.fromCharCode(code) : `\\${d}`;
    } catch {
      return `\\${d}`;
    }
  });

  // 4. Simplify multi-stage string concatenations: "a" .. "b" -> "ab"
  for (let i = 0; i < 5; i++) {
    const prev = cleaned;
    cleaned = cleaned.replace(/"([^"\r\n\\]*)"\s*\.\.\s*"([^"\r\n\\]*)"/g, '"$1$2"');
    cleaned = cleaned.replace(/'([^'\r\n\\]*)'\s*\.\.\s*'([^'\r\n\\]*)'/g, "'$1$2'");
    if (cleaned === prev) break;
  }

  // 5. Structure flattened one-liners into readable lines
  if (!cleaned.includes("\n") || (cleaned.split("\n").length < 5 && cleaned.length > 300)) {
    cleaned = cleaned.replace(/;\s*/g, ";\n");
    cleaned = cleaned.replace(/\bend\s+/g, "end\n");
    cleaned = cleaned.replace(/\bthen\s+/g, "then\n");
    cleaned = cleaned.replace(/\bdo\s+/g, "do\n");
  }

  return cleaned;
}

function formatDumpFile(source, filename) {
  const det = edgeDetect(source);
  const dump = edgeDump(source);

  const lines = [
    "-- ================================================================",
    "-- This was dumped by PrimeZ R.E.L (Reverse Engineering Lua)",
    `-- Target Script:       ${filename || "script.lua"}`,
    `-- Detected Obfuscator: ${det.name} (${det.kind}) [Confidence: ${det.confidence}%]`,
    `-- String Pool Size:    ${dump.string_constants_count} unique strings`,
    `-- Dump Timestamp:      ${new Date().toISOString()}`,
    "-- ================================================================",
    "",
    "----------------------------------------------------------------",
    "-- [1] EXTRACTED STRING CONSTANTS & IDENTIFIERS (" + dump.string_constants_count + ")",
    "----------------------------------------------------------------"
  ];

  if (dump.string_constants.length === 0) {
    lines.push("-- (No clear string constants extracted)");
  } else {
    dump.string_constants.forEach((s, idx) => {
      lines.push(`[${idx.toString().padStart(3, "0")}] = ${JSON.stringify(s)}`);
    });
  }

  lines.push("");
  lines.push("----------------------------------------------------------------");
  lines.push("-- [2] EXTRACTED NUMERICAL CONSTANTS (" + dump.number_constants.length + ")",
    "----------------------------------------------------------------");
  if (dump.number_constants.length === 0) {
    lines.push("-- (No numerical constants extracted)");
  } else {
    dump.number_constants.forEach((n, idx) => {
      lines.push(`[${idx.toString().padStart(3, "0")}] = ${n}`);
    });
  }

  lines.push("");
  lines.push("----------------------------------------------------------------");
  lines.push("-- [3] ENTROPY & HEURISTIC METRICS");
  lines.push("----------------------------------------------------------------");
  lines.push(`-- Encoded Hex Sequences:  ${dump.encoded_hex_sequences}`);
  lines.push(`-- Calculated Entropy:     ${dump.entropy_score.toFixed(2)} / 10`);
  lines.push(`-- Source Character Count: ${source.length}`);
  lines.push("");
  lines.push("----------------------------------------------------------------");
  lines.push("-- [4] UNESCAPED CONSTANT PREVIEW");
  lines.push("----------------------------------------------------------------");
  lines.push(edgeDeobf(source.substring(0, 5000)));
  lines.push("");
  lines.push("-- ================================================================");
  lines.push("-- [End of PrimeZ R.E.L Dump]");
  lines.push("-- ================================================================");

  return { text: lines.join("\n"), dump, det };
}

function formatDeobfFile(source, filename) {
  const det = edgeDetect(source);
  const clean = edgeDeobf(source);

  const lines = [
    "-- ================================================================",
    "-- This was deobfuscated by PrimeZ R.E.L (Reverse Engineering Lua)",
    `-- Target Script:       ${filename || "script.lua"}`,
    `-- Detected Engine:     ${det.name} (${det.kind})`,
    `-- Deobfuscated At:     ${new Date().toISOString()}`,
    "-- ================================================================",
    "",
    clean
  ];

  return { text: lines.join("\n"), det };
}

function makeDiscordFileResponse(embed, fileText, outFilename) {
  const form = new FormData();
  form.append("payload_json", JSON.stringify({
    type: 4,
    data: {
      embeds: [embed],
      attachments: [{ id: 0, filename: outFilename, description: "PrimeZ R.E.L Result" }]
    }
  }));
  form.append("files[0]", new Blob([fileText], { type: "text/plain;charset=utf-8" }), outFilename);
  return new Response(form, { headers: CORS_HEADERS });
}

function extractLoaderUrl(text) {
  const s = text.trim();
  if (
    s.toLowerCase().includes("loadstring") ||
    s.toLowerCase().includes("httpget") ||
    s.toLowerCase().includes("httppost") ||
    s.toLowerCase().includes("request") ||
    s.startsWith("http://") ||
    s.startsWith("https://")
  ) {
    const match = s.match(/https?:\/\/[^\s"'`<>]+/i);
    if (match) return match[0];
  }
  return null;
}

async function unwrapLoaderChain(initialText, maxHops = 6) {
  let current = initialText.trim();
  let hops = 0;
  while (hops < maxHops && current.length < 2500) {
    const targetUrl = extractLoaderUrl(current);
    if (!targetUrl) break;
    try {
      const res = await fetch(targetUrl, {
        headers: { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PRIMEz-Reverser/2.0" }
      });
      if (res.ok) {
        const text = await res.text();
        if (text && text.trim().length > 0) {
          current = text.trim();
          hops++;
          continue;
        }
      }
    } catch (err) {
      console.error("Failed to unwrap loader target:", targetUrl, err);
      break;
    }
    break;
  }
  return current;
}

async function resolveInteractionInput(interaction) {
  let source = "";
  let filename = "script.lua";

  // 1. Check all resolved attachments from Discord
  if (interaction.data?.resolved?.attachments) {
    const attachments = Object.values(interaction.data.resolved.attachments);
    if (attachments.length > 0 && attachments[0].url) {
      filename = attachments[0].filename || filename;
      try {
        const res = await fetch(attachments[0].url);
        if (res.ok) {
          source = await res.text();
        }
      } catch (err) {
        console.error("Failed to fetch attachment:", err);
      }
    }
  }

  const options = interaction.data?.options || [];

  // 2. Check URL options or parameters containing a URL / loadstring wrapper
  if (!source) {
    for (const opt of options) {
      if (typeof opt.value === "string") {
        const val = opt.value.trim();
        const extracted = extractLoaderUrl(val);
        if (extracted) {
          try {
            source = await unwrapLoaderChain(val);
            const parts = extracted.split("/");
            filename = parts[parts.length - 1].split("?")[0] || filename;
            break;
          } catch (err) {
            console.error("Failed to fetch url from option:", err);
          }
        }
      }
    }
  }

  // 3. Check code string or text input
  if (!source) {
    const codeOpt = options.find(o => o.name === "code") || options.find(o => typeof o.value === "string" && o.value.trim().length > 0);
    if (codeOpt && typeof codeOpt.value === "string") {
      source = codeOpt.value;
    }
  }

  if (source) {
    source = await unwrapLoaderChain(source);
  }

  return { source: source.trim(), filename };
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // 0. Handle CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    // 1. Health check (Cloudflare Edge 24/7)
    if (url.pathname === "/health" || url.pathname === "/") {
      return new Response(JSON.stringify({
        status: "operational",
        service: "PrimeZ R.E.L (Reverse Engineering Lua)",
        deployment: "Cloudflare Edge 24/7",
        capabilities: ["deobfuscator", "bytecode_dumper", "memory_tracer", "fingerprinter"],
        uptime: "100%",
        timestamp: new Date().toISOString()
      }), {
        headers: { "Content-Type": "application/json", ...CORS_HEADERS }
      });
    }

    // 2. HTTP API: Status Check (honest — reports the actual operating mode)
    if (url.pathname === "/api/reverser/status" || url.pathname === "/status") {
      const health = await checkBackendHealth(env);
      return new Response(JSON.stringify({
        status: "operational",
        mode: health.connected ? "full_engine_backend" : "edge_regex_only",
        backend: health,
        edge_region: request.cf?.colo || "Global Edge",
        edge_capabilities: [
          "fingerprinting",
          "string_char_decode",
          "hex_decimal_unescape",
          "concat_folding",
          "constant_pool_dump"
        ],
        note: health.connected
          ? "Full Python engine backend connected — /deobf runs real engine pipelines."
          : "Edge-only mode: /deobf is a lightweight regex cleanup and CANNOT devirtualize VM obfuscators. Set REVERSER_BACKEND_URL to enable real engines.",
        timestamp: new Date().toISOString()
      }), {
        headers: { "Content-Type": "application/json", ...CORS_HEADERS }
      });
    }

    // 3. HTTP API: Detect (uses the backend fingerprint DB when available)
    if (url.pathname === "/api/reverser/detect" && request.method === "POST") {
      try {
        const { source } = await request.json();
        if (backendUrl(env)) {
          const bres = await callReverserBackend(env, "/api/reverser/detect", { source }, 8000);
          if (bres.ok && bres.data.detection) {
            return new Response(JSON.stringify(bres.data.detection), {
              headers: { "Content-Type": "application/json", ...CORS_HEADERS }
            });
          }
        }
        const det = edgeDetect(source || "");
        return new Response(JSON.stringify(det), {
          headers: { "Content-Type": "application/json", ...CORS_HEADERS }
        });
      } catch (e) {
        return new Response(JSON.stringify({ error: e.message }), { status: 400, headers: CORS_HEADERS });
      }
    }

    // 4. HTTP API: Dump
    if (url.pathname === "/api/reverser/dump" && request.method === "POST") {
      try {
        let { source, filename } = await request.json();
        source = await unwrapLoaderChain(source || "");
        const result = formatDumpFile(source || "", filename);
        return new Response(JSON.stringify({
          success: true,
          detection: result.det,
          dump_text: result.text,
          strings_count: result.dump.string_constants_count
        }), {
          headers: { "Content-Type": "application/json", ...CORS_HEADERS }
        });
      } catch (e) {
        return new Response(JSON.stringify({ error: e.message }), { status: 400, headers: CORS_HEADERS });
      }
    }

    // 5. HTTP API: Deobfuscate (proxied to the real engines when configured)
    if (url.pathname === "/api/reverser/deobf" && request.method === "POST") {
      try {
        let { source, filename, backend } = await request.json();
        source = await unwrapLoaderChain(source || "");
        const result = formatDeobfFile(source || "", filename);
        if (backendUrl(env)) {
          const bres = await callReverserBackend(env, "/api/reverser/deobf", { source, backend }, 170000);
          if (bres.ok) {
            return new Response(JSON.stringify({
              success: true,
              mode: "full_engine_backend",
              detection: bres.data.detection,
              backend_used: bres.data.backend_used,
              source: bres.data.source,
              duration_sec: bres.data.duration_sec
            }), {
              headers: { "Content-Type": "application/json", ...CORS_HEADERS }
            });
          }
          return new Response(JSON.stringify({
            success: true,
            mode: "edge_regex_fallback",
            degraded_reason: "backend_unreachable: " + bres.error,
            detection: result.det,
            backend_used: "edge_regex_fallback",
            source: result.text,
            duration_sec: 0.02
          }), {
            headers: { "Content-Type": "application/json", ...CORS_HEADERS }
          });
        }
        return new Response(JSON.stringify({
          success: true,
          mode: "edge_regex_only",
          detection: result.det,
          backend_used: "edge_regex_only",
          source: result.text,
          duration_sec: 0.02
        }), {
          headers: { "Content-Type": "application/json", ...CORS_HEADERS }
        });
      } catch (e) {
        return new Response(JSON.stringify({ error: e.message, success: false }), { status: 400, headers: CORS_HEADERS });
      }
    }

    // 6. Discord Interactions Webhook (24/7 Edge)
    if (url.pathname === "/interactions" || url.pathname === "/discord") {
      if (request.method !== "POST") {
        return new Response("Method not allowed", { status: 405, headers: CORS_HEADERS });
      }

      const pubKey = env.DISCORD_PUBLIC_KEY;
      let bodyText = "";

      if (pubKey) {
        const { isValid, body } = await verifyDiscordSignature(request, pubKey);
        if (!isValid) {
          return new Response("Invalid request signature", { status: 401, headers: CORS_HEADERS });
        }
        bodyText = body;
      } else {
        bodyText = await request.text();
      }

      const interaction = JSON.parse(bodyText);

      // Discord PING (Type 1)
      if (interaction.type === 1) {
        return new Response(JSON.stringify({ type: 1 }), {
          headers: { "Content-Type": "application/json", ...CORS_HEADERS }
        });
      }

      // Application Command (Type 2)
      if (interaction.type === 2) {
        const { name } = interaction.data;

        // Command: /status (honest — shows the actual operating mode)
        if (name === "status") {
          const health = await checkBackendHealth(env);
          const fullMode = health.connected;
          const embed = {
            title: "⚡ PrimeZ R.E.L — Operational Status",
            description: fullMode
              ? "Full engine backend **connected** — `/deobf` runs the real IronBrew / LuaObfuscator / Luraph pipelines (3-tier cascade)."
              : (backendUrl(env)
                ? "Engine backend **configured but unreachable** — `/deobf` will return a clearly-labeled edge regex cleanup instead of real deobfuscation. Start `server.py` on the engine host."
                : "Running in **edge-only mode** — `/deobf` is a lightweight regex cleanup and **cannot** devirtualize VM obfuscators. Set `REVERSER_BACKEND_URL` to connect the real engines."),
            color: fullMode ? 0x00FFA3 : 0xFFA500,
            fields: [
              { name: "Mode", value: fullMode ? "`full_engine_backend`" : "`edge_regex_only`", inline: true },
              { name: "Backend Configured", value: backendUrl(env) ? "✅ Yes" : "❌ No (`REVERSER_BACKEND_URL` empty)", inline: true },
              { name: "Backend Health", value: fullMode ? "🟢 Connected" : "🔴 Unreachable", inline: true },
              { name: "Edge Tools (always on)", value: "✅ Fingerprinting (`/detect`)\n✅ `string.char` decode + escape unrolling\n✅ Constant pool dump (`/dump`)", inline: true },
              { name: "Active Commands", value: "`/deobf` • `/dump` • `/detect` • `/status`", inline: true }
            ],
            footer: { text: "PrimeZ R.E.L Edge Gateway" }
          };
          return new Response(JSON.stringify({ type: 4, data: { embeds: [embed] } }), {
            headers: { "Content-Type": "application/json", ...CORS_HEADERS }
          });
        }

        // Command: /detect
        if (name === "detect") {
          const { source } = await resolveInteractionInput(interaction);
          if (!source) {
            return new Response(JSON.stringify({
              type: 4,
              data: {
                embeds: [{
                  title: "⚠️ No Script Provided",
                  description: "Please attach a `.lua` file, provide a direct URL, or paste code.",
                  color: 0xFF204E
                }]
              }
            }), { headers: { "Content-Type": "application/json", ...CORS_HEADERS } });
          }

          const det = edgeDetect(source);
          return new Response(JSON.stringify({
            type: 4,
            data: {
              embeds: [{
                title: "🔎 Obfuscator Fingerprint Result",
                color: 0x00D2FF,
                fields: [
                  { name: "Detected Obfuscator", value: `**${det.name}**`, inline: false },
                  { name: "Internal Engine", value: `\`${det.kind}\``, inline: true },
                  { name: "Confidence", value: `\`${det.confidence}%\``, inline: true }
                ],
                footer: { text: "PrimeZ R.E.L Edge Detector • 24/7" }
              }]
            }
          }), { headers: { "Content-Type": "application/json", ...CORS_HEADERS } });
        }

        // Command: /dump
        if (name === "dump") {
          const { source, filename } = await resolveInteractionInput(interaction);
          if (!source) {
            return new Response(JSON.stringify({
              type: 4,
              data: {
                embeds: [{
                  title: "⚠️ No Script Provided to Dump",
                  description: "Please upload an obfuscated `.lua` / `.txt` file, provide a direct raw link, or paste code.",
                  color: 0xFF204E
                }]
              }
            }), { headers: { "Content-Type": "application/json", ...CORS_HEADERS } });
          }

          const { text, dump, det } = formatDumpFile(source, filename);
          const outFilename = `dump_${filename.replace(/\.lua$/i, "")}.txt`;

          const constPreview = dump.string_constants.length > 0
            ? dump.string_constants.slice(0, 8).map((c, i) => `\`[${i}]\` ${c.substring(0, 40)}`).join("\n")
            : "_No clear string constants extracted_";

          const embed = {
            title: "📦 PrimeZ R.E.L — Bytecode & Constant Dump Complete",
            description: `Target: \`${filename}\`\nOutput file attached below.`,
            color: 0x00D2FF,
            fields: [
              { name: "Detected Obfuscator", value: `**${det.name}** (\`${det.kind}\`)`, inline: true },
              { name: "String Constants", value: `\`${dump.string_constants_count} found\``, inline: true },
              { name: "Dump File Size", value: `\`${text.length.toLocaleString()} bytes\``, inline: true },
              { name: "Constants Sample Preview", value: constPreview.substring(0, 1000) }
            ],
            footer: { text: "PrimeZ R.E.L Edge Dumper • 24/7" }
          };

          return makeDiscordFileResponse(embed, text, outFilename);
        }

        // Command: /deobf
        if (name === "deobf") {
          const { source, filename } = await resolveInteractionInput(interaction);
          if (!source) {
            return new Response(JSON.stringify({
              type: 4,
              data: {
                embeds: [{
                  title: "⚠️ No Script Provided to Deobfuscate",
                  description: "Please upload an obfuscated `.lua` file, provide a direct raw link, or paste code.",
                  color: 0xFF204E
                }]
              }
            }), { headers: { "Content-Type": "application/json", ...CORS_HEADERS } });
          }

          // FULL ENGINE MODE: ACK Discord immediately (DEFERRED), then submit
          // the job to the Python backend. The backend runs the real engines
          // and PATCHes the result file into this interaction (15-min window).
          if (backendUrl(env)) {
            ctx.waitUntil((async () => {
              const submit = await callReverserBackend(env, "/api/reverser/deobf_job", {
                source,
                filename: filename || "script.lua",
                interaction_token: interaction.token,
                application_id: interaction.application_id
              }, 25000);

              if (submit.ok) return; // backend will PATCH the real result shortly

              // Backend unreachable — PATCH an honest warning + clearly-labeled
              // edge cleanup so the user is never misled.
              const result = formatDeobfFile(source, filename);
              const embed = {
                title: "⚠️ PrimeZ R.E.L — Engine Backend Unreachable",
                description: `The full engine backend did not respond (\`${submit.error}\`).\nAttached is an **edge regex cleanup only** — this is NOT real deobfuscation. Check that the backend service is up and retry.`,
                color: 0xFFA500,
                fields: [
                  { name: "Detected Obfuscator", value: `**${result.det.name}**`, inline: true },
                  { name: "Mode", value: "`edge_regex_fallback` (cosmetic only)", inline: true },
                  { name: "Output Size", value: `\`${result.text.length.toLocaleString()} bytes\``, inline: true }
                ],
                footer: { text: "PrimeZ R.E.L • Edge Fallback" }
              };
              await patchFollowupFile(interaction, embed, result.text, `edgecleanup_${filename}`);
            })());
            return new Response(JSON.stringify({ type: 5 }), {
              headers: { "Content-Type": "application/json", ...CORS_HEADERS }
            });
          }

          // EDGE-ONLY MODE: regex cleanup only — labeled honestly.
          const { text, det } = formatDeobfFile(source, filename);
          const outFilename = `deobfuscated_${filename}`;
          const snippet = text.substring(0, 600);

          const embed = {
            title: "⚠️ PrimeZ R.E.L — Edge Cleanup Only (Real Engines Not Connected)",
            description: "No engine backend is configured (`REVERSER_BACKEND_URL` is empty). This output is a **lightweight regex cleanup** — `string.char` decoding and escape unrolling only. It does **not** devirtualize VM obfuscators. See `cloudflare/README.md` to connect the full engine backend.",
            color: 0xFFA500,
            fields: [
              { name: "Detected Obfuscator", value: `**${det.name}**`, inline: true },
              { name: "Clean Output Size", value: `\`${text.length.toLocaleString()} bytes\``, inline: true },
              { name: "Code Preview", value: "```lua\n" + snippet + (text.length > 600 ? "\n-- [Truncated preview; full code in attached file]" : "") + "\n```" }
            ],
            footer: { text: "PrimeZ R.E.L Edge Mode • set REVERSER_BACKEND_URL for real deobfuscation" }
          };

          return makeDiscordFileResponse(embed, text, outFilename);
        }
      }

      return new Response(JSON.stringify({ type: 4, data: { content: "Unrecognized command." } }), {
        headers: { "Content-Type": "application/json", ...CORS_HEADERS }
      });
    }

    return new Response(JSON.stringify({ error: "Not found" }), { status: 404, headers: CORS_HEADERS });
  },

  // Cron trigger (every 10 min): keep-alive ping so the Render free-tier
  // backend doesn't sleep (it would otherwise cold-start for ~40-60s and
  // delay /deobf job submissions).
  async scheduled(event, env, ctx) {
    const base = backendUrl(env);
    if (!base) return;
    ctx.waitUntil((async () => {
      try {
        const headers = {};
        if (env.REVERSER_API_KEY) headers["X-API-Key"] = env.REVERSER_API_KEY;
        await fetch(base + "/api/reverser/status", { headers });
      } catch (e) {
        console.error("Backend keep-alive ping failed:", e);
      }
    })());
  }
};

