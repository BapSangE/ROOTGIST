-- Supabase 예약을 정각으로(사용자 결정 2026-11-11). 공식 소식·트렌딩 모델 오후 수집은 KST 14:17 → 12:00으로 당긴다.
-- 미국 회사 발표는 서부 근무 시간(KST 새벽 2시~오전 10시)에 나와 오전 10시쯤이면 다 모인다. 14:17까지 기다릴 까닭이 없고,
-- 점심 무렵에 그날 아침까지의 미국 소식이 올라와 있게 한다. 앱 안내도 「오후 3시쯤」 → 「오후 1시쯤」(lib/features/common/collect_schedule.dart).
-- 17분은 GitHub 예약이 정각에 몰려 밀리는 걸 피하던 값이다. pg_cron이 workflow_dispatch로 바로 시작시키니 정각이면 된다.
-- pg_cron 시각은 UTC: 03:00 = KST 12:00. 같은 이름으로 부르면 기존 예약을 덮어쓴다.
select cron.schedule('rootgist-official-news', '0 3 * * *', $$select public.dispatch_workflow('official-news.yml')$$);

-- X 수집(20261111120000_x_posts_dispatch.sql)도 2·32분 → 정각·30분. 정각을 피할 까닭은 GitHub 예약에만 있다.
select cron.schedule('rootgist-x-posts', '0,30 * * * *', $$select public.dispatch_workflow('x-posts.yml')$$);
