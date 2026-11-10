"""X(구 트위터) 계정 새 글 수집(docs/X_WATCHLIST.md, 2026-11-06).

「한도 초기화」「사용량 리셋」「무료 개방」 같은 소식은 X에서 먼저 나오고 블로그에는 안 쓰는 경우가 많아,
정해 둔 계정(worker/x_accounts.py)의 새 글만 공식 X API v2로 받는다. 검색은 쓰지 않는다(넓게 받으면 비용이 커진다).

비용(쓴 만큼 내기, 2026-11 기준): 게시물 1개 읽기 약 $0.005, 사용자 조회 1명 약 $0.010.
- 계정별로 마지막으로 받은 글(since_id)을 기억해 새 글만 받는다. 처음 보는 계정은 최근 24시간만.
- 하루 읽기 상한(X_DAILY_READ_CAP, 기본 200개 ≈ $1)에 닿으면 그날은 멈춘다.
- 사용자 id는 한 번 찾으면 저장해 다시 조회하지 않는다.
- 크레딧은 선불이라 자동 충전을 꺼 두면 다 쓴 뒤 402로 멈출 뿐 더 청구되지 않는다.

키: 환경 변수 또는 레포 루트 .env
    X_BEARER_TOKEN                          없으면 아무것도 하지 않고 끝난다(워크플로가 실패하지 않게)
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  있으면 x_posts 테이블과 worker_state에 저장, 없으면 worker/out/ 파일로만
    X_DAILY_READ_CAP                        하루 게시물 읽기 상한(선택)

    python3 -m worker.x_posts                  # 켜진 계정
    python3 -m worker.x_posts --handles sama   # 이 계정만(꺼져 있어도)
    python3 -m worker.x_posts --no-db          # DB 설정이 있어도 파일로만

출력: worker/out/x_posts.json(이번 실행에 받은 글), worker/out/x_state.json(상태). 커밋하지 않는다(HANDOFF 0.1).
"""
import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

from . import llm
from .db import Db
from .run import setting
from .x_accounts import ACCOUNTS

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "worker" / "out"
STATE_FILE = OUT / "x_state.json"
STATE_KEY = "x_posts"
API = "https://api.x.com/2"
UA = "ROOTGIST/1.0 (+https://bapsange.github.io/ROOTGIST/privacy/)"

PRICE_POST, PRICE_USER = 0.005, 0.010  # 비용 추정용. 실제 청구는 X 개발자 콘솔 Billing이 기준
DAILY_CAP = 200
FIRST_LOOKBACK_H = 24
# 한 번에 한 쪽만 받는다(페이지를 넘기면 한 계정이 상한을 다 쓸 수 있다). 30분마다 돌면 한 계정이 그사이 20개 넘게
# 올리는 일은 드물고, 넘으면 오래된 쪽이 빠진다(로그에 남긴다).
PER_REQUEST = 20
USAGE_DAYS = 62  # 사용량 기록은 두 달치만

# 혜택·한도 소식 낱말. 「limit」「free」 단독은 뺐다: 첫 실행(2026-11-10)에서 물리 논문 「exact limit」, 일반 글의 「free」가 걸렸다.
# 한도는 사용량 맥락(rate/usage/weekly… limits, 한도 상향)만, 무료는 혜택 표현(for free, free tier, now free…)만 본다.
PERK_WORDS = re.compile(
    r"\b(resets?|resetting|rate[- ]?limits?|usage limits?|(?:weekly|daily|hourly|session|5-hour|five-hour) limits?|"
    r"higher limits|limits? (?:raised|increased|doubled|lifted)|(?:raised|increased|doubled|lifted|removed) (?:the )?limits?|"
    r"quotas?|credits?|[23]x|doubled?|unlimited|promos?|promotion|discounts?|on us|giveaway|bonus|"
    r"free (?:trial|tier|plan|access|credits?|for|to use)|for free|(?:now|completely|totally) free|free users|trials?)\b", re.I)
NOT_PERK = re.compile(r"\bfeel free\b|\bfree to\b|\bfree speech\b|\bhands[- ]free\b", re.I)


class XError(Exception):
    def __init__(self, status: int, body: str):
        super().__init__(f"X API HTTP {status}: {body}")
        self.status = status


def x_get(token: str):
    def get(path: str, params: dict) -> dict:
        url = f"{API}/{path}?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            raise XError(e.code, e.read()[:300].decode("utf-8", "replace")) from e
    return get


def perk_words(text: str) -> list[str]:
    cleaned = NOT_PERK.sub(" ", text)
    return sorted({m.group(0).lower() for m in PERK_WORDS.finditer(cleaned)})


