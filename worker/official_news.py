"""연구소 공식 소식 수집(PROPOSALS P8d). 세 종류(kind):

- post: 연구소 블로그 글. 제목을 한국어로 옮기고, 본문 문단을 근거로 AI 요약 1~2문장 + 핵심 내용 최대 3개를 만든다.
  핵심 내용마다 근거 문단 번호와 그 문단의 원문 구절(앱이 원문의 그 자리로 여는 링크에만 쓴다)을 단다.
  본문 전체를 옮기지 않고, 상세는 원문 링크로 보낸다(권리 검토 A8 대상). OpenAI는 글 페이지가 자동 접근을 막아(403)
  피드 소개문만 근거로 쓴다.
- notice: 개발자 커뮤니티의 운영자 공지 게시판. post와 같다(본문은 피드에 들어 있다). 일반 게시판은 넣지 않는다.
- release: SDK·도구 릴리스와 API 릴리스 노트. 버전 제목은 뜻이 없어 출처마다 기간 안의 것을 한 항목으로 묶고,
  릴리스 노트 본문만 근거로 개발자용 3줄 요약을 만든다.

- models: Hugging Face 트렌딩 모델(PROPOSALS P9). 메타데이터(만든 곳·과제·크기·라이선스·반응)와, 모델 카드에 적힌 내용만
  근거로 한 「제작사가 내세운 강점」(강점·제작사 측정 점수·한계). 성인·검열 해제 계열은 거른다.

SUPABASE_URL·SUPABASE_SERVICE_ROLE_KEY가 있으면 official_news·trending_models 테이블에 저장하고(앱은 RPC로 읽는다),
실행 사이 상태(번역·요약 캐시, Anthropic 사이트맵 게시일)는 worker_state 테이블에 둔다. 없으면 worker/out/ 파일로만
(커밋 금지, HANDOFF 0.1). 매일 배치는 .github/workflows/daily-batch.yml의 official-news 잡.

    python3 -m worker.official_news            # 수집 + 번역·요약(LLM 키 필요, 없으면 원문만. llm.py)
    python3 -m worker.official_news --no-llm   # 번역 없이
    python3 -m worker.official_news --no-db    # DB 설정이 있어도 파일로만

worker/out/official_news.json          수집 결과
worker/out/official_news.define.json   DB 없이 앱 미리보기용(--dart-define-from-file)
"""
import argparse
import email.utils
import gzip
import hashlib
import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path

from . import llm
from .db import Db
from .run import setting

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "worker" / "out"
UA = "ROOTGIST/1.0 (+https://bapsange.github.io/ROOTGIST/privacy/)"
WINDOW_DAYS = 14  # 이 기간 안의 글만
PER_SOURCE = 5  # 출처마다 최신 몇 개
# Anthropic 사이트맵의 수정 시각은 쓸 수 없다: 2026-10-23에 연구 페이지 수백 개가 한꺼번에 다시 배포돼 몇 초 차이로 같아졌고,
# 목록 페이지(/news, /research)도 최신 글을 다 싣지 않는다. 그래서 글마다 한 번 읽어 게시일을 저장하고, 다음부터는 새 주소만 읽는다.
# ponytail: 미리보기에서는 worker/out/의 파일, 정식 배치에서는 DB 테이블에 둔다.
ANTHROPIC_SEEN = OUT / "anthropic_seen.json"
DIGEST_CACHE = OUT / "digest_cache.json"  # 주소(릴리스는 제목) → 번역·요약

HF_TRENDING = "https://huggingface.co/api/models?sort=trendingScore&limit=40"
TRENDING_TOP = 10
# 앱에 보일 과제만(위에서부터 많이 쓰이는 것). 나머지 과제와 아래 낱말이 이름·태그에 있는 모델은 뺀다.
MODEL_TASKS = {"text-generation", "image-text-to-text", "text-to-image", "image-to-image", "image-to-video", "text-to-video",
               "text-to-speech", "automatic-speech-recognition", "any-to-any", "feature-extraction", "sentence-similarity"}
MODEL_BLOCK = re.compile(r"uncensor|nsfw|abliterat|erotic|porn|lewd|hentai|nude|18\+", re.I)
CARD_CHARS = 20000

