-- 논문별 한국어 하이라이트 위치(G2). 번역문에서 그 용어를 실제로 옮긴 표기(번역문의 부분 문자열).
-- 사전 대응어(term_ko)와 번역 표기가 다를 때(예: 고정 디코더 / 동결된 디코더) 하이라이트가 빠지던 문제.
-- 빈 문자열은 "확인했지만 번역문에서 찾지 못함".
alter table public.paper_glossary add column ko_span text;

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
        -- 대응어를 보일 수 있는 용어만 번역문 위치도 내보낸다
        'term_ko_span', case when public.display_term_ko(gl.sense_id) is not null then nullif(gl.ko_span, '') end,
        'full_form_en', coalesce(nullif(gl.full_form_en, ''), public.display_full_form(gl.sense_id))
      ) order by gl.idx)
      from public.paper_glossary gl where gl.paper_id = p.paper_id
    ), '[]'::jsonb)
  )
  from public.papers p
  left join public.paper_ai a on a.paper_id = p.paper_id
  where p.paper_id = pid and not p.withdrawn;
$$;
