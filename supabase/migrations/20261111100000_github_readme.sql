-- GitHub 순위 저장소 상세(2026-11-11): README를 AI가 한국어로 정리한 것.
-- {summary: [1~3문장], uses: [최대 3개], how: 시작하는 법 한 문장 | null}. 정리 못 한 저장소는 null.
-- 수집은 worker/official_news.py summarize_readme. 앱 상세 화면(/repo/…)이 list_github_rankings로 읽는다.

alter table public.github_rankings add column readme_ko jsonb;

create or replace function public.list_github_rankings()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'collected_at', to_char(max(r.collected_at) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'periods', coalesce((
      select jsonb_object_agg(p.period, p.body) from (
        select g.period, jsonb_build_object(
          'start', to_char(min(g.period_start) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
          'end', to_char(max(g.period_end) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
          'repos', jsonb_agg(jsonb_build_object(
            'rank', g.rank, 'full_name', g.full_name, 'url', g.url,
            'description_en', g.description_en, 'description_ko', g.description_ko,
            'language', g.language, 'stars', g.stars, 'forks', g.forks,
            'created_at', to_char(g.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
            'readme_ko', g.readme_ko
          ) order by g.rank)
        ) as body
        from public.github_rankings g
        group by g.period
      ) p
    ), '{}'::jsonb))
  from public.github_rankings r;
$$;
