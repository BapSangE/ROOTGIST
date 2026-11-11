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
import base64
import difflib
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

from . import glossary, llm, x_posts
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
NEWS_TERMS_SEEN = OUT / "news_terms_seen.json"  # 용어 후보를 이미 물어본 소식·모델 id

HF_TRENDING = "https://huggingface.co/api/models?sort=trendingScore&limit=100"
TRENDING_TOP = 10  # 「트렌딩」 칸
NEW_DAYS, NEW_TOP = 14, 20  # 「새로 나옴」 칸 후보: 트렌딩 100위 안에서 최근 14일 안에 공개된 모델 20개까지(앱이 최신순 10개를 보인다)
# 앱에 보일 과제만(위에서부터 많이 쓰이는 것). 나머지 과제와 아래 낱말이 이름·태그에 있는 모델은 뺀다.
MODEL_TASKS = {"text-generation", "image-text-to-text", "text-to-image", "image-to-image", "image-to-video", "text-to-video",
               "text-to-speech", "automatic-speech-recognition", "any-to-any", "feature-extraction", "sentence-similarity"}
MODEL_BLOCK = re.compile(r"uncensor|nsfw|abliterat|erotic|porn|lewd|hentai|nude|18\+", re.I)
CARD_CHARS = 20000
CARD_VERSION = 2  # 2: 평가 항목마다 무엇을 재는지(about)·높을수록 좋은지(higher_better)(2026-11-10)

# OpenAI 피드에는 회사 소식·사례·정책 글이 섞여 있다. 개발 소식에 가까운 분류만.
OPENAI_CATEGORIES = {"Research", "Product", "Safety", "Safety & Alignment", "Publication"}
# 출처마다 받을 분류(하나라도 있으면)와 뺄 분류. 없는 출처는 모두 받는다.
KEEP_CATEGORIES = {
    "openai": OPENAI_CATEGORIES,
    "meta": {"AI Research"},  # Meta 엔지니어링 블로그: 광고·데이터센터·문화 글은 뺀다
    "nvidia": {"Open Source", "NVIDIA Research", "Research"},  # 회사 블로그: 제품 홍보·행사 글이 많아 오픈소스·연구만
    "nvidia_dev": {"Agentic AI / Generative AI", "NVIDIA Research"},  # 개발자 블로그: 하루 몇 편, AI 쪽만
}
DROP_CATEGORIES = {"nvidia": {"Gaming", "GeForce NOW", "Cloud Gaming"}}
# 데이터센터·AI 인프라 소식(사용자 요청 2026-11-03). 위 분류 필터가 버리던 인프라 글도 받고, 분류는 「Infrastructure」로 붙인다.
# 인프라 분류: 그 분류면 제목과 상관없이 받는다(Meta 「Prometheus: 기가와트급 슈퍼클러스터」, NVIDIA AI 팩토리 글이 빠지고 있었다).
INFRA_CATEGORIES = {"meta": {"Data Center Engineering", "Core Infra"}, "nvidia": {"AI Infrastructure", "AI Factory"}}
# 정책·회사 글이 섞인 분류: 제목에 인프라 낱말이 있을 때만(OpenAI는 데이터센터 부지 글을 Global Affairs로 낸다).
INFRA_BY_TITLE = {"openai": {"Global Affairs", "Company"}}
# 회사 전체 소식 피드: 제목에 인프라 낱말이 있는 글만 받는다.
INFRA_FEEDS = {"google", "microsoft", "azure", "amazon"}
INFRA_WORDS = re.compile(
    r"data ?cent(?:er|re)s?|gigawatts?|megawatts?|\b\d+(?:\.\d+)?\s?[GM]W\b|supercomput\w*|superclusters?|AI factor(?:y|ies)|"
    r"infrastructure|power plants?|nuclear|power grid|energy grid|liquid cooling|Stargate", re.I)
# HF 블로그의 /blog/<계정>/<글>은 누구나 쓸 수 있는 커뮤니티 글이라, 알려진 회사 계정만 그 회사 소식으로 받는다.
# 칩은 그 회사, 분류 자리에 「Hugging Face 블로그」. 계정 → (출처 id, 표시 이름)
HF_BLOG_ORGS = {
    "nvidia": ("nvidia", "NVIDIA"), "meta-llama": ("meta", "Meta"), "facebook": ("meta", "Meta"),
    "google": ("google", "Google"), "microsoft": ("microsoft", "Microsoft"), "ibm-granite": ("ibm", "IBM"),
    "ibm-research": ("ibm", "IBM"), "ibm": ("ibm", "IBM"), "allenai": ("ai2", "Ai2"), "LiquidAI": ("liquidai", "Liquid AI"),
    "Qwen": ("qwen", "Qwen"), "mistralai": ("mistral", "Mistral AI"), "amazon": ("amazon", "Amazon"),
    "deepseek-ai": ("deepseek", "DeepSeek"), "xai-org": ("xai", "xAI"), "openai": ("openai", "OpenAI"),
}
RSS_SOURCES = [
    # (id, 표시 이름, 피드)
    ("openai", "OpenAI", "https://openai.com/news/rss.xml"),
    ("deepmind", "Google DeepMind", "https://deepmind.google/blog/rss.xml"),
    ("google_research", "Google Research", "https://research.google/blog/rss/"),
    ("huggingface", "Hugging Face", "https://huggingface.co/blog/feed.xml"),
    # ai.meta.com은 RSS가 없고 robots.txt가 자동 수집을 금지한다. 엔지니어링 블로그는 RSS를 공개하고 robots.txt가 막지 않는다
    ("meta", "Meta", "https://engineering.fb.com/feed/"),
    ("nvidia", "NVIDIA", "https://blogs.nvidia.com/feed/"),
    ("nvidia_dev", "NVIDIA 개발자", "https://developer.nvidia.com/blog/feed"),
    # 공지 게시판만(직원 글). 일반 게시판은 하루 30개 넘는 사용자 질문이라 넣지 않는다.
    ("openai_community", "OpenAI 커뮤니티", "https://community.openai.com/c/announcements/6.rss"),
    # 데이터센터 소식(INFRA_FEEDS). 모두 robots.txt가 자동 수집을 막지 않는다(2026-11-03 확인).
    # Cloudflare·Open Compute Project는 robots.txt가 막고, AMD·Intel·Oracle은 피드가 없거나 접근을 막는다. 업계 언론은 넣지 않는다.
    ("google", "Google", "https://blog.google/inside-google/infrastructure/rss/"),
    ("microsoft", "Microsoft", "https://blogs.microsoft.com/feed/"),
    ("azure", "Microsoft Azure", "https://azure.microsoft.com/en-us/blog/feed/"),
    ("amazon", "Amazon", "https://www.aboutamazon.com/news/feed"),
]
RELEASE_DAYS = 7  # 릴리스는 이번 주 것을 한 항목으로
RELEASE_SOURCES = [
    # (id, 표시 이름, 릴리스 피드, 사람이 보는 페이지)
    ("claude_code", "Claude Code", "https://github.com/anthropics/claude-code/releases.atom", "https://github.com/anthropics/claude-code/releases"),
    ("anthropic_sdk", "Anthropic Python SDK", "https://github.com/anthropics/anthropic-sdk-python/releases.atom",
     "https://github.com/anthropics/anthropic-sdk-python/releases"),
    ("openai_sdk", "OpenAI Python SDK", "https://github.com/openai/openai-python/releases.atom", "https://github.com/openai/openai-python/releases"),
    # x.ai 뉴스는 자동 접근을 막는다(403, 우회하지 않는다). 개발자에게 바로 쓸모 있는 SDK 릴리스만
    ("xai_sdk", "xAI Python SDK", "https://github.com/xai-org/xai-sdk-python/releases.atom", "https://github.com/xai-org/xai-sdk-python/releases"),
]
CLAUDE_API_NOTES = "https://docs.claude.com/en/release-notes/overview"
# 개발자 화제(kind=hot): 공식 발표가 아닌, 개발자들이 많이 본 글과 새 도구. 공식 API만 쓴다.
HN_SEARCH = "https://hn.algolia.com/api/v1/search_by_date"  # Hacker News 공식 검색 API(Algolia)
HN_HOURS, HN_MIN_POINTS, HN_TOP = 36, 60, 15  # 최근 36시간, 60점 이상, AI 관련 상위 15개
GH_SEARCH = "https://api.github.com/search/repositories"  # GitHub 공식 검색 API
GH_TOPICS, GH_DAYS, GH_MIN_STARS, GH_TOP = ("llm", "ai-agents", "generative-ai"), 7, 100, 5
# 순위는 별 총합이 아니라 「뜨는 속도」(HN 순위식): 별 ÷ (생긴 뒤 시간 + 12)^1.5. 별 총합 순이면 별을 모을 시간이 길었던
# 며칠 전 저장소가 늘 위에 남아 어제오늘 뜬 도구가 보이지 않았다(2026-11-06). +12시간은 갓 생긴 저장소가 별 백여 개로 튀지 않게.
GH_AGE_PAD_H, GH_GRAVITY, GH_HN_BOOST = 12, 1.5, 2.0
GH_MIN_KB = 20  # 거의 빈 저장소(README만)는 뺀다
GH_LIST = re.compile(r"\bawesome\b|\b(curated|collection of|list of)\b", re.I)  # 링크 모음은 「새 도구」가 아니다
# 제목으로 AI 관련 글만 고른다(HN 첫 화면은 AI 외 글이 대부분)
AI_WORDS = re.compile(
    r"\b(AI|LLMs?|GPT[- ]?\d*|ChatGPT|Claude|Gemini|Anthropic|OpenAI|Llama|Mistral|DeepSeek|Qwen|Grok|Copilot|Codex|Cursor|"
    r"(?:AI|coding|LLM) agents?|agentic|transformers?|diffusion models?|inference|RAG|MCP|neural|machine learning|deep learning|"
    r"fine-?tun\w*|embeddings?|prompt\w*|world models?|vibe cod\w*)\b", re.I)  # 「agents」「tokens」만으로는 안 고른다(ICE 요원 기사가 걸렸다)
