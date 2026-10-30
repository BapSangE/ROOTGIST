-- 공식 소식·모델 글의 용어 (2026-10-30)
-- 1) term_candidates: 소식 글에서 온 후보를 구분하고(source), 검토자가 볼 문맥(처음 본 글 id·문장)을 남긴다.
--    논문 쪽 sync는 논문에 더 이상 없는 대기 후보를 지우는데, 소식 후보는 지우지 않는다(worker/glossary.py).
-- 2) list_terms: 앱에 보이는 의미 전부(논문에 쓰였는지와 상관없이). 소식 후보를 승인하면 논문에 없어도 사전에 든다.

alter table public.term_candidates
  add column source text not null default 'paper' check (source in ('paper', 'news')),
  add column first_news_id text,
  add column context_ko text;

create or replace function public.list_terms()
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
    limit 1000
  ) x;
$$;
revoke execute on function public.list_terms() from public;
grant execute on function public.list_terms() to anon, authenticated, service_role;
