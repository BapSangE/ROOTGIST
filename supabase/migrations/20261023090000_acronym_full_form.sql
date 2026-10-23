-- 약어의 영문 정식 명칭(C02 한 줄).
-- paper_glossary.full_form_en: 초록이 직접 풀어 쓴 표기(규칙 추출, 원문 그대로) — 검토 없이 보인다.
-- term_candidates.full_form_en_draft: 초록에 풀이가 없을 때 LLM 초안. 빈 문자열은 "확인했지만 없음".
--   검토자가 full_form_en에 고쳐 쓰거나 그대로 승인하면 term_senses.full_form_en으로 옮긴다.
alter table public.paper_glossary add column full_form_en text;
alter table public.term_senses add column full_form_en text;
alter table public.term_candidates
  add column full_form_en_draft text,
  add column full_form_en text;

-- 앱에 보여도 되는 의미의 정식 명칭. 표시 조건은 display_term_ko와 같다.
create function public.display_full_form(sid text)
returns text language sql stable security definer set search_path = '' as $$
  select nullif(s.full_form_en, '') from public.term_senses s
  where s.sense_id = sid
    and s.definition_kind <> 'source_machine_translation_verbatim'
    and (s.review_status = 'approved'
         or (s.ai_review_status = 'first_pass_complete' and s.review_status = 'pending'
             and exists (select 1 from public.app_config c where c.key = 'show_ai_reviewed_terms' and c.value = 'true')));
$$;
revoke execute on function public.display_full_form(text) from public;

-- get_paper: glossary에 full_form_en(초록 풀이 우선, 없으면 사전)을 더한다. 나머지는 이전 정의와 같다.
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
        'full_form_en', coalesce(nullif(gl.full_form_en, ''), public.display_full_form(gl.sense_id))
      ) order by gl.idx)
      from public.paper_glossary gl where gl.paper_id = p.paper_id
    ), '[]'::jsonb)
  )
  from public.papers p
  left join public.paper_ai a on a.paper_id = p.paper_id
  where p.paper_id = pid and not p.withdrawn;
$$;
