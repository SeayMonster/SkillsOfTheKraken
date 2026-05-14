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
import urllib.request
import urllib.parse
import urllib.error

CLAUDE_DIR = pathlib.Path.home() / ".claude"
DIGEST_HTML = CLAUDE_DIR / "plugin-digest.html"
DIGEST_CACHE = CLAUDE_DIR / "plugin-digest-cache.json"

GITHUB_SEARCH_TOPICS = ["claude-plugin", "claude-skill", "claude-code-plugin", "claude-code-skills"]
GITHUB_SEARCH_KEYWORDS = ["claude code skills", "claude code plugin"]
GITHUB_API = "https://api.github.com"


class RateLimitError(Exception):
    pass


def _github_get(path: str) -> dict:
    """Make an unauthenticated GitHub API GET request."""
    url = f"{GITHUB_API}{path}"
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json",
                                                "User-Agent": "plugin-digest/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        if e.code == 403:
            raise RateLimitError("GitHub API rate limit exceeded")
        raise


def search_github_plugins() -> list[dict]:
    """Search GitHub for Claude plugin repos across topics and keywords."""
    results = []

    # Topic searches
    for topic in GITHUB_SEARCH_TOPICS:
        try:
            data = _github_get(f"/search/repositories?q=topic:{topic}&sort=stars&per_page=30")
            results.extend(data.get("items", []))
        except RateLimitError:
            break
        except Exception:
            continue

    # Keyword searches
    for keyword in GITHUB_SEARCH_KEYWORDS:
        try:
            encoded = urllib.parse.quote(keyword)
            data = _github_get(f"/search/repositories?q={encoded}&sort=stars&per_page=20")
            results.extend(data.get("items", []))
        except (RateLimitError, Exception):
            continue

    return results


def get_known_marketplace_repos() -> list[dict]:
    """Read extraKnownMarketplaces from settings.json and return as repo dicts."""
    settings_path = CLAUDE_DIR / "settings.json"
    if not settings_path.exists():
        return []
    try:
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
        marketplaces = settings.get("extraKnownMarketplaces", {})
        repos = []
        for _key, val in marketplaces.items():
            repo_name = val.get("source", {}).get("repo")
            if repo_name:
                try:
                    data = _github_get(f"/repos/{repo_name}")
                    repos.append(data)
                except Exception:
                    continue
        return repos
    except Exception:
        return []


def deduplicate_repos(repos: list[dict]) -> list[dict]:
    """Remove duplicate repos by full_name."""
    seen = set()
    result = []
    for repo in repos:
        name = repo.get("full_name", "")
        if name and name not in seen:
            seen.add(name)
            result.append(repo)
    return result


def rank_by_stars(repos: list[dict], top_n: int = 10) -> list[dict]:
    """Sort repos by stargazers_count descending, return top_n."""
    sorted_repos = sorted(repos, key=lambda r: r.get("stargazers_count", 0), reverse=True)
    return sorted_repos[:top_n]

def main():
    use_cached = "--cached" in sys.argv
    print("Plugin Digest starting...")

if __name__ == "__main__":
    main()