def _iso(t: datetime) -> str:
    return t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _usage_today(state: dict, now: datetime) -> dict:
    day = now.astimezone(timezone.utc).date().isoformat()
    usage = state.setdefault("usage", {})
    for old in sorted(usage)[:-USAGE_DAYS]:
        del usage[old]
    return usage.setdefault(day, {"posts": 0, "users": 0, "requests": 0})


def resolve_ids(handles: list[str], state: dict, get, today: dict) -> list[str]:
    """아직 id를 모르는 핸들을 한 번에 찾는다. X가 못 찾은 핸들을 돌려준다."""
    ids = state.setdefault("user_ids", {})
    missing = [h for h in handles if h.lower() not in ids]
    if not missing:
        return []
    got = get("users/by", {"usernames": ",".join(missing), "user.fields": "name"})
    today["requests"] += 1
    found = got.get("data") or []
    today["users"] += len(found)
    for u in found:
        ids[u["username"].lower()] = {"id": u["id"], "username": u["username"], "name": u.get("name")}
    return [h for h in missing if h.lower() not in ids]


def to_row(t: dict, user: dict, tier: int, now: datetime) -> dict:
    text = (t.get("note_tweet") or {}).get("text") or t["text"]
    m = t.get("public_metrics") or {}
    words = perk_words(text)
    # 글에 단 링크(t.co가 아니라 펼친 주소). 앱이 같은 주소의 공식 소식에 X 반응으로 붙인다
    links = []
    for u in ((t.get("note_tweet") or {}).get("entities") or t.get("entities") or {}).get("urls") or []:
        link = u.get("unwound_url") or u.get("expanded_url")
        if link and not re.match(r"https?://(x|twitter)\.com/", link) and link not in links:
            links.append(link)
    return {
        "id": t["id"], "handle": user["username"], "author_name": user.get("name"), "tier": tier, "text": text,
        "url": f"https://x.com/{user['username']}/status/{t['id']}", "posted_at": t["created_at"],
        "likes": m.get("like_count"), "reposts": m.get("retweet_count"), "replies": m.get("reply_count"),
        "quotes": m.get("quote_count"), "perk": bool(words), "perk_words": words, "links": links, "collected_at": _iso(now),
    }


def collect(accounts: list[tuple[str, str, int, bool]], state: dict, get, now: datetime, cap: int = DAILY_CAP):
    """(받은 글, 멈춘 이유 또는 None). state는 제자리에서 바뀐다(since_id·사용량·id)."""
    today = _usage_today(state, now)
    rows, stop = [], None
    try:
        for h in resolve_ids([a[0] for a in accounts], state, get, today):
            print(f"  X에서 찾지 못한 핸들: @{h} (바뀌었거나 없어진 계정, x_accounts.py 확인)")
    except XError as e:
        return rows, f"사용자 조회 실패: {e}"
    since = state.setdefault("since", {})
    for handle, _, tier, _ in accounts:
        user = state["user_ids"].get(handle.lower())
        if not user:
            continue
        left = cap - today["posts"]
        if left < 5:  # API 최소 max_results가 5
            stop = f"하루 읽기 상한 {cap}개에 닿아 멈춤"
            break
        params = {"max_results": min(PER_REQUEST, left), "exclude": "replies,retweets",
                  "tweet.fields": "created_at,public_metrics,note_tweet,entities"}
        if sid := since.get(handle.lower()):
            params["since_id"] = sid
        else:
            params["start_time"] = _iso(now - timedelta(hours=FIRST_LOOKBACK_H))
        try:
            got = get(f"users/{user['id']}/tweets", params)
        except XError as e:
            if e.status == 429:
                stop = "요청 한도(429)에 닿아 멈춤, 다음 실행에 이어 받는다"
            elif e.status == 402:
                stop = "크레딧이 없음(402). X 개발자 콘솔에서 충전 상태 확인"
            elif e.status in (401, 403):
                stop = f"토큰이 거부됨({e.status}). X_BEARER_TOKEN 확인"
            else:
                print(f"  @{handle}: {e}")
                continue
            break
        today["requests"] += 1
        data, meta = got.get("data") or [], got.get("meta") or {}
        today["posts"] += len(data)
        if meta.get("newest_id"):
            since[handle.lower()] = meta["newest_id"]
        if meta.get("next_token"):
            print(f"  @{handle}: 새 글이 {len(data)}개보다 많아 오래된 쪽은 건너뜀")
        rows += [to_row(t, user, tier, now) for t in data]
    return rows, stop


