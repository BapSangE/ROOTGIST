"""하루치 배치: 수집 → 상위 10편 선별 → 문장 분할 → LLM(auto_select) → 검증 → 후처리 → 저장.

    python -m worker.run                    # 어제(KST 기준) UTC 날짜 D 목록, 상위 10편
    python -m worker.run --date 2026-10-21  # 특정 UTC 날짜 D
    python -m worker.run --limit 1          # 1편만(짧은 확인용)

같은 날짜를 다시 돌리면 다음 날 보충(ops config 1.1, A7)으로 동작한다: 이미 노출한 편은 바꾸지 않고,
늦게 올라온 논문은 보관 목록(is_exposed=false)에만 더하고, 노출 편 중 해설 준비 중인 것만 다시 만든다.

키: 환경 변수 또는 레포 루트 .env
    NVIDIA_API_KEY(또는 nvidia_key)         필수
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  있으면 Supabase에 저장, 없으면 파일로만
출력: worker/out/ (git 제외). 실제 초록·번역이 들어 있으므로 커밋하거나 외부에 공유하지 않는다(HANDOFF 0.1, NVIDIA 시험 약관).
"""
import argparse
import json
import os
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from . import build, collect, glossary, llm, split, validate
from .db import Db

ROOT = Path(__file__).resolve().parent.parent


def setting(*names: str) -> str | None:
    """환경 변수 우선, 없으면 .env. 따옴표는 벗긴다."""
    for n in names:
        if v := os.environ.get(n):
            return v
    env = ROOT / ".env"
    if env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            k, sep, v = line.partition("=")
            if sep and k.strip() in names:
                return v.strip().strip("\"'")
    return None


