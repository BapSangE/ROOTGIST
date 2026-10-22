"""HF Daily Papers 수집과 상위 N편 선별 (HANDOFF 4.1, batch_worker_notes.md 1장, ops config 1.1)."""
import json
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

API = "https://huggingface.co/api/daily_papers"
PAGE = 10


class CollectError(Exception):
    pass


def _get(url: str, log) -> bytes:
    """시간 제한 30초, 최대 4회 재시도(지수 대기, 기준 2초)."""
    last = None
    for attempt in range(5):
        t0 = time.monotonic()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "rootgist-batch/1"})
            with urllib.request.urlopen(req, timeout=30) as r:
                body = r.read()
                log({"url": url, "status": r.status, "latency_ms": int((time.monotonic() - t0) * 1000)})
                return body
        except urllib.error.HTTPError as e:
            body = e.read()
            log({"url": url, "status": e.code, "latency_ms": int((time.monotonic() - t0) * 1000), "error_body": body[:2000].decode("utf-8", "replace")})
            last = e
            if e.code < 500 and e.code != 429:
                break  # 4xx(429 제외)는 다시 해도 같다
        except OSError as e:  # URLError, socket.timeout 포함
            log({"url": url, "status": None, "error": repr(e)})
            last = e
        if attempt < 4:
            time.sleep(2 * 2**attempt)
    raise CollectError(f"{url}: {last!r}")


def fetch_day(date: str, raw_dir: Path, log) -> list[dict]:
    """date(UTC D)의 목록 전부. 받은 건수가 PAGE보다 적으면 멈춘다. 페이지 원본은 raw_dir에 보관."""
    raw_dir.mkdir(parents=True, exist_ok=True)
    items, p = [], 0
    while True:
        url = f"{API}?date={date}&sort=publishedAt&limit={PAGE}&p={p}"
        body = _get(url, log)
        (raw_dir / f"p{p}.json").write_bytes(body)
        try:
            page = json.loads(body)
        except json.JSONDecodeError as e:
            raise CollectError(f"{url}: JSON 파싱 실패 {e}") from e
        if not isinstance(page, list):
            raise CollectError(f"{url}: 목록이 아님")
        items += page
        if len(page) < PAGE:
            return items
        p += 1
        time.sleep(0.5)


def to_paper(item: dict) -> dict | None:
    """4.1 필드만 뽑는다. 철회 논문은 None. HF의 ai_summary·ai_keywords는 쓰지 않는다."""
    p = item.get("paper") or {}
    if p.get("withdrawnAt"):
        return None
    return {
        "paper_id": p["id"],
        "title_en": p["title"],
        "abstract_en": p["summary"],  # 원문 그대로 저장
        "authors": [a.get("name", "") for a in p.get("authors", [])],
        "org_name": (p.get("organization") or {}).get("fullname"),  # 게시 조직(저자 소속 아님)
        "published_at": p["publishedAt"],  # 최상위 publishedAt 말고 paper.publishedAt
        "upvotes": p.get("upvotes", 0),  # 배치 시각 값으로 고정
        # 주소만 저장하고 화면에는 쓰지 않는다(A8 권리 검토 전)
        "thumbnail_url": item.get("thumbnail"),
        "media_urls": item.get("mediaUrls") or p.get("mediaUrls") or [],
    }


def select_top(papers: list[dict], n: int = 10) -> list[dict]:
    """upvote 내림차순 → paper.publishedAt 최신순 → paper_id 오름차순."""
    def ts(p):
        return datetime.fromisoformat(p["published_at"].replace("Z", "+00:00")).timestamp()

    # 같은 논문이 페이지에 두 번 오면 하나만
    unique = {p["paper_id"]: p for p in papers}.values()
    return sorted(unique, key=lambda p: (-p["upvotes"], -ts(p), p["paper_id"]))[:n]