# OpenAI 피드에는 회사 소식·사례·정책 글이 섞여 있다. 개발 소식에 가까운 분류만.
OPENAI_CATEGORIES = {"Research", "Product", "Safety", "Safety & Alignment", "Publication"}
RSS_SOURCES = [
    # (id, 표시 이름, 피드)
    ("openai", "OpenAI", "https://openai.com/news/rss.xml"),
    ("deepmind", "Google DeepMind", "https://deepmind.google/blog/rss.xml"),
    ("google_research", "Google Research", "https://research.google/blog/rss/"),
    ("huggingface", "Hugging Face", "https://huggingface.co/blog/feed.xml"),
    # 공지 게시판만(직원 글). 일반 게시판은 하루 30개 넘는 사용자 질문이라 넣지 않는다.
    ("openai_community", "OpenAI 커뮤니티", "https://community.openai.com/c/announcements/6.rss"),
]
RELEASE_DAYS = 7  # 릴리스는 이번 주 것을 한 항목으로
RELEASE_SOURCES = [
    # (id, 표시 이름, 릴리스 피드, 사람이 보는 페이지)
    ("claude_code", "Claude Code", "https://github.com/anthropics/claude-code/releases.atom", "https://github.com/anthropics/claude-code/releases"),
    ("anthropic_sdk", "Anthropic Python SDK", "https://github.com/anthropics/anthropic-sdk-python/releases.atom",
     "https://github.com/anthropics/anthropic-sdk-python/releases"),
    ("openai_sdk", "OpenAI Python SDK", "https://github.com/openai/openai-python/releases.atom", "https://github.com/openai/openai-python/releases"),
]
CLAUDE_API_NOTES = "https://docs.claude.com/en/release-notes/overview"
NOTES_CHARS = 8000  # 요약에 넘길 릴리스 노트 길이 상한
MAX_PARAS, BODY_CHARS = 60, 12000  # 글 요약에 넘길 문단 수·길이 상한


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Encoding": "gzip"})
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()
        # DeepMind는 gzip으로 보낸다
        return gzip.decompress(body) if r.headers.get("Content-Encoding") == "gzip" or body[:2] == b"\x1f\x8b" else body


def _children(e) -> dict:
    return {c.tag.split("}")[-1]: (c.text or c.get("href") or "").strip() for c in e}


def _date(s: str):
    try:
        d = email.utils.parsedate_to_datetime(s)
    except (TypeError, ValueError):
        try:
            d = datetime.fromisoformat(s.replace("Z", "+00:00"))
        except ValueError:
            return None
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)  # Anthropic 일부 글은 시간대 없이 날짜만 있다


def from_rss(source: str, label: str, url: str) -> list[dict]:
    root = ET.fromstring(fetch(url))
    out = []
    for item in root.iter():
        if item.tag.split("}")[-1] not in ("item", "entry"):
            continue
        k = _children(item)
        cats = [c.text for c in item if c.tag.split("}")[-1] == "category" and c.text]
        link = k.get("link", "")
        if source == "openai" and not set(cats) & OPENAI_CATEGORIES:
            continue
        # HF 블로그의 /blog/<조직>/<글>은 커뮤니티 글이다. HF가 직접 쓴 /blog/<글>만.
        if source == "huggingface" and len(link.split("/blog/", 1)[-1].strip("/").split("/")) != 1:
            continue
        when = _date(k.get("pubDate") or k.get("published") or k.get("updated") or "")
        if not when:
            continue
        notice = source.endswith("_community")
        out.append({"source": source, "source_label": label, "kind": "notice" if notice else "post",
                    "category": "Announcement" if notice else (cats[0] if cats else None),
                    "title_en": html.unescape(k.get("title", "")).strip(), "url": link, "published_at": when,
                    "_desc": k.get("description") or k.get("summary") or ""})  # 공지 본문·OpenAI 소개문
    return out


def paragraphs(page: str) -> list[str]:
    """본문 문단(<p>·<li>, 40자 이상). <article>로 좁히면 HF·DeepMind는 본문이 빠져 페이지 전체에서 읽는다."""
    page = re.sub(r"<(script|style|nav|footer|header)\b.*?</\1>", "", page, flags=re.S)
    out = []
    for frag in re.findall(r"<(?:p|li)\b[^>]*>(.*?)</(?:p|li)>", page, re.S):
        t = _text(frag)
        if len(t) >= 40 and t not in out:
            out.append(t)
    return out[:MAX_PARAS]