# 글이 실린 사이트 → 칩 이름. 모르는 사이트는 주소(www. 뺌) 그대로
SITE_NAMES = {"mistral.ai": "Mistral AI", "openai.com": "OpenAI", "anthropic.com": "Anthropic", "deepmind.google": "Google DeepMind",
              "blog.google": "Google", "ai.meta.com": "Meta", "x.ai": "xAI", "huggingface.co": "Hugging Face", "github.com": "GitHub",
              "news.ycombinator.com": "Hacker News", "nvidia.com": "NVIDIA", "blogs.nvidia.com": "NVIDIA"}
NOTES_CHARS = 8000  # 요약에 넘길 릴리스 노트 길이 상한
MAX_PARAS, BODY_CHARS = 60, 12000  # 글 요약에 넘길 문단 수·길이 상한


def fetch(url: str) -> bytes:
    headers = {"User-Agent": UA, "Accept-Encoding": "gzip"}
    # GitHub 검색은 키 없이 분당 10번이라, 배치(Actions)가 넘겨 주는 GITHUB_TOKEN이 있으면 붙인다(분당 30번)
    if url.startswith("https://api.github.com/") and (token := setting("GITHUB_TOKEN")):
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()
        # DeepMind는 gzip으로 보낸다
        return gzip.decompress(body) if r.headers.get("Content-Encoding") == "gzip" or body[:2] == b"\x1f\x8b" else body


# 피드·페이지 제목이 주소 끝 조각뿐인 글(HF 블로그에서 제목을 안 정한 「nemotron-halloween」, 2026-11-02).
# 본문의 첫 진짜 제목(h1)을 쓴다. 못 찾으면 그대로 둔다.
SLUG = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)+")


def is_slug_title(title: str, url: str) -> bool:
    return bool(SLUG.fullmatch(title)) and url.rstrip("/").rsplit("/", 1)[-1] == title


