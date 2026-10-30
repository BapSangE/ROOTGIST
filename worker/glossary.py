"""용어 사전 적재·논문 용어 연결·자체 축적.

    python -m worker.glossary import <연구 레포>/data/terms_ext/dictionary_review_v0.1
    python -m worker.glossary sync     # 승인된 후보를 사전으로 옮기고, 연결 안 된 논문 용어를 연결·후보로 쌓음

배치(run.py)는 끝날 때 sync를 부른다. 사전 데이터는 공개 레포에 넣지 않고 Supabase에만 둔다.
"""
import csv
import hashlib
import json
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

from . import acronym
from .db import Db


def normalize(s: str) -> str:
    """검색용 표기: 소문자, 하이픈·연속 공백 → 공백 하나."""
    return re.sub(r"\s+", " ", s.lower().replace("-", " ")).strip()


def singular(n: str) -> str:
    """정규화 표기의 단수 후보(chunks → chunk). bias처럼 틀릴 수 있으니 단독으로 쓰지 말고 실제 표기와 대조한다."""
    if n.endswith("ies"):
        return n[:-3] + "y"
    if n.endswith("s") and not n.endswith("ss"):
        return n[:-1]
    return n


def variants(s: str) -> set[str]:
    """복수형만 단수로 하나 더 본다(backbones → backbone). 어간 추출은 하지 않는다."""
    n = normalize(s)
    return {n, singular(n)}


def merge_plurals(forms: set[str]) -> dict[str, str]:
    """표기 → 후보 키. 단수 표기가 실제로 있을 때만 복수 표기를 그쪽으로 합친다(bias는 bia가 없으니 그대로)."""
    return {n: singular(n) if singular(n) != n and singular(n) in forms else n for n in forms}


def _null(v: str):
    return None if v in ("\\N", "") else v


def import_dictionary(db: Db, folder: Path):
    """연구 레포 dictionary_review_v0.1 CSV → terms·term_senses·term_aliases. 다시 돌려도 같은 결과(upsert)."""
    def rows(name):
        with (folder / name).open(encoding="utf-8", newline="") as f:
            return list(csv.DictReader(f))

    def chunks(items, n=500):
        for i in range(0, len(items), n):
            yield items[i:i + n]

    terms = [{"term_id": r["term_id"], "canonical_en": r["canonical_en"], "canonical_ko": _null(r["canonical_ko"]),
              "review_status": r["review_status"]} for r in rows("terms.csv")]
    senses = [{"sense_id": r["sense_id"], "term_id": r["term_id"], "canonical_ko": _null(r["canonical_ko"]),
               "definition_ko": _null(r["definition_ko"]), "scope": _null(r["scope"]), "domain": _null(r["domain"]),
               "definition_kind": r["definition_kind"], "ai_review_status": r["ai_review_status"],
               "review_status": r["review_status"], "human_reviewer": _null(r["human_reviewer"]),
               "source_media_review_required": r["source_media_review_required"] == "true",
               "review_note_ko": _null(r["review_note_ko"])} for r in rows("term_senses.csv")]
    aliases = [{"alias_id": r["alias_id"], "sense_id": r["sense_id"], "surface_form": r["surface_form"],
                "normalized_form": _null(r["normalized_form"]), "relation_type": r["relation_type"],
                "review_status": r["review_status"], "auto_match_allowed": r["auto_match_allowed"] == "true"}
               for r in rows("term_aliases.csv")]
    for table, items, key in (("terms", terms, "term_id"), ("term_senses", senses, "sense_id"), ("term_aliases", aliases, "alias_id")):
        for part in chunks(items):
            db.upsert(table, part, key)
        print(f"{table}: {len(items)}")


