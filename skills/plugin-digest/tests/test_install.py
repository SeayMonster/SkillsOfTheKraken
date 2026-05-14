import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / "scripts"))

from unittest.mock import patch, MagicMock
from fetch_and_generate import get_install_url, build_generic_install_steps

def test_get_install_url_returns_raw_url_when_install_ps1_exists():
    # Mock _check_file_exists to return True for install.ps1
    with patch("fetch_and_generate._check_file_exists") as mock_check:
        mock_check.return_value = True
        url = get_install_url("SeayMonster/SkillsOfTheKraken")
    assert url == "https://raw.githubusercontent.com/SeayMonster/SkillsOfTheKraken/main/install.ps1"

def test_get_install_url_returns_none_when_no_installer():
    with patch("fetch_and_generate._check_file_exists") as mock_check:
        mock_check.return_value = False
        url = get_install_url("some/random-plugin")
    assert url is None

def test_build_generic_install_steps_returns_list():
    steps = build_generic_install_steps("owner/my-plugin", "my-plugin", "1.0.0")
    assert isinstance(steps, list)
    assert len(steps) > 0
    # Steps should be strings describing what to do
    combined = " ".join(steps)
    assert "settings.json" in combined
    assert "installed_plugins" in combined