def body_paragraphs(item: dict) -> list[str]:
    if item["source"] == "openai" or item["kind"] == "notice":
        desc = item["_desc"]
        return paragraphs(desc) or ([_text(desc)] if _text(desc) else [])
    return paragraphs(fetch(item["url"]).decode("utf-8", "replace"))


def _text(fragment: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", fragment))).strip()


def from_releases(source: str, label: str, url: str, page: str, now: datetime) -> list[dict]:
    """GitHub 릴리스(Atom). 기간 안의 버전들을 한 항목으로 묶는다."""
    root = ET.fromstring(fetch(url))
    rel = []
    for e in root:
        if e.tag.split("}")[-1] != "entry":
            continue
        k = _children(e)
        when = _date(k.get("updated", ""))
        if when and now - when <= timedelta(days=RELEASE_DAYS):
            rel.append((when, k.get("title", "").strip(), _text(k.get("content", ""))))
    if not rel:
        return []
    rel.sort()
    first, last = rel[0][1], rel[-1][1]
    span = last if len(rel) == 1 else f"{first}~{last}"
    notes = "\n\n".join(f"[{t}]\n{body}" for _, t, body in reversed(rel))[:NOTES_CHARS]
    return [{"source": source, "source_label": label, "kind": "release", "category": "Release",
             "title_en": f"{label} {span}" + ("" if len(rel) == 1 else f" ({len(rel)} releases)"),
             "title_ko": f"{label} 업데이트 {len(rel)}건 ({span})",
             "url": page, "published_at": rel[-1][0], "notes": notes}]


def from_claude_api_notes(now: datetime) -> list[dict]:
    """Claude API 릴리스 노트: <h3 id="october-22-2026">날짜</h3> 아래 목록. 기간 안의 날짜를 한 항목으로."""
    page = fetch(CLAUDE_API_NOTES).decode("utf-8", "replace")
    parts = re.split(r'<h3 id="([a-z]+-\d{1,2}-\d{4})"', page)
    days = []
    for slug, body in zip(parts[1::2], parts[2::2]):
        try:
            when = datetime.strptime(slug, "%B-%d-%Y").replace(tzinfo=timezone.utc)
        except ValueError:
            continue
        if now - when <= timedelta(days=WINDOW_DAYS):
            items = [_text(li) for li in re.findall(r"<li[^>]*>(.*?)</li>", body.split("<h2", 1)[0], re.S)]
            days.append((when, [i for i in items if i]))
    days = [d for d in days if d[1]]
    if not days:
        return []
    days.sort()
    notes = "\n\n".join(f"[{w.date()}]\n" + "\n".join(f"- {i}" for i in its) for w, its in reversed(days))[:NOTES_CHARS]
    n = sum(len(its) for _, its in days)
    return [{"source": "claude_api", "source_label": "Claude API", "kind": "release", "category": "Release",
             "title_en": f"Claude API release notes ({n} changes)", "title_ko": f"Claude API 변경 사항 {n}건",
             "url": CLAUDE_API_NOTES, "published_at": days[-1][0], "notes": notes}]


def from_anthropic(seen: dict) -> list[dict]:
    """RSS가 없다. 사이트맵의 /news·/research 글 중 처음 보는 주소만 페이지를 읽어 datePublished·제목을 seen에 남긴다."""
    root = ET.fromstring(fetch("https://www.anthropic.com/sitemap.xml"))
    out = []
    for u in root:
        loc = _children(u).get("loc", "")
        m = re.search(r"/(news|research)/[^/]+$", loc)
        if not m:
            continue
        if loc not in seen:
            seen[loc] = None  # 읽지 못한 페이지(게시일 없음)도 다시 읽지 않는다
            try:
                page = fetch(loc).decode("utf-8", "replace")
                d = re.search(r'"datePublished"\s*:\s*"([^"]+)"', page)
                t = re.search(r"<title>(.*?)</title>", page, re.S)
                if d and t:
                    seen[loc] = {"published_at": d.group(1), "title_en": html.unescape(t.group(1)).replace(" \\ Anthropic", "").strip()}
            except OSError:
                del seen[loc]  # 네트워크 오류는 다음에 다시
            time.sleep(0.4)  # 사이트에 부담 주지 않게
        if seen.get(loc):
            out.append({"source": "anthropic", "source_label": "Anthropic", "kind": "post",
                        "category": "Research" if m.group(1) == "research" else "News",
                        "title_en": seen[loc]["title_en"], "url": loc, "published_at": _date(seen[loc]["published_at"])})
    return out


# 실행 사이에 남기는 상태(anthropic_seen·digest_cache). DB가 있으면 worker_state 테이블, 없으면 worker/out 파일.
# GitHub Actions는 매번 빈 머신이라 파일만으로는 첫 실행(40분대)을 매일 되풀이한다.
def load_state(db, key: str, path: Path) -> dict:
    if db:
        rows = db.select("worker_state", f"key=eq.{key}&select=value")
        if rows:
            return rows[0]["value"]
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def save_state(db, key: str, path: Path, value: dict):
    OUT.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=1), encoding="utf-8")
    if db:
        db.upsert("worker_state", [{"key": key, "value": value, "updated_at": datetime.now(timezone.utc).isoformat()}], "key")