def main(argv=None):
    sys.stdout.reconfigure(line_buffering=True)  # 파이프로 받아도 진행 줄이 바로 보이게
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", help="UTC 날짜 D (YYYY-MM-DD). 기본: KST 기준 어제")
    ap.add_argument("--limit", type=int, default=10, help="노출·해설 편수(기본 10)")
    ap.add_argument("--out", type=Path, default=ROOT / "worker" / "out")
    ap.add_argument("--prompt", choices=sorted(llm.PROMPTS), default=setting("ROOTGIST_PROMPT") or llm.DEFAULT_PROMPT,
                    help=f"프롬프트 버전(기본 {llm.DEFAULT_PROMPT}, 환경 변수 ROOTGIST_PROMPT로도 지정)")
    ap.add_argument("--papers", help="이 논문들만 해설을 다시 만든다(쉼표 구분). 프롬프트 비교용")
    ap.add_argument("--dry-run", action="store_true", help="Supabase에 쓰지 않는다(읽기만). 프롬프트 비교용")
    ap.add_argument("--regenerate", action="store_true",
                    help="이미 낸 날의 노출 편 해설을 모두 다시 만든다(노출·순위는 그대로). 프롬프트를 바꾼 뒤 과거분 맞추기용")
    args = ap.parse_args(argv)
    meta = {**META, "prompt_version": llm.prompt_version(args.prompt)}

    # 기본 D = KST 기준 어제. 예약 실행(KST 05:00 = UTC 20:00 전날)에서도 수동 실행에서도 같은 날을 고른다.
    kst_today = datetime.now(timezone(timedelta(hours=9))).date()
    source_date = args.date or (kst_today - timedelta(days=1)).isoformat()
    digest_date = (date.fromisoformat(source_date) + timedelta(days=1)).isoformat()  # KST 05:00 배치일 = D+1
    raw = args.out / "raw" / source_date
    raw.mkdir(parents=True, exist_ok=True)
    lock = threading.Lock()

    def log(rec: dict):  # 호출·요청 기록. API 키는 절대 넣지 않는다.
        with lock, (raw / "calls.jsonl").open("a", encoding="utf-8") as f:
            f.write(json.dumps({"at": datetime.now(timezone.utc).isoformat(), **rec}, ensure_ascii=False) + "\n")

    key = setting("NVIDIA_API_KEY", "nvidia_key") or sys.exit("NVIDIA API 키가 없습니다(NVIDIA_API_KEY 또는 .env).")
    url, secret = setting("SUPABASE_URL"), setting("SUPABASE_SERVICE_ROLE_KEY")
    db = Db(url, secret) if url and secret else None
    if db is None:
        print("Supabase 설정이 없어 파일로만 저장합니다.")

    try:
        items = collect.fetch_day(source_date, raw / "hf", log)
    except collect.CollectError as e:
        log({"stage": "collect", "error": str(e)})
        _record_delayed(db, args.out, digest_date, source_date)
        print(f"수집 실패 → {digest_date} 지연으로 기록: {e}")
        return 1

    papers = [p for p in (collect.to_paper(i) for i in items) if p]
    ordered = collect.select_top(papers, len(papers))  # 전체 순위. 상위 limit편만 노출
    by_id = {p["paper_id"]: p for p in ordered}
    prior = db.digest_papers(digest_date) if db and not args.papers else []
    prior_exposed = [r["paper_id"] for r in prior if r["is_exposed"]]
    preferred = glossary.preferred_terms(db) if db and args.prompt != "v0.5.2" else []

    if args.papers:  # 비교용: 지정한 논문만, 이미 있어도 다시 만든다
        exposed_ids = [i for i in args.papers.split(",") if i in by_id]
        late, regenerate = [], exposed_ids
        print(f"{source_date}: 지정 {len(exposed_ids)}편을 {args.prompt}로 생성")
    elif prior_exposed:  # 다음 날 보충
        exposed_ids = prior_exposed
        known = {r["paper_id"] for r in prior}
        late = [p for p in ordered if p["paper_id"] not in known]
        statuses = {r["paper_id"]: r["status"] for r in db.select(
            "paper_ai", f"paper_id=in.({','.join(exposed_ids)})&select=paper_id,status")}
        regenerate = [i for i in exposed_ids if (args.regenerate or statuses.get(i) != "ready") and i in by_id]
        print(f"{source_date}: 보충 — 새로 올라온 {len(late)}편은 보관 목록에만, 해설 다시 만들 편 {len(regenerate)}")
    else:
        exposed_ids = [p["paper_id"] for p in ordered[: args.limit]]
        late, regenerate = [], exposed_ids
        print(f"{source_date}: {len(items)}건 수집, 철회 제외 {len(papers)}건, 상위 {len(exposed_ids)}편 처리")

    def one(pid):
        p = by_id[pid]
        try:
            sentences = split.to_sentences(p["abstract_en"])
        except ValueError as e:
            log({"paper_id": pid, "stage": "split", "error": str(e)})
            return pid, build.paper_detail(p, [], None), [], None, None
        messages = llm.build_messages(p["title_en"], p["abstract_en"], sentences, args.prompt,
                                      glossary.terms_in(preferred, p["abstract_en"]))
        out, model = llm.generate(key, messages, lambda o: validate.check(o, sentences), lambda r: log({**meta, "paper_id": pid, **r}))
        print(f"  {pid}: {f'ok ({model})' if out else '실패 → 해설 준비 중'}")
        return pid, build.paper_detail(p, sentences, validate.postprocess(out) if out else None), sentences, out, model

    with ThreadPoolExecutor(max_workers=3) as pool:  # 모델당 동시 3건(ops config 1장)
        made = {r[0]: r for r in pool.map(one, regenerate)}
    # 노출 순서대로 상세를 모은다. 이번에 안 만든 편은 이미 저장된 상세를 읽는다.
    details = [made[i][1] if i in made else db.rpc("get_paper", pid=i) for i in exposed_ids]
    details = [d for d in details if d]
    if args.papers:  # 비교용은 논문 상세 파일만 남기고 끝낸다(다이제스트·DB는 그대로)
        build.write(args.out, {"digest_date": "compare", "source_date": source_date, "status": "empty"}, None, details)
        print(f"저장: {args.out}/papers (비교용, {args.prompt})")
        return 0

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    ranked = [by_id.get(d["paper_id"], {"upvotes": 0}) for d in details]
    day = build.digest(digest_date, now, ranked, details)
    entry = {"digest_date": digest_date, "source_date": source_date, "status": day["status"],
             "paper_count": len(details), "primary_topic": build.primary_topic(details, day["featured_paper_id"]),
             "last_success_at": now}
    build.write(args.out, entry, day, details)

    if db and not args.dry_run:
        _save(db, entry, ordered, prior, exposed_ids, late, made, day["featured_paper_id"], meta)
        # 새 논문 용어를 사전에 연결하고 없는 표기는 후보로 쌓는다. LLM이 필요한 초안·표기 위치는 여기서 하지 않는다
        # (워크플로 마지막 단계 `python -m worker.glossary sync`가 한다).
        glossary.sync(db, None)
    ready = sum(d["ai_status"] == "ready" for d in details)
    print(f"저장: {args.out}{' + Supabase' if db else ''} (digest {digest_date}, 해설 {ready}/{len(details)}편)")
    return 0


