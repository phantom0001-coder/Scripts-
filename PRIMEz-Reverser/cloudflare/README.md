# 🌐 PRIMEz Reverser — Cloudflare Worker Deployment

This Worker acts as an ultra-fast, serverless edge gateway for **PRIMEz Reverser**:
- Serves Discord Slash Commands (`/status`, `/detect`, `/deobf`) via Discord Interactions Webhooks.
- Executes instant edge fingerprinting in < 15ms.
- Proxies complex VM reverse-engineering jobs to the PRIMEz Reverser backend.

---

## 🚀 How to Deploy

### 1. Authenticate with Cloudflare
```bash
npx wrangler login
```

### 2. Configure Discord Secrets
Inside the `cloudflare/` directory:
```bash
npx wrangler secret put DISCORD_PUBLIC_KEY
npx wrangler secret put DISCORD_APPLICATION_ID
npx wrangler secret put DISCORD_BOT_TOKEN
```

### 3. Deploy to Cloudflare Edge
```bash
npx wrangler deploy
```

Once deployed, set your Discord Application's **Interactions Endpoint URL** to:
```
https://primez-reverser.<your-subdomain>.workers.dev/interactions
```
