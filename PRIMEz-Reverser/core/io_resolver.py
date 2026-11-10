import re
import urllib.request
from pathlib import Path

URL_REGEX = re.compile(r'https?://[^\s<>"{}|\\^`]+', re.IGNORECASE)
CODEBLOCK_REGEX = re.compile(r'```(?:lua|luau|txt)?\s*([\s\S]*?)```', re.IGNORECASE)

async def download_url(url: str, timeout: int = 15) -> str:
    """Download text from raw pastes, discord attachments, or URLs."""
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PRIMEz-Reverser/1.0"}
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

async def resolve_input(raw_input: str) -> str:
    """Intelligently resolve raw input: URL, codeblock, or raw code."""
    stripped = raw_input.strip()
    
    # Check if single direct URL
    if stripped.startswith("http://") or stripped.startswith("https://"):
        urls = URL_REGEX.findall(stripped)
        if urls:
            return await download_url(urls[0])
            
    # Check if contained in markdown block
    cleaned = clean_codeblock(stripped)
    return cleaned
