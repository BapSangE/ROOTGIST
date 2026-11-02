-- list_terms 상한 1000 → 5000(2026-11-02). 미검토 용어 942개 승인으로 사전이 972개가 되어 곧 넘는다.
-- 이전에는 정렬 없이 1000개를 잘라 넘치면 어떤 용어가 빠질지 정해지지 않았다. 이제 많이 쓰인 순으로 자른다.
-- 5000개면 응답이 약 1.4MB(지금 972개 270KB).
-- 같은 날 미검토 의미를 일괄 승인했더니 「모델」·「평가」·「연구(outliers)」 같은 흔하거나 잘못 이어진 낱말이 소식 하이라이트·키워드 칩에
-- 잔뜩 걸렸다(소식 104건 44개 → 359개). 앱은 이 사전을 소식·모델 상세 하이라이트에만 쓰므로, 일괄 승인 전 기준대로
-- AI 1차 검토를 마친 의미(ai_review_status = first_pass_complete)만 돌려준다. 논문 화면(get_paper)은 그대로 승인된 의미를 다 쓴다.
-- 소식에 넣을 용어는 그 의미의 ai_review_status를 first_pass_complete로 올린다. 나머지는 20261031130000_usable_aliases의 정의와 같다.
create or replace function public.list_terms()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('terms', coalesce(jsonb_agg(t order by (t->>'papers')::int desc, t->>'term'), '[]'::jsonb))
  from (
    select t from (
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
        and s.ai_review_status = 'first_pass_complete'
    ) y
    order by (t->>'papers')::int desc, t->>'term'
    limit 5000
  ) x;
$$;
revoke execute on function public.list_terms() from public;
grant execute on function public.list_terms() to anon, authenticated, service_role;
