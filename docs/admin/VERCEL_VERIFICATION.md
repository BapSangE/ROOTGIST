# Vercel 실제 배포 검증

2026-10-29 · 사용자 직접 재배포

- 프로젝트 rootgist, Production 배포 dpl_4hZKAxwFZS22WZkAxiPPDJMC2qoN의 READY 확인.
- 배포 커밋 5acc85ddf1484b081bec3c6b20480e1b5f7fb727 (main). 이후 사용자가 추가한 TestFlight 관련 커밋이며 임의로 수정/되돌리지 않았다.
- 접속 주소: https://rootgist.vercel.app/login
- 필수 환경변수 5개가 Production에 등록됨을 이름/대상 기준으로 확인했다. Secret 필드는 저장 후 값을 조회할 수 없어 실제 값을 읽거나 출력하지 않았다.
- GET /login 200, 실제 관리자 로그인 form 렌더링, 연결 설정 오류 없음. 브라우저에서도 확인했다. 초기 Python/브라우저 요청 지연·timeout이 있었고 이후 curl/플랫폼 fetch/브라우저 표시로 성공을 재확인했다. 지연 원인을 앱 오류나 특정 브라우저 문제로 단정하지 않는다.
- GET /admin: 307 → /login. GET /api/admin/v1/terms: 401 AUTH_REQUIRED. 두 요청 모두 private/no-store.
- 선택한 30분 범위의 런타임 오류/경고 조회에서 보고된 오류 없음. 전체 운영 시간의 무오류를 보장하는 결과는 아니다.
- 실제 비밀번호 로그인은 사용자가 직접 진행하도록 요청했다. 배포 도메인에서 인증된 데이터 조회·쓰기 423은 아직 확인하지 않았다. 기존 로컬 검증과 구분한다.
- 새 migration/운영 DB 적용·데이터 변경·설정 변경·재배포 실행은 하지 않았다. 이번 확인은 사용자 수행 배포의 읽기 전용 검증이다.

현재 사용자 로그인 완료를 기다린다. 비밀번호·키·세션 쿠키는 채팅이나 로그/문서에 기록하지 않는다. 원격 환경변수 변경은 이 배포에 실제로 반영된 form과 API 응답을 통해 확인하며 기존 localhost 세션을 배포 도메인에 복사하지 않는다.