# 한국어 번역(2026-11-10): 앱 HOT 칸·혜택 카드에 원문과 함께 「AI 번역」으로 보인다. 30분마다 도는 이 수집기는
# LLM을 부르지 않고, 하루 두 번 도는 공식 소식 배치(official_news.py)가 최근 글 중 번역이 없는 것만 옮긴다.
TRANSLATE_DAYS, TRANSLATE_MAX, TRANSLATE_BATCH, TRANSLATE_CHARS = 3, 80, 15, 1500
X_TRANSLATE_SYSTEM = (
    "You translate English posts from X (Twitter) by AI companies and AI news accounts into natural Korean for a Korean reading app. "
    "Translate faithfully: do not summarize, add, explain or guess. Keep product, model, company and person names, @handles, "
    "#hashtags, numbers and URLs exactly as written. Write in the polite 해요체 (~해요, ~했어요, ~돼요). "
    "Return only a JSON object: {\"posts\": [\"...\", ...]} with one Korean string per input post, in the same order."
)


def translate_texts(texts: list[str], api_key: str, log) -> list[str] | None:
    msgs = [{"role": "system", "content": X_TRANSLATE_SYSTEM},
            {"role": "user", "content": json.dumps({"posts": [t[:TRANSLATE_CHARS] for t in texts]}, ensure_ascii=False)}]

    def check(out):
        got = out.get("posts") if isinstance(out, dict) else None
        if not isinstance(got, list) or len(got) != len(texts) or not all(isinstance(x, str) and x.strip() for x in got):
            return ["posts_mismatch"]
        return []

    out, _ = llm.generate(api_key, msgs, check, log)
    return [x.strip() for x in out["posts"]] if out else None


def translate_recent(db, api_key: str, now: datetime) -> str:
    """최근 TRANSLATE_DAYS일 글 중 번역(text_ko)이 없는 것을 옮겨 저장한다. 결과 한 줄을 돌려준다."""
    since = urllib.parse.quote(_iso(now - timedelta(days=TRANSLATE_DAYS)))
    todo = db.select("x_posts", f"select=id,text&text_ko=is.null&posted_at=gte.{since}&order=posted_at.desc&limit={TRANSLATE_MAX}")
    done = 0
    for i in range(0, len(todo), TRANSLATE_BATCH):
        chunk = todo[i:i + TRANSLATE_BATCH]
        ko = translate_texts([r["text"] for r in chunk], api_key, lambda e: None)
        for r, t in zip(chunk, ko or []):
            db._req("PATCH", f"x_posts?id=eq.{r['id']}", {"text_ko": t}, "return=minimal")
            done += 1
    return f"X 글 번역: 새 {done}/{len(todo)}개"


# 반응 수 다시 받기(2026-11-10): 30분마다 새 글만 받으면 좋아요가 거의 0일 때 저장돼 앱이 반응 순으로 세울 수 없다.
# 올라온 지 REFRESH_AFTER_H~REFRESH_UNTIL_H시간 된 글을 한 번만 다시 받는다(글마다 읽기 1번, 하루 상한에 함께 센다).
REFRESH_AFTER_H, REFRESH_UNTIL_H, REFRESH_MAX = 4, 30, 100


def refresh_metrics(db, get, state: dict, now: datetime, cap: int = DAILY_CAP) -> str:
    today = _usage_today(state, now)
    left = min(REFRESH_MAX, cap - today["posts"])
    if left <= 0:
        return "반응 다시 받기: 하루 상한이라 건너뜀"
    lo, hi = (urllib.parse.quote(_iso(now - timedelta(hours=h))) for h in (REFRESH_UNTIL_H, REFRESH_AFTER_H))
    todo = db.select("x_posts", f"select=id&refreshed_at=is.null&posted_at=gte.{lo}&posted_at=lte.{hi}&order=posted_at.asc&limit={left}")
    if not todo:
        return "반응 다시 받기: 없음"
    got = get("tweets", {"ids": ",".join(r["id"] for r in todo), "tweet.fields": "public_metrics"})
    today["requests"] += 1
    data = got.get("data") or []
    today["posts"] += len(data)
    stamp = _iso(now)
    seen = set()
    for t in data:
        m = t.get("public_metrics") or {}
        db._req("PATCH", f"x_posts?id=eq.{t['id']}", {"likes": m.get("like_count"), "reposts": m.get("retweet_count"),
                                                      "replies": m.get("reply_count"), "quotes": m.get("quote_count"),
                                                      "refreshed_at": stamp}, "return=minimal")
        seen.add(t["id"])
    for r in todo:  # X에서 지워진 글: 표시 규정상 앱에서도 내린다
        if r["id"] not in seen:
            db.delete("x_posts", id=r["id"])
    return f"반응 다시 받기: {len(seen)}개, 지워진 글 {len(todo) - len(seen)}개 삭제"


