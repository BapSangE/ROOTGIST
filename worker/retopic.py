"""이미 저장된 논문의 분야(topic_tags)만 다시 분류한다. 요약·번역·용어는 그대로 둔다.

    python -m worker.retopic --dry-run   # 분류만 받아 바뀔 내용을 보여 준다. 논문·다이제스트는 고치지 않는다
    python -m worker.retopic             # 받아서 paper_ai.topic_*와 digests.primary_topic(G10)에 반영

p2 프롬프트 v0.6.2(2026-11-01)에서 분야 코드가 5개 → 9개가 됐다. 그전에 만든 해설은 옛 분류라
「멀티모달」에 이미지 생성·3D·로봇 논문이 몰려 있다. 해설 전체를 다시 만들면 요약 문장도 바뀌고 비용이 크므로
제목·초록만 보내 분류만 받는다. 분류 기준 문장은 프롬프트 문서의 `topic_tags` 항목을 그대로 쓴다.
받은 분류는 worker_state(retopic)에 남겨, 같은 논문을 다시 부르지 않는다(--dry-run 뒤 적용, 중간에 끊긴 뒤 재실행).
키: run.py와 같다(DEEPSEEK_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY).
"""
import argparse
import json
import re
import sys
import threading
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from . import build, llm
from .db import Db

PROMPT = "v0.6.2"
STATE = Path(__file__).resolve().parent / "out" / "retopic.json"


def system_prompt(version: str = PROMPT) -> str:
    doc = llm.PROMPTS[version].read_text(encoding="utf-8")
    rule = re.search(r"^- `topic_tags`:.*?(?=^- `term_difficulty`:)", doc, re.S | re.M).group(0).strip()
    return "\n\n".join([
        "제공된 논문 영문 제목과 초록만 보고 논문의 분야를 분류한다. 초록 밖의 내용을 상상하지 않는다. "
        '응답은 JSON 하나만 출력한다: {"topic_tags": ["대표 코드", "둘째 코드(없으면 생략)"]}',
        rule,
    ])


def build_messages(title_en: str, abstract: str, version: str = PROMPT) -> list[dict]:
    user = "\n".join([
        f"original_title: {title_en}",
        f"abstract: {abstract}",
        f"allowed_topics: {json.dumps(llm.allowed_topics(version), separators=(',', ':'))}",
    ])
    return [{"role": "system", "content": system_prompt(version)}, {"role": "user", "content": user}]


def check(out, version: str = PROMPT) -> list[str]:
    tags = out.get("topic_tags") if isinstance(out, dict) else None
    if not isinstance(tags, list) or not 1 <= len(tags) <= 2 or len(set(tags)) != len(tags):
        return ["topic_tags: 서로 다른 코드 1~2개여야 한다"]
    if bad := [t for t in tags if t not in llm.allowed_topics(version)]:
        return [f"topic_tags: 허용되지 않은 코드 {bad}"]
    return []


def classify(key: str, title_en: str, abstract: str, log=lambda r: None) -> list[str] | None:
    out, _ = llm.generate(key, build_messages(title_en, abstract), check, log)
    return out["topic_tags"] if out else None


def digest_topics(db: Db, changed: set[str]) -> list[dict]:
    """바뀐 논문이 노출된 날의 대표 분야(G10)를 다시 계산한다."""
    rows = db.select_all("digest_papers", "is_exposed=eq.true&select=digest_date,paper_id,is_featured&order=digest_date,rank")
    days: dict[str, list[dict]] = {}
    for r in rows:
        days.setdefault(r["digest_date"], []).append(r)
    ids = sorted({r["paper_id"] for r in rows})
    topics = {a["paper_id"]: a["topic_primary"] for a in db.select_all(
        "paper_ai", f"paper_id=in.({','.join(ids)})&select=paper_id,topic_primary&order=paper_id")} if ids else {}
    result = []
    for day, papers in days.items():
        if not changed & {p["paper_id"] for p in papers}:
            continue
        details = [{"paper_id": p["paper_id"], "topic_primary": topics.get(p["paper_id"])} for p in papers]
        featured = next((p["paper_id"] for p in papers if p["is_featured"]), None)
        result.append({"digest_date": day, "primary_topic": build.primary_topic(details, featured)})
    return result


