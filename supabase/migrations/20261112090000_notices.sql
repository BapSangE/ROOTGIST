-- 서버 공지(2026-11-12, PROPOSALS P6). 앱 업데이트 없이 공지를 올리고, 앱을 열면 안 본 새 공지를 팝업으로 띄운다.
-- 앱에 묶인 docs/notices.md(처음 공지들)는 그대로 두고, 앱이 이 테이블의 공지와 합쳐 설정 › 공지사항에 보인다.
-- 쓰기는 Supabase 대시보드(Table Editor)에서 직접. 앱은 list_notices로 읽기만 한다.
-- body: docs/notices.md와 같은 마크다운 일부(빈 줄로 나눈 문단, 「- 」 목록, 「## 」 소제목).
-- popup: 앱을 열 때 팝업으로 띄울지. 「다시 보지 않기」를 누른 기기에는 다시 뜨지 않는다(기기 저장값).
-- 팝업은 그 기기의 첫 실행 3일 전 이후에 게시된 공지만 띄운다: 새로 설치한 사람에게 오래된 공지가 뜨지 않게.
-- hidden: 내리고 싶은 공지는 지우지 말고 true로(앱 저장본에서도 다음 연결 때 빠진다).

create table public.notices (
  id bigint generated always as identity primary key,
  title text not null,
  body text not null default '',
  published_at timestamptz not null default now(),
  popup boolean not null default true,
  hidden boolean not null default false,
  created_at timestamptz not null default now()
);
create index notices_published_at on public.notices (published_at desc);

alter table public.notices enable row level security;

-- 게시 시각이 지난 공지만(published_at을 미래로 두면 그때 나간다)
create function public.list_notices()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('notices', coalesce(jsonb_agg(jsonb_build_object(
    'id', n.id, 'title', n.title, 'body', n.body, 'popup', n.popup,
    'published_at', to_char(n.published_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  ) order by n.published_at desc), '[]'::jsonb))
  from (select * from public.notices where not hidden and published_at <= now() order by published_at desc limit 50) n;
$$;

revoke execute on function public.list_notices() from public;
grant execute on function public.list_notices() to anon, authenticated, service_role;
