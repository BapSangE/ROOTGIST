-- 배치를 정시에 시작시키기(2026-11-03). GitHub Actions 예약(schedule)은 붐비면 3~6시간 늦게 시작한다
-- (KST 02:17 예약이 11-03에는 08:52에 시작). 수동 실행(workflow_dispatch)은 바로 시작하므로
-- Supabase pg_cron이 정시에 GitHub API로 workflow_dispatch를 부른다. GitHub 예약은 예비로 남긴다
-- (이미 처리한 날짜면 몇 분 만에 끝난다).
--
-- 토큰은 이 파일에 넣지 않는다. 이 저장소만·Actions 쓰기 권한만 준 fine-grained 토큰을 SQL 편집기에서 Vault에 넣는다:
--   select vault.create_secret('<토큰>', 'github_actions_dispatch');
-- 바꿀 때: select vault.update_secret((select id from vault.secrets where name = 'github_actions_dispatch'), '<새 토큰>');
-- 결과 확인: select status_code, content, created from net._http_response order by created desc limit 5;  (204면 성공)
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

create or replace function public.dispatch_workflow(workflow text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  token text;
begin
  if workflow not in ('daily-batch.yml', 'official-news.yml') then
    raise exception 'unknown workflow %', workflow;
  end if;
  select decrypted_secret into token from vault.decrypted_secrets where name = 'github_actions_dispatch';
  if token is null then
    raise warning 'github_actions_dispatch 토큰이 Vault에 없어 % 실행을 건너뜀', workflow;
    return null;
  end if;
  return net.http_post(
    url := 'https://api.github.com/repos/BapSangE/ROOTGIST/actions/workflows/' || workflow || '/dispatches',
    body := '{"ref": "main"}'::jsonb,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || token,
      'Accept', 'application/vnd.github+json',
      'X-GitHub-Api-Version', '2022-11-28',
      'User-Agent', 'rootgist-cron',
      'Content-Type', 'application/json'));
end $$;
revoke execute on function public.dispatch_workflow(text) from public, anon, authenticated;

-- pg_cron 시각은 UTC. 같은 이름으로 다시 부르면 덮어쓴다.
-- UTC 20:00 = KST 05:00: HF 하루 논문 목록이 대부분 찬 뒤(daily-batch.yml 주석). 노출 상위 10편은 첫 실행 때 정해진다.
select cron.schedule('rootgist-daily-batch', '0 20 * * *', $$select public.dispatch_workflow('daily-batch.yml')$$);
-- UTC 05:17 = KST 14:17: 공식 소식·트렌딩 모델 오후 수집(official-news.yml).
select cron.schedule('rootgist-official-news', '17 5 * * *', $$select public.dispatch_workflow('official-news.yml')$$);
