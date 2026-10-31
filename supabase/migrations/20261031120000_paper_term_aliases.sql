-- 용어 별칭(2026-10-31): 관리자 웹에서 한국어·영문 별칭을 더할 수 있게 했다(relation_type ko_alias·admin_alias, 승인 상태).
-- get_paper의 논문 용어에도 별칭을 실어, 논문 상세(AI 요약·핵심 내용)·리더에서 별칭 표기도 용어로 찾게 한다.
-- 공식 소식·모델 상세는 list_terms의 aliases를 이미 쓴다. 나머지는 20261029120000과 같다.

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
          where al.sense_id = gl.sense_id and (al.review_status = 'approved' or al.relation_type in ('ko_alias', 'admin_alias'))
        ), '[]'::jsonb) end
      ) order by gl.idx)
      from public.paper_glossary gl where gl.paper_id = p.paper_id
    ), '[]'::jsonb)
  )
  from public.papers p
  left join public.paper_ai a on a.paper_id = p.paper_id
  where p.paper_id = pid and not p.withdrawn;
$$;
