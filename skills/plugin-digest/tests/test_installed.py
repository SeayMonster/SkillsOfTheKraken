import sys, pathlib, json, tempfile
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / "scripts"))

from fetch_and_generate import get_installed_plugins, filter_uninstalled, get_plugin_repo_key

def test_get_installed_plugins_returns_dict(tmp_path):
    installed = {
        "version": 2,
        "plugins": {
            "superpowers@superpowers-marketplace": [
                {"version": "5.0.7", "installPath": "/some/path"}
            ]
        }
    }
    f = tmp_path / "installed_plugins.json"
    f.write_text(json.dumps(installed))
    result = get_installed_plugins(installed_path=f)
    assert "superpowers@superpowers-marketplace" in result
    assert result["superpowers@superpowers-marketplace"]["version"] == "5.0.7"

def test_get_installed_plugins_returns_empty_if_missing(tmp_path):
    result = get_installed_plugins(installed_path=tmp_path / "nonexistent.json")
    assert result == {}

def test_filter_uninstalled_excludes_installed_repos():
    repos = [
        {"full_name": "obra/superpowers", "stargazers_count": 2841},
        {"full_name": "some/new-plugin", "stargazers_count": 500},
    ]
    installed_repos = {"obra/superpowers"}
    result = filter_uninstalled(repos, installed_repos)
    assert len(result) == 1
    assert result[0]["full_name"] == "some/new-plugin"

def test_get_plugin_repo_key_extracts_repo_name():
    # installed_plugins.json entries use plugin@marketplace format
    # We map them back to full_name for filtering
    assert get_plugin_repo_key("SeayMonster/SkillsOfTheKraken") == "seaymonster/skillsofthekraken"
