"""검증된 출력 → 앱이 읽는 JSON 3종 (HANDOFF 4.3). Supabase 저장(4.4)은 M4 후반에 이 모양 그대로 옮긴다."""
import json
from collections import Counter
from pathlib import Path

from . import acronym
from .validate import highlights


def paper_detail(p: dict, sentences: list[dict], out: dict | None) -> dict:
    """③ getPaper. out이 None이면 해설 준비 중(pending): 다음 배치에서 다시 만든다."""
    base = {
        "paper_id": p["paper_id"],
        "title_en": p["title_en"],
        "authors": p["authors"],
        "org_name": p["org_name"],
        "published_at": p["published_at"][:10],
        "hf_url": f"https://huggingface.co/papers/{p['paper_id']}",
        "arxiv_url": f"https://arxiv.org/abs/{p['paper_id']}",
    }
    plain = [{"sentence_id": s["sentence_id"], "kind": s["kind"], "text": s["text"]} for s in sentences]
    if out is None:
        return {**base, "title_ko": None, "topic_primary": None, "topic_secondary": None, "ai_status": "pending",
                "summary_ko": None, "key_points": [], "sentences": [{**s, "translation_ko": None} for s in plain],
                "glossary": []}
    tr = {t["sentence_id"]: t["translation_ko"] for t in out["sentence_translations"]}
    tags = out["topic_tags"]
    return {
        **base,
        "title_ko": out["title_ko"],
        "topic_primary": tags[0],
        "topic_secondary": tags[1] if len(tags) > 1 else None,
        "ai_status": "ready",
        "summary_ko": out["summary_ko"],
        "key_points": [{"claim_ko": k["claim_ko"], "evidence_sentence_ids": k["evidence_sentence_ids"]} for k in out["key_points"]],
        "sentences": [{**s, "translation_ko": tr.get(s["sentence_id"])} for s in plain],
        "glossary": [
            {"term": g["term"], "definition_ko": g["definition_ko"], "context_ko": g["context_ko"],
             "sentence_ids": g["sentence_ids"], "highlight": h,
             # 약어면 초록이 직접 풀어 쓴 정식 명칭(없으면 빈 문자열 = 확인했지만 없음)
             "full_form_en": (acronym.from_abstract(g["term"], p["abstract_en"]) or "") if acronym.is_acronym(g["term"]) else None}
            for g, h in zip(out["glossary"], highlights(out["glossary"], sentences))
        ],
        "limitations": out["limitations"],  # MVP 화면 미사용, 저장만
    }


def featured(details: list[dict]) -> str | None:
    """G9: 순위대로 ready이고 근거 있는 핵심 내용이 1개 이상인 첫 논문."""
    return next((d["paper_id"] for d in details if d["ai_status"] == "ready" and d["key_points"]), None)


def primary_topic(details: list[dict], featured_id: str | None) -> str | None:
    """G10: 그날 노출 논문 topic_primary 최빈값, 동률이면 주요 연구의 분야."""
    counts = Counter(d["topic_primary"] for d in details if d["topic_primary"])
    if not counts:
        return None
    top = max(counts.values())
    tied = [t for t, c in counts.items() if c == top]
    fav = next((d["topic_primary"] for d in details if d["paper_id"] == featured_id), None)
    return fav if fav in tied else tied[0]


def digest(digest_date: str, last_success_at: str, ranked: list[dict], details: list[dict]) -> dict:
    """② getDigest. ranked·details는 같은 순위 순서."""
    fid = featured(details)
    return {
        "digest_date": digest_date,
        "status": "published" if details else "empty",
        "last_success_at": last_success_at,
        "featured_paper_id": fid,
        "papers": [
            {
                "paper_id": d["paper_id"], "rank": i, "title_en": d["title_en"], "title_ko": d["title_ko"],
                "first_author": d["authors"][0] if d["authors"] else "", "author_count": len(d["authors"]),
                "published_at": d["published_at"], "topic_primary": d["topic_primary"],
                "topic_secondary": d["topic_secondary"],
                "key_points_preview": [k["claim_ko"] for k in d["key_points"]],
                "ai_status": d["ai_status"], "upvotes": p["upvotes"],
            }
            for i, (p, d) in enumerate(zip(ranked, details), start=1)
        ],
    }


def write(out_dir: Path, entry: dict, day: dict | None, details: list[dict]):
    """① digests.json에 그날 항목을 넣거나 바꾸고(최신순), ②·③ 파일을 쓴다."""
    (out_dir / "digests").mkdir(parents=True, exist_ok=True)
    (out_dir / "papers").mkdir(parents=True, exist_ok=True)
    index_path = out_dir / "digests.json"
    index = json.loads(index_path.read_text(encoding="utf-8")) if index_path.exists() else {"digests": [], "next_cursor": None}
    index["digests"] = sorted(
        [d for d in index["digests"] if d["digest_date"] != entry["digest_date"]] + [entry],
        key=lambda d: d["digest_date"], reverse=True,
    )
    dump = lambda path, obj: path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
    dump(index_path, index)
    if day is not None:
        dump(out_dir / "digests" / f"{entry['digest_date']}.json", day)
    for d in details:
        dump(out_dir / "papers" / f"{d['paper_id']}.json", d)