def heading_title(page: str, slug: str) -> str | None:
    for m in re.finditer(r"<h1\b.*?>(.*?)</h1>", page, re.S):
        t = _text(m.group(1).rsplit('">', 1)[-1])  # 클래스 값 속 「>」(&amp;>a)를 지나 실제 글자만
        if t and " " in t and t.lower() != slug:
            return t
    return None


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
        # RSS는 <category>글자</category>, Atom은 <category term="…"/>
        cats = [html.unescape(t) for c in item if c.tag.split("}")[-1] == "category" and (t := (c.text or c.get("term") or "").strip())]
        link = k.get("link", "")
        title = html.unescape(k.get("title", "")).strip()
        infra = bool(set(cats) & INFRA_CATEGORIES.get(source, set())
                     or (source in INFRA_FEEDS or set(cats) & INFRA_BY_TITLE.get(source, set())) and INFRA_WORDS.search(title))
        if source in INFRA_FEEDS and not infra:
            continue
        if not infra and source in KEEP_CATEGORIES and not set(cats) & KEEP_CATEGORIES[source]:
            continue
        if set(cats) & DROP_CATEGORIES.get(source, set()) or (source == "nvidia" and not infra and any(c.startswith("GTC") for c in cats)):
            continue  # NVIDIA 행사(GTC) 기간 글은 지역 사례·홍보가 대부분(인프라 발표는 받는다)
        src, lab, cat = source, label, ("Infrastructure" if infra else cats[0] if cats else None)
        if source == "huggingface":
            path = link.split("/blog/", 1)[-1].strip("/").split("/")
            if len(path) == 2 and path[0] in HF_BLOG_ORGS:
                (src, lab), cat = HF_BLOG_ORGS[path[0]], "Hugging Face Blog"
            elif len(path) != 1:  # 모르는 계정의 커뮤니티 글
                continue
        when = _date(k.get("pubDate") or k.get("published") or k.get("updated") or "")
        if not when:
            continue
        notice = source.endswith("_community")
        out.append({"source": src, "source_label": lab, "kind": "notice" if notice else "post",
                    "category": "Announcement" if notice else cat,
                    "title_en": title, "url": link, "published_at": when,
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
    if item["source"] == "github":  # 저장소 설명 한 줄(번역만)
        return [item["_desc"]]
    if item["kind"] == "hot" and (item["url"].startswith("https://news.ycombinator.com/") or not robots_allow(item["url"])):
        return []  # robots.txt가 막는 사이트·HN 안의 글은 요약 없이 제목·점수·링크만
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


_robots: dict[str, object] = {}


def robots_allow(url: str) -> bool:
    """원문 사이트의 robots.txt가 우리 수집기를 허용하는지(화제 글 요약 전에). 못 읽으면 허용으로 본다(표준 관례)."""
    from urllib import robotparser

    host = urllib.parse.urlsplit(url)
    base = f"{host.scheme}://{host.netloc}"
    if base not in _robots:
        rp = robotparser.RobotFileParser()
        try:
            rp.parse(fetch(base + "/robots.txt").decode("utf-8", "replace").splitlines())
        except Exception:
            rp = None
        _robots[base] = rp
    rp = _robots[base]
    return rp is None or rp.can_fetch(UA, url)


def site_label(url: str) -> str:
    host = urllib.parse.urlsplit(url).netloc.lower().removeprefix("www.")
    return SITE_NAMES.get(host) or next((v for k, v in SITE_NAMES.items() if host.endswith("." + k)), host)


def from_hn(now: datetime) -> list[dict]:
    """Hacker News: 최근 36시간 60점 넘는 글 중 제목이 AI 관련인 것, 점수 순 15개. 점수·댓글은 실행마다 새로 받는다."""
    q = urllib.parse.urlencode({"tags": "story", "hitsPerPage": 200,
                                "numericFilters": f"created_at_i>{int((now - timedelta(hours=HN_HOURS)).timestamp())},points>={HN_MIN_POINTS}"})
    hits = json.loads(fetch(f"{HN_SEARCH}?{q}"))["hits"]
    out = []
    for h in sorted(hits, key=lambda h: -(h.get("points") or 0)):
        title = (h.get("title") or "").strip()
        if not AI_WORDS.search(title):
            continue
        discussion = f"https://news.ycombinator.com/item?id={h['objectID']}"
        url = h.get("url") or discussion  # Ask HN 등 본문이 HN에 있는 글
        out.append({"source": "hn", "source_label": site_label(url), "kind": "hot", "category": "Hacker News",
                    "title_en": html.unescape(title), "url": url, "published_at": _date(h["created_at"]),
                    "points": h.get("points") or 0, "comments": h.get("num_comments") or 0, "discussion_url": discussion,
                    "_desc": ""})
        if len(out) == HN_TOP:
            break
    return out


_CJK = re.compile(r"[\u3040-\u30ff\u4e00-\u9fff]")  # 일본어 가나·한자(한글은 뺀다)


def gh_score(stars: int, created: datetime, now: datetime, on_hn: bool = False) -> float:
    """뜨는 속도: 별 ÷ (생긴 뒤 시간 + 12)^1.5. Hacker News에도 올라온 저장소는 두 배."""
    hours = max((now - created).total_seconds() / 3600, 0)
    return stars / (hours + GH_AGE_PAD_H) ** GH_GRAVITY * (GH_HN_BOOST if on_hn else 1)


def gh_quality(r: dict) -> bool:
    """「새 도구」로 보기 어려운 저장소를 거른다: 설명 없음·대부분 중국어·일본어(실데이터: 상위가 안드로이드용 중국어 저장소),
    링크 모음(awesome-·curated list), 거의 빈 저장소, 별은 모였는데 포크가 하나도 없는 저장소(별을 부풀린 경우가 많다)."""
    desc = (r.get("description") or "").strip()
    if not desc or len(_CJK.findall(desc)) > len(desc) * 0.2:
        return False
    if GH_LIST.search(r.get("name", "")) or GH_LIST.search(desc):
        return False
    if r.get("size") is not None and r["size"] < GH_MIN_KB:
        return False
    return not (r.get("forks_count") == 0 and (r.get("stargazers_count") or 0) >= GH_MIN_STARS)


def from_github(now: datetime, hn_urls: set[str] = frozenset()) -> list[dict]:
    """GitHub: 최근 7일 안에 생긴 AI 저장소(별 100개 이상) 중 품질 거르기를 지난 것을 뜨는 속도 순 5개.
    hn_urls(Hacker News 화제 주소)에 있는 저장소는 점수를 더 준다. 설명은 「원문 소개문」처럼 번역만 한다."""
    since = (now - timedelta(days=GH_DAYS)).date().isoformat()
    hn = {_norm_url(u) for u in hn_urls}
    found: dict[str, dict] = {}
    for topic in GH_TOPICS:
        # 별 순 상위만 받으면 막 뜨는 저장소가 빠지므로 넉넉히(30개) 받아 아래에서 속도로 다시 세운다
        q = urllib.parse.urlencode({"q": f"topic:{topic} created:>={since} stars:>={GH_MIN_STARS}", "sort": "stars",
                                    "order": "desc", "per_page": 30})
        for r in json.loads(fetch(f"{GH_SEARCH}?{q}"))["items"]:
            if r["html_url"] in found or not gh_quality(r):
                continue
            desc = r["description"].strip()
            created = _date(r["created_at"])
            stars = r.get("stargazers_count") or 0
            found[r["html_url"]] = {
                "source": "github", "source_label": "GitHub", "kind": "hot", "category": "GitHub",
                "title_en": f"{r['name']}: {desc}"[:160], "url": r["html_url"], "published_at": created,
                "points": stars, "comments": None, "discussion_url": None, "_desc": desc,
                "_score": gh_score(stars, created, now, _norm_url(r["html_url"]) in hn)}
    return sorted(found.values(), key=lambda i: -i["_score"])[:GH_TOP]


# GitHub 칸의 기간별 순위(2026-11-10): 일간·주간·월간. GitHub는 「기간 동안 늘어난 별」을 주지 않으므로
# 「그 기간 안에 생긴 저장소」를 별 많은 순으로 세운다. 기간 시작·끝은 앱이 그대로 보여 준다(언제부터 언제 기준인지).
# 주제(topic)로만 찾으면 갓 생긴 저장소는 주제를 아직 안 달아 하루치가 2~4개뿐이었다(실데이터) → 이름·설명·주제의 낱말로 찾는다
# (GitHub 검색은 OR를 다섯 개까지만 받는다). 갓 생긴 저장소는 별이 적어 기간이 짧을수록 최소 별 수를 낮춘다.
GH_PERIODS = (("day", timedelta(days=1), 10), ("week", timedelta(days=7), 50), ("month", timedelta(days=30), 100))
GH_RANK_WORDS = "llm OR agent OR ai OR claude OR mcp in:name,description,topics"
GH_RANK_TOP = 20
# 낱말 검색에는 게임 치트·「무료 정품 인증」 같은 홍보 저장소가 섞인다(포크 0개로 별 40개씩, 실데이터 2026-11-10)
GH_SPAM = re.compile(r"\b(cheats?|hacks?|crack(ed)?|keygen|aimbot|esp|pre-?activated|free[- ]?(claude|gpt|chatgpt|opus))\b", re.I)


def gh_rank_ok(r: dict) -> bool:
    """순위에 넣을 저장소: 「새 도구」 거르기(gh_quality) + 홍보 낱말 없음 + 포크가 하나는 있음(아무도 안 써 본 저장소는 뺀다)."""
    text = f"{r.get('name', '')} {r.get('description') or ''}"
    return gh_quality(r) and not GH_SPAM.search(text) and (r.get("forks_count") or 0) >= 1


def gh_rankings(now: datetime) -> dict[str, dict]:
    """{기간: {"start", "end", "repos": [...]}}. 기간 안에 생긴 AI 저장소를 별 많은 순으로 받아,
    거르기(gh_rank_ok)를 지난 것 20개. 한 기간이 실패해도 나머지는 돌려준다."""
    out: dict[str, dict] = {}
    for period, span, min_stars in GH_PERIODS:
        start = now - span
        since = start.strftime("%Y-%m-%dT%H:%M:%SZ")
        q = urllib.parse.urlencode({"q": f"{GH_RANK_WORDS} created:>={since} stars:>={min_stars}", "sort": "stars",
                                    "order": "desc", "per_page": 100})
        try:
            items = json.loads(fetch(f"{GH_SEARCH}?{q}"))["items"]
        except Exception:
            continue
        found: dict[str, dict] = {}
        for r in items:
            if r["html_url"] in found or not gh_rank_ok(r):
                continue
            found[r["html_url"]] = {
                "full_name": r["full_name"], "url": r["html_url"], "description_en": r["description"].strip()[:300],
                "language": r.get("language"), "stars": r.get("stargazers_count") or 0,
                "forks": r.get("forks_count") or 0, "created_at": _date(r["created_at"])}
        repos = sorted(found.values(), key=lambda x: (-x["stars"], x["full_name"]))[:GH_RANK_TOP]
        for i, x in enumerate(repos):
            x["rank"] = i + 1
        out[period] = {"start": start, "end": now, "repos": repos}
    return out


# 번호가 붙은 모델 이름(앱 briefing.dart의 출시 규칙과 같다): 「Mistral Large 4」「Gemini 4 Carbon」「GPT-6.1」 → mistral-large-4 …
MODEL_NAME = re.compile(r"\b(gpt|gemini|claude|llama|mistral|grok|qwen|deepseek|nemotron|gemma|phi|sora|veo|imagen)"
                        r"(?:[- ]?(v?\d+(?:\.\d+)*)|[- ](?!code\b)(\w+)[- ](\d+(?:\.\d+)*))", re.I)


def model_keys(text: str) -> set[str]:
    return {"-".join(p.lower() for p in m.groups() if p) for m in MODEL_NAME.finditer(text or "")}


def _norm_url(u: str) -> str:
    p = urllib.parse.urlsplit(u)
    return p.netloc.lower().removeprefix("www.") + p.path.rstrip("/")


def attach_hn(items: list[dict], hot: list[dict]) -> list[dict]:
    """HN 글이 이미 모은 공식 소식과 같은 글(주소)이거나 같은 모델·제품 이름을 다루면 따로 두지 않고 그 소식에 점수·댓글을 붙인다.
    남은 HN 글만 돌려준다. 공식 출처가 없는 발표(예: mistral.ai)는 그대로 남아 화제로 보인다."""
    official = {_norm_url(i["url"]): i for i in items}
    keys = [(names(i), i) for i in items]
    left = []
    for h in hot:
        if h["source"] != "hn":
            left.append(h)
            continue
        mk = model_keys(h["title_en"])
        same = (official.get(_norm_url(h["url"]))
                or next((i for k, i in keys if k & names(h)), None)
                or next((i for i in items if mk & model_keys(i.get("title_en", ""))), None))
        if same is None:
            left.append(h)
        elif (same.get("points") or 0) < h["points"]:
            same.update(points=h["points"], comments=h["comments"], discussion_url=h["discussion_url"])
    return left


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
X_TERM_DAYS = 3  # 용어 후보를 뽑을 X 글: 최근 며칠 안에 올라와 번역된 것


def extra_term_texts(db, rank_rows: list[dict], now: datetime) -> list[dict]:
    """소식·모델 글 말고도 용어 후보를 뽑을 한국어 글: 번역된 X 글, GitHub 순위 저장소의 한국어 설명.
    id 앞에 출처(x:, gh:)를 붙여 소식 id와 섞이지 않게 한다(이미 물어본 글은 news_terms_seen에 남는다)."""
    out = []
    since = (now - timedelta(days=X_TERM_DAYS)).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        posts = db.select_all("x_posts", f"text_ko=not.is.null&posted_at=gte.{since}&select=id,text_ko&order=posted_at.desc")
    except Exception:  # x_posts 테이블이 없는 환경
        posts = []
    out += [{"id": f"x:{p['id']}", "summary_ko": p["text_ko"]} for p in posts if (p.get("text_ko") or "").strip()]
    repos = {r["full_name"]: r.get("description_ko") for r in rank_rows if (r.get("description_ko") or "").strip()}
    out += [{"id": f"gh:{name}", "summary_ko": ko} for name, ko in repos.items()]
    return out


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
                "summary_ko", "key_points", "thin", "related", "points", "comments", "discussion_url")
RANK_COLUMNS = ("id", "period", "rank", "full_name", "url", "description_en", "description_ko", "language", "stars", "forks",
                "created_at", "period_start", "period_end", "readme_ko")
MODEL_COLUMNS = ("id", "rank", "author", "name", "task", "params", "license", "likes", "downloads", "created_at",
                 "arxiv", "url", "card", "variants")


# 관련 소식: 같은 실행에서 모은 공식 자료끼리, 모델·제품 이름처럼 확실한 이름이 겹칠 때만 잇는다
# (예: 「Introducing GPT-6.1 Terra」 ↔ OpenAI Python SDK 릴리스 「gpt-6.1-terra 모델 식별자 추가」).
# 이름 = 「영문자-숫자」로 시작하는 7자 이상(gpt-6.1-terra, claude-opus-5, gemini-4-argon). 띄어쓰기는 -로 본다.
# 「gpt-6」처럼 짧은 이름은 같은 계열 글을 다 잇게 되어 뺀다.
NAME = re.compile(r"[a-z]+(?:-[a-z]+)*-\d+(?:\.\d+)*(?:-[a-z]+)?")
SKIP = {"introducing", "developing", "building", "using", "with", "for", "and", "the", "new", "our", "api에"}


def names(item: dict) -> set[str]:
    text = " ".join([item.get("title_en") or "", item.get("_desc") or "", item.get("notes") or "",
                     *[p.get("text", "") for p in item.get("key_points") or []]])
    flat = re.sub(r"\s+", "-", text.lower())
    out = set()
    for n in NAME.findall(flat):
        parts = n.split("-")
        while parts and parts[0] in SKIP:  # 「introducing-gpt-6.1-terra」 → 「gpt-6.1-terra」
            parts.pop(0)
        n = "-".join(parts)
        if len(n) >= 7 and not re.fullmatch(r"v\d.*", n):
            out.add(n)
    return out


def link_related(items: list[dict], limit: int = 3):
    found = {i["id"]: names(i) for i in items}
    for i in items:
        mine = found[i["id"]]
        i["related"] = [j["id"] for j in items if j is not i and mine & found[j["id"]]][:limit]


# 같은 회사의 공식 출처끼리 같은 발표를 따로 실으면(회사 블로그 + 그 회사의 HF 블로그 글 + 커뮤니티 공지) 하나만 남긴다.
# 남기는 순서: 회사 자체 블로그(개발자 블로그 포함) > HF 블로그의 회사 계정 > 커뮤니티 공지. 같으면 먼저 올라온 글.
COMPANY = {"openai_community": "openai", "deepmind": "google", "google_research": "google", "nvidia_dev": "nvidia", "azure": "microsoft"}
SAME_DAYS, SAME_TITLE = 3, 0.6  # 3일 안, 영문 제목 글자쌍 겹침 60% 이상이면 같은 발표


def _rank(item: dict) -> int:
    return 2 if item["source"].endswith("_community") else 1 if item.get("category") == "Hugging Face Blog" else 0


def _same_story(a: dict, b: dict) -> bool:
    if COMPANY.get(a["source"], a["source"]) != COMPANY.get(b["source"], b["source"]):
        return False
    if abs(a["published_at"] - b["published_at"]) > timedelta(days=SAME_DAYS):
        return False
    x, y = _bigrams(a["title_en"]), _bigrams(b["title_en"])
    similar = len(x & y) / len(x | y) >= SAME_TITLE if x and y else False
    title_names = lambda i: names({"title_en": i["title_en"]})  # 제목 속 모델·제품 이름(gemini-4-carbon)만
    return similar or bool(title_names(a) & title_names(b))


def merge_official(items: list[dict]) -> tuple[list[dict], list[dict]]:
    """(남길 글, 뺀 글). 공식 발표·공지(kind post·notice)만 본다. 화제·릴리스는 그대로."""
    order = sorted((i for i in items if i["kind"] in ("post", "notice")), key=lambda i: (_rank(i), i["published_at"]))
    kept, dropped = [], []
    for i in order:
        (dropped if any(_same_story(i, k) for k in kept) else kept).append(i)
    gone = {id(i) for i in dropped}
    return [i for i in items if id(i) not in gone], dropped


def save_db(db, items: list[dict], models: list[dict], now: datetime):
    """소식은 쌓고(주소마다 한 줄, 다시 모으면 덮어쓴다), 모델 순위는 이번 실행 것으로 바꾼다."""
    stamp = now.isoformat()
    news = [{**{k: i.get(k) for k in NEWS_COLUMNS}, "key_points": i.get("key_points") or [], "collected_at": stamp} for i in items]
    try:
        db.upsert("official_news", news, "id")
    except Exception:  # 화제 열(points·comments·discussion_url)과 kind=hot을 더하는 마이그레이션 전이면 화제를 빼고 저장한다
        old = ("points", "comments", "discussion_url")
        db.upsert("official_news", [{k: v for k, v in r.items() if k not in old} for r in news if r["kind"] != "hot"], "id")
    if models:  # 트렌딩을 못 받은 날은 어제 순위를 그대로 둔다
        rows = [{**{k: m.get(k) for k in MODEL_COLUMNS}, "collected_at": stamp} for m in models]
        try:
            db.upsert("trending_models", rows, "id")
        except Exception:  # variants 열을 더하는 마이그레이션 전이면 그 열만 빼고 저장한다
            db.upsert("trending_models", [{k: v for k, v in r.items() if k != "variants"} for r in rows], "id")
        db._req("DELETE", f"trending_models?collected_at=lt.{urllib.parse.quote(stamp)}", prefer="return=minimal")


def _iso(d: datetime) -> str:
    return d.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def rank_records(ranks: dict[str, dict]) -> list[dict]:
    """기간별 순위 → github_rankings 테이블 줄(기간·저장소마다 한 줄)."""
    return [{"id": f"{period}:{x['full_name']}", "period": period, "rank": x["rank"], "full_name": x["full_name"],
             "url": x["url"], "description_en": x["description_en"], "description_ko": x.get("description_ko"),
             "language": x["language"], "stars": x["stars"], "forks": x["forks"], "created_at": _iso(x["created_at"]),
             "period_start": _iso(v["start"]), "period_end": _iso(v["end"]), "readme_ko": x.get("readme_ko")}
            for period, v in ranks.items() for x in v["repos"]]


def rankings_doc(rows: list[dict], now: datetime) -> dict:
    """앱이 읽는 모양(list_github_rankings와 같다): {"collected_at", "periods": {기간: {"start", "end", "repos"}}}."""
    periods: dict[str, dict] = {}
    for r in rows:
        p = periods.setdefault(r["period"], {"start": r["period_start"], "end": r["period_end"], "repos": []})
        p["repos"].append({k: r[k] for k in RANK_COLUMNS if k not in ("id", "period", "period_start", "period_end")})
    return {"collected_at": _iso(now), "periods": periods}


def save_rankings(db, rows: list[dict], now: datetime):
    """이번에 받은 기간만 새 순위로 바꾼다(못 받은 기간은 지난 순위를 그대로 둔다)."""
    stamp = now.isoformat()
    full = [{k: r.get(k) for k in RANK_COLUMNS} | {"collected_at": stamp} for r in rows]
    try:
        db.upsert("github_rankings", full, "id")
    except Exception:  # readme_ko 열을 더하는 마이그레이션 전이면 그 열만 빼고 저장한다
        db.upsert("github_rankings", [{k: v for k, v in r.items() if k != "readme_ko"} for r in full], "id")
    for period in sorted({r["period"] for r in rows}):
        db._req("DELETE", f"github_rankings?period=eq.{period}&collected_at=lt.{urllib.parse.quote(stamp)}",
                prefer="return=minimal")


def pick(items: list[dict], now: datetime) -> list[dict]:
    """출처마다 기간 안의 최신 PER_SOURCE개. HF 블로그 피드 하나에서 여러 회사 출처가 나와 출처별로 센다."""
    recent = [i for i in items if now - i["published_at"] <= timedelta(days=WINDOW_DAYS)]
    recent.sort(key=lambda i: i["published_at"], reverse=True)
    count: dict[str, int] = {}
    out = []
    for i in recent:
        if count.get(i["source"], 0) < PER_SOURCE:
            count[i["source"]] = count.get(i["source"], 0) + 1
            out.append(i)
    return out


# 제목은 뉴스 헤드라인처럼 명사형으로 끝맺는다. 연구소 블로그 말고 Hacker News·GitHub 제목도 온다: 말장난·관용구를 글자대로
# 옮겨 「Proton의 전하를 뒤집은 것은」(회사 Proton) 같은 번역이 나왔고 「~만든다」·「~제공」·「~나 보다」가 섞였다(2026-11-02).
TRANSLATE_SYSTEM = (
    "You translate English headlines (AI lab blogs, Hacker News posts, GitHub repositories) into natural, concise Korean headlines "
    "for a Korean reading app. Keep product, model, company, project and benchmark names in their original spelling; "
    "names like Proton, Claude or Gemini are companies or products, not ordinary words. Translate the meaning of puns and idioms, "
    "not the literal words. Write Korean news-headline style that ends in a noun or noun phrase (e.g. 「~ 공개」, 「~ 차단」, "
    "「~ 통합」), never a sentence ending such as ~다, ~요 or ~나 보다. Do not add or remove information. "
    "Each input may come with context: the opening of the post. Use it only to understand what the headline means "
    "(which sense of an ambiguous word, what a pun refers to); do not add facts from it to the title. "
    "For a GitHub repository written as 「name: description」, keep 「name: 」 and follow it with a short Korean description "
    "of about 30 characters or less, keeping only the main idea. "
    "Return only a JSON object: {\"titles\": [\"...\", ...]} with exactly one Korean title per input, in the same order."
)


TITLE_CONTEXT_CHARS = 400  # 제목 뜻을 가리는 데 쓰는 본문 앞부분(제목만으로는 「Proton's charge」를 「전하」로 옮겼다)


def translate(titles: list[str], api_key: str, log, contexts: list[str] | None = None) -> list[str] | None:
    payload = ({"items": [{"title": t, "context": (c or "")[:TITLE_CONTEXT_CHARS]} for t, c in zip(titles, contexts)]}
               if contexts else {"titles": titles})
    msgs = [{"role": "system", "content": TRANSLATE_SYSTEM},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)}]

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


