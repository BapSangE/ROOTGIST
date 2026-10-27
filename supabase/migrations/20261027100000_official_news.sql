-- 공식 소식·HF 트렌딩 모델 (PROPOSALS P8d·P9). 수집은 worker/official_news.py.
-- 쓰기는 배치 워커(비밀 키)만. 앱(공개 키)은 테이블을 직접 읽지 못하고 아래 함수 2개로만 읽는다.

create table public.official_news (
  id text primary key,                       -- sha1(url) 앞 12자. 앱 상세 주소(/news/:id)
  source text not null,                      -- openai, anthropic, claude_code …
  source_label text not null,
  kind text not null check (kind in ('post', 'notice', 'release')),
  category text,
  title_en text not null,
  title_ko text,
  url text not null unique,
  published_at timestamptz not null,
  summary_ko text,                           -- 릴리스는 없음(핵심 내용만)
  key_points jsonb not null default '[]',    -- [{text, para, quote}]
  collected_at timestamptz not null default now()
);
create index official_news_published_at on public.official_news (published_at desc);

-- 매 실행 순위를 통째로 바꾼다(이번 실행에 없는 모델은 지운다).
create table public.trending_models (
  id text primary key,                       -- HF 모델 id (author/name)
  rank int not null,
  author text not null,
  name text not null,
  task text,
  params bigint,
  license text,
  likes int,
  downloads int,
  created_at timestamptz,
  arxiv text[],
  url text not null,
  card jsonb,                                -- {strengths, benchmarks, limitation}. 정리 못 한 카드는 null
  collected_at timestamptz not null default now()
);

-- 배치 사이에 남겨야 하는 수집기 상태(GitHub Actions는 매번 빈 머신이라 파일이 남지 않는다).
-- anthropic_seen: 사이트맵 페이지별 게시일, digest_cache: 번역·요약 재사용.
create table public.worker_state (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.official_news enable row level security;
alter table public.trending_models enable row level security;
alter table public.worker_state enable row level security;

-- 최근 30일, 최신순. 응답 모양은 worker/out/official_news.json의 items와 같다.
create function public.list_official_news(lim int default 60)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('items', coalesce(jsonb_agg(jsonb_build_object(
    'id', n.id, 'source', n.source, 'source_label', n.source_label, 'kind', n.kind, 'category', n.category,
    'title_en', n.title_en, 'title_ko', n.title_ko, 'url', n.url,
    'published_at', to_char(n.published_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'summary_ko', n.summary_ko, 'key_points', n.key_points
  ) order by n.published_at desc), '[]'::jsonb))
  from (
    select * from public.official_news
    where published_at > now() - interval '30 days'
    order by published_at desc
    limit least(greatest(lim, 1), 200)
  ) n;
$$;

create function public.list_trending_models()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('models', coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id, 'rank', m.rank, 'author', m.author, 'name', m.name, 'task', m.task, 'params', m.params,
    'license', m.license, 'likes', m.likes, 'downloads', m.downloads,
    'created_at', to_char(m.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'arxiv', to_jsonb(m.arxiv), 'url', m.url, 'card', m.card
  ) order by m.rank), '[]'::jsonb))
  from public.trending_models m;
$$;

revoke execute on function public.list_official_news(int), public.list_trending_models() from public;
grant execute on function public.list_official_news(int), public.list_trending_models() to anon, authenticated, service_role;
