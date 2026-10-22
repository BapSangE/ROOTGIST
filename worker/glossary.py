"""용어 사전 적재·논문 용어 연결·자체 축적.

    python -m worker.glossary import <연구 레포>/data/terms_ext/dictionary_review_v0.1
    python -m worker.glossary sync     # 승인된 후보를 사전으로 옮기고, 연결 안 된 논문 용어를 연결·후보로 쌓음

배치(run.py)는 끝날 때 sync를 부른다. 사전 데이터는 공개 레포에 넣지 않고 Supabase에만 둔다.
"""
import csv
import hashlib
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

from .db import Db


def normalize(s: str) -> str:
    """검색용 표기: 소문자, 하이픈·연속 공백 → 공백 하나."""
    return re.sub(r"\s+", " ", s.lower().replace("-", " ")).strip()


def variants(s: str) -> set[str]:
    """복수형만 단수로 하나 더 본다(backbones → backbone). 어간 추출은 하지 않는다."""
    n = normalize(s)
    out = {n}
    if n.endswith("ies"):
        out.add(n[:-3] + "y")
    elif n.endswith("s") and not n.endswith("ss"):
        out.add(n[:-1])
    return out


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
    """승인되고 한국어 대응어가 채워진 후보 → 사전(사람 승인 의미, definition_kind=paper_glossary)."""
    ready = db.select("term_candidates", "review_status=eq.approved&sense_id=is.null&canonical_ko=not.is.null&select=*")
    for c in ready:
        h = _hash(c["normalized_form"])
        tid, sid = f"T-cand-{h}", f"SENSE-cand-{h}"
        db.upsert("terms", [{"term_id": tid, "canonical_en": c["surface_form"], "canonical_ko": c["canonical_ko"],
                             "review_status": "approved"}], "term_id")
        db.upsert("term_senses", [{"sense_id": sid, "term_id": tid, "canonical_ko": c["canonical_ko"],
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


def sync(db: Db):
    promoted = promote_candidates(db)
    aliases = db.select_all("term_aliases", "select=sense_id,surface_form&order=alias_id")
    rows = db.select_all("paper_glossary", "sense_id=is.null&select=paper_id,idx,term,definition_ko&order=paper_id,idx")
    links, candidates = plan_links(rows, aliases)
    for pid, idx, sid in links:
        db.update("paper_glossary", {"sense_id": sid}, paper_id=pid, idx=idx)
    # 후보는 정규화 표기 하나당 한 행. seen_count는 아직 연결 안 된 논문 용어 중 같은 표기 수(다시 돌려도 같은 값).
    # 검토 상태는 덮어쓰지 않는다. 일괄 upsert는 모든 행의 키가 같아야 해서 기존 값을 그대로 다시 보낸다.
    known = {c["normalized_form"]: c["review_status"]
             for c in db.select_all("term_candidates", "select=normalized_form,review_status&order=normalized_form")}
    now = datetime.now(timezone.utc).isoformat()
    db.upsert("term_candidates", [
        {"normalized_form": n, "surface_form": g[0]["term"], "definition_ko": g[0]["definition_ko"],
         "first_paper_id": g[0]["paper_id"], "seen_count": len(g), "last_seen_at": now,
         "review_status": known.get(n, "pending")}
        for n, g in candidates.items()
    ], "normalized_form")
    print(f"용어: 후보→사전 {promoted}, 새 연결 {len(links)}, 사전에 없는 표기 {len(candidates)}")


if __name__ == "__main__":
    from .run import setting

    db = Db(setting("SUPABASE_URL"), setting("SUPABASE_SERVICE_ROLE_KEY"))
    if sys.argv[1:2] == ["import"]:
        import_dictionary(db, Path(sys.argv[2]))
        sync(db)
    elif sys.argv[1:2] == ["sync"]:
        sync(db)
    else:
        sys.exit(__doc__)