# 일반 영어 낱말을 그대로 둔 핵심 내용이 나왔다(「agent context compaction 설정」, 「intent-aware workflow」, 2026-11-02).
PLAIN_KOREAN = (" Translate ordinary English words and phrases into Korean; keep English only for proper nouns "
                "(product, model, company, feature names) and code identifiers such as API names, flags or file names.")


RELEASE_SYSTEM = (
    "You summarize software release notes for Korean developers. Use only the release notes given; do not guess or add anything. "
    "Pick the up to 3 changes a developer would care about most (new features first, then important fixes). "
    "Write each as one short Korean sentence; keep API, feature, flag and product names in their original spelling. "
    "Return only a JSON object: {\"points\": [\"...\"]} with 1 to 3 items."
) + PLAIN_KOREAN + HAEYO


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
    "summary: 1 or 2 Korean sentences on what the post is about; start with the subject itself (the product, model or finding), "
    "never with 「이 글은」 or 「이 포스트는」. points: up to 3 key points, each one Korean sentence, "
    "para: the number of the paragraph that supports it, quote: 3 to 10 consecutive words copied exactly from that paragraph. "
    "If the paragraphs are too short for key points, return an empty points list."
) + PLAIN_KOREAN + HAEYO


# 번역·요약 지시를 바꾸면 올린다. 다른 버전으로 만든 제목·요약·릴리스 핵심 내용은 다시 만든다(모델 카드는 그대로).
# 2: 제목 명사형·말장난, 영어 남김 줄이기, 「이 글은」 금지(2026-11-02)
STYLE_VERSION = 2
# 제목 번역 지시만 바꿀 때 올린다(요약은 그대로 두고 제목만 다시). 2: 본문 앞부분을 맥락으로, GitHub 설명 짧게(2026-11-02)
TITLE_VERSION = 2

