"""배치 워커 검사. 가상 텍스트만 쓴다(HANDOFF 0.1). 실행: python -m unittest worker.test_worker"""
import json
import unittest
from unittest import mock

from . import build, collect, llm, split, validate

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
            out, model = llm.generate("k", [], lambda o: validate.check(o, sentences()), lambda r: None, sleep=lambda s: None)
        return out, model, calls

    def test_retry_then_fallback(self):
        good = "```json\n" + json.dumps(output()) + "\n```"  # 코드 펜스도 꺼내 읽는다
        out, model, calls = self.run_with(["not json", "{}", good])
        self.assertEqual(model, llm.FALLBACK[0])
        self.assertEqual(calls, [llm.PRIMARY[0], llm.PRIMARY[0], llm.FALLBACK[0]])
        self.assertEqual(out["title_ko"], "가상 제목")

    def test_transient_retries_then_ok(self):
        out, model, calls = self.run_with([llm.Transient("503"), json.dumps(output())])
        self.assertEqual(model, llm.PRIMARY[0])
        self.assertEqual(len(calls), 2)

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


if __name__ == "__main__":
    unittest.main()
