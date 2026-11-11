import re
import urllib.request
from pathlib import Path

URL_REGEX = re.compile(r'https?://[^\s"\'`<>]+', re.IGNORECASE)
CODEBLOCK_REGEX = re.compile(r'```(?:lua|luau|txt)?\s*([\s\S]*?)```', re.IGNORECASE)

def extract_loader_url(text: str) -> str | None:
    """Extract a target URL from direct links, loadstring(...) or game:HttpGet(...) wrappers."""
    s = text.strip()
    if (
        "loadstring" in s.lower()
        or "httpget" in s.lower()
        or "httppost" in s.lower()
        or "request" in s.lower()
        or s.startswith("http://")
        or s.startswith("https://")
    ):
        urls = URL_REGEX.findall(s)
        if urls:
            return urls[0]
    return None

async def download_url(url: str, timeout: int = 15) -> str:
    """Download text from raw pastes, discord attachments, or URLs."""
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PRIMEz-Reverser/2.0"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = resp.read()
        return data.decode("utf-8", errors="replace")

def clean_codeblock(text: str) -> str:
    """Extract code from inside markdown codeblocks if present."""
    match = CODEBLOCK_REGEX.search(text)
    if match:
        return match.group(1).strip()
    return text.strip()

async def resolve_input(raw_input: str, max_hops: int = 6) -> str:
    """Intelligently resolve raw input, unwrap loadstring chains, URLs, or markdown code."""
    cleaned = clean_codeblock(raw_input.strip())
    current = cleaned
    
    # Recursively unwrap loaders (e.g. loadstring(game:HttpGet("https://..."))())
    for _ in range(max_hops):
        if len(current) < 2500:
            target_url = extract_loader_url(current)
            if target_url:
                try:
                    fetched = await download_url(target_url)
                    if fetched.strip():
                        current = clean_codeblock(fetched.strip())
                        continue
                except Exception:
                    break
        break
        
    return current
