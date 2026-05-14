import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / "scripts"))

from fetch_and_generate import deduplicate_repos, rank_by_stars

def test_deduplicate_repos_removes_duplicates():
    repos = [
        {"full_name": "obra/superpowers", "stargazers_count": 100},
        {"full_name": "obra/superpowers", "stargazers_count": 100},  # duplicate
        {"full_name": "other/plugin", "stargazers_count": 50},
    ]
    result = deduplicate_repos(repos)
    assert len(result) == 2

def test_rank_by_stars_sorts_descending():
    repos = [
        {"full_name": "low/stars", "stargazers_count": 10},
        {"full_name": "high/stars", "stargazers_count": 500},
        {"full_name": "mid/stars", "stargazers_count": 100},
    ]
    result = rank_by_stars(repos)
    assert result[0]["full_name"] == "high/stars"
    assert result[1]["full_name"] == "mid/stars"
    assert result[2]["full_name"] == "low/stars"

def test_rank_by_stars_takes_top_n():
    repos = [{"full_name": f"repo/{i}", "stargazers_count": i} for i in range(20)]
    result = rank_by_stars(repos, top_n=10)
    assert len(result) == 10
    assert result[0]["stargazers_count"] == 19  # highest first
