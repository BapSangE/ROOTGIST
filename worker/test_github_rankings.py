import json
import unittest
import urllib.parse
from datetime import datetime, timezone
from unittest import mock

from worker import official_news


def repo(name, stars, created, desc="AI agent tool", forks=3, size=500):
    return {"name": name, "full_name": f"x/{name}", "html_url": f"https://github.com/x/{name}", "description": desc,
            "stargazers_count": stars, "forks_count": forks, "size": size, "language": "Python", "created_at": created}


class GithubRankingsTest(unittest.TestCase):
    now = datetime(2026, 11, 10, 6, 0, tzinfo=timezone.utc)

    def run_with(self, by_since):
        asked = []

        def fake(url):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)["q"][0]
            asked.append(q)
            since = q.split("created:>=")[1].split()[0]
            # 첫 묶음에만 돌려준다(묶음마다 같은 저장소가 다시 와도 한 번만 세는지는 따로 본다)
            first = q.startswith(official_news.GH_RANK_WORDS[0])
            return json.dumps({"items": by_since.get(since, []) if first else []}).encode()

        with mock.patch.object(official_news, "fetch", fake):
            return official_news.gh_rankings(self.now), asked

    def test_each_period_has_its_own_window_and_star_floor(self):
        got, asked = self.run_with({})
        self.assertEqual(set(got), {"day", "week", "month"})
        self.assertEqual(got["day"]["start"], datetime(2026, 11, 9, 6, 0, tzinfo=timezone.utc))
        self.assertEqual(got["week"]["start"], datetime(2026, 11, 3, 6, 0, tzinfo=timezone.utc))
        self.assertEqual(got["month"]["start"], datetime(2026, 10, 11, 6, 0, tzinfo=timezone.utc))
        self.assertTrue(all(v["end"] == self.now for v in got.values()))
        self.assertEqual(len(asked), 9)  # 기간 3 × 낱말 묶음 3(결과가 100개 이하면 둘째 쪽은 받지 않는다)
        self.assertTrue(asked[0].endswith("created:>=2026-11-09T06:00:00Z stars:>=10"))
        self.assertTrue(asked[-1].endswith("created:>=2026-10-11T06:00:00Z stars:>=100"))
        self.assertTrue(all(q.count(" OR ") <= 4 for q in asked))  # GitHub 검색은 OR 다섯 낱말까지
        self.assertEqual(len({q.split(" in:")[0] for q in asked}), 3)

    def test_ranks_by_stars_dedupes_and_filters_quality_and_spam(self):
        week = [repo("big", 900, "2026-11-05T00:00:00Z"), repo("small", 120, "2026-11-06T00:00:00Z"),
                repo("awesome-llm", 5000, "2026-11-05T00:00:00Z"), repo("big", 900, "2026-11-05T00:00:00Z"),
                repo("warframe-aio", 400, "2026-11-05T00:00:00Z", desc="Free Warframe cheat for Windows with ESP"),
                repo("lonely", 300, "2026-11-05T00:00:00Z", forks=0)]
        got, _ = self.run_with({"2026-11-03T06:00:00Z": week})
        self.assertEqual([(r["rank"], r["full_name"]) for r in got["week"]["repos"]], [(1, "x/big"), (2, "x/small")])
        self.assertEqual(got["day"]["repos"], [])

    def test_words_split_into_groups_pages_merged_and_deduped(self):
        pages = []

        def fake(url):
            qs = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
            q, page = qs["q"][0], int(qs["page"][0])
            if "2026-11-03T06" not in q:
                return json.dumps({"items": []}).encode()
            pages.append((q.split(" in:")[0], page))
            if q.startswith(official_news.GH_RANK_WORDS[0]):  # 첫 묶음은 결과가 많아 둘째 쪽까지
                items = [repo("big", 900, "2026-11-05T00:00:00Z")] if page == 1 else [repo("tail", 120, "2026-11-06T00:00:00Z")]
                return json.dumps({"total_count": 150, "items": items}).encode()
            # 다른 묶음: 새 저장소 하나와 이미 찾은 저장소
            return json.dumps({"total_count": 2, "items": [repo("codex-tool", 300, "2026-11-08T00:00:00Z"),
                                                             repo("big", 900, "2026-11-05T00:00:00Z")]}).encode()

        with mock.patch.object(official_news, "fetch", fake):
            got = official_news.gh_rankings(self.now)
        self.assertIn((official_news.GH_RANK_WORDS[0], 2), pages)
        self.assertNotIn((official_news.GH_RANK_WORDS[1], 2), pages)
        names = [r["full_name"] for r in got["week"]["repos"]]
        self.assertEqual(sorted(names), ["x/big", "x/codex-tool", "x/tail"])  # 둘째 쪽·다른 묶음도, 같은 저장소는 한 번만

    def test_month_weights_by_age_day_by_stars(self):
        old_big = repo("old-big", 3000, "2026-10-12T06:00:00Z")  # 29일 전
        new_hit = repo("new-hit", 1500, "2026-11-08T06:00:00Z")  # 2일 전
        got, _ = self.run_with({"2026-10-11T06:00:00Z": [old_big, new_hit],
                                "2026-11-09T06:00:00Z": [repo("a", 40, "2026-11-10T05:00:00Z"), repo("b", 60, "2026-11-09T07:00:00Z")]})
        # 30일: 3000/√32 ≈ 530 < 1500/√5 ≈ 671 → 별은 적어도 막 뜬 저장소가 위. 별 총합 순이면 반대였다
        self.assertEqual([r["full_name"] for r in got["month"]["repos"]], ["x/new-hit", "x/old-big"])
        self.assertEqual([r["full_name"] for r in got["day"]["repos"]], ["x/b", "x/a"])  # 24시간은 별 순 그대로

    def test_failed_period_is_skipped_others_kept(self):
        def fake(url):
            if "2026-11-09T06" in url:
                raise OSError("rate limited")
            return json.dumps({"items": [repo("a", 300, "2026-11-01T00:00:00Z")]}).encode()

        with mock.patch.object(official_news, "fetch", fake):
            got = official_news.gh_rankings(self.now)
        self.assertEqual(set(got), {"week", "month"})

    def test_rows_and_app_doc_keep_period_bounds(self):
        got, _ = self.run_with({"2026-11-03T06:00:00Z": [repo("big", 900, "2026-11-05T00:00:00Z")]})
        rows = official_news.rank_records(got)
        self.assertEqual(rows[0]["id"], "week:x/big")
        doc = official_news.rankings_doc(rows, self.now)
        week = doc["periods"]["week"]
        self.assertEqual((week["start"], week["end"]), ("2026-11-03T06:00:00Z", "2026-11-10T06:00:00Z"))
        self.assertEqual(week["repos"][0]["full_name"], "x/big")
        self.assertNotIn("period", week["repos"][0])
        self.assertIn("readme_ko", week["repos"][0])  # 앱 상세가 읽는 README 정리(아직 없으면 null)

    def test_save_rankings_without_readme_column_still_saves(self):
        saved = []

        class FakeDb:
            def upsert(self, table, rows, key):
                if any("readme_ko" in r for r in rows):
                    raise RuntimeError("column readme_ko does not exist")
                saved.extend(rows)

            def _req(self, *a, **k): pass

        got, _ = self.run_with({"2026-11-03T06:00:00Z": [repo("big", 900, "2026-11-05T00:00:00Z")]})
        official_news.save_rankings(FakeDb(), official_news.rank_records(got), self.now)
        self.assertEqual(len(saved), len(official_news.rank_records(got)))  # 마이그레이션 전이면 그 열만 빼고


if __name__ == "__main__":
    unittest.main()