# 원문이 이만큼(글자)보다 짧으면 요약하지 않고 소개문을 한국어로 옮기기만 한다. OpenAI는 글 페이지가 자동 접근을
# 막아(403) 피드 소개문 한 줄(50자 안팎)만 근거로 쓸 수 있는데, 그걸로 요약을 만들면 제목을 되풀이하거나
# 지어내게 된다(「GPT-6.1 Terra를 소개하는 글이에요」, 실기기 QA 2026-10-27).
THIN_CHARS = 200


def _norm(t: str) -> str:
    return re.sub(r"[\s.,·!?「」\"'()]+", "", t or "").lower()


def _bigrams(t: str) -> set[str]:
    t = _norm(t)
    return {t[i:i + 2] for i in range(len(t) - 1)}


def contained(part: str, whole: str) -> float:
    """part의 글자쌍 중 whole에 들어 있는 비율. 단순 유사도는 「요약을 다시 쓴 핵심 내용」(0.93)과
    「요약의 한 부분을 짚은 핵심 내용」(0.81)을 가르지 못했다(2026-10-27 실데이터)."""
    p = _bigrams(part)
    return len(p & _bigrams(whole)) / len(p) if p else 0.0


# 「이 글은 …을 소개해요」로 여는 요약(10-31 프롬프트에서 금지했는데도 나온다). 받지 않고 다시 만든다
OPENING = re.compile(r"^\s*이\s*(글|포스트|게시물|게시글|영상|발표|문서|기사)(은|는|에서는)")