def load_state(db) -> dict:
    if db:
        got = db.select("worker_state", f"key=eq.{STATE_KEY}&select=value")
        if got:
            return got[0]["value"]
    return json.loads(STATE_FILE.read_text(encoding="utf-8")) if STATE_FILE.exists() else {}


def save(db, rows: list[dict], state: dict, now: datetime):
    """글을 먼저 저장하고 상태(since_id)는 그다음: 글 저장이 실패하면 다음 실행에 다시 받는다."""
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "x_posts.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
    if db:
        db.upsert("x_posts", rows, "id")
        db.upsert("worker_state", [{"key": STATE_KEY, "value": state, "updated_at": _iso(now)}], "key")
    STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8")


def cost_line(state: dict, now: datetime) -> str:
    usage = state.get("usage", {})
    day = now.astimezone(timezone.utc).date().isoformat()
    month = [u for d, u in usage.items() if d[:7] == day[:7]]
    cost = lambda us: sum(u["posts"] * PRICE_POST + u["users"] * PRICE_USER for u in us)  # noqa: E731
    t = usage.get(day, {"posts": 0, "users": 0})
    return (f"오늘 게시물 {t['posts']}개·사용자 {t['users']}명 ≈ ${cost([t]):.2f}, "
            f"이번 달 게시물 {sum(u['posts'] for u in month)}개 ≈ ${cost(month):.2f} (추정, 실제는 콘솔 Billing)")


def main(argv=None):
    sys.stdout.reconfigure(line_buffering=True)
    ap = argparse.ArgumentParser()
    ap.add_argument("--handles", help="이 계정만(쉼표 구분, 꺼진 계정도 받는다)")
    ap.add_argument("--no-db", action="store_true", help="DB 설정이 있어도 파일로만")
    args = ap.parse_args(argv)

    token = setting("X_BEARER_TOKEN")
    if not token:
        print("X_BEARER_TOKEN이 없어 건너뜁니다.")
        return 0
    if args.handles:
        want = {h.strip().lstrip("@").lower() for h in args.handles.split(",") if h.strip()}
        accounts = [a for a in ACCOUNTS if a[0].lower() in want]
        accounts += [(h, h, 3, True) for h in want - {a[0].lower() for a in ACCOUNTS}]
    else:
        accounts = [a for a in ACCOUNTS if a[3]]
    cap = int(setting("X_DAILY_READ_CAP") or DAILY_CAP)
    url, secret = setting("SUPABASE_URL"), setting("SUPABASE_SERVICE_ROLE_KEY")
    db = Db(url, secret) if url and secret and not args.no_db else None
    if db is None:
        print("Supabase에 쓰지 않고 파일로만 저장합니다.")

    now = datetime.now(timezone.utc)
    state = load_state(db)
    print(f"X 계정 {len(accounts)}곳 확인 (하루 상한 {cap}개)")
    get = x_get(token)
    rows, stop = collect(accounts, state, get, now, cap)
    save(db, rows, state, now)
    if db and not stop:
        try:
            print(refresh_metrics(db, get, state, now, cap))
            db.upsert("worker_state", [{"key": STATE_KEY, "value": state, "updated_at": _iso(now)}], "key")
        except (XError, RuntimeError) as e:  # 마이그레이션 전(refreshed_at 열 없음)이거나 X 오류
            print(f"반응 다시 받기 실패: {e}")
    # 새 글 번역(2026-11-10): 하루 한 번(공식 소식 배치)만 옮기면 그사이 들어온 글이 앱에 영어로 하루 가까이 남았다.
    # 번역 없는 글만 옮기므로 30분마다 몇 개뿐이다. LLM 키가 없거나 실패해도 수집은 성공으로 남기고, 공식 소식 배치가 다시 채운다.
    key = llm.api_key()
    if db and key:
        try:
            print(translate_recent(db, key, now))
        except Exception as e:
            print(f"X 글 번역 실패: {e!r}")
    perks = [r for r in rows if r["perk"]]
    print(f"새 글 {len(rows)}개, 혜택·한도 낱말 {len(perks)}개")
    for r in perks:
        print(f"  ★ @{r['handle']} {r['perk_words']}: {r['text'][:100]!r}")
    print(cost_line(state, now))
    if stop:
        print(f"멈춤: {stop}")
        # 토큰·크레딧 문제는 사람이 봐야 하니 워크플로를 실패로 남긴다. 상한·429는 정상 멈춤.
        return 1 if ("402" in stop or "토큰" in stop or "조회 실패" in stop) else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