META = {"sentence_splitter_version": split.SPLITTER_VERSION, "glossary_mode": "auto_select",
        "schema_version": llm.SCHEMA_VERSION, "temperature": 0}


def _save(db: Db, entry, ordered, prior, exposed_ids, late, made, featured_id, meta):
    """FK 순서: papers → digests → digest_papers → 문장·해설."""
    db.upsert("papers", [
        {"paper_id": p["paper_id"], "title_en": p["title_en"], "abstract_en": p["abstract_en"],
         "abstract_sha256": llm.sha256(p["abstract_en"]), "authors": p["authors"], "org_name": p["org_name"],
         "published_at": p["published_at"], "withdrawn": False,
         "thumbnail_url": p["thumbnail_url"], "media_urls": p["media_urls"]}
        for p in ordered
    ], "paper_id")
    prev_late = (db.select("digests", f"digest_date=eq.{entry['digest_date']}&select=late_added_count") or [{}])[0]
    db.upsert("digests", [{**entry, "late_added_count": prev_late.get("late_added_count", 0) + len(late)}], "digest_date")

    if prior:  # 보충: 노출 편은 그대로 두고 주요 연구 표시만 다시 계산, 늦게 온 편은 뒤 순위로
        upvotes = {r["paper_id"]: r["upvotes_at_batch"] for r in prior}
        rows = [{"digest_date": entry["digest_date"], "paper_id": i, "rank": r + 1, "upvotes_at_batch": upvotes[i],
                 "is_exposed": True, "is_featured": i == featured_id} for r, i in enumerate(exposed_ids)]
        start = max(r["rank"] for r in prior)
        rows += [{"digest_date": entry["digest_date"], "paper_id": p["paper_id"], "rank": start + n,
                  "upvotes_at_batch": p["upvotes"], "is_exposed": False, "is_featured": False}
                 for n, p in enumerate(late, start=1)]
    else:
        exposed = set(exposed_ids)
        rows = [{"digest_date": entry["digest_date"], "paper_id": p["paper_id"], "rank": r, "upvotes_at_batch": p["upvotes"],
                 "is_exposed": p["paper_id"] in exposed, "is_featured": p["paper_id"] == featured_id}
                for r, p in enumerate(ordered, start=1)]
    db.upsert("digest_papers", rows, "digest_date,paper_id")

    for pid, (_, detail, sentences, out, model) in made.items():
        src = next(p for p in ordered if p["paper_id"] == pid)
        db.save_paper_ai(pid, llm.sha256(src["abstract_en"]), sentences, detail, out, model, meta)


def _record_delayed(db: Db | None, out_dir: Path, digest_date: str, source_date: str):
    """수집 실패: 그날이 아직 없을 때만 지연으로 기록한다(이미 낸 날은 덮지 않는다)."""
    entry = {"digest_date": digest_date, "source_date": source_date, "status": "delayed", "paper_count": 0,
             "primary_topic": None, "last_success_at": _last_success(out_dir)}
    build.write(out_dir, entry, None, [])
    if db and not db.select("digests", f"digest_date=eq.{digest_date}&select=digest_date"):
        last = db.select("digests", "status=neq.delayed&select=last_success_at&order=last_success_at.desc&limit=1")
        db.upsert("digests", [{**entry, "last_success_at": last[0]["last_success_at"] if last else None}], "digest_date")


def _last_success(out_dir: Path) -> str | None:
    path = out_dir / "digests.json"
    if not path.exists():
        return None
    ok = [d["last_success_at"] for d in json.loads(path.read_text(encoding="utf-8"))["digests"] if d["status"] != "delayed"]
    return max(ok, default=None)


if __name__ == "__main__":
    raise SystemExit(main())
