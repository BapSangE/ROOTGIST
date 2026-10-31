-- 앱에서 쓸 별칭 규칙(2026-10-31, 사용자 결정): 한국어(한글) 별칭은 승인됐거나 관리자가 직접 넣은 것만.
-- 검토 전인 구글 번역 참고 한국어 별칭(source_translation, 예: 「절제」)이 공식 소식·모델 카드에서 엉뚱한 낱말을 용어로 잡던 것을 막는다.
-- 영문 별칭(원래 이름·약어·풀이)은 표기 변형이라 검토 전이어도 그대로 쓴다. list_terms·get_paper 둘 다 같은 규칙.

create or replace function public.alias_usable(surface text, review_status text, relation_type text)
returns boolean language sql immutable set search_path = '' as $$
  select surface !~ '[가-힣]' or review_status = 'approved' or relation_type in ('ko_alias', 'admin_alias');
$$;

create or replace function public.list_terms()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('terms', coalesce(jsonb_agg(t order by (t->>'papers')::int desc, t->>'term'), '[]'::jsonb))
  from (
    select jsonb_build_object(
      'term', te.canonical_en,
      'aliases', coalesce((select jsonb_agg(distinct a.surface_form) from public.term_aliases a
        where a.sense_id = s.sense_id and public.alias_usable(a.surface_form, a.review_status, a.relation_type)), '[]'::jsonb),
      'term_ko', public.display_term_ko(s.sense_id),
      'definition_ko', s.definition_ko,
      'full_form_en', public.display_full_form(s.sense_id),
      'papers', (select count(distinct g.paper_id) from public.paper_glossary g where g.sense_id = s.sense_id)
    ) t
    from public.term_senses s
    join public.terms te on te.term_id = s.term_id
    where public.display_term_ko(s.sense_id) is not null
      and nullif(s.definition_ko, '') is not null
    limit 1000
  ) x;
$$;

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
        'full_form_en', coalesce(nullif(gl.full_form_en, ''), public.display_full_form(gl.sense_id)),
        -- 사전 별칭(승인됐거나 관리자가 직접 넣은 것). 앱 사전에 보이는 의미일 때만. 앱은 한국어 글에서 이 표기도 용어로 찾는다
        'aliases', case when public.display_term_ko(gl.sense_id) is null then '[]'::jsonb else coalesce((
          select jsonb_agg(distinct al.surface_form) from public.term_aliases al
          where al.sense_id = gl.sense_id and public.alias_usable(al.surface_form, al.review_status, al.relation_type)
        ), '[]'::jsonb) end
      ) order by gl.idx)
      from public.paper_glossary gl where gl.paper_id = p.paper_id
    ), '[]'::jsonb)
  )
  from public.papers p
  left join public.paper_ai a on a.paper_id = p.paper_id
  where p.paper_id = pid and not p.withdrawn;
$$;