NEWS_COLUMNS = ("id", "source", "source_label", "kind", "category", "title_en", "title_ko", "url", "published_at",
                "summary_ko", "key_points")
MODEL_COLUMNS = ("id", "rank", "author", "name", "task", "params", "license", "likes", "downloads", "created_at",
                 "arxiv", "url", "card")


def save_db(db, items: list[dict], models: list[dict], now: datetime):
    """소식은 쌓고(주소마다 한 줄, 다시 모으면 덮어쓴다), 모델 순위는 이번 실행 것으로 바꾼다."""
    stamp = now.isoformat()
    db.upsert("official_news", [{**{k: i.get(k) for k in NEWS_COLUMNS}, "key_points": i.get("key_points") or [],
                                 "collected_at": stamp} for i in items], "id")
    if models:  # 트렌딩을 못 받은 날은 어제 순위를 그대로 둔다
        db.upsert("trending_models", [{**{k: m.get(k) for k in MODEL_COLUMNS}, "collected_at": stamp} for m in models], "id")
        db._req("DELETE", f"trending_models?collected_at=lt.{urllib.parse.quote(stamp)}", prefer="return=minimal")


def pick(items: list[dict], now: datetime) -> list[dict]:
    recent = [i for i in items if now - i["published_at"] <= timedelta(days=WINDOW_DAYS)]
    recent.sort(key=lambda i: i["published_at"], reverse=True)
    return recent[:PER_SOURCE]


TRANSLATE_SYSTEM = (
    "You translate English headlines from AI lab blogs into natural, concise Korean headlines for a Korean reading app. "
    "Keep product, model, company and benchmark names in their original spelling. Do not add or remove information. "
    "Return only a JSON object: {\"titles\": [\"...\", ...]} with exactly one Korean title per input, in the same order."
)


def translate(titles: list[str], api_key: str, log) -> list[str] | None:
    msgs = [{"role": "system", "content": TRANSLATE_SYSTEM},
            {"role": "user", "content": json.dumps({"titles": titles}, ensure_ascii=False)}]

    def check(out):
        t = out.get("titles") if isinstance(out, dict) else None
        if not isinstance(t, list) or len(t) != len(titles) or not all(isinstance(x, str) and x.strip() for x in t):
            return ["titles_mismatch"]
        return []

    out, _ = llm.generate(api_key, msgs, check, log)
    return [x.strip() for x in out["titles"]] if out else None


# 앱 문장은 해요체(공지·안내와 같은 말투). 릴리스 요약이 「추가되었습니다」로 나왔다(실기기 QA).
HAEYO = (" Write every Korean sentence in the polite 해요체 used by Korean consumer apps, with endings like "
         "~해요, ~했어요, ~돼요, ~됐어요, ~있어요. Never use 합니다체 (~합니다, ~했습니다, ~됩니다) or plain ~다 endings.")


def not_haeyo(texts) -> bool:
    """한 문장이라도 「~다」(합니다체·평서형)로 끝나면 True. 명사로 끝나는 짧은 문장은 그대로 둔다."""
    return any(isinstance(t, str) and t.strip().rstrip(".!?\"')]").endswith("다") for t in texts)


RELEASE_SYSTEM = (
    "You summarize software release notes for Korean developers. Use only the release notes given; do not guess or add anything. "
    "Pick the up to 3 changes a developer would care about most (new features first, then important fixes). "
    "Write each as one short Korean sentence; keep API, feature, flag and product names in their original spelling. "
    "Return only a JSON object: {\"points\": [\"...\"]} with 1 to 3 items."
) + HAEYO