def meta_opening(summary: str | None) -> bool:
    return bool(summary and OPENING.match(summary))


META = re.compile(r"(소개|설명|정리)하는 글이에요|다루는 글이에요|내용을 다뤄요")


def tautology(title_ko: str | None, summary: str) -> bool:
    """요약이 제목을 되풀이할 뿐인가: 모든 문장이 제목 글자를 거의 그대로 쓰거나 「소개하는 글이에요」류 말뿐."""
    sents = [x for x in re.split(r"(?<=[.!?])\s+", summary.strip()) if x]
    return bool(sents) and all((title_ko and contained(title_ko, x) >= 0.8) or META.search(x) for x in sents)


def drop_repeats(summary: str, points: list[dict]) -> list[dict]:
    """요약이나 앞 핵심 내용을 다시 쓴 핵심 내용(글자쌍 90% 이상이 이미 나온 것)은 뺀다."""
    out = []
    for pt in points:
        if contained(pt["text"], summary) < 0.9 and all(contained(pt["text"], q["text"]) < 0.9 for q in out):
            out.append(pt)
    return out


THIN_SYSTEM = (
    "Translate the given short English blurb into one natural Korean sentence for a Korean reading app. "
    "Do not add, explain, or guess anything that is not in the blurb. Keep product, model and company names in their original spelling. "
    "Return only a JSON object: {\"summary\": \"...\"}."
) + HAEYO


def translate_blurb(blurb: str, api_key: str, log) -> str | None:
    """짧은 원문(피드 소개문)을 한국어 한 문장으로. 요약이 아니라 번역이다(앱은 「원문 소개문」으로 보여 준다)."""
    msgs = [{"role": "system", "content": THIN_SYSTEM}, {"role": "user", "content": blurb}]

    def check(out):
        s = out.get("summary") if isinstance(out, dict) else None
        if not isinstance(s, str) or not s.strip():
            return ["summary_missing"]
        return ["not_haeyo"] if not_haeyo([s]) else []

    out, _ = llm.generate(api_key, msgs, check, log)
    return out["summary"].strip() if out else None


def summarize_post(title: str, paras: list[str], api_key: str, log, title_ko: str | None = None) -> tuple[str, list[dict]] | None:
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
        if not_haeyo([out["summary"]] + [pt["text"] for pt in pts]):
            return ["not_haeyo"]
        if meta_opening(out["summary"]):
            return ["summary_meta_opening"]
        return ["summary_repeats_title"] if tautology(title_ko, out["summary"]) else []

    out, _ = llm.generate(api_key, msgs, check, log)
    if not out:
        return None
    points = []
    for pt in out["points"]:
        q = (pt.get("quote") or "").strip()
        # 구절이 그 문단에 실제로 있어야 원문의 그 자리로 여는 링크를 단다(없으면 문단 번호만)
        points.append({"text": pt["text"].strip(), "para": pt["para"], "quote": q if q and q in paras[pt["para"] - 1] else None})
    return out["summary"].strip(), drop_repeats(out["summary"], points)


def _parent(tags: list[str]) -> tuple[str | None, bool]:
    """HF 태그의 원래 모델(base_model:quantized:X·finetune:X…)과 양자화판인지."""
    for kind in ("quantized", "finetune", "adapter", "merge"):
        x = next((t.split(":", 2)[2] for t in tags if t.startswith(f"base_model:{kind}:")), None)
        if x:
            return x, kind == "quantized"
    return next((t.split(":", 1)[1] for t in tags if t.startswith("base_model:") and t.count(":") == 1), None), False


# 이름으로 알 수 있는 재포장판(같은 가중치를 다른 형식으로 다시 올린 것). 태그가 finetune이어도 대표로 올리지 않는다
REPACK = re.compile(r"gguf|comfy|fp8|fp4|nvfp4|awq|gptq|mlx|bnb|int4|int8|exl2|onnx|quant", re.I)


def group_variants(models: list[dict]) -> list[tuple[dict, list[dict]]]:
    """트렌딩 순 목록 → [(대표, 변형들)]. 양자화판(GGUF·FP8…)은 원래 모델 쪽으로, 같은 회사가 같은 바탕 모델에서
    만든 것(LFM3-1.7B · LFM3-VL-2B)은 한 묶음으로. 다른 회사의 미세 조정은 따로 둔다. 묶음 순서는 가장 높은 순위."""
    ids = {m["id"] for m in models}
    parent = {m["id"]: _parent(m.get("tags") or []) for m in models}

    def key(mid: str, seen=()) -> str:
        base, quant = parent.get(mid, (None, False))
        if not base or mid in seen:
            return mid
        if quant or base.split("/")[0] == mid.split("/")[0]:
            return key(base, seen + (mid,)) if base in ids else base
        return mid

    groups: dict[str, list[dict]] = {}
    for m in models:
        groups.setdefault(key(m["id"]), []).append(m)
    out = []
    for g in groups.values():
        # 대표: 양자화·재포장판(GGUF·Comfy·FP8…)이 아닌 것 중 가장 높은 순위. 원본이 묶음에 있으면 원본이 위로 온다
        # (flux-3-image-klein-comfy보다 flux-3-image-klein). 모두 재포장판이면 가장 높은 순위.
        rep = next((m for m in g if not parent[m["id"]][1] and not REPACK.search(m["id"].split("/")[-1])), g[0])
        out.append((rep, [m for m in g if m is not rep]))
    return out


def from_hf_trending(now: datetime | None = None) -> list[dict]:
    now = now or datetime.now(timezone.utc)
    listing = [m for m in json.loads(fetch(HF_TRENDING))
               if m.get("pipeline_tag") in MODEL_TASKS and not MODEL_BLOCK.search(m["id"] + " " + " ".join(m.get("tags") or []))]
    out = []
    for m, variants in group_variants(listing):
        created = m.get("createdAt")
        fresh = bool(created) and now - datetime.fromisoformat(created.replace("Z", "+00:00")) <= timedelta(days=NEW_DAYS)
        fresh_count = sum(1 for o in out if o["_fresh"])
        if len(out) >= TRENDING_TOP and not (fresh and fresh_count < NEW_TOP):
            if fresh_count >= NEW_TOP:
                break
            continue
        tags = m.get("tags") or []
        info = json.loads(fetch(f"https://huggingface.co/api/models/{m['id']}"))
        lic = next((t.split(":", 1)[1] for t in tags if t.startswith("license:")), None)
        out.append({"id": m["id"], "author": info.get("author") or m["id"].split("/")[0], "name": m["id"].split("/")[-1],
                    "task": m.get("pipeline_tag"), "params": (info.get("safetensors") or {}).get("total"),
                    "license": lic, "likes": info.get("likes"), "downloads": info.get("downloads"),
                    "created_at": info.get("createdAt") or created, "rank": len(out) + 1,
                    "arxiv": [t.split(":", 1)[1] for t in tags if t.startswith("arxiv:")][:1] or None,
                    "url": f"https://huggingface.co/{m['id']}",
                    "variants": [{"id": v["id"], "name": v["id"].split("/")[-1], "author": v["id"].split("/")[0],
                                  "quantized": _parent(v.get("tags") or [])[1]} for v in variants[:5]],
                    "_fresh": fresh})
    for o in out:
        del o["_fresh"]
    return out


