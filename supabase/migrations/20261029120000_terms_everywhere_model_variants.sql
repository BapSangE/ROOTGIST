-- 용어 설명 넓히기 · 모델 목록 다양화(2026-10-29).
-- 1) get_paper: 사전에 없는 용어도 번역문 속 표기(ko_span)를 내보내 한글 하이라이트가 걸리게 한다.
-- 2) list_terms: 공식 소식·모델 상세에서 쓰는 공용 용어 사전. 앱에 보일 수 있는 의미 중 논문에 한 번 이상 쓰인 것만.
-- 3) trending_models.variants: 같은 모델의 양자화판·형제 모델 묶음.

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
        'term_ko', public.display_term_ko(gl.sense_id),
        -- 번역문 속 표기는 사전 연결과 상관없이 내보낸다(우리 번역문의 부분 문자열). 대응어(term_ko)는 여전히 승인분만
        'term_ko_span', nullif(gl.ko_span, ''),
        'full_form_en', coalesce(nullif(gl.full_form_en, ''), public.display_full_form(gl.sense_id))
      ) order by gl.idx)
      from public.paper_glossary gl where gl.paper_id = p.paper_id
    ), '[]'::jsonb)
  )
  from public.papers p
  left join public.paper_ai a on a.paper_id = p.paper_id
  where p.paper_id = pid and not p.withdrawn;
$$;

create function public.list_terms()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('terms', coalesce(jsonb_agg(t order by (t->>'papers')::int desc, t->>'term'), '[]'::jsonb))
  from (
    select jsonb_build_object(
      'term', te.canonical_en,
      'aliases', coalesce((select jsonb_agg(distinct a.surface_form) from public.term_aliases a where a.sense_id = s.sense_id), '[]'::jsonb),
      'term_ko', public.display_term_ko(s.sense_id),
      'definition_ko', s.definition_ko,
      'full_form_en', public.display_full_form(s.sense_id),
      'papers', (select count(distinct g.paper_id) from public.paper_glossary g where g.sense_id = s.sense_id)
    ) t
    from public.term_senses s
    join public.terms te on te.term_id = s.term_id
    where public.display_term_ko(s.sense_id) is not null
      and nullif(s.definition_ko, '') is not null
      and exists (select 1 from public.paper_glossary g where g.sense_id = s.sense_id)
    limit 1000
  ) x;
$$;
revoke execute on function public.list_terms() from public;
grant execute on function public.list_terms() to anon, authenticated, service_role;

alter table public.trending_models add column variants jsonb not null default '[]'::jsonb;

create or replace function public.list_trending_models()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('models', coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id, 'rank', m.rank, 'author', m.author, 'name', m.name, 'task', m.task, 'params', m.params,
    'license', m.license, 'likes', m.likes, 'downloads', m.downloads,
    'created_at', to_char(m.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'arxiv', to_jsonb(m.arxiv), 'url', m.url, 'card', m.card, 'variants', m.variants
  ) order by m.rank), '[]'::jsonb))
  from public.trending_models m;
$$;
