"""하루치 배치: 수집 → 상위 10편 선별 → 문장 분할 → LLM(auto_select) → 검증 → 후처리 → 저장.

    python -m worker.run                    # 어제(UTC) 목록, 상위 10편
    python -m worker.run --date 2026-10-21  # 특정 UTC 날짜 D
    python -m worker.run --limit 1          # 1편만(짧은 확인용)

API 키: 환경 변수 NVIDIA_API_KEY, 없으면 레포 루트 .env의 NVIDIA_API_KEY 또는 nvidia_key.
출력: worker/out/ (git 제외). 실제 초록·번역이 들어 있으므로 커밋하거나 외부에 공유하지 않는다(HANDOFF 0.1, NVIDIA 시험 약관).
ponytail: Supabase 저장과 다음 날 보충(ops config 1.1)은 Supabase 연결 때 추가한다.
"""
import argparse
import json
import os
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from . import build, collect, llm, split, validate

ROOT = Path(__file__).resolve().parent.parent


def api_key() -> str:
    if key := os.environ.get("NVIDIA_API_KEY"):
        return key
    env = ROOT / ".env"
    if env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            k, sep, v = line.partition("=")
            if sep and k.strip() in ("NVIDIA_API_KEY", "nvidia_key"):
                return v.strip().strip("\"'")
    raise SystemExit("NVIDIA API 키가 없습니다(NVIDIA_API_KEY 또는 .env).")


def main(argv=None):
    sys.stdout.reconfigure(line_buffering=True)  # 파이프로 받아도 진행 줄이 바로 보이게
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", help="UTC 날짜 D (YYYY-MM-DD). 기본: 어제(UTC)")
    ap.add_argument("--limit", type=int, default=10, help="해설 만들 편수(기본 10)")
    ap.add_argument("--out", type=Path, default=ROOT / "worker" / "out")
    args = ap.parse_args(argv)

    source_date = args.date or (datetime.now(timezone.utc).date() - timedelta(days=1)).isoformat()
    digest_date = (date.fromisoformat(source_date) + timedelta(days=1)).isoformat()  # KST 05:00 배치일 = D+1
    raw = args.out / "raw" / source_date
    raw.mkdir(parents=True, exist_ok=True)
    lock = threading.Lock()

    def log(rec: dict):  # 호출·요청 기록. API 키는 절대 넣지 않는다.
        with lock, (raw / "calls.jsonl").open("a", encoding="utf-8") as f:
            f.write(json.dumps({"at": datetime.now(timezone.utc).isoformat(), **rec}, ensure_ascii=False) + "\n")

    key = api_key()
    try:
        items = collect.fetch_day(source_date, raw / "hf", log)
    except collect.CollectError as e:
        log({"stage": "collect", "error": str(e)})
        prev = _last_success(args.out)
        build.write(args.out, {"digest_date": digest_date, "source_date": source_date, "status": "delayed",
                               "paper_count": 0, "primary_topic": None, "last_success_at": prev}, None, [])
        print(f"수집 실패 → {digest_date} 지연으로 기록: {e}")
        return 1

    papers = [p for p in (collect.to_paper(i) for i in items) if p]
    ranked = collect.select_top(papers, args.limit)
    print(f"{source_date}: {len(items)}건 수집, 철회 제외 {len(papers)}건, 상위 {len(ranked)}편 처리")

    def one(p):
        try:
            sentences = split.to_sentences(p["abstract_en"])
        except ValueError as e:
            log({"paper_id": p["paper_id"], "stage": "split", "error": str(e)})
            return build.paper_detail(p, [], None)
        messages = llm.build_messages(p["title_en"], p["abstract_en"], sentences)
        meta = {"paper_id": p["paper_id"], "abstract_sha256": llm.sha256(p["abstract_en"]),
                "sentence_splitter_version": split.SPLITTER_VERSION, "glossary_mode": "auto_select",
                "prompt_version": llm.PROMPT_VERSION, "schema_version": llm.SCHEMA_VERSION, "temperature": 0}
        out, model = llm.generate(key, messages, lambda o: validate.check(o, sentences), lambda r: log({**meta, **r}))
        status = f"ok ({model})" if out else "실패 → 해설 준비 중"
        print(f"  {p['paper_id']}: {status}")
        return build.paper_detail(p, sentences, validate.postprocess(out) if out else None)

    with ThreadPoolExecutor(max_workers=3) as pool:  # 모델당 동시 3건(ops config 1장)
        details = list(pool.map(one, ranked))

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    day = build.digest(digest_date, now, ranked, details)
    entry = {"digest_date": digest_date, "source_date": source_date, "status": day["status"],
             "paper_count": len(details), "primary_topic": build.primary_topic(details, day["featured_paper_id"]),
             "last_success_at": now}
    build.write(args.out, entry, day, details)
    ready = sum(d["ai_status"] == "ready" for d in details)
    print(f"저장: {args.out} (digest {digest_date}, 해설 {ready}/{len(details)}편)")
    return 0


def _last_success(out_dir: Path) -> str | None:
    path = out_dir / "digests.json"
    if not path.exists():
        return None
    ok = [d["last_success_at"] for d in json.loads(path.read_text(encoding="utf-8"))["digests"] if d["status"] != "delayed"]
    return max(ok, default=None)


if __name__ == "__main__":
    raise SystemExit(main())
