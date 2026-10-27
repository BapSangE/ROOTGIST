"""배치 워커 검사. 가상 텍스트만 쓴다(HANDOFF 0.1). 실행: python -m unittest worker.test_worker"""
import json
import unittest
from datetime import datetime, timezone
from unittest import mock

from . import build, collect, llm, official_news, split, validate

ABSTRACT = (
    "We study toy routing in example graphs, e.g. small grids. Our method improves accuracy by 3.5 pp. "
    "Results hold for $n > 2$ nodes.\nCode: https://example.com/toy-repo"
)


def sentences():
    return split.to_sentences(ABSTRACT)


def output(**over):
    out = {
        "schema_version": "p2-output-v0.2", "glossary_mode": "auto_select",
        "title_ko": "가상 제목", "summary_ko": "가상 요약 30\\% 개선.",
        "key_points": [{"claim_ko": "가상 핵심", "evidence_sentence_ids": ["A02"]}],
        "sentence_translations": [
            {"sentence_id": "A01", "translation_ko": "번역 1"},
            {"sentence_id": "A02", "translation_ko": "번역 2"},
            {"sentence_id": "A03", "translation_ko": "번역 3"},
        ],
        "glossary": [{"term": "toy routing", "definition_ko": "가상 정의.", "context_ko": "가상 문맥.",
                      "sentence_ids": ["A01"], "term_id": None, "term_difficulty": "unknown",
                      "explanation_level": "standard"}],
        "topic_tags": ["optimization"], "limitations": [],
    }
    out.update(over)
    return out


class SplitTest(unittest.TestCase):
    def test_split_ids_kinds_roundtrip(self):
        s = sentences()
        self.assertEqual([x["sentence_id"] for x in s], ["A01", "A02", "A03", "A04"])
        self.assertEqual([x["kind"] for x in s], ["text", "text", "text", "link"])
        self.assertIn("e.g. small", s[0]["text"])  # 약어 뒤에서 나누지 않음
        self.assertEqual(s[2]["text"], "Results hold for $n > 2$ nodes.")
        for x in s:  # 오프셋은 원문 그대로
            self.assertEqual(ABSTRACT[x["start"]:x["end"]], x["text"])


class SelectTest(unittest.TestCase):
    def test_upvotes_then_newer_then_id(self):
        def p(pid, up, at):
            return {"paper_id": pid, "upvotes": up, "published_at": at}
        ranked = collect.select_top([
            p("0000.00003", 5, "2026-10-17T10:00:00.000Z"),
            p("0000.00002", 5, "2026-10-18T10:00:00.000Z"),
            p("0000.00001", 5, "2026-10-18T10:00:00.000Z"),
            p("0000.00004", 9, "2026-10-01T00:00:00.000Z"),
        ], 3)
        self.assertEqual([x["paper_id"] for x in ranked], ["0000.00004", "0000.00001", "0000.00002"])

    def test_media_urls_kept(self):
        p = collect.to_paper({"thumbnail": "https://example.com/t.png",
                              "paper": {"id": "0000.00001", "title": "T", "summary": "S", "publishedAt": "2026-10-18T00:00:00.000Z",
                                        "mediaUrls": ["https://example.com/a.mp4"]}})
        self.assertEqual((p["thumbnail_url"], p["media_urls"]), ("https://example.com/t.png", ["https://example.com/a.mp4"]))

    def test_withdrawn_excluded(self):
        self.assertIsNone(collect.to_paper({"paper": {"id": "x", "withdrawnAt": "2026-10-18"}}))


