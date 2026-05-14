"""
Plugin Digest — fetch top Claude plugins from GitHub, generate HTML digest,
serve locally for one-click install.

Usage:
    python fetch_and_generate.py          # fetch fresh + open browser
    python fetch_and_generate.py --cached # use cached results (skip GitHub)
"""
import json
import pathlib
import sys

CLAUDE_DIR = pathlib.Path.home() / ".claude"
DIGEST_HTML = CLAUDE_DIR / "plugin-digest.html"
DIGEST_CACHE = CLAUDE_DIR / "plugin-digest-cache.json"

def main():
    use_cached = "--cached" in sys.argv
    print("Plugin Digest starting...")

if __name__ == "__main__":
    main()