CARD_SYSTEM = (
    "You read a Hugging Face model card and report, in Korean, only what the model's makers claim in it. Do not guess or use outside knowledge (the only exception is a benchmark's \"about\", below). "
    "Return only a JSON object: {\"strengths\": [\"...\"], \"benchmarks\": [{\"name\": \"...\", \"score\": \"...\", \"about\": \"...\" or null, \"higher_better\": true, false or null}], \"limitation\": \"...\" or null}. "
    "strengths: up to 3 short Korean sentences on what the makers say the model is for or good at. "
    "benchmarks: up to 4 benchmark results the makers report for this model, name exactly as written and score as written (e.g. \"74.2%\"). "
    "Each benchmark also has \"about\": one short Korean noun phrase saying what it measures (e.g. \"실제 GitHub 이슈를 고치는 코딩 능력\", "
    "\"여러 단계 지시를 정확히 따르는 능력\", \"음성을 글로 옮길 때 틀린 낱말 비율\"). Write it only when the card explains the benchmark "
    "or it is a well-known public benchmark you are sure about; otherwise null. Never guess from the name alone. "
    "And \"higher_better\": true if a higher score is better (accuracy, pass rate), false if lower is better (error rate, latency, loss), "
    "null if unclear. "
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
              and all(isinstance(b, dict) and isinstance(b.get("name"), str) and isinstance(b.get("score"), str)
                      and (b.get("about") is None or (isinstance(b["about"], str) and len(b["about"]) <= 60))
                      and b.get("higher_better") in (None, True, False) for b in bm)
              and (lim is None or isinstance(lim, str)))
        if not ok:
            return ["card_shape"]
        return ["not_haeyo"] if not_haeyo(st + [lim]) else []

    out, _ = llm.generate(api_key, msgs, check, log)
    if not out:
        return None
    # 점수는 카드 원문에 그대로 있어야 한다(지어낸 숫자를 막는다)
    out["benchmarks"] = [{"name": b["name"], "score": b["score"], "about": clean_about(b.get("about")),
                          "higher_better": b.get("higher_better")}
                         for b in out["benchmarks"] if b["score"].strip() and b["score"].strip() in card]
    return out


def clean_about(about) -> str | None:
    """평가 항목 풀이: 빈 값·영어만인 풀이는 버리고, 끝 마침표를 뗀다(앱은 이름 아래 작은 줄로 보인다)."""
    if not isinstance(about, str) or not re.search(r"[가-힣]", about):
        return None
    return about.strip().rstrip(".") or None


# GitHub 순위 저장소 상세(2026-11-11): README를 받아 무엇을 하는 저장소인지 한국어로. 앱 상세 화면이 보여 준다.
README_CHARS = 12000
README_VERSION = 1
README_SYSTEM = (
    "You read a GitHub repository README and explain, in Korean, only what the README itself says. Do not guess or use outside knowledge. "
    "Return only a JSON object: {\"summary\": [\"...\"], \"uses\": [\"...\"], \"how\": \"...\" or null}. "
    "summary: 1 to 3 short Korean sentences on what this repository is and what it does, for a developer seeing it for the first time. "
    "uses: up to 3 short Korean noun phrases for what people can use it for (e.g. \"로컬에서 LLM 에이전트 실행\"). Empty list if the README does not say. "
    "how: one Korean sentence on how to start (install command or first step) as the README states it, keeping commands in their original form, or null. "
    "Keep product, library, model and command names in their original spelling."
) + HAEYO


def readme_text(raw: str) -> str:
    """README에서 요약에 쓸 글만: 배지·그림·HTML 꼬리표를 빼고 빈 줄을 줄인다."""
    t = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", raw)           # ![badge](...)
    t = re.sub(r"\[\s*\]\([^)]*\)", "", t)                  # 그림을 뺀 빈 링크
    t = re.sub(r"<img\b[^>]*>|<[^>]+>", "", t)
    t = re.sub(r"\n{3,}", "\n\n", t)
    return t.strip()[:README_CHARS]


def fetch_readme(full_name: str) -> str:
    """GitHub API의 README(기본 브랜치, 파일 이름이 무엇이든). 없으면 빈 글."""
    try:
        j = json.loads(fetch(f"https://api.github.com/repos/{full_name}/readme"))
        return base64.b64decode(j.get("content") or "").decode("utf-8", "replace")
    except Exception:
        return ""


