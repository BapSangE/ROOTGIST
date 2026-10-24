"""모델 출력 검증과 후처리 (batch_worker_notes.md 4장, ops config 3장, HANDOFF 8.3·8.4).

모델의 자기 판정을 믿지 않고 입력 문장과 대조한다.
"""
import json
import re
from pathlib import Path

from jsonschema import Draft202012Validator

SCHEMA = json.loads((Path(__file__).resolve().parent.parent / "docs" / "contract" / "p2_output_schema_v0.2.json").read_text(encoding="utf-8"))
_validator = Draft202012Validator(SCHEMA)
ALLOWED_TOPICS = {"llm", "agent", "multimodal", "optimization", "other"}
# 한자(CJK 통합·확장 A·호환), 히라가나, 가타카나
FOREIGN = re.compile(r"[぀-ヿ㐀-䶿一-鿿豈-﫿]")
KO_FIELDS = ("title_ko", "summary_ko")


def korean_texts(out: dict):
    """외국 문자 검사·LaTeX 변환 대상 한국어 문자열."""
    yield from (out.get(k) or "" for k in KO_FIELDS)
    for k in out.get("key_points") or []:
        yield k.get("claim_ko") or ""
    for t in out.get("sentence_translations") or []:
        yield t.get("translation_ko") or ""
    for g in out.get("glossary") or []:
        yield g.get("definition_ko") or ""
        yield g.get("context_ko") or ""
    yield from out.get("limitations") or []


def check(out, sentences: list[dict]) -> list[str]:
    """검사 1~4 + 외국 문자(재시도 대상). 빈 목록이면 통과."""
    errors = [f"schema: {'/'.join(map(str, e.path)) or '$'}: {e.message}" for e in _validator.iter_errors(out)]
    if errors or not isinstance(out, dict):
        return errors or ["schema: not an object"]
    if out["glossary_mode"] != "auto_select":
        errors.append("mode: glossary_mode != auto_select")

    text_ids = [s["sentence_id"] for s in sentences if s["kind"] == "text"]
    got = [t["sentence_id"] for t in out["sentence_translations"]]
    if got != text_ids:
        errors.append(f"align: translations {got} != text sentences {text_ids}")

    ids = set(text_ids)
    for i, k in enumerate(out["key_points"]):
        if bad := [x for x in k["evidence_sentence_ids"] if x not in ids]:
            errors.append(f"evidence: key_points[{i}] {bad}")
    texts = [s["text"] for s in sentences if s["kind"] == "text"]
    for i, g in enumerate(out["glossary"]):
        if bad := [x for x in g["sentence_ids"] if x not in ids]:
            errors.append(f"evidence: glossary[{i}] {bad}")
        if g["term_id"] is not None:
            errors.append(f"term: glossary[{i}] term_id must be null")
        if not any(g["term"] in t for t in texts):
            errors.append(f"term: glossary[{i}] {g['term']!r} not verbatim in source")

    if any(FOREIGN.search(t) for t in korean_texts(out)):
        errors.append("foreign: 한자·가나 포함")
    return errors


# 8.3 (A6) + 프롬프트의 「times」 규칙. 원문 초록은 바꾸지 않고, 모델이 놓친 한국어 출력에만 저장 전에 적용한다.
# 앱의 latexDisplay(영문 원문 표시용)는 맨 「times」를 바꾸지 않는다("3 times faster"는 정상 영어).
def latex_display(s: str) -> str:
    s = re.sub(r"\\([%_&#$])", r"\1", s)
    s = re.sub(r"(?<=\d)\s*\\?times\s*(?=\d)", "×", s)  # 3 \times 4, 4 times 4 → ×
    s = re.sub(r"(?<=\d)\s*\\times\b|(?<=\d)times\b", "×", s)  # 10\times, 3times → ×
    s = re.sub(r"(?<=\S)---?(?=\S)", "–", s)  # LaTeX 줄표 --/--- 가 그대로 옮겨진 경우(모델--하네스 → 모델–하네스)
    # LaTeX 붙임 공백 ~ 는 공백으로. 숫자 사이 ~ 는 한국어 범위 표기(15~300초)라 남긴다(에뮬레이터 QA).
    return re.sub(r"(?<!\d)~|~(?!\d)|\\,", " ", s)


def postprocess(out: dict) -> dict:
    """ops config 3장. 원본 응답은 따로 보관하므로 여기서는 저장용 사본을 만든다."""
    out = json.loads(json.dumps(out))
    for k in KO_FIELDS:
        out[k] = latex_display(out[k])
    for k in out["key_points"]:
        k["claim_ko"] = latex_display(k["claim_ko"])
    for t in out["sentence_translations"]:
        t["translation_ko"] = latex_display(t["translation_ko"])
    for g in out["glossary"]:
        g["definition_ko"] = latex_display(g["definition_ko"])
        g["context_ko"] = latex_display(g["context_ko"])
    tags = [t if t in ALLOWED_TOPICS else "other" for t in out["topic_tags"]]
    out["topic_tags"] = list(dict.fromkeys(tags))
    return out


def highlights(glossary: list[dict], sentences: list[dict]) -> list[bool]:
    """8.4: 지정 문장(kind=text) 원문에 표기 그대로 있고, 정의가 있고 한자·가나가 없고, 같은 표기 중복이 아닐 때."""
    by_id = {s["sentence_id"]: s for s in sentences}
    seen, result = set(), []
    for g in glossary:
        in_source = any(
            by_id.get(i, {}).get("kind") == "text" and g["term"] in by_id[i]["text"] for i in g["sentence_ids"]
        )
        ok = in_source and g["definition_ko"].strip() != "" and not FOREIGN.search(g["definition_ko"]) and g["term"] not in seen
        seen.add(g["term"])
        result.append(ok)
    return result
