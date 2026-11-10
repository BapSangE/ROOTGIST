-- X(구 트위터) 계정 새 글(2026-11-06, docs/X_WATCHLIST.md). 수집은 worker/x_posts.py.
-- 목적: 「한도 초기화」「사용량 리셋」「무료 개방」처럼 X에서 먼저 나오는 소식을 잡는다.
-- 쓰기는 배치 워커(비밀 키)만. 앱은 list_x_posts로 최근 3일 글을 읽는다(2026-11-10: 탐색 HOT 칸·발표 반응·홈 혜택 카드).
-- X 표시 규정: 앱은 글 원문·작성자 이름·@핸들·시각·원문 링크를 함께 보인다. 번역(text_ko)은 원문 아래 「AI 번역」으로만.
-- perk: 혜택·한도 낱말이 있는 글(worker/x_posts.py PERK_WORDS). 낱말 검사라 오탐이 있을 수 있다.
-- since_id(계정별 마지막으로 받은 글)·사용량 기록은 worker_state의 key='x_posts'에 둔다.

create table public.x_posts (
  id text primary key,                       -- X 게시물 id
  handle text not null,                      -- @ 없이, X에 보이는 대소문자 그대로
  author_name text,
  tier smallint not null,                    -- 명단 순위(1 혜택·한도 발표, 2 회사 공식, 3 소식 정리)
  text text not null,                        -- 긴 글(note_tweet)은 전체 본문
  url text not null,
  posted_at timestamptz not null,
  likes integer,
  reposts integer,
  replies integer,
  quotes integer,
  perk boolean not null default false,
  perk_words text[] not null default '{}',
  links text[] not null default '{}',        -- 글에 단 링크(펼친 주소). 앱이 같은 주소의 공식 소식에 X 반응으로 붙인다
  text_ko text,
  refreshed_at timestamptz,                  -- 반응 수(좋아요 등)를 한 번 다시 받은 시각. 막 받은 글은 반응이 거의 0이라                              -- 한국어 번역(공식 소식 배치가 채운다, worker/x_posts.py translate_recent)
  collected_at timestamptz not null default now()
);
create index x_posts_posted_at on public.x_posts (posted_at desc);
create index x_posts_perk on public.x_posts (posted_at desc) where perk;

alter table public.x_posts enable row level security;

create function public.list_x_posts()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('posts', coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'handle', p.handle, 'author_name', p.author_name, 'tier', p.tier,
    'text', p.text, 'text_ko', p.text_ko, 'url', p.url,
    'posted_at', to_char(p.posted_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'likes', p.likes, 'reposts', p.reposts, 'replies', p.replies,
    'perk', p.perk, 'links', to_jsonb(p.links)
  ) order by p.posted_at desc), '[]'::jsonb))
  from (select * from public.x_posts where posted_at > now() - interval '3 days' order by posted_at desc limit 300) p;
$$;

revoke execute on function public.list_x_posts() from public;
grant execute on function public.list_x_posts() to anon, authenticated, service_role;