def summarize_release(notes: str, api_key: str, log) -> list[dict] | None:
    msgs = [{"role": "system", "content": RELEASE_SYSTEM}, {"role": "user", "content": notes}]

    def check(out):
        p = out.get("points") if isinstance(out, dict) else None
        ok = isinstance(p, list) and 1 <= len(p) <= 3 and all(isinstance(x, str) and x.strip() for x in p)
        return ([] if not not_haeyo(p) else ["not_haeyo"]) if ok else ["points_invalid"]

    out, _ = llm.generate(api_key, msgs, check, log)
    return [{"text": x.strip()} for x in out["points"]] if out else None


POST_SYSTEM = (
    "You write a short Korean digest of an English blog post for Korean developers. Use only the numbered paragraphs given. "
    "Do not guess, add facts, or translate the whole post. Keep product, model, company and benchmark names in their original spelling. "
    "Return only a JSON object: {\"summary\": \"...\", \"points\": [{\"text\": \"...\", \"para\": N, \"quote\": \"...\"}]}. "
    "summary: 1 or 2 Korean sentences on what the post is about. points: up to 3 key points, each one Korean sentence, "
    "para: the number of the paragraph that supports it, quote: 3 to 10 consecutive words copied exactly from that paragraph. "
    "If the paragraphs are too short for key points, return an empty points list."
) + HAEYO


def summarize_post(title: str, paras: list[str], api_key: str, log) -> tuple[str, list[dict]] | None:
    body, used = [], 0
    for i, p in enumerate(paras, 1):
        if used + len(p) > BODY_CHARS:
            break
        body.append(f"[{i}] {p}")
        used += len(p)
    msgs = [{"role": "system", "content": POST_SYSTEM}, {"role": "user", "content": f"TITLE: {title}\n\n" + "\n\n".join(body)}]

    def check(out):
        if not isinstance(out, dict) or not isinstance(out.get("summary"), str) or not out["summary"].strip():
            return ["summary_missing"]
        pts = out.get("points")
        if not isinstance(pts, list) or len(pts) > 3:
            return ["points_invalid"]
        for pt in pts:
            if not (isinstance(pt, dict) and isinstance(pt.get("text"), str) and isinstance(pt.get("para"), int) and 1 <= pt["para"] <= len(body)):
                return ["point_evidence_invalid"]  # 근거 문단이 없는 핵심 내용은 받지 않는다
        return ["not_haeyo"] if not_haeyo([out["summary"]] + [pt["text"] for pt in pts]) else []

    out, _ = llm.generate(api_key, msgs, check, log)
    if not out:
        return None
    points = []
    for pt in out["points"]:
        q = (pt.get("quote") or "").strip()
        # 구절이 그 문단에 실제로 있어야 원문의 그 자리로 여는 링크를 단다(없으면 문단 번호만)
        points.append({"text": pt["text"].strip(), "para": pt["para"], "quote": q if q and q in paras[pt["para"] - 1] else None})
    return out["summary"].strip(), points


def from_hf_trending() -> list[dict]:
    out = []
    for m in json.loads(fetch(HF_TRENDING)):
        tags = m.get("tags") or []
        if m.get("pipeline_tag") not in MODEL_TASKS or MODEL_BLOCK.search(m["id"] + " " + " ".join(tags)):
            continue
        info = json.loads(fetch(f"https://huggingface.co/api/models/{m['id']}"))
        lic = next((t.split(":", 1)[1] for t in tags if t.startswith("license:")), None)
        out.append({"id": m["id"], "author": info.get("author") or m["id"].split("/")[0], "name": m["id"].split("/")[-1],
                    "task": m.get("pipeline_tag"), "params": (info.get("safetensors") or {}).get("total"),
                    "license": lic, "likes": info.get("likes"), "downloads": info.get("downloads"),
                    "created_at": info.get("createdAt"), "rank": len(out) + 1,
                    "arxiv": [t.split(":", 1)[1] for t in tags if t.startswith("arxiv:")][:1] or None,
                    "url": f"https://huggingface.co/{m['id']}"})
        if len(out) == TRENDING_TOP:
            break
    return out


CARD_SYSTEM = (
    "You read a Hugging Face model card and report, in Korean, only what the model's makers claim in it. Do not guess or use outside knowledge. "
    "Return only a JSON object: {\"strengths\": [\"...\"], \"benchmarks\": [{\"name\": \"...\", \"score\": \"...\"}], \"limitation\": \"...\" or null}. "
    "strengths: up to 3 short Korean sentences on what the makers say the model is for or good at. "
    "benchmarks: up to 4 benchmark results the makers report for this model, name exactly as written and score as written (e.g. \"74.2%\"). "
    "limitation: one Korean sentence on a limitation the makers state, or null. Use empty lists when the card says nothing."
) + HAEYO