def summarize_readme(raw: str, api_key: str, log) -> dict | None:
    text = readme_text(raw)
    if len(text) < 300:  # 설명이 거의 없는 README는 요약하지 않는다(지어내기 쉽다)
        return None
    msgs = [{"role": "system", "content": README_SYSTEM}, {"role": "user", "content": text}]

    def check(out):
        if not isinstance(out, dict):
            return ["not_object"]
        sm, uses, how = out.get("summary"), out.get("uses"), out.get("how")
        ok = (isinstance(sm, list) and 1 <= len(sm) <= 3 and all(isinstance(x, str) and x.strip() and len(x) <= 200 for x in sm)
              and isinstance(uses, list) and len(uses) <= 3 and all(isinstance(x, str) and x.strip() and len(x) <= 60 for x in uses)
              and (how is None or (isinstance(how, str) and len(how) <= 200)))
        if not ok:
            return ["readme_shape"]
        if not all(re.search(r"[가-힣]", x) for x in sm):
            return ["not_korean"]
        return ["not_haeyo"] if not_haeyo(sm + [how]) else []

    out, _ = llm.generate(api_key, msgs, check, log)
    if not out:
        return None
    how = out.get("how")
    return {"summary": [x.strip() for x in out["summary"]],
            "uses": [x.strip().rstrip(".") for x in out["uses"] if re.search(r"[가-힣]", x)],
            "how": how.strip() if isinstance(how, str) and how.strip() else None}


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

    hot = []
    for label, collect in (("Hacker News", from_hn),
                           # HN에 같이 오른 저장소는 GitHub 순위에서 점수를 더 준다(그래서 HN을 먼저 모은다)
                           ("GitHub 새 AI 도구", lambda now: from_github(now, {h["url"] for h in hot}))):
        try:
            got = collect(now)
            report.append(f"{label}: {len(got)}개")
            hot += got
        except Exception as e:
            report.append(f"{label}: 실패 {e!r}")

    try:
        ranks = gh_rankings(now)
        report.append("GitHub 기간별 순위: " + ", ".join(f"{k} {len(v['repos'])}개" for k, v in ranks.items()) if ranks else "GitHub 기간별 순위: 실패")
    except Exception as e:
        ranks = {}
        report.append(f"GitHub 기간별 순위: 실패 {e!r}")

    try:
        models = from_hf_trending()
        report.append(f"HF 트렌딩 모델: {len(models)}개")
    except Exception as e:
        models = []
        report.append(f"HF 트렌딩 모델: 실패 {e!r}")

    items = [i for i in items if i["url"] not in blocked]
    items, merged = merge_official(items)
    report.append(f"같은 발표 합치기: {len(merged)}개를 공식 원문 쪽으로" + (f" ({', '.join(m['source_label'] for m in merged)})" if merged else ""))
    releases = [r for r in releases if r["url"] not in blocked]
    hot = [h for h in attach_hn(items + releases, hot) if h["url"] not in blocked]
    report.append(f"화제: 공식 소식에 붙인 HN 반응 {sum(1 for i in items + releases if i.get('points'))}개, 따로 보일 화제 {len(hot)}개")
    items += hot  # 화제도 글처럼 제목 번역·요약(robots.txt가 허용하는 사이트만)
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
        if hit.get("v") != STYLE_VERSION:
            hit = {}
        pts = [p.get("text") for p in hit.get("key_points") or []]
        stale = (not_haeyo([hit.get("summary_ko")] + pts)  # 예전 합니다체 요약
                 or ("thin" not in hit and hit.get("summary_ko") is not None)  # 짧은 원문 구분 전에 만든 요약
                 or (hit.get("summary_ko") and not hit.get("thin") and tautology(hit.get("title_ko"), hit["summary_ko"]))
                 or (not hit.get("thin") and meta_opening(hit.get("summary_ko"))))
        if stale:
            hit = {"title_ko": hit.get("title_ko")}  # 요약은 다시 만들고 제목 번역은 그대로
        if hit.get("tv") != TITLE_VERSION:
            hit.pop("title_ko", None)
        item.update({k: v for k, v in hit.items() if k in ("title_ko", "summary_ko", "key_points", "thin")})
    for item in items:
        if is_slug_title(item["title_en"], item["url"]):
            try:
                item["title_en"] = heading_title(fetch(item["url"]).decode("utf-8", "replace"), item["title_en"]) or item["title_en"]
            except Exception:
                pass
    todo = [i for i in items if not i.get("title_ko")]

    def read_body(item):  # 제목 맥락과 요약이 같은 본문을 쓴다(한 번만 받는다)
        try:
            item["_paras"] = body_paragraphs(item)
        except Exception:
            item["_paras"] = []

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(read_body, [i for i in items if not i.get("title_ko") or not i.get("summary_ko")]))
    contexts = [" ".join(i["_paras"]) for i in todo]
    ko = translate([i["title_en"] for i in todo], key, lambda e: None, contexts) if key and todo else None
    report.append(f"제목 번역: 새 {len(todo)}개 " + ("완료" if ko or not todo else "건너뜀(키 없음)" if not key else "실패, 원문만"))
    for i, item in enumerate(todo):
        item["title_ko"] = ko[i] if ko else None
    def digest_post(item):
        if item.get("summary_ko"):
            return  # 지난 실행에서 요약했다
        paras = item.get("_paras") or []
        if not key or not paras:
            item["summary_ko"], item["key_points"] = None, []
            return
        if sum(map(len, paras)) < THIN_CHARS:  # 소개문 한 줄: 요약 대신 번역만
            item["thin"] = True
            item["summary_ko"], item["key_points"] = translate_blurb(" ".join(paras), key, lambda e: None), []
            return
        got = summarize_post(item["title_en"], paras, key, lambda e: None, item.get("title_ko"))
        item["summary_ko"], item["key_points"] = got if got else (None, [])

    def digest_release(r):
        hit = cache.get(r["title_en"])
        if hit and (hit.get("v") != STYLE_VERSION or not_haeyo([p.get("text") for p in hit["key_points"]])):
            hit = None
        r["key_points"] = hit["key_points"] if hit else (summarize_release(r["notes"], key, lambda e: None) if key else None) or []

    def digest_model(m):
        hit = cache.get(m["url"])
        if hit and hit["card"] and (not_haeyo(hit["card"]["strengths"] + [hit["card"].get("limitation")])
                                    or hit.get("cv") != CARD_VERSION):  # 평가 항목 풀이가 없던 카드는 다시 정리
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
            cache[i["url"]] = {"title_ko": i["title_ko"], "summary_ko": i["summary_ko"], "key_points": i["key_points"],
                               "thin": bool(i.get("thin")), "v": STYLE_VERSION, "tv": TITLE_VERSION}
    for r in releases:
        if r["key_points"]:
            cache[r["title_en"]] = {"key_points": r["key_points"], "v": STYLE_VERSION}
    for m in models:
        if m["card"] is not None:
            cache[m["url"]] = {"card": m["card"], "cv": CARD_VERSION}
    # 순위 저장소 설명: 한 번 옮긴 설명은 캐시에서(설명이 바뀌면 다시). 여러 기간에 같은 저장소가 나와도 한 번만
    repos = {x["url"]: x for v in ranks.values() for x in v["repos"]}
    for x in repos.values():
        hit = cache.get("ghd:" + x["url"])
        x["description_ko"] = hit["ko"] if hit and hit.get("en") == x["description_en"] else None
    todo = [x for x in repos.values() if not x["description_ko"]]
    for i in range(0, len(todo) if key else 0, 25):
        chunk = todo[i:i + 25]
        ko = translate([x["description_en"] for x in chunk], key, lambda e: None)
        for x, t in zip(chunk, ko or []):
            x["description_ko"] = t
            cache["ghd:" + x["url"]] = {"en": x["description_en"], "ko": t}
    # README 요약: 한 번 정리한 저장소는 캐시에서(순위에 머무는 며칠 동안 README가 크게 바뀌는 일은 드물다)
    for x in repos.values():
        hit = cache.get("ghr:" + x["url"])
        x["readme_ko"] = hit["readme"] if hit and hit.get("v") == README_VERSION else None
    fresh = [x for x in repos.values() if x["readme_ko"] is None and not (cache.get("ghr:" + x["url"]) or {}).get("none")]

    def digest_readme(x):
        raw = fetch_readme(x["full_name"])
        x["_thin"] = len(readme_text(raw)) < 300
        x["readme_ko"] = None if x["_thin"] else summarize_readme(raw, key, lambda e: None)

    if key and fresh:
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(digest_readme, fresh))
        for x in fresh:  # 설명이 거의 없는 README도 남겨 두어 매번 다시 받지 않는다(요약 실패는 다음 배치에 다시)
            if x["readme_ko"]:
                cache["ghr:" + x["url"]] = {"readme": x["readme_ko"], "v": README_VERSION}
            elif x["_thin"]:
                cache["ghr:" + x["url"]] = {"none": True, "v": README_VERSION}
            x.pop("_thin", None)
    for v in ranks.values():
        for x in v["repos"]:
            x["description_ko"] = repos[x["url"]]["description_ko"]
            x["readme_ko"] = repos[x["url"]]["readme_ko"]
    if repos:
        report.append(f"순위 저장소 설명 번역: {sum(bool(x['description_ko']) for x in repos.values())}/{len(repos)}, "
                      f"README 요약: {sum(bool(x['readme_ko']) for x in repos.values())}/{len(repos)}")
    save_state(db, "digest_cache", DIGEST_CACHE, cache)
    items += releases
    for item in items:
        item["id"] = hashlib.sha1(item["url"].encode()).hexdigest()[:12]  # 앱 상세 화면 주소용
    link_related(items)
    for item in items:
        item.pop("_desc", None)
        item.pop("_score", None)
        item.pop("_paras", None)
        item.pop("notes", None)
        item["thin"] = bool(item.get("thin"))
        item["published_at"] = item["published_at"].astimezone(timezone.utc).isoformat()

    items.sort(key=lambda i: i["published_at"], reverse=True)
    OUT.mkdir(parents=True, exist_ok=True)
    rank_rows = rank_records(ranks)
    doc = {"collected_at": now.isoformat(), "window_days": WINDOW_DAYS, "items": items, "models": models,
           "github_rankings": rankings_doc(rank_rows, now)}
    (OUT / "official_news.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
    (OUT / "official_news.define.json").write_text(
        json.dumps({"OFFICIAL_NEWS_PREVIEW": json.dumps(doc, ensure_ascii=False)}, ensure_ascii=False), encoding="utf-8")
    if db:
        save_db(db, items, models, now)
        if rank_rows:
            try:
                save_rankings(db, rank_rows, now)
                report.append(f"DB 저장: GitHub 순위 {len(rank_rows)}줄")
            except Exception as e:  # 순위 테이블 마이그레이션 전이면 건너뛴다
                report.append(f"DB 저장: GitHub 순위 실패 {e!r}")
        for m in merged:  # 지난 실행에서 따로 저장된 중복 글도 지운다
            db.delete("official_news", id=hashlib.sha1(m["url"].encode()).hexdigest()[:12])
        report.append(f"DB 저장: 소식 {len(items)}개, 모델 {len(models)}개")
        if key:  # X 글 번역(x_posts 테이블이 없으면 건너뛴다)
            try:
                report.append(x_posts.translate_recent(db, key, now))
            except Exception as e:
                report.append(f"X 글 번역: 실패 {e!r}")
        # 소식·모델 글의 용어 후보(관리자 웹에서 승인하면 다음 배치에 앱 사전에 들어간다). 실패해도 소식 저장에는 영향이 없다
        if key:
            seen = load_state(db, "news_terms_seen", NEWS_TERMS_SEEN)
            try:
                added = glossary.news_candidates(db, items + models + extra_term_texts(db, rank_rows, now), key, seen, report.append)
                report.append(f"용어 후보: 새 글 기준 {added}개 추가(검토 대기)")
            except Exception as e:
                report.append(f"용어 후보: 실패 {e!r}")
            save_state(db, "news_terms_seen", NEWS_TERMS_SEEN, seen)
    print("\n".join(report))
    print(f"총 {len(items)}개 → {OUT / 'official_news.json'}")


if __name__ == "__main__":
    sys.exit(main())
