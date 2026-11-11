-- X 글 수집도 Supabase pg_cron이 30분마다 깨운다(2026-11-11).
-- x-posts.yml의 GitHub 예약(7,37분)은 붐비면 건너뛰어서 11-10에는 하루 4번만 돌았다(30분마다가 아니라 3~6시간 간격).
-- 그 사이 올라온 「한도 초기화」 같은 소식이 몇 시간씩 늦게 들어왔다. daily-batch·official-news처럼 workflow_dispatch로 바로 시작시킨다
-- (20261103090000_cron_dispatch.sql, 토큰은 같은 Vault 비밀 github_actions_dispatch).
-- 자주 깨워도 비용은 늘지 않는다: 계정마다 마지막으로 받은 글 다음부터만 받고(since_id), 하루 읽기 상한(X_DAILY_READ_CAP)도 그대로다.
-- GitHub 예약은 예비로 남긴다. 겹쳐 시작해도 워크플로 concurrency(x-posts)가 차례로 돌린다.
create or replace function public.dispatch_workflow(workflow text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  token text;
begin
  if workflow not in ('daily-batch.yml', 'official-news.yml', 'x-posts.yml') then
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

-- 매시 2분·32분(UTC든 KST든 같은 분). GitHub 예약(7·37분)과 겹치지 않게 비켜 둔다.
select cron.schedule('rootgist-x-posts', '2,32 * * * *', $$select public.dispatch_workflow('x-posts.yml')$$);
