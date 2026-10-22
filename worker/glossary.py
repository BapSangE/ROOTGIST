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
                                   "human_reviewer": c.get("human_reviewer")}], "sense_id")
        db.upsert("term_aliases", [{"alias_id": f"ALIAS-cand-{h}", "sense_id": sid, "surface_form": c["surface_form"],
                                    "normalized_form": c["normalized_form"], "relation_type": "canonical_name",
                                    "review_status": "approved", "auto_match_allowed": True}], "alias_id")
        db.update("term_candidates", {"sense_id": sid}, normalized_form=c["normalized_form"])
    return len(ready)


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


def draft_korean(db: Db, api_key: str, limit: int = 200, batch: int = 40) -> int:
    """초안이 없는 대기 후보에 한국어 대응어 초안을 채운다. 검토자는 승인 또는 수정만 한다."""
    from . import llm

    todo = db.select("term_candidates", f"review_status=eq.pending&canonical_ko_draft=is.null"
                                        f"&select=normalized_form,surface_form,definition_ko&order=seen_count.desc&limit={limit}")
    done = 0
    for i in range(0, len(todo), batch):
        part = todo[i:i + batch]
        terms = [c["surface_form"] for c in part]
        payload = [{"term": c["surface_form"], "definition_ko": c["definition_ko"]} for c in part]
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


def sync(db: Db, api_key: str | None = None):
    promoted = promote_candidates(db)
    aliases = db.select_all("term_aliases", "select=sense_id,surface_form&order=alias_id")
    rows = db.select_all("paper_glossary", "sense_id=is.null&select=paper_id,idx,term,definition_ko&order=paper_id,idx")
    links, candidates = plan_links(rows, aliases)
    for pid, idx, sid in links:
        db.update("paper_glossary", {"sense_id": sid}, paper_id=pid, idx=idx)
    # 후보는 표기 하나당 한 행, 복수형은 단수형 후보로 합친다. seen_count는 아직 연결 안 된 논문 용어 중
    # 같은 후보로 묶이는 수(다시 돌려도 같은 값). 검토 상태는 덮어쓰지 않는다.
    known = {c["normalized_form"]: c for c in db.select_all(
        "term_candidates", "select=normalized_form,review_status,canonical_ko_draft,draft_model,sense_id&order=normalized_form")}
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
    candidates = merged
    drafted = draft_korean(db, api_key) if api_key else 0
    print(f"용어: 후보→사전 {promoted}, 새 연결 {len(links)}, 사전에 없는 표기 {len(candidates)}, 대응어 초안 {drafted}")


if __name__ == "__main__":
    from .run import setting

    db = Db(setting("SUPABASE_URL"), setting("SUPABASE_SERVICE_ROLE_KEY"))
    key = setting("NVIDIA_API_KEY", "nvidia_key")
    if sys.argv[1:2] == ["import"]:
        import_dictionary(db, Path(sys.argv[2]))
        sync(db, key)
    elif sys.argv[1:2] == ["sync"]:
        sync(db, key)
    else:
        sys.exit(__doc__)