def summarize_card(card: str, api_key: str, log) -> dict | None:
    msgs = [{"role": "system", "content": CARD_SYSTEM}, {"role": "user", "content": card[:CARD_CHARS]}]

    def check(out):
        if not isinstance(out, dict):
            return ["not_object"]
        st, bm, lim = out.get("strengths"), out.get("benchmarks"), out.get("limitation")
        ok = (isinstance(st, list) and len(st) <= 3 and all(isinstance(x, str) for x in st)
              and isinstance(bm, list) and len(bm) <= 4
              and all(isinstance(b, dict) and isinstance(b.get("name"), str) and isinstance(b.get("score"), str) for b in bm)
              and (lim is None or isinstance(lim, str)))
        if not ok:
            return ["card_shape"]
        return ["not_haeyo"] if not_haeyo(st + [lim]) else []

    out, _ = llm.generate(api_key, msgs, check, log)
    if not out:
        return None
    # 점수는 카드 원문에 그대로 있어야 한다(지어낸 숫자를 막는다)
    out["benchmarks"] = [b for b in out["benchmarks"] if b["score"].strip() and b["score"].strip() in card]
    return out


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-llm", action="store_true")
    ap.add_argument("--no-db", action="store_true", help="Supabase 설정이 있어도 파일로만")
    args = ap.parse_args(argv)
    now = datetime.now(timezone.utc)
    url, secret = setting("SUPABASE_URL"), setting("SUPABASE_SERVICE_ROLE_KEY")
    db = Db(url, secret) if url and secret and not args.no_db else None

    items, report = [], []
    for source, label, url in RSS_SOURCES:
        try:
            got = pick(from_rss(source, label, url), now)
        except Exception as e:  # 한 출처가 깨져도 나머지는 모은다
            report.append(f"{label}: 실패 {e!r}")
            continue
        report.append(f"{label}: {len(got)}개")
        items += got
    # 권리자 삭제 요청(docs/RIGHTS.md 6장): worker_state의 blocked_urls에 넣은 주소는 다시 모으지 않는다
    blocked = set(load_state(db, "blocked_urls", OUT / "blocked_urls.json").get("urls", []))
    seen = load_state(db, "anthropic_seen", ANTHROPIC_SEEN)
    try:
        got = pick(from_anthropic(seen), now)
        report.append(f"Anthropic: {len(got)}개")
        items += got
    except Exception as e:
        report.append(f"Anthropic: 실패 {e!r}")
    save_state(db, "anthropic_seen", ANTHROPIC_SEEN, seen)
    releases = []
    for source, label, url, page in RELEASE_SOURCES:
        try:
            got = from_releases(source, label, url, page, now)
            report.append(f"{label} 릴리스: {got[0]['title_ko'] if got else '이번 주 없음'}")
            releases += got
        except Exception as e:
            report.append(f"{label} 릴리스: 실패 {e!r}")
    try:
        got = from_claude_api_notes(now)
        report.append(f"Claude API 릴리스 노트: {got[0]['title_ko'] if got else '없음'}")
        releases += got
    except Exception as e:
        report.append(f"Claude API 릴리스 노트: 실패 {e!r}")

    try:
        models = from_hf_trending()
        report.append(f"HF 트렌딩 모델: {len(models)}개")
    except Exception as e:
        models = []
        report.append(f"HF 트렌딩 모델: 실패 {e!r}")

    items = [i for i in items if i["url"] not in blocked]
    releases = [r for r in releases if r["url"] not in blocked]
    models = [m for m in models if m["url"] not in blocked]
    key = None if args.no_llm else llm.api_key()
    cache = load_state(db, "digest_cache", DIGEST_CACHE)
    # 다른 제공처로 만든 번역·요약은 버리고 새로 만든다(NVIDIA 무료 등급 결과는 다른 사람에게 보여 줄 수 없다)
    if key and cache.get("_provider") != llm.provider():
        report.append(f"캐시 제공처 {cache.get('_provider', '표시 없음')} → {llm.provider()}: 번역·요약 다시 만들기")
        cache = {}
    if key:
        cache["_provider"] = llm.provider()
    for item in items:
        hit = cache.get(item["url"], {})
        if not_haeyo([hit.get("summary_ko")] + [p.get("text") for p in hit.get("key_points") or []]):
            hit = {"title_ko": hit.get("title_ko")}  # 예전 합니다체 요약은 다시 만든다(제목 번역은 그대로)
        item.update({k: v for k, v in hit.items() if k in ("title_ko", "summary_ko", "key_points")})
    todo = [i for i in items if not i.get("title_ko")]
    ko = translate([i["title_en"] for i in todo], key, lambda e: None) if key and todo else None
    report.append(f"제목 번역: 새 {len(todo)}개 " + ("완료" if ko or not todo else "건너뜀(키 없음)" if not key else "실패, 원문만"))
    for i, item in enumerate(todo):
        item["title_ko"] = ko[i] if ko else None
    def digest_post(item):
        if item.get("summary_ko"):
            return  # 지난 실행에서 요약했다
        try:
            paras = body_paragraphs(item)
        except Exception:
            paras = []
        got = summarize_post(item["title_en"], paras, key, lambda e: None) if key and paras else None
        item["summary_ko"], item["key_points"] = got if got else (None, [])

    def digest_release(r):
        hit = cache.get(r["title_en"])
        if hit and not_haeyo([p.get("text") for p in hit["key_points"]]):
            hit = None
        r["key_points"] = hit["key_points"] if hit else (summarize_release(r["notes"], key, lambda e: None) if key else None) or []

    def digest_model(m):
        hit = cache.get(m["url"])
        if hit and hit["card"] and not_haeyo(hit["card"]["strengths"] + [hit["card"].get("limitation")]):
            hit = None
        if hit:
            m["card"] = hit["card"]
            return
        try:
            card = fetch(f"https://huggingface.co/{m['id']}/raw/main/README.md").decode("utf-8", "replace")
        except OSError:
            card = ""
        # 설명이 거의 없는 카드(예 LTX-2.5, 126자)는 「밝히지 않았어요」로 둔다
        m["card"] = summarize_card(card, key, lambda e: None) if key and len(card) >= 300 else None

    with ThreadPoolExecutor(max_workers=4) as pool:  # 글·릴리스·모델마다 LLM 호출이 하나씩이라 몇 개씩 같이 돌린다
        list(pool.map(digest_post, items))
        list(pool.map(digest_release, releases))
        list(pool.map(digest_model, models))
    report.append(f"글 요약: {sum(bool(i['summary_ko']) for i in items)}/{len(items)}, "
                  f"릴리스 요약: {sum(bool(r['key_points']) for r in releases)}/{len(releases)}, "
                  f"모델 카드: {sum(bool(m['card']) for m in models)}/{len(models)}")
    for i in items:
        if i.get("summary_ko"):
            cache[i["url"]] = {"title_ko": i["title_ko"], "summary_ko": i["summary_ko"], "key_points": i["key_points"]}
    for r in releases:
        if r["key_points"]:
            cache[r["title_en"]] = {"key_points": r["key_points"]}
    for m in models:
        if m["card"] is not None:
            cache[m["url"]] = {"card": m["card"]}
    save_state(db, "digest_cache", DIGEST_CACHE, cache)
    items += releases
    for item in items:
        item.pop("_desc", None)
        item.pop("notes", None)
        item["id"] = hashlib.sha1(item["url"].encode()).hexdigest()[:12]  # 앱 상세 화면 주소용
        item["published_at"] = item["published_at"].astimezone(timezone.utc).isoformat()

    items.sort(key=lambda i: i["published_at"], reverse=True)
    OUT.mkdir(parents=True, exist_ok=True)
    doc = {"collected_at": now.isoformat(), "window_days": WINDOW_DAYS, "items": items, "models": models}
    (OUT / "official_news.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
    (OUT / "official_news.define.json").write_text(
        json.dumps({"OFFICIAL_NEWS_PREVIEW": json.dumps(doc, ensure_ascii=False)}, ensure_ascii=False), encoding="utf-8")
    if db:
        save_db(db, items, models, now)
        report.append(f"DB 저장: 소식 {len(items)}개, 모델 {len(models)}개")
    print("\n".join(report))
    print(f"총 {len(items)}개 → {OUT / 'official_news.json'}")


if __name__ == "__main__":
    sys.exit(main())
