-- ROOTGIST 초기 스키마 (HANDOFF 4.4) + 앱 읽기 함수 3개 (4.3).
-- 쓰기는 배치 워커(비밀 키)만. 앱(공개 키)은 테이블을 직접 읽지 못하고 아래 함수로만 읽는다.

create table public.digests (
  digest_date date primary key,              -- KST 배치일
  source_date date not null,                 -- HF에 넘긴 UTC 날짜 D
  status text not null check (status in ('published', 'empty', 'delayed')),
  paper_count int not null default 0,        -- 노출 편수
  primary_topic text,                        -- G10
  last_success_at timestamptz,
  late_added_count int not null default 0    -- 다음 날 보충으로 보관 목록에만 더한 편수(A7)
);

create table public.papers (
  paper_id text primary key,
  title_en text not null,
  abstract_en text not null,                 -- 원문 그대로
  abstract_sha256 text not null,
  authors text[] not null default '{}',
  org_name text,                             -- 게시 조직(저자 소속 아님, A5)
  published_at timestamptz not null,
  withdrawn boolean not null default false
);

create table public.digest_papers (
  digest_date date not null references public.digests on delete cascade,
  paper_id text not null references public.papers,
  rank int not null,
  upvotes_at_batch int not null,             -- 배치 시각 값 고정(A4)
  is_featured boolean not null default false,
  is_exposed boolean not null default false, -- 상위 10편
  primary key (digest_date, paper_id)
);

create table public.paper_sentences (
  paper_id text not null references public.papers on delete cascade,
  sentence_id text not null,                 -- A01~
  start_offset int not null,                 -- abstract_en 문자 위치 [start, end)
  end_offset int not null,
  kind text not null check (kind in ('text', 'link', 'meta')),
  splitter_version text not null,
  primary key (paper_id, sentence_id)
);

create table public.paper_ai (
  paper_id text primary key references public.papers on delete cascade,
  abstract_sha256 text not null,
  status text not null check (status in ('ready', 'pending', 'failed')),
  title_ko text,
  summary_ko text,
  topic_primary text,
  topic_secondary text,
  limitations text[] not null default '{}',
  model_id text,
  prompt_version text,
  schema_version text,
  generated_at timestamptz,
  raw_response jsonb                         -- 검증 통과한 모델 출력 원본(후처리 전)
);

create table public.paper_key_points (
  paper_id text not null references public.paper_ai on delete cascade,
  idx int not null,
  claim_ko text not null,
  evidence_sentence_ids text[] not null,
  primary key (paper_id, idx)
);

create table public.paper_translations (
  paper_id text not null references public.paper_ai on delete cascade,
  sentence_id text not null,
  translation_ko text not null,
  primary key (paper_id, sentence_id)
);

create table public.paper_glossary (
  paper_id text not null references public.paper_ai on delete cascade,
  idx int not null,
  term text not null,
  definition_ko text not null,
  context_ko text not null,
  sentence_ids text[] not null,
  term_difficulty text,                      -- 잠정값
  highlight boolean not null,                -- 8.4 판정
  primary key (paper_id, idx)
);

-- RLS만 켜고 정책은 두지 않는다: 공개 키로는 테이블을 읽거나 쓸 수 없다. 비밀 키는 RLS를 우회한다.
alter table public.digests enable row level security;
alter table public.papers enable row level security;
alter table public.digest_papers enable row level security;
alter table public.paper_sentences enable row level security;
alter table public.paper_ai enable row level security;
alter table public.paper_key_points enable row level security;
alter table public.paper_translations enable row level security;
alter table public.paper_glossary enable row level security;

-- ① 날짜 목록(최신순). next_cursor를 before_date로 다시 넘기면 다음 페이지.
create function public.list_digests(before_date date default null, lim int default 30)
returns jsonb language sql stable security definer set search_path = '' as $$
  with n as (select least(greatest(coalesce(lim, 30), 1), 100) as n),
  page as (
    select d.* from public.digests d
    where before_date is null or d.digest_date < before_date
    order by d.digest_date desc
    limit (select n + 1 from n)
  ),
  shown as (select * from page order by digest_date desc limit (select n from n))
  select jsonb_build_object(
    'digests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'digest_date', digest_date, 'source_date', source_date, 'status', status,
        'paper_count', paper_count, 'primary_topic', primary_topic, 'last_success_at', last_success_at
      ) order by digest_date desc) from shown), '[]'::jsonb),
    'next_cursor', case when (select count(*) from page) > (select n from n) then (select min(digest_date) from shown) end
  );
