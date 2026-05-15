import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / "scripts"))

from fetch_and_generate import generate_html

SAMPLE_TOP10 = [
    {"full_name": f"owner/plugin-{i}", "stargazers_count": 1000 - i * 50,
     "description": f"Plugin {i} description"} for i in range(10)
]
SAMPLE_UPDATES = [
    {"plugin_key": "old-plugin@marketplace", "full_name": "owner/old-plugin",
     "installed_version": "1.0.0", "latest_version": "1.2.0",
     "description": "Old plugin needing update"}
]

def test_generate_html_returns_string():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert isinstance(html, str)
    assert "<!DOCTYPE html>" in html

def test_top3_have_gold_class():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert html.count('class="card top3-card') == 3

def test_install_buttons_point_to_local_server():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert "localhost:9999/install" in html

def test_needs_update_section_shown_when_updates_exist():
    html = generate_html(SAMPLE_TOP10, SAMPLE_UPDATES, port=9999)
    assert "Needs Update" in html
    assert "1.0.0" in html
    assert "1.2.0" in html

def test_needs_update_section_hidden_when_no_updates():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert "Needs Update" not in html

def test_footer_contains_skill_command():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert "/crisp-dev:plugin-digest" in html

def test_modal_overlay_present():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert 'id="modal-overlay"' in html

def test_install_button_calls_open_modal():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert 'onclick="openModal()"' in html

def test_modal_js_functions_present():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert "function openModal()" in html
    assert "function closeModal()" in html
    assert "function confirmInstall()" in html
    assert "function refreshPage()" in html

def test_refresh_url_in_js():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert "localhost:9999/refresh" in html

def test_install_selected_function_removed():
    html = generate_html(SAMPLE_TOP10, [], port=9999)
    assert "function installSelected()" not in html