def main(argv=None):
    from .official_news import load_state, save_state
    from .run import setting

    sys.stdout.reconfigure(line_buffering=True)
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="분류만 받는다. 논문·다이제스트는 고치지 않는다")
    ap.add_argument("--papers", help="이 논문들만(쉼표 구분)")
    args = ap.parse_args(argv)

    key = llm.api_key() or sys.exit("LLM API 키가 없습니다(DEEPSEEK_API_KEY 또는 NVIDIA_API_KEY).")
    url, secret = setting("SUPABASE_URL"), setting("SUPABASE_SERVICE_ROLE_KEY")
    if not (url and secret):
        sys.exit("SUPABASE_URL·SUPABASE_SERVICE_ROLE_KEY가 없습니다.")
    db = Db(url, secret)
    print(f"LLM 제공처: {llm.provider()}, 분류 기준 p2-prompt-{PROMPT}")

    # v0.6.2 이후로 만든 해설은 이미 새 분류다
    ai = [a for a in db.select_all("paper_ai", "status=eq.ready&select=paper_id,topic_primary,topic_secondary,prompt_version"
                                               "&order=paper_id")
          if a["prompt_version"] != llm.prompt_version(PROMPT)]
    if args.papers:
        wanted = set(args.papers.split(","))
        ai = [a for a in ai if a["paper_id"] in wanted]
    state = load_state(db, "retopic", STATE)
    todo = [a["paper_id"] for a in ai if a["paper_id"] not in state]
    print(f"옛 분류 {len(ai)}편, 새로 분류할 편 {len(todo)}(나머지는 지난 실행 결과 재사용)")

    if todo:
        papers = {p["paper_id"]: p for p in db.select_all(
            "papers", f"paper_id=in.({','.join(todo)})&select=paper_id,title_en,abstract_en&order=paper_id")}
        lock, usage = threading.Lock(), Counter()

        def log(rec):
            if u := rec.get("usage"):
                with lock:
                    usage.update({k: u.get(k) or 0 for k in ("prompt_tokens", "completion_tokens")})

        def one(pid):
            p = papers[pid]
            tags = classify(key, p["title_en"], p["abstract_en"], log)
            print(f"  {pid}: {tags or '실패(그대로 둔다)'}")
            return pid, tags

        with ThreadPoolExecutor(max_workers=3) as pool:
            for pid, tags in pool.map(one, todo):
                if tags:
                    state[pid] = tags
        save_state(db, "retopic", STATE, state)
        print(f"토큰: 입력 {usage['prompt_tokens']}, 출력 {usage['completion_tokens']}")

    changes = []
    for a in ai:
        tags = state.get(a["paper_id"])
        new = (tags[0], tags[1] if len(tags) > 1 else None) if tags else None
        if new and new != (a["topic_primary"], a["topic_secondary"]):
            changes.append((a["paper_id"], (a["topic_primary"], a["topic_secondary"]), new))
    before = Counter(a["topic_primary"] for a in ai)
    after = Counter((state[a["paper_id"]][0] if a["paper_id"] in state else a["topic_primary"]) for a in ai)
    print(f"대표 분야 전: {dict(before.most_common())}")
    print(f"대표 분야 후: {dict(after.most_common())}")
    print(f"바뀌는 편 {len(changes)}")
    for pid, old, new in changes:
        print(f"  {pid}: {old} → {new}")

    if args.dry_run:
        print("--dry-run: 논문·다이제스트는 고치지 않았습니다.")
        return 0
    for pid, _, (primary, secondary) in changes:
        db.update("paper_ai", {"topic_primary": primary, "topic_secondary": secondary}, paper_id=pid)
    days = digest_topics(db, {pid for pid, _, _ in changes})
    for d in days:
        db.update("digests", {"primary_topic": d["primary_topic"]}, digest_date=d["digest_date"])
    print(f"반영: 논문 {len(changes)}편, 다이제스트 대표 분야 {len(days)}일")
    return 0


if __name__ == "__main__":
    sys.exit(main())
