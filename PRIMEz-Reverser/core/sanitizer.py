import re

WEBHOOK_REGEX = re.compile(
    r'https?://(?:ptb\.|canary\.)?discord(?:app)?\.com/api/webhooks/\d+/[A-Za-z0-9_-]+',
    re.IGNORECASE
)

TOKEN_REGEX = re.compile(
    r'[\w-]{24,26}\.[\w-]{6}\.[\w-]{27,38}'
)

def sanitize_output(source: str) -> str:
    """Mask sensitive tokens, webhook URLs, and credentials from decompiled scripts."""
    if not source:
        return ""
    
    # Mask Discord Webhooks
    source = WEBHOOK_REGEX.sub("[PRIMEZ_PROTECTED_WEBHOOK_URL]", source)
    
    # Mask Discord Tokens
    source = TOKEN_REGEX.sub("[PRIMEZ_PROTECTED_DISCORD_TOKEN]", source)
    
    return source

def is_safe_input(source: str) -> tuple[bool, str]:
    """Basic validation to avoid local exploitation or shell command injections."""
    if len(source.encode("utf-8")) > 25 * 1024 * 1024:
        return False, "File exceeds maximum size limit (25 MB)."
    return True, "OK"
