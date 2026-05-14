import pytest

MOCK_SEARCH_RESULTS = [
    {"full_name": "obra/superpowers", "stargazers_count": 2841,
     "description": "Core skills library", "topics": ["claude-plugin"]},
    {"full_name": "SeayMonster/SkillsOfTheKraken", "stargazers_count": 847,
     "description": "Crisp dev skills", "topics": ["claude-skill"]},
    {"full_name": "obra/episodic-memory", "stargazers_count": 612,
     "description": "Semantic memory", "topics": ["claude-plugin"]},
    {"full_name": "some/new-plugin", "stargazers_count": 500,
     "description": "New cool plugin", "topics": ["claude-code-plugin"]},
    {"full_name": "another/plugin", "stargazers_count": 400,
     "description": "Another plugin", "topics": ["claude-plugin"]},
    {"full_name": "yet/another", "stargazers_count": 300,
     "description": "Yet another", "topics": ["claude-plugin"]},
    {"full_name": "cool/tool", "stargazers_count": 250,
     "description": "Cool tool", "topics": ["claude-plugin"]},
    {"full_name": "nice/thing", "stargazers_count": 200,
     "description": "Nice thing", "topics": ["claude-plugin"]},
    {"full_name": "great/skill", "stargazers_count": 150,
     "description": "Great skill", "topics": ["claude-skill"]},
    {"full_name": "awesome/plugin", "stargazers_count": 100,
     "description": "Awesome plugin", "topics": ["claude-plugin"]},
    {"full_name": "basic/one", "stargazers_count": 50,
     "description": "Basic one", "topics": ["claude-plugin"]},
]

MOCK_INSTALLED = {
    "version": 2,
    "plugins": {
        "superpowers@superpowers-marketplace": [
            {"scope": "user",
             "installPath": "C:\\Users\\bseay\\.claude\\plugins\\cache\\superpowers-marketplace\\superpowers\\5.0.7",
             "version": "5.0.7",
             "installedAt": "2026-04-30T06:47:10Z", "lastUpdated": "2026-05-09T07:45:30Z"}
        ],
        "crisp-dev@SkillsOfTheKraken": [
            {"scope": "user",
             "installPath": "C:\\Users\\bseay\\.claude\\plugins\\cache\\SkillsOfTheKraken\\crisp-dev\\1.0.0",
             "version": "1.0.0",
             "installedAt": "2026-04-30T02:31:11Z", "lastUpdated": "2026-05-09T07:45:30Z"}
        ],
    }
}

@pytest.fixture
def mock_search_results():
    return MOCK_SEARCH_RESULTS

@pytest.fixture
def mock_installed():
    return MOCK_INSTALLED