$$;

-- ② 하루 다이제스트. 노출 10편만, 순위순. 없는 날은 null.
create function public.get_digest(d date)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'digest_date', g.digest_date,
    'status', g.status,
    'last_success_at', g.last_success_at,
    'featured_paper_id', (select dp.paper_id from public.digest_papers dp where dp.digest_date = g.digest_date and dp.is_featured limit 1),
    'papers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'paper_id', p.paper_id, 'rank', dp.rank, 'title_en', p.title_en, 'title_ko', a.title_ko,
        'first_author', coalesce(p.authors[1], ''), 'author_count', coalesce(cardinality(p.authors), 0),
        'published_at', to_char(p.published_at at time zone 'UTC', 'YYYY-MM-DD'),
        'topic_primary', a.topic_primary, 'topic_secondary', a.topic_secondary,
        'key_points_preview', coalesce((
          select jsonb_agg(k.claim_ko order by k.idx) from public.paper_key_points k where k.paper_id = p.paper_id
        ), '[]'::jsonb),
        'ai_status', coalesce(a.status, 'pending')
      ) order by dp.rank)
      from public.digest_papers dp
      join public.papers p on p.paper_id = dp.paper_id
      left join public.paper_ai a on a.paper_id = p.paper_id
      where dp.digest_date = g.digest_date and dp.is_exposed
    ), '[]'::jsonb)
  )
  from public.digests g where g.digest_date = d;
$$;

-- ③ 논문 상세. 문장 원문은 abstract_en에서 오프셋으로 잘라 낸다(저장값 그대로).
create function public.get_paper(pid text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'paper_id', p.paper_id, 'title_en', p.title_en, 'title_ko', a.title_ko,
    'authors', to_jsonb(p.authors), 'org_name', p.org_name,
    'published_at', to_char(p.published_at at time zone 'UTC', 'YYYY-MM-DD'),
    'hf_url', 'https://huggingface.co/papers/' || p.paper_id,
    'arxiv_url', 'https://arxiv.org/abs/' || p.paper_id,
    'topic_primary', a.topic_primary, 'topic_secondary', a.topic_secondary,
    'ai_status', coalesce(a.status, 'pending'),
    'summary_ko', a.summary_ko,
    'key_points', coalesce((
      select jsonb_agg(jsonb_build_object('claim_ko', k.claim_ko, 'evidence_sentence_ids', to_jsonb(k.evidence_sentence_ids)) order by k.idx)
      from public.paper_key_points k where k.paper_id = p.paper_id
    ), '[]'::jsonb),
    'sentences', coalesce((
      select jsonb_agg(jsonb_build_object(
        'sentence_id', s.sentence_id, 'kind', s.kind,
        'text', substr(p.abstract_en, s.start_offset + 1, s.end_offset - s.start_offset),
        'translation_ko', t.translation_ko
      ) order by s.start_offset)
      from public.paper_sentences s
      left join public.paper_translations t on t.paper_id = s.paper_id and t.sentence_id = s.sentence_id
      where s.paper_id = p.paper_id
    ), '[]'::jsonb),
    'glossary', coalesce((
      select jsonb_agg(jsonb_build_object(
        'term', gl.term, 'definition_ko', gl.definition_ko, 'context_ko', gl.context_ko,
        'sentence_ids', to_jsonb(gl.sentence_ids), 'highlight', gl.highlight
      ) order by gl.idx)
      from public.paper_glossary gl where gl.paper_id = p.paper_id
    ), '[]'::jsonb)
  )
  from public.papers p
  left join public.paper_ai a on a.paper_id = p.paper_id
  where p.paper_id = pid and not p.withdrawn;
$$;

revoke execute on function public.list_digests(date, int), public.get_digest(date), public.get_paper(text) from public;
grant execute on function public.list_digests(date, int), public.get_digest(date), public.get_paper(text) to anon, authenticated, service_role;