def _hash(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()[:16]


def promote_candidates(db: Db) -> int:
    """승인된 후보 → 사전(사람 승인 의미, definition_kind=paper_glossary).
    한국어 대응어는 검토자가 쓴 canonical_ko, 없으면 AI 초안(승인했다는 건 초안을 채택했다는 뜻)."""
    ready = db.select("term_candidates", "review_status=eq.approved&sense_id=is.null"
                                         "&or=(canonical_ko.not.is.null,canonical_ko_draft.not.is.null)&select=*")
    for c in ready:
        h = _hash(c["normalized_form"])
        tid, sid = f"T-cand-{h}", f"SENSE-cand-{h}"
        ko = c["canonical_ko"] or c["canonical_ko_draft"]
        db.upsert("terms", [{"term_id": tid, "canonical_en": c["surface_form"], "canonical_ko": ko,
                             "review_status": "approved"}], "term_id")
        db.upsert("term_senses", [{"sense_id": sid, "term_id": tid, "canonical_ko": ko,
                                   "definition_ko": c["definition_ko"], "definition_kind": "paper_glossary",
                                   "ai_review_status": "first_pass_complete", "review_status": "approved",
                                   "human_reviewer": c.get("human_reviewer"),
                                   # 정식 명칭도 같은 규칙: 검토자가 쓴 값, 없으면 초안(빈 문자열 = 없음)
                                   "full_form_en": c.get("full_form_en") or c.get("full_form_en_draft") or None}],
                  "sense_id")
        db.upsert("term_aliases", [{"alias_id": f"ALIAS-cand-{h}", "sense_id": sid, "surface_form": c["surface_form"],
                                    "normalized_form": c["normalized_form"], "relation_type": "canonical_name",
                                    "review_status": "approved", "auto_match_allowed": True}], "alias_id")
        db.update("term_candidates", {"sense_id": sid}, normalized_form=c["normalized_form"])
    return len(ready)


def preferred_terms(db: Db) -> list[tuple[str, str, str]]:
    """사람이 승인한 의미의 (정규화 별칭, 별칭 원문, 한국어 표기). 프롬프트 v0.6의 preferred_terms 재료."""
    senses = {s["sense_id"]: s["canonical_ko"] for s in db.select_all(
        "term_senses", "review_status=eq.approved&canonical_ko=not.is.null&select=sense_id,canonical_ko&order=sense_id")}
    if not senses:
        return []
    aliases = db.select_all("term_aliases", "select=sense_id,surface_form&order=alias_id")
    return [(normalize(a["surface_form"]), a["surface_form"], senses[a["sense_id"]]) for a in aliases if a["sense_id"] in senses]


def terms_in(preferred: list[tuple[str, str, str]], abstract: str) -> list[dict]:
    """초록에 단어 단위로 나오는 승인 표기만(복수형 포함). 같은 영문이 여러 번 걸리면 하나만."""
    text = normalize(abstract)
    out = {}
    for n, surface, ko in preferred:
        if re.search(rf"(?<![a-z0-9]){re.escape(n)}s?(?![a-z0-9])", text):
            out.setdefault(n, {"term": surface, "ko": ko})
    return list(out.values())


def plan_links(glossary_rows: list[dict], aliases: list[dict]):
    """연결 안 된 논문 용어 → ([(paper_id, idx, sense_id)], {정규화 표기: [행...]} 후보).
    표기가 한 의미로만 이어질 때만 연결한다. 여러 의미면(agent 등) 연결도 후보도 만들지 않고 둔다.
    ponytail: 사전 별칭은 모두 auto_match_allowed=false(사람 미승인)지만, 내부 테스트 결정(2026-10-22)에 따라
    정규화 일치 단일 의미는 연결한다. 외부 공개 전에는 auto_match_allowed 별칭만 쓰도록 좁힌다."""
    index = defaultdict(set)
    for a in aliases:
        for v in variants(a["surface_form"]):
            index[v].add(a["sense_id"])
    links, candidates = [], defaultdict(list)
    for g in glossary_rows:
        found = set().union(*(index.get(v, set()) for v in variants(g["term"])))
        if len(found) == 1:
            links.append((g["paper_id"], g["idx"], found.pop()))
        elif not found:
            candidates[normalize(g["term"])].append(g)
    return links, candidates


DRAFT_RULES = """AI·머신러닝 논문 용어의 한국어 대응어를 제안한다. 아래 규칙을 지킨다.
- 한국 AI·머신러닝 커뮤니티, 논문, 교재에서 실제로 많이 쓰는 표기를 고른다. 음차가 자리 잡은 말은 음차(예: 트랜스포머, 백본), 번역어가 자리 잡은 말은 번역어(예: 강화 학습, 지식 증류)로 쓴다.
- 약어와 고유명(모델·데이터셋·벤치마크·방법 이름)은 원문 그대로 둔다(예: LoRA, GPT-4, MMLU).
- 대응어만 쓴다. 설명, 따옴표, 괄호 속 원어 병기를 붙이지 않는다.
- 한글·영문·숫자·공백·하이픈만 쓴다. 한자와 가나는 쓰지 않는다.
- 입력의 모든 term을 입력 순서대로 정확히 한 번씩, term 값은 한 글자도 바꾸지 않고 그대로 복사한다.
- 확실하지 않으면 가장 무난한 표기를 고르고, 새 용어를 지어내지 않는다.
- translation은 이 용어가 나온 논문 문장의 한국어 번역이다. 거기서 이 용어를 옮긴 표기가 분야에서 자연스러우면 그 표기를 그대로 쓴다(번역문과 표기가 같아야 화면에서 강조된다).
출력은 JSON 하나만: {"items": [{"term": "...", "canonical_ko": "..."}]}"""


def check_drafts(out, terms: list[str]) -> list[str]:
    """LLM 초안 검증: 입력 용어와 순서·표기 일치, 빈 값·긴 값·외국 문자 없음."""
    items = out.get("items") if isinstance(out, dict) else None
    if not isinstance(items, list) or [i.get("term") for i in items] != terms:
        return ["terms: 입력 용어와 순서·표기가 다름"]
    from .validate import FOREIGN

    bad = [i["term"] for i in items
           if not isinstance(i.get("canonical_ko"), str) or not 0 < len(i["canonical_ko"].strip()) <= 60
           or "\n" in i["canonical_ko"] or FOREIGN.search(i["canonical_ko"])]
    return [f"ko: {bad}"] if bad else []


def _translation_of(db: Db, c: dict) -> str:
    """후보가 처음 나온 논문에서 그 용어가 있는 문장들의 한국어 번역(초안을 번역 표기에 맞추기 위한 문맥)."""
    if not c.get("first_paper_id"):
        return ""
    rows = db.select("paper_glossary", f"paper_id=eq.{c['first_paper_id']}&select=term,sentence_ids")
    row = next((r for r in rows if c["normalized_form"] in variants(r["term"])), None)
    if not row:
        return ""
    tr = {t["sentence_id"]: t["translation_ko"] for t in db.select(
        "paper_translations", f"paper_id=eq.{c['first_paper_id']}&select=sentence_id,translation_ko")}
    return " ".join(tr[s] for s in row["sentence_ids"] if s in tr)


def draft_korean(db: Db, api_key: str, limit: int = 200, batch: int = 40) -> int:
    """초안이 없는 대기 후보에 한국어 대응어 초안을 채운다. 검토자는 승인 또는 수정만 한다."""
    from . import llm

    todo = db.select("term_candidates", f"review_status=eq.pending&canonical_ko_draft=is.null"
                                        f"&select=normalized_form,surface_form,definition_ko,first_paper_id&order=seen_count.desc&limit={limit}")
    done = 0
    for i in range(0, len(todo), batch):
        part = todo[i:i + batch]
        terms = [c["surface_form"] for c in part]
        payload = [{"term": c["surface_form"], "definition_ko": c["definition_ko"], "translation": _translation_of(db, c)} for c in part]
        messages = [{"role": "system", "content": DRAFT_RULES},
                    {"role": "user", "content": json.dumps(payload, ensure_ascii=False)}]
        out, model = llm.generate(api_key, messages, lambda o: check_drafts(o, terms), lambda r: None)
        if out is None:
            print(f"  대응어 초안 실패({len(part)}개), 다음 배치에서 다시")
            continue
        for c, item in zip(part, out["items"]):
            db.update("term_candidates", {"canonical_ko_draft": item["canonical_ko"].strip(), "draft_model": model},
                      normalized_form=c["normalized_form"])
        done += len(part)
    return done


FULL_FORM_RULES = """AI·머신러닝 약어의 영문 정식 명칭을 알려 준다.
- 분야에서 널리 쓰이고 뜻이 하나로 정해진 약어만 정식 명칭을 쓴다(예: SLAM → Simultaneous Localization and Mapping).
- 모델·데이터셋·벤치마크 이름처럼 정식 명칭이 따로 없거나, 여러 뜻이 가능하거나, 확실하지 않으면 null.
- 새 명칭을 지어내지 않는다. 설명 없이 명칭만 쓴다.
- 입력의 모든 term을 입력 순서대로 정확히 한 번씩, term 값은 그대로 복사한다.
출력은 JSON 하나만: {"items": [{"term": "...", "full_form_en": "..." 또는 null}]}"""


def fill_paper_full_forms(db: Db) -> int:
    """이미 저장된 논문 용어 중 약어의 정식 명칭을 초록에서 채운다(예전 배치분). 없으면 빈 문자열로 표시해 다시 보지 않는다."""
    rows = [r for r in db.select_all("paper_glossary", "full_form_en=is.null&select=paper_id,idx,term&order=paper_id,idx")
            if acronym.is_acronym(r["term"])]
    abstracts = {}
    for r in rows:
        if r["paper_id"] not in abstracts:
            abstracts[r["paper_id"]] = db.select("papers", f"paper_id=eq.{r['paper_id']}&select=abstract_en")[0]["abstract_en"]
        full = acronym.from_abstract(r["term"], abstracts[r["paper_id"]]) or ""
        db.update("paper_glossary", {"full_form_en": full}, paper_id=r["paper_id"], idx=r["idx"])
    return len(rows)


def draft_full_forms(db: Db, api_key: str | None) -> int:
    """약어 후보의 정식 명칭 초안: 처음 본 논문 초록에 풀이가 있으면 그것, 없으면 LLM(글자 대조 통과만). 없으면 빈 문자열."""
    todo = [c for c in db.select_all("term_candidates", "review_status=eq.pending&full_form_en_draft=is.null"
                                                        "&select=normalized_form,surface_form,definition_ko,first_paper_id&order=normalized_form")
            if acronym.is_acronym(c["surface_form"])]
    ask = []
    for c in todo:
        abstract = db.select("papers", f"paper_id=eq.{c['first_paper_id']}&select=abstract_en")[0]["abstract_en"]
        if full := acronym.from_abstract(c["surface_form"], abstract):
            db.update("term_candidates", {"full_form_en_draft": full}, normalized_form=c["normalized_form"])
        else:
            ask.append(c)
    if ask and api_key:
        from . import llm

        terms = [c["surface_form"] for c in ask]
        messages = [{"role": "system", "content": FULL_FORM_RULES},
                    {"role": "user", "content": json.dumps([{"term": c["surface_form"], "definition_ko": c["definition_ko"]} for c in ask], ensure_ascii=False)}]
        out, _ = llm.generate(api_key, messages,
                              lambda o: [] if isinstance(o, dict) and [i.get("term") for i in o.get("items", [])] == terms else ["terms"],
                              lambda r: None)
        for c, item in zip(ask, (out or {}).get("items", [])):
            full = item.get("full_form_en") if isinstance(item.get("full_form_en"), str) else ""
            # 약어 글자와 안 맞는 명칭은 버린다(지어낸 명칭 방지)
            db.update("term_candidates", {"full_form_en_draft": full if full and acronym.matches(c["surface_form"], full) else ""},
                      normalized_form=c["normalized_form"])
    return len(todo)


SPAN_RULES = """한국어 번역문에서 영문 용어를 옮긴 부분을 찾는다.
- 각 항목의 translations 중에서 term(영문 용어)을 옮긴 한국어 부분을 번역문에 쓰인 글자 그대로 복사한다. 띄어쓰기도 그대로.
- 뒤에 붙은 조사(을·를·이·가·은·는·의·에·로 등)는 뺀다. 괄호 속 원어 병기도 뺀다.
- 번역문에 해당 부분이 없거나 확실하지 않으면 null. 번역문에 없는 표현을 만들지 않는다.
- 입력의 모든 term을 입력 순서대로 정확히 한 번씩, term 값은 그대로 복사한다.
출력은 JSON 하나만: {"items": [{"term": "...", "span": "..." 또는 null}]}"""


def _strip_paren(ko: str) -> str:
    return re.sub(r"\s*\(.*\)$", "", ko).strip()


def _show_ai(db: Db) -> bool:
    return (db.select("app_config", "key=eq.show_ai_reviewed_terms&select=value") or [{}])[0].get("value") == "true"


def _shown(s: dict, show_ai: bool) -> bool:
    """앱에 보이는 의미인가(DB display_term_ko와 같은 규칙). 기계 번역 원문 정의는 승인해도 보이지 않는다."""
    return s["definition_kind"] != "source_machine_translation_verbatim" and (
        s["review_status"] == "approved" or (show_ai and s["ai_review_status"] == "first_pass_complete" and s["review_status"] == "pending"))


SPAN_PAPERS = 40  # 한 번에 LLM으로 표기를 찾는 논문 수. 지난 논문은 며칠에 걸쳐 채운다(배치 시간 초과 방지)


def align_spans(db: Db, api_key: str | None) -> int:
    """논문 용어마다 번역문 속 실제 표기(ko_span)를 채운다(G2 하이라이트 위치). 사전에 없는 용어도 채운다.
    사전 대응어가 번역문에 그대로 있으면 그것, 영문 표기가 번역문에 남아 있으면(SFT·VLM) 그것,
    없으면 LLM이 번역문에서 고른 부분 문자열(번역문에 실제로 있는 글자만). 못 찾으면 빈 문자열."""
    rows = db.select_all("paper_glossary", "ko_span=is.null&select=paper_id,idx,term,sentence_ids,sense_id&order=paper_id,idx")
    if not rows:
        return 0
    flag = _show_ai(db)
    ids = sorted({r["sense_id"] for r in rows if r["sense_id"]})
    senses = {}
    for i in range(0, len(ids), 100):
        for s in db.select("term_senses", f"sense_id=in.({','.join(ids[i:i + 100])})&select=sense_id,canonical_ko,definition_kind,review_status,ai_review_status"):
            senses[s["sense_id"]] = _strip_paren(s["canonical_ko"]) if _shown(s, flag) and s["canonical_ko"] else None
    by_paper = defaultdict(list)
    for r in rows:
        by_paper[r["paper_id"]].append(r)
    asked = 0
    for pid, prs in by_paper.items():
        tr = {t["sentence_id"]: t["translation_ko"] for t in db.select("paper_translations", f"paper_id=eq.{pid}&select=sentence_id,translation_ko")}
        ask = []
        for r in prs:
            ko, texts = senses.get(r["sense_id"]), [tr[s] for s in r["sentence_ids"] if s in tr and tr[s]]
            found = next((c for c in (ko, r["term"]) if c and any(c in t for t in texts)), None)
            if found:
                db.update("paper_glossary", {"ko_span": found}, paper_id=pid, idx=r["idx"])
            elif not texts:  # 번역이 없는 논문: 찾을 곳이 없다
                db.update("paper_glossary", {"ko_span": ""}, paper_id=pid, idx=r["idx"])
            else:
                ask.append((r, texts))
        if not ask or not api_key or asked >= SPAN_PAPERS:
            continue
        asked += 1
        from . import llm

        terms = [r["term"] for r, _ in ask]
        payload = [{"term": r["term"], "translations": texts} for r, texts in ask]
        messages = [{"role": "system", "content": SPAN_RULES}, {"role": "user", "content": json.dumps(payload, ensure_ascii=False)}]
        out, _ = llm.generate(api_key, messages,
                              lambda o: [] if isinstance(o, dict) and [i.get("term") for i in o.get("items", [])] == terms else ["terms"],
                              lambda r: None)
        if out is None:
            continue  # 호출 실패: 다음 배치에서 다시
        for (r, texts), item in zip(ask, out.get("items", [])):
            span = (item or {}).get("span")
            ok = isinstance(span, str) and span.strip() and any(span.strip() in t for t in texts)  # 번역문에 실제로 있는 글자만
            db.update("paper_glossary", {"ko_span": span.strip() if ok else ""}, paper_id=pid, idx=r["idx"])
    return len(rows)


# --- 공식 소식·모델 글의 용어 (앱 term_text.dart findTerm과 같은 규칙으로 찾는다) ---
# 사전은 논문 용어로만 자라서 소식·릴리스·모델 글(MoE·양자화·MCP …)에는 맞는 용어가 거의 없었다(실데이터 2026-10-30:
# 소식 60건 중 9건, 릴리스 0건). 소식 글에서 AI가 용어 후보와 일반 정의를 뽑아 후보 목록에 넣고, 관리자 웹에서 승인하면
# 다음 배치에 사전 의미가 되어 앱의 모든 카드에서 설명이 붙는다.
_ASCII, _HANGUL = re.compile(r"[A-Za-z0-9]"), re.compile(r"[가-힣]")
NEWS_TERM_BATCH = 15  # 한 번에 AI에 넘기는 글 수
NEWS_TERMS_PER_ITEM = 3


def find_term(text: str, label: str) -> int:
    """text에서 label이 낱말로 나오는 첫 자리(없으면 -1). 영문은 앞뒤가 영문·숫자가 아닐 때, 한글은 앞이 한글이 아닐 때만."""
    if not label:
        return -1
    at = text.find(label)
    while at >= 0:
        before = text[at - 1] if at else ""
        after = text[at + len(label)] if at + len(label) < len(text) else ""
        if not ((_ASCII.match(label[0]) and before and _ASCII.match(before))
                or (_ASCII.match(label[-1]) and after and _ASCII.match(after))
                or (_HANGUL.match(label[0]) and before and _HANGUL.match(before))):
            return at
        at = text.find(label, at + 1)
    return -1


def content_text(item: dict) -> str:
    """앱 상세 화면에 보이는 한국어 글(용어 하이라이트가 붙는 곳): 소식 요약·핵심 내용, 모델 카드 강점·한계."""
    card = item.get("card") or {}
    parts = [item.get("summary_ko"), *[p.get("text") for p in item.get("key_points") or [] if isinstance(p, dict)],
             *(card.get("strengths") or []), card.get("limitation")]
    return "\n".join(p for p in parts if isinstance(p, str) and p.strip())


NEWS_TERM_RULES = """AI 소식 앱의 한국어 글에서, 개발자 독자가 뜻을 몰라 설명이 필요할 기술 용어를 고른다. 아래 규칙을 지킨다.
- 글마다 최대 3개. 설명이 필요한 용어가 없으면 빈 목록.
- AI·머신러닝·소프트웨어 개발의 개념, 기법, 구조, 프로토콜만 고른다(예: 전문가 혼합(MoE), 양자화, 컨텍스트 창, 투기적 디코딩, MCP, 함수 호출).
- 회사·제품·모델·서비스·사람 이름(Claude, Gemini, GPT-6.1, Codex, Hugging Face), 일반 낱말(AI, 모델, 데이터, 성능, 기능), 버전 번호는 고르지 않는다.
- 개발자라면 이미 아는 넓은 낱말(context, prompt, parameter, backend, upstream, endpoint, coverage, API, SDK)은 고르지 않는다. 그 낱말이 들어간 더 구체적인 용어(context window)가 글에 있으면 그것을 고른다.
- 한 제품·게임·코드에서만 쓰는 이름이나 설정 값(device_map, tolerance 0, 함수 이름, 옵션 이름)은 고르지 않는다. 여러 글에서 다시 나올 만한 분야 용어만 고른다.
- 같은 개념을 가리키는 표기는 하나만 고른다(tool call과 tool calling 중 하나).
- ko는 글에 실제로 쓰인 표기를 한 글자도 바꾸지 않고 그대로 복사한다(괄호 속 원어는 빼도 된다). 글에 없는 표기는 쓰지 않는다. 용어의 일부만 잘라 쓰지 않는다(「서비스형 모델」을 「서비스형」으로 쓰지 않는다).
- term은 그 용어의 영문 표준 표기(약어면 약어, 예: MoE, quantization, context window).
- definition_ko는 이 글이 아니라 분야 전반의 일반 정의를 한두 문장으로, 명사형으로 끝낸다(예: 「여러 전문가 하위 신경망 중 입력마다 일부만 골라 계산하는 모델 구조.」). 한자·가나를 쓰지 않는다.
- 입력의 모든 id를 입력 순서대로 정확히 한 번씩.
출력은 JSON 하나만: {"items": [{"id": "...", "terms": [{"term": "...", "ko": "...", "definition_ko": "..."}]}]}"""


def check_news_terms(out, batch: list[tuple[str, str]]) -> list[str]:
    from .validate import FOREIGN

    items = out.get("items") if isinstance(out, dict) else None
    if not isinstance(items, list) or [i.get("id") for i in items] != [b[0] for b in batch]:
        return ["ids: 입력 글과 순서·id가 다름"]
    bad = []
    for item in items:
        for t in item.get("terms") or []:
            if not (isinstance(t, dict) and all(isinstance(t.get(k), str) and t[k].strip() for k in ("term", "ko", "definition_ko"))
                    and len(t["term"]) <= 80 and len(t["ko"]) <= 40 and len(t["definition_ko"]) <= 300
                    and not FOREIGN.search(t["ko"] + t["definition_ko"])):
                bad.append(item["id"])
    return [f"terms: {sorted(set(bad))}"] if bad else []


# AI가 규칙을 어겨도 한 번 더 거른다: 개발자가 이미 아는 넓은 낱말(첫 실행 2026-10-30에 91개 중 섞여 나온 것)
BROAD_TERMS = {"ai", "api", "sdk", "model", "data", "context", "prompt", "parameter", "backend", "frontend", "upstream",
               "downstream", "endpoint", "coverage", "performance", "feature", "token", "agent", "workflow", "benchmark",
               "inference", "training", "dataset", "framework", "library", "server", "client", "pipeline"}


def plan_news_terms(out: dict, texts: dict[str, str], skip: set[str], skip_ko: set[str] = frozenset()) -> dict[str, dict]:
    """AI가 고른 용어 → 새 후보 {정규화 표기: 행}. 글에 실제로 없는 표기(지어낸 것), 이미 사전·후보에 있는 표기는 버린다.
    같은 용어가 여러 글에 나오면 한 후보로 합치고 seen_count로 센다(처음 본 글이 문맥)."""
    found, ko_seen = {}, set(skip_ko)
    for item in out.get("items") or []:
        text = texts.get(item.get("id"), "")
        for t in (item.get("terms") or [])[:NEWS_TERMS_PER_ITEM]:
            ko = _strip_paren(t["ko"].strip())
            n = normalize(t["term"])
            if len(ko) < 2 or find_term(text, ko) < 0 or (variants(t["term"]) & skip) or n in BROAD_TERMS:
                continue
            # 같은 용어가 여러 글에 나오면 센다. 영문은 달라도 한국어 표기가 같으면(tool call·tool calling → 도구 호출) 같은 후보로
            same = found.get(n) or next((r for r in found.values() if r["canonical_ko_draft"] == ko), None)
            if same:
                same["seen_count"] += 1
                continue
            if ko in ko_seen:  # 이미 있는 후보·사전 의미와 표기가 같다
                continue
            ko_seen.add(ko)
            line = next(l for l in text.split("\n") if find_term(l, ko) >= 0)
            found[n] = {"normalized_form": n, "surface_form": t["term"].strip(), "definition_ko": t["definition_ko"].strip(),
                        "canonical_ko_draft": ko, "seen_count": 1, "source": "news", "first_news_id": item["id"],
                        "context_ko": line[:300], "review_status": "pending"}
    return found


def news_candidates(db: Db, contents: list[dict], api_key: str, seen: dict, log=print) -> int:
    """새 소식·모델 글에서 용어 후보를 뽑아 term_candidates에 넣는다(검토 대기). seen = 이미 본 글 id(다시 묻지 않는다).
    이미 앱에 보이는 사전 의미의 표기나 있는 후보(승인·반려 포함)는 건너뛴다. 검수한 후보는 건드리지 않는다."""
    from . import llm

    texts = {c["id"]: content_text(c) for c in contents if c["id"] not in seen}
    texts = {k: v for k, v in texts.items() if v}
    if not texts:
        return 0
    flag = _show_ai(db)
    senses = db.select_all("term_senses", "select=sense_id,canonical_ko,definition_kind,review_status,ai_review_status&order=sense_id")
    shown = {s["sense_id"] for s in senses if _shown(s, flag)}
    skip = {v for a in db.select_all("term_aliases", "select=sense_id,surface_form&order=alias_id")
            if a["sense_id"] in shown for v in variants(a["surface_form"])}
    cands = db.select_all("term_candidates", "select=normalized_form,canonical_ko,canonical_ko_draft&order=normalized_form")
    skip |= {c["normalized_form"] for c in cands}
    skip_ko = {_strip_paren(k) for c in cands for k in (c.get("canonical_ko"), c.get("canonical_ko_draft")) if k}
    skip_ko |= {_strip_paren(s["canonical_ko"]) for s in senses if s["sense_id"] in shown and s.get("canonical_ko")}
    ids, added = list(texts), {}
    model = None
    for i in range(0, len(ids), NEWS_TERM_BATCH):
        batch = [(k, texts[k]) for k in ids[i:i + NEWS_TERM_BATCH]]
        messages = [{"role": "system", "content": NEWS_TERM_RULES},
                    {"role": "user", "content": json.dumps([{"id": k, "text": v} for k, v in batch], ensure_ascii=False)}]
        out, model = llm.generate(api_key, messages, lambda o: check_news_terms(o, batch), lambda r: None)
        if out is None:
            log(f"  소식 용어 후보 실패({len(batch)}개 글), 다음 배치에서 다시")
            continue
        for n, row in plan_news_terms(out, texts, skip | set(added), skip_ko | {r["canonical_ko_draft"] for r in added.values()}).items():
            added[n] = {**row, "draft_model": model}
        for k, _ in batch:
            seen[k] = True
    now = datetime.now(timezone.utc).isoformat()
    # 새 표기만 넣는다(있는 후보는 위에서 건너뛰었다). 같은 밤에 논문 쪽이 먼저 같은 후보를 만들었으면 그대로 둔다.
    if added:
        db.insert_ignore("term_candidates", [{**r, "last_seen_at": now} for r in added.values()], "normalized_form")
    return len(added)


def sync(db: Db, api_key: str | None = None):
    promoted = promote_candidates(db)
    fill_paper_full_forms(db)
    aliases = db.select_all("term_aliases", "select=sense_id,surface_form&order=alias_id")
    rows = db.select_all("paper_glossary", "sense_id=is.null&select=paper_id,idx,term,definition_ko&order=paper_id,idx")
    links, candidates = plan_links(rows, aliases)
    for pid, idx, sid in links:
        db.update("paper_glossary", {"sense_id": sid}, paper_id=pid, idx=idx)
    # 후보는 표기 하나당 한 행, 복수형은 단수형 후보로 합친다. seen_count는 아직 연결 안 된 논문 용어 중
    # 같은 후보로 묶이는 수(다시 돌려도 같은 값). 검토 상태는 덮어쓰지 않는다.
    known = {c["normalized_form"]: c for c in db.select_all(
        "term_candidates", "select=normalized_form,review_status,canonical_ko_draft,draft_model,sense_id,source&order=normalized_form")}
    key = merge_plurals(set(candidates) | set(known))
    merged = defaultdict(list)
    for n, g in candidates.items():
        merged[key[n]] += g
    # 이미 저장된 복수형 후보(대기 중)는 지우고, 초안은 단수형 후보로 옮긴다.
    carried = {}
    for n, c in known.items():
        if key[n] != n and c["review_status"] == "pending" and c["sense_id"] is None:
            if c["canonical_ko_draft"] and not (known.get(key[n]) or {}).get("canonical_ko_draft"):
                carried[key[n]] = (c["canonical_ko_draft"], c["draft_model"])
            db.delete("term_candidates", normalized_form=n)
    now = datetime.now(timezone.utc).isoformat()
    db.upsert("term_candidates", [
        {"normalized_form": n,
         # 표기는 단수형 원문이 있으면 그것(action chunks보다 action chunk)
         "surface_form": next((r["term"] for r in g if normalize(r["term"]) == n), g[0]["term"]),
         "definition_ko": g[0]["definition_ko"], "first_paper_id": g[0]["paper_id"], "seen_count": len(g),
         "last_seen_at": now, "review_status": (known.get(n) or {}).get("review_status", "pending")}
        for n, g in merged.items()
    ], "normalized_form")
    for n, (draft, model) in carried.items():
        db.update("term_candidates", {"canonical_ko_draft": draft, "draft_model": model}, normalized_form=n)
    # 해설을 다시 만들어 더 이상 어느 논문에도 없는 대기 후보는 지운다(검토 목록 정리). 승인·반려한 후보와
    # 소식 글에서 온 후보(논문에 없는 게 정상)는 남긴다.
    stale = [n for n, c in known.items()
             if n not in merged and key[n] == n and c["review_status"] == "pending" and c["sense_id"] is None
             and c.get("source", "paper") == "paper"]
    for n in stale:
        db.delete("term_candidates", normalized_form=n)
    candidates = merged
    # api_key가 없으면 LLM이 필요 없는 부분만(사전 대응어가 번역문에 그대로 있는 위치, 초록 속 약어 풀이) 한다.
    # 매일 배치는 다이제스트를 먼저 끝내고, LLM 부분은 워크플로 마지막 단계에서 따로 돌린다(무료 등급이 느려 시간 초과로 배치 전체가 끊긴 일, 2026-10-24).
    drafted = draft_korean(db, api_key) if api_key else 0
    draft_full_forms(db, api_key)
    aligned = align_spans(db, api_key)
    print(f"용어: 번역문 표기 위치 확인 {aligned}")
    print(f"용어: 후보→사전 {promoted}, 새 연결 {len(links)}, 사전에 없는 표기 {len(candidates)}, 대응어 초안 {drafted}")


if __name__ == "__main__":
    from . import llm
    from .run import setting

    db = Db(setting("SUPABASE_URL"), setting("SUPABASE_SERVICE_ROLE_KEY"))
    key = llm.api_key()
    if sys.argv[1:2] == ["import"]:
        import_dictionary(db, Path(sys.argv[2]))
        sync(db, key)
    elif sys.argv[1:2] == ["sync"]:
        sync(db, key)
    else:
        sys.exit(__doc__)
