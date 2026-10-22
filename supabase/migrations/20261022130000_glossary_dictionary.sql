-- 용어 사전(연구 레포 dictionary_review_v0.1)과 자체 축적 후보, 논문 용어 ↔ 사전 의미 연결.
-- 앱 표시: 한국어 대응어(C02, G1)와 한국어 쪽 하이라이트(S03, G2)에만 쓴다. 정의 본문은 지금처럼 LLM의 「이 논문에서의 뜻」.

create table public.terms (
  term_id text primary key,
  canonical_en text not null,
  canonical_ko text,
  review_status text not null default 'pending'
);

create table public.term_senses (
  sense_id text primary key,
  term_id text not null references public.terms on delete cascade,
  canonical_ko text,
  definition_ko text,
  scope text,
  domain text,
  -- source_machine_translation_verbatim(Google AI 번역 원문, 공개 금지) | ai_rewritten | paper_glossary(자체 축적)
  definition_kind text not null,
  ai_review_status text not null,          -- not_reviewed | first_pass_complete
  review_status text not null default 'pending' check (review_status in ('pending', 'approved', 'rejected', 'deferred')),
  human_reviewer text,
  source_media_review_required boolean not null default false,
  review_note_ko text
);

create table public.term_aliases (
  alias_id text primary key,
  sense_id text not null references public.term_senses on delete cascade,
  surface_form text not null,
  normalized_form text,
  relation_type text not null,
  review_status text not null default 'pending',
  auto_match_allowed boolean not null default false
);
create index term_aliases_sense on public.term_aliases (sense_id);

-- 자체 축적: 사전에 없는 논문 용어를 모은다. 검토자가 Table Editor에서 canonical_ko를 채우고 review_status를
-- approved로 바꾸면 다음 배치가 사전(terms·term_senses·term_aliases)으로 옮긴다.
create table public.term_candidates (
  normalized_form text primary key,
  surface_form text not null,
  canonical_ko text,                       -- 검토자가 채우는 한국어 대응어
  definition_ko text not null,             -- 처음 본 논문의 LLM 정의(일반 정의, G3)
  first_paper_id text references public.papers,
  seen_count int not null default 1,
  last_seen_at timestamptz not null default now(),
  review_status text not null default 'pending' check (review_status in ('pending', 'approved', 'rejected')),
  human_reviewer text,
  sense_id text references public.term_senses on delete set null  -- 사전으로 옮긴 뒤 채움
);

alter table public.paper_glossary add column sense_id text references public.term_senses on delete set null;

-- 앱 표시 설정. show_ai_reviewed_terms=true면 사람 승인 전 AI 1차 검토본(ai_rewritten)도 보인다.
-- 외부 공개(지인 베타 포함) 전에 false로 바꾼다.
create table public.app_config (key text primary key, value text not null);
insert into public.app_config values ('show_ai_reviewed_terms', 'true');

alter table public.terms enable row level security;
alter table public.term_senses enable row level security;
alter table public.term_aliases enable row level security;
alter table public.term_candidates enable row level security;
alter table public.app_config enable row level security;

-- 앱에 보여도 되는 의미의 한국어 대응어. 기계 번역 원문은 어떤 설정에서도 내보내지 않는다.
create function public.display_term_ko(sid text)
returns text language sql stable security definer set search_path = '' as $$
  select s.canonical_ko from public.term_senses s
  where s.sense_id = sid
    and s.definition_kind <> 'source_machine_translation_verbatim'
    and (s.review_status = 'approved'
         or (s.ai_review_status = 'first_pass_complete' and s.review_status = 'pending'
             and exists (select 1 from public.app_config c where c.key = 'show_ai_reviewed_terms' and c.value = 'true')));
$$;
revoke execute on function public.display_term_ko(text) from public;

-- get_paper: glossary에 term_ko(표시 가능한 한국어 대응어 또는 null)를 더한다. 나머지는 초기 정의와 같다.
create or replace function public.get_paper(pid text)
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
        'sentence_ids', to_jsonb(gl.sentence_ids), 'highlight', gl.highlight,
        'term_ko', public.display_term_ko(gl.sense_id)
      ) order by gl.idx)
      from public.paper_glossary gl where gl.paper_id = p.paper_id
    ), '[]'::jsonb)
  )
  from public.papers p
  left join public.paper_ai a on a.paper_id = p.paper_id
  where p.paper_id = pid and not p.withdrawn;
$$;