class ValidateTest(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(validate.check(output(), sentences()), [])

    def test_failures(self):
        s = sentences()
        cases = {
            "align": output(sentence_translations=[{"sentence_id": "A01", "translation_ko": "x"}]),
            "evidence": output(key_points=[{"claim_ko": "x", "evidence_sentence_ids": ["A04"]}]),  # link 문장
            "term": output(glossary=[{**output()["glossary"][0], "term": "Toy routing"}]),  # 대소문자 다름
            "foreign": output(title_ko="가상 題目"),
            "schema": output(topic_tags=["vision"]),
            "mode": output(glossary_mode="fixed_terms"),
        }
        for kind, out in cases.items():
            with self.subTest(kind):
                self.assertTrue(any(e.startswith(kind) for e in validate.check(out, s)), validate.check(out, s))

    def test_postprocess_and_highlight(self):
        out = validate.postprocess(output(summary_ko="30\\% 개선, 4 times 4, 3\\times 빠름, GPU~A"))
        self.assertEqual(out["summary_ko"], "30% 개선, 4×4, 3× 빠름, GPU A")
        self.assertEqual(validate.latex_display("모델--하네스, 뇌---몸, -- 단독"), "모델–하네스, 뇌–몸, -- 단독")
        self.assertEqual(validate.latex_display("15~300초, 그림~3, et al.~"), "15~300초, 그림 3, et al. ")
        dup = output()["glossary"][0]
        self.assertEqual(validate.highlights([dup, dup, {**dup, "definition_ko": " "}], sentences()), [True, False, False])


class BuildTest(unittest.TestCase):
    def test_pending_and_featured(self):
        p = {"paper_id": "0000.00001", "title_en": "T", "authors": ["A", "B"], "org_name": None,
             "published_at": "2026-10-18T10:00:00.000Z", "upvotes": 3}
        pending = build.paper_detail(p, sentences(), None)
        ready = build.paper_detail({**p, "paper_id": "0000.00002"}, sentences(), validate.postprocess(output()))
        self.assertEqual(pending["ai_status"], "pending")
        self.assertEqual(ready["glossary"][0]["highlight"], True)
        self.assertEqual(ready["sentences"][3]["translation_ko"], None)  # link 문장은 번역 없음
        day = build.digest("2026-10-19", "2026-10-18T20:00:00Z", [p, p], [pending, ready])
        self.assertEqual(day["featured_paper_id"], "0000.00002")  # G9: pending 건너뜀
        self.assertEqual(day["papers"][1]["key_points_preview"], ["가상 핵심"])
        self.assertEqual(build.primary_topic([pending, ready], "0000.00002"), "optimization")


class GlossaryLinkTest(unittest.TestCase):
    def test_single_sense_links_ambiguous_and_missing(self):
        from . import glossary
        aliases = [
            {"sense_id": "S-backbone", "surface_form": "backbone"},
            {"sense_id": "S-agent-rl", "surface_form": "agent"},
            {"sense_id": "S-agent-ai", "surface_form": "Agent"},  # 같은 표기, 다른 의미
        ]
        rows = [
            {"paper_id": "p", "idx": 0, "term": "Backbones"},  # 대소문자·복수형
            {"paper_id": "p", "idx": 1, "term": "agent"},  # 다의어 → 연결도 후보도 아님
            {"paper_id": "p", "idx": 2, "term": "trajectory-drift"},
            {"paper_id": "q", "idx": 0, "term": "trajectory drift"},  # 같은 표기는 후보 하나로
        ]
        links, candidates = glossary.plan_links(rows, aliases)
        self.assertEqual(links, [("p", 0, "S-backbone")])
        self.assertEqual(list(candidates), ["trajectory drift"])
        self.assertEqual(len(candidates["trajectory drift"]), 2)


class MergePluralsTest(unittest.TestCase):
    def test_merge_only_when_singular_exists(self):
        from .glossary import merge_plurals
        key = merge_plurals({"action chunk", "action chunks", "bias", "policies", "policy", "lens"})
        self.assertEqual(key["action chunks"], "action chunk")
        self.assertEqual(key["policies"], "policy")
        self.assertEqual(key["bias"], "bias")  # bia가 없으니 그대로
        self.assertEqual(key["lens"], "lens")


class AcronymTest(unittest.TestCase):
    def test_detect_and_match(self):
        from .acronym import is_acronym, matches
        self.assertTrue(all(map(is_acronym, ["SLAM", "LoRA", "MLLMs", "GPT-4"])))
        self.assertFalse(any(map(is_acronym, ["backbone", "Transformer", "trajectory drift"])))
        self.assertTrue(matches("SLAM", "Simultaneous Localization and Mapping"))
        self.assertTrue(matches("LoRA", "Low-Rank Adaptation"))
        self.assertTrue(matches("MLLMs", "Multimodal Large Language Models"))
        self.assertFalse(matches("SLAM", "Sparse Linear Attention Module for Vision"))

    def test_from_abstract(self):
        from .acronym import from_abstract
        a = "We study Multimodal large language models (MLLMs) and toy agents. SLAM (simultaneous localization and mapping) helps."
        self.assertEqual(from_abstract("MLLMs", a), "Multimodal large language models")
        self.assertEqual(from_abstract("SLAM", a), "simultaneous localization and mapping")
        self.assertIsNone(from_abstract("MTEB", "We evaluate on MTEB."))  # 풀이가 없으면 지어내지 않음


class PreferredTermsTest(unittest.TestCase):
    def test_word_boundary_and_plural(self):
        from .glossary import terms_in
        pref = [("backbone", "backbone", "백본"), ("rl", "RL", "강화 학습"), ("instruction following", "instruction following", "지시 수행")]
        got = terms_in(pref, "We freeze two Backbones for instruction-following; URLs are not RL-free.")
        self.assertEqual([t["ko"] for t in got], ["백본", "강화 학습", "지시 수행"])
        self.assertEqual(terms_in(pref, "control of the world"), [])  # "rl"이 world 안에 있어도 단어가 아님

    def test_v06_template_has_preferred_terms(self):
        user = llm.build_messages("T", ABSTRACT, sentences(), "v0.6", [{"term": "backbone", "ko": "백본"}])[1]["content"]
        self.assertIn('preferred_terms: [{"term": "backbone", "ko": "백본"}]', user)
        self.assertNotIn("preferred_terms", llm.build_messages("T", ABSTRACT, sentences(), "v0.5.2")[1]["content"])


class DraftCheckTest(unittest.TestCase):
    def test_draft_validation(self):
        from .glossary import check_drafts
        terms = ["trajectory drift", "LoRA"]
        ok = {"items": [{"term": "trajectory drift", "canonical_ko": "궤적 이탈"}, {"term": "LoRA", "canonical_ko": "LoRA"}]}
        self.assertEqual(check_drafts(ok, terms), [])
        self.assertTrue(check_drafts({"items": ok["items"][::-1]}, terms))  # 순서 다름
        bad = {"items": [{"term": "trajectory drift", "canonical_ko": "軌跡 이탈"}, {"term": "LoRA", "canonical_ko": " "}]}
        self.assertEqual(check_drafts(bad, terms), ["ko: ['trajectory drift', 'LoRA']"])


class GenerateTest(unittest.TestCase):
    """ops config 2장 재시도·예비 모델 전환."""

    def run_with(self, results):
        calls = []

        def fake(key, model, messages):
            calls.append(model[0])
            r = results.pop(0)
            if isinstance(r, Exception):
                raise r
            return {"content": r, "finish_reason": "stop", "model_id": model[0]}

        with mock.patch.object(llm, "stream_chat", fake):
            out, model = llm.generate("k", [], lambda o: validate.check(o, sentences()), lambda r: None, sleep=lambda s: None,
                                      models=llm.DEEPSEEK_MODELS)
        return out, model, calls

    def test_retry_then_fallback(self):
        good = "```json\n" + json.dumps(output()) + "\n```"  # 코드 펜스도 꺼내 읽는다
        out, model, calls = self.run_with(["not json", "{}", good])
        primary, fallback = llm.DEEPSEEK_MODELS
        self.assertEqual(model, fallback[0])
        self.assertEqual(calls, [primary[0], primary[0], fallback[0]])
        self.assertEqual(out["title_ko"], "가상 제목")

    def test_transient_retries_then_ok(self):
        out, model, calls = self.run_with([llm.Transient("503"), json.dumps(output())])
        self.assertEqual(model, llm.DEEPSEEK_MODELS[0][0])
        self.assertEqual(len(calls), 2)

    def test_provider_by_key(self):
        with mock.patch.object(llm, "_setting", lambda n: {"DEEPSEEK_API_KEY": "d", "NVIDIA_API_KEY": "n"}.get(n)):
            self.assertEqual((llm.provider(), llm.api_key(), llm.active_models()), ("deepseek", "d", llm.DEEPSEEK_MODELS))
        with mock.patch.object(llm, "_setting", lambda n: {"NVIDIA_API_KEY": "n"}.get(n)):
            self.assertEqual((llm.provider(), llm.api_key(), llm.active_models()), ("nvidia", "n", llm.NVIDIA_MODELS))

    def test_stream_chat_sends_to_model_endpoint(self):
        sent = {}

        class Resp:
            headers = {}
            def __enter__(self): return self
            def __exit__(self, *a): return False
            def __iter__(self):
                return iter([b'data: {"choices":[{"delta":{"content":"{}"},"finish_reason":"stop"}]}\n', b"data: [DONE]\n"])

        def fake_open(req, timeout):
            sent["url"], sent["body"] = req.full_url, json.loads(req.data)
            return Resp()

        with mock.patch.object(llm.urllib.request, "urlopen", fake_open):
            r = llm.stream_chat("k", llm.DEEPSEEK_MODELS[0], [])
        self.assertEqual(sent["url"], "https://api.deepseek.com/chat/completions")
        self.assertEqual((sent["body"]["model"], sent["body"]["max_tokens"]), ("deepseek-flash", 64000))
        self.assertEqual(r["content"], "{}")

    def test_all_fail(self):
        out, model, calls = self.run_with(["x", "x", "x"])
        self.assertIsNone(out)
        self.assertEqual(len(calls), 3)


class PromptTest(unittest.TestCase):
    def test_prompt_sections_from_contract(self):
        system, mode_b = llm.load_prompt()
        self.assertIn("p2-output-v0.2", system)
        self.assertIn("auto_select", mode_b)
        self.assertNotIn("```", mode_b)
        msgs = llm.build_messages("T", ABSTRACT, sentences())
        self.assertIn('"evidence_sentence_ids"', msgs[0]["content"])  # 스키마 원문이 SYSTEM에 붙는다
        user = msgs[1]["content"]
        self.assertIn('"kind": "link"', user)  # link·meta도 넣어 모델이 건너뛰게 한다
        self.assertIn(f"abstract_sha256: {llm.sha256(ABSTRACT)}", user)



FEED = b"""<?xml version="1.0"?><rss><channel>
<item><title>Research post</title><link>https://example.com/a</link><category>Research</category><pubDate>Thu, 22 Oct 2026 10:00:00 GMT</pubDate></item>
<item><title>Customer story</title><link>https://example.com/b</link><category>Story</category><pubDate>Thu, 22 Oct 2026 10:00:00 GMT</pubDate></item>
<item><title>Old research</title><link>https://example.com/c</link><category>Research</category><pubDate>Mon, 01 Sep 2026 10:00:00 GMT</pubDate></item>
</channel></rss>"""
HF_FEED = b"""<?xml version="1.0"?><rss><channel>
<item><title>Official</title><link>https://huggingface.co/blog/official-post</link><pubDate>Thu, 22 Oct 2026 10:00:00 GMT</pubDate></item>
<item><title>Community</title><link>https://huggingface.co/blog/some-org/community-post</link><pubDate>Thu, 22 Oct 2026 10:00:00 GMT</pubDate></item>
</channel></rss>"""


class OfficialNewsTest(unittest.TestCase):
    NOW = official_news.datetime(2026, 10, 26, tzinfo=official_news.timezone.utc)

    def test_openai_keeps_dev_categories_within_window(self):
        with mock.patch.object(official_news, "fetch", return_value=FEED):
            got = official_news.pick(official_news.from_rss("openai", "OpenAI", "x"), self.NOW)
        self.assertEqual([i["title_en"] for i in got], ["Research post"])  # 사례 글·14일 넘은 글 제외

    def test_hf_keeps_only_official_posts(self):
        with mock.patch.object(official_news, "fetch", return_value=HF_FEED):
            got = official_news.from_rss("huggingface", "Hugging Face", "x")
        self.assertEqual([i["title_en"] for i in got], ["Official"])

    def test_releases_grouped_into_one_item(self):
        atom = b"""<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom">
<entry><title>v1.2</title><updated>2026-10-23T10:00:00Z</updated><content type="html">&lt;p&gt;Added B&lt;/p&gt;</content></entry>
<entry><title>v1.1</title><updated>2026-10-21T10:00:00Z</updated><content type="html">&lt;p&gt;Fixed A&lt;/p&gt;</content></entry>
<entry><title>v1.0</title><updated>2026-10-01T10:00:00Z</updated><content type="html">old</content></entry>
</feed>"""
        with mock.patch.object(official_news, "fetch", return_value=atom):
            got = official_news.from_releases("x", "Tool", "u", "page", self.NOW)
        self.assertEqual(len(got), 1)  # 이번 주 두 버전을 한 항목으로, 3주 전 것은 뺀다
        self.assertEqual(got[0]["title_ko"], "Tool 업데이트 2건 (v1.1~v1.2)")
        self.assertEqual(got[0]["kind"], "release")
        self.assertIn("[v1.2]\nAdded B", got[0]["notes"])  # 최신 버전 노트가 먼저

    def test_claude_api_notes_by_date_heading(self):
        page = (b'<h2>2026</h2><h3 id="october-22-2026">October 22, 2026</h3><ul><li>Added <code>x</code> tool</li><li>Fixed y</li></ul>'
                b'<h3 id="august-01-2026">August 1, 2026</h3><ul><li>old</li></ul>')
        with mock.patch.object(official_news, "fetch", return_value=page):
            got = official_news.from_claude_api_notes(self.NOW)
        self.assertEqual(got[0]["title_ko"], "Claude API 변경 사항 2건")
        self.assertIn("- Added x tool", got[0]["notes"])
        self.assertNotIn("old", got[0]["notes"])

    def test_community_feed_is_notice(self):
        with mock.patch.object(official_news, "fetch", return_value=HF_FEED):
            got = official_news.from_rss("openai_community", "OpenAI 커뮤니티", "x")
        self.assertEqual({i["kind"] for i in got}, {"notice"})

    def test_paragraphs_from_whole_page(self):
        page = "<nav><p>menu menu menu menu menu menu menu menu menu menu</p></nav><div><p>" + "A" * 50 + "</p><li>short</li></div>"
        self.assertEqual(official_news.paragraphs(page), ["A" * 50])  # nav·짧은 줄 제외

    def test_post_points_need_evidence_and_real_quote(self):
        paras = ["Alpha model is faster than before on long inputs.", "Pricing drops by half for everyone."]
        reply = {"summary": "요약", "points": [{"text": "빨라졌어요", "para": 1, "quote": "faster than before"},
                                             {"text": "싸졌어요", "para": 2, "quote": "not in the paragraph"}]}
        with mock.patch.object(llm, "stream_chat", return_value={"content": json.dumps(reply, ensure_ascii=False), "finish_reason": "stop"}):
            summary, points = official_news.summarize_post("T", paras, "k", lambda e: None)
        self.assertEqual(summary, "요약")
        self.assertEqual([p["quote"] for p in points], ["faster than before", None])  # 문단에 없는 구절은 링크에서 뺀다
        bad = {"summary": "요약", "points": [{"text": "근거 없음", "para": 9, "quote": "x"}]}
        with mock.patch.object(llm, "stream_chat", return_value={"content": json.dumps(bad), "finish_reason": "stop"}):
            self.assertIsNone(official_news.summarize_post("T", paras, "k", lambda e: None))  # 없는 문단 번호는 받지 않는다

    def test_trending_filters_tasks_and_blocked_names(self):
        listing = json.dumps([
            {"id": "a/good", "pipeline_tag": "text-generation", "tags": ["license:mit", "arxiv:2601.00001"]},
            {"id": "b/Model-Uncensored", "pipeline_tag": "text-generation", "tags": []},
            {"id": "c/robot", "pipeline_tag": "robotics", "tags": []},
        ]).encode()
        detail = json.dumps({"author": "a", "safetensors": {"total": 27_000_000_000}, "likes": 5, "downloads": 9}).encode()
        with mock.patch.object(official_news, "fetch", side_effect=lambda u: listing if "sort=" in u else detail):
            got = official_news.from_hf_trending()
        self.assertEqual([m["id"] for m in got], ["a/good"])
        self.assertEqual((got[0]["params"], got[0]["license"], got[0]["arxiv"]), (27_000_000_000, "mit", ["2601.00001"]))

    def test_save_db_upserts_news_and_replaces_models(self):
        calls = []
        class FakeDb:
            def upsert(self, table, rows, on_conflict):
                calls.append(("upsert", table, rows, on_conflict))
            def _req(self, method, path, body=None, prefer=None):
                calls.append((method, path))
        now = datetime(2026, 10, 27, tzinfo=timezone.utc)
        item = {"id": "abc", "source": "openai", "source_label": "OpenAI", "kind": "post", "category": None,
                "title_en": "T", "title_ko": "제목", "url": "https://e.com/a", "published_at": "2026-10-26T00:00:00+00:00",
                "summary_ko": "요약", "key_points": None, "_desc": "버린다"}
        official_news.save_db(FakeDb(), [item], [{"id": "a/b", "rank": 1, "url": "u", "card": None}], now)
        news = calls[0]
        self.assertEqual((news[1], news[3]), ("official_news", "id"))
        self.assertNotIn("_desc", news[2][0])  # 테이블에 없는 열은 보내지 않는다
        self.assertEqual(news[2][0]["key_points"], [])
        self.assertEqual(calls[1][1], "trending_models")
        self.assertEqual(calls[2][0], "DELETE")  # 이번 실행에 없는 모델은 지운다
        self.assertIn("collected_at=lt.", calls[2][1])
        calls.clear()
        official_news.save_db(FakeDb(), [item], [], now)
        self.assertEqual([c[1] for c in calls], ["official_news"])  # 트렌딩을 못 받은 날은 그대로 둔다

    def test_tautology_and_repeated_points(self):
        # 실데이터(2026-10-27): 제목만 되풀이한 요약은 거르고, 내용 있는 요약은 남긴다
        self.assertTrue(official_news.tautology("GPT-6.1 Terra 소개",
            "GPT-6.1 Terra를 소개하는 글이에요. 빠르고 뛰어난 컴퓨터 사용을 모두에게 제공하는 내용을 다뤄요."))
        self.assertFalse(official_news.tautology("Anthropic, IPO 제안 위해 SEC에 S-1 제출",
            "Anthropic이 미국 SEC에 S-1 등록서류를 제출했어요. 나스닥 상장을 추진 중이지만 공모 규모는 아직 정해지지 않았어요."))
        summary = "이 글은 어떤 애플리케이션에도 빠르고 집중적이며 비용이 낮은 의사결정을 제공하는 Decisions API를 소개해요."
        kept = official_news.drop_repeats(summary, [
            {"text": "Decisions API는 어떤 애플리케이션에도 빠르고 집중적이며 비용이 낮은 의사결정을 제공해요."},  # 요약을 다시 씀
            {"text": "요청마다 응답 시간이 100ms 안쪽이에요."},
        ])
        self.assertEqual([p["text"] for p in kept], ["요청마다 응답 시간이 100ms 안쪽이에요."])

    def test_thin_source_is_translated_not_summarized(self):
        calls = []
        def fake(key, model, messages):
            calls.append(messages[0]["content"])
            return {"content": json.dumps({"summary": "빠르고 뛰어난 컴퓨터 사용을 모두에게 열어요."}, ensure_ascii=False), "finish_reason": "stop"}
        with mock.patch.object(llm, "stream_chat", fake):
            got = official_news.translate_blurb("Bringing fast and capable computer use to everyone", "k", lambda e: None)
        self.assertEqual(got, "빠르고 뛰어난 컴퓨터 사용을 모두에게 열어요.")
        self.assertIn("Do not add, explain, or guess", calls[0])

    def test_related_links_by_model_name(self):
        items = [
            {"id": "a", "title_en": "Introducing GPT-6.1 Terra", "_desc": "Bringing fast computer use"},
            {"id": "b", "title_en": "OpenAI Python SDK v3.36.0~v3.39.0 (5 releases)",
             "key_points": [{"text": "API에 gpt-6.1-terra 모델 식별자가 추가됐어요."}]},
            {"id": "c", "title_en": "GPT-6.1 Sol helps CodeRabbit strengthen security"},  # 다른 모델
            {"id": "d", "title_en": "Introducing GPT-6 Astra"},  # 「gpt-6」처럼 짧은 이름으로는 잇지 않는다
        ]
        official_news.link_related(items)
        self.assertEqual([i["related"] for i in items], [["b"], ["a"], [], []])

    def test_haeyo_rejects_hamnida_and_plain_endings(self):
        from worker.official_news import not_haeyo
        self.assertTrue(not_haeyo(["API 버전 지원이 추가되었습니다."]))
        self.assertTrue(not_haeyo(["새 모델을 공개했다"]))
        self.assertFalse(not_haeyo(["API 버전 지원이 추가됐어요.", "message threads 지원", None]))
        self.assertFalse(not_haeyo(["코딩에 강해요(제작사 측정)."]))

    def test_card_scores_must_appear_in_card(self):
        card = "Our model scores 74.2% on SWE-bench Verified."
        reply = {"strengths": ["코딩용"], "benchmarks": [{"name": "SWE-bench Verified", "score": "74.2%"}, {"name": "X", "score": "99%"}], "limitation": None}
        with mock.patch.object(llm, "stream_chat", return_value={"content": json.dumps(reply, ensure_ascii=False), "finish_reason": "stop"}):
            out = official_news.summarize_card(card, "k", lambda e: None)
        self.assertEqual([b["score"] for b in out["benchmarks"]], ["74.2%"])  # 카드에 없는 점수는 버린다

    def test_date_without_timezone_is_utc(self):
        self.assertEqual(official_news._date("2026-10-22").tzinfo, official_news.timezone.utc)

    def test_translate_requires_one_title_each(self):
        with mock.patch.object(llm, "stream_chat", side_effect=lambda *a: {"content": json.dumps({"titles": ["하나"]}), "finish_reason": "stop"}):
            self.assertIsNone(official_news.translate(["one", "two"], "k", lambda e: None, ))


if __name__ == "__main__":
    unittest.main()
