import sys, pathlib, json, threading
import http.client
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / "scripts"))

from unittest.mock import patch
import fetch_and_generate as fag
from fetch_and_generate import make_install_handler, find_free_port
import http.server


def _start_test_server(port: int) -> http.server.HTTPServer:
    handler = make_install_handler(port)
    server = http.server.HTTPServer(("localhost", port), handler)
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    return server


def test_refresh_returns_200_and_writes_html(tmp_path):
    cache_data = {
        "top10": [{"full_name": "a/my-plugin", "stargazers_count": 100, "description": "test"}],
        "needs_update": []
    }
    port = find_free_port()
    cache_file = tmp_path / "plugin-digest-cache.json"
    html_file = tmp_path / "plugin-digest.html"
    cache_file.write_text(json.dumps(cache_data))

    server = _start_test_server(port)
    try:
        with patch.object(fag, "DIGEST_CACHE", cache_file), \
             patch.object(fag, "DIGEST_HTML", html_file), \
             patch("fetch_and_generate.get_installed_plugins", return_value={}), \
             patch("fetch_and_generate.get_installed_repo_names", return_value=set()):
            conn = http.client.HTTPConnection("localhost", port, timeout=5)
            conn.request("GET", "/refresh")
            resp = conn.getresponse()
            body = json.loads(resp.read())
    finally:
        server.shutdown()

    assert resp.status == 200
    assert body["success"] is True
    assert html_file.exists()
    assert "my-plugin" in html_file.read_text()


def test_refresh_filters_newly_installed_plugin(tmp_path):
    cache_data = {
        "top10": [
            {"full_name": "a/my-plugin", "stargazers_count": 100, "description": "test"},
            {"full_name": "b/other-plugin", "stargazers_count": 50, "description": "other"},
        ],
        "needs_update": []
    }
    port = find_free_port()
    cache_file = tmp_path / "plugin-digest-cache.json"
    html_file = tmp_path / "plugin-digest.html"
    cache_file.write_text(json.dumps(cache_data))

    server = _start_test_server(port)
    try:
        with patch.object(fag, "DIGEST_CACHE", cache_file), \
             patch.object(fag, "DIGEST_HTML", html_file), \
             patch("fetch_and_generate.get_installed_plugins", return_value={}), \
             patch("fetch_and_generate.get_installed_repo_names", return_value={"a/my-plugin"}):
            conn = http.client.HTTPConnection("localhost", port, timeout=5)
            conn.request("GET", "/refresh")
            resp = conn.getresponse()
            resp.read()
    finally:
        server.shutdown()

    html_content = html_file.read_text()
    assert "my-plugin" not in html_content
    assert "other-plugin" in html_content


def test_refresh_returns_500_when_no_cache(tmp_path):
    port = find_free_port()
    missing_cache = tmp_path / "nonexistent-cache.json"
    html_file = tmp_path / "plugin-digest.html"

    server = _start_test_server(port)
    try:
        with patch.object(fag, "DIGEST_CACHE", missing_cache), \
             patch.object(fag, "DIGEST_HTML", html_file):
            conn = http.client.HTTPConnection("localhost", port, timeout=5)
            conn.request("GET", "/refresh")
            resp = conn.getresponse()
            body = json.loads(resp.read())
    finally:
        server.shutdown()

    assert resp.status == 500
    assert body["success"] is False
