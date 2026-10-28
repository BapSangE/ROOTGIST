# ROOTGIST Admin — 실제 연결 검증

2026-10-28 · 기준 커밋 `3a765404212b3dff50566d6ff015dd3a6fff880f`

## 현재 결정

**기존 ROOTGIST_DB 하나를 관리자 웹에서 읽기 전용으로 사용한다.** 사용자가 별도 검증 DB 준비 요청을 철회했다. 별도 DB·브랜치·컨테이너·테스트 계정은 생성하지 않았다. 운영 콘텐츠/스키마/정책/마이그레이션 변경 및 배포 없음. 공식 CLI 2.122.0 다운로드까지만 했으며 init/start/클라우드 link는 실행하지 않았다.

Supabase Auth 사용자가 0명이므로 사용자 본인이 대시보드에서 실제 관리자 1명을 생성하기로 했다. 비밀번호·서버 키는 채팅/문서/Git에 넣지 않는다. 실제 로그인에는 Auth 세션 생성/갱신이 필요하며, 콘텐츠 읽기 전용과 구분한다.

## 확인한 결과

- ROOTGIST_DB ACTIVE_HEALTHY, main만 존재.
- 읽기 전용 information_schema 조회로 어댑터 16개 테이블·106개 열을 대조했다. 누락 열 없음. public 테이블 16개 모두 RLS 활성 상태.
- 테이블 메타데이터의 추정 행 수 최대는 term_aliases 1,893행. 실제 조회 exact count와 별도이며 R0의 10,000행 제한 이내로 보인다.
- HTTPS GET `/auth/v1/health` 200. 공개 키의 terms/term_candidates 조회 200, visible rows 0. 전체 RLS 정책의 모든 경우를 검증한 것은 아니다.
- 원문 없이 읽기 전용 집계로 확인: 문장 오프셋 534행·뉴스 key_points 39행·related 39행·모델 card 10행에서 확인한 형식 오류 0. related는 JSONB가 아닌 text[]다. 첫 집계 쿼리에서 타입 함수를 잘못 적용해 오류가 났고, text[]용 검사로 수정해 성공했다.
- 실제 Supabase URL/공개 키로 로컬 production Next.js 임시 서버를 실행해 접근 경계를 확인했다. 로그인 GET 200, 관리자 페이지 307→/login, API 미로그인 GET/POST/PUT/PATCH/DELETE 모두 401. 서명 없는 위조 관리자 세션 쿠키도 401. 전부 private/no-store.
- 위 임시 서버는 **임시 불가능 UUID와 서버 키 없음**으로 미인증 경계만 검증했다. 관리자 로그인/서버 전용 조회 성공의 증거가 아니다. 검사 후 종료했다.

## 로컬 설정

`admin/.env.local`을 0600 권한으로 만들었다. ADMIN_DATA_MODE=supabase, 실제 URL, 공개 키만 설정했다. `.gitignore` 적용을 확인했다. `ADMIN_USER_ID`와 `SUPABASE_SECRET_KEY`는 아직 비어 있다.

1. [사용자 관리](https://supabase.com/dashboard/project/heiqxjuwighlefvqyevz/auth/users) → Add user → Create new user에서 실제 관리자 계정을 생성하고 이메일 확인 상태를 설정한다.
2. 생성한 User UID를 ADMIN_USER_ID에, [API Keys](https://supabase.com/dashboard/project/heiqxjuwighlefvqyevz/settings/api-keys)의 서버 전용 키를 SUPABASE_SECRET_KEY에 로컬 입력한다. 비밀번호는 파일에 넣지 않고 로그인 화면에서만 사용한다.
3. 관리자 UUID 검증 후에만 서버 전용 조회가 실행된다. 서버 키 자체는 DB 쓰기 권한을 가질 수 있다. 현재 **앱 전송기의 GET/HEAD 테이블 조회 제한 및 서버 쓰기 차단**으로 읽기 전용을 강제하며, DB 자격 증명이 SELECT 전용 역할인 것은 아니다.

## 남은 검증

- 실제 관리자 로그인 → getUser 검증 → 여섯 화면 및 DTO/API 조회.
- 인증된 POST/PUT/PATCH/DELETE가 423으로 차단되는지 확인. 운영 DB 쓰기 요청을 직접 시험하지 않는다.
- 유효하지 않은 세션은 401. 만료 access token과 무효 refresh를 구분한다. 계정/토큰을 변경·폐기하는 시험은 현재 사용자 세션에 영향을 주지 않는 범위에서만 한다.
- 비관리자 실제 세션은 계정이 없으므로 미검증. 테스트 계정은 만들지 않는다. 기존 단위 테스트의 403을 실제 비관리자 로그인 증거로 대신하지 않는다.
- notices/source catalog는 코드 스냅샷, 운영 실행 이력은 미연동인 상태를 유지한다.
- 현재 Playwright E2E는 fixture 전용이고 macOS Chromium 실행 제약이 남아 있다. 실제 Auth 검증으로 보고하지 않는다. 실제 계정으로 테스트할 때 trace/스크린샷에 쿠키·토큰·암호를 기록하지 않는다.

## 공식 참고

- [Supabase SSR 인증](https://supabase.com/docs/guides/auth/server-side/creating-a-client)
- [Supabase API 키](https://supabase.com/docs/guides/api/api-keys)
- [TLS 변경 공지](https://supabase.com/changelog/cbc-tls-ciphers-deprecated)

## 관리자 설정 후 실제 키 검증

- 사용자 설정 후 실제 환경 파일의 필수 항목이 채워졌고 대상 URL이 ROOTGIST_DB와 일치함을 값 노출 없이 확인했다.
- Auth Admin GET으로 설정한 관리자 UUID가 실제 계정과 일치하고 이메일 확인 완료·email provider임을 확인했다. 계정 이메일/UUID/비밀번호는 이 문서에 기록하지 않는다.
- 서버 키의 HEAD 조회로 어댑터와 같은 열 목록 16개 테이블 모두 성공, 전부 R0 10,000행 제한 이내임을 확인했다. worker_state는 blocked_urls 필터 결과 0행이다.
- 실제 서버 키가 `.next/static`의 JS/JSON/HTML 29개 파일과 로그인 HTML에 포함되지 않음을 확인했다. 로그인 응답은 200 및 private/no-store다.
- 기존 단위·통합 테스트를 재실행해 27 passed / 외부 fixture HTTP 1 skipped를 확인했다. 이 결과를 실제 관리자 세션의 E2E로 보지 않는다.
- 실제 연결 모드 production Next를 localhost:3101에 실행하고 사용자에게 직접 로그인하도록 요청했다. 비밀번호·세션을 전달받거나 Auth generateLink로 우회 로그인하지 않았다.
- 이 시점에는 사용자 직접 로그인 대기 중이며 인증된 앱 조회/POST 차단 검증은 아직 미완료다. 상단의 미설정 기록은 과거 사전 점검 시점의 상태다.

## 사용자 직접 로그인 후 실제 검증 결과

- 실제 관리자 이메일/암호 로그인 후 세션이 유지되는 것을 브라우저에서 확인했다. 비밀번호·액세스/리프레시 토큰·쿠키 값을 읽거나 복사·출력·파일 저장하지 않았다.
- 실제 관리자 세션의 dashboard 및 terms 조회 200, fixture=false, capability 전부 false, private/no-store. 집계는 논문 349, 뉴스 39, 적용 위치 419, 위험 적용 216, 사전/후보 검토 대기 948이었다. 단일 시점 조회이며 고정 운영 수치가 아니다.
- POST/PUT/PATCH/DELETE `/api/admin/v1/commands`는 모두 423 WRITES_NOT_READY. 특정 콘텐츠 ID나 승인 action 없이 차단 경계만 확인했다. Supabase 테이블에 쓰기 요청을 보내지 않았다.
- 별도 localhost:3102 프로세스의 관리자 허용 UUID만 불일치시키고 같은 실제 사용자 세션으로 테스트했다. GET 2종 및 변경 verb 4종 모두 403 ADMIN_ONLY. 운영 ADMIN_USER_ID·계정·DB는 바꾸지 않았다. 이 결과는 별도 비관리자 계정을 만든 검증과 구분한다.
- 대시보드/용어/논문/뉴스·모델/공지/출처·운영 여섯 화면을 실제 연결 모드로 열었다. 용어 실제 원문·번역·하이라이트, 검색 0건/복귀, 의미 연결과 저장 비활성을 확인했다. ko_span 표기 ‘월드 모델’을 ‘월드’로 바꾸면 메모리 미리보기만 변경되며 원래 표기로 복구했다.
- 논문 A02 근거 클릭은 번역 탭 유지 및 실제 A02 번역 textarea DOM 렌더링을 확인했다. 브라우저 도구의 isVisible은 false였으므로 자동 가시성 assertion 통과로 기록하지 않는다. 위치/화면 높이·스크롤을 포함한 UX 확인은 별도로 남긴다.
- 실제 thin 소식은 원문 소개문 번역·핵심 내용 없음으로 표시됐다. 모델 화면은 실제 모델 목록/메타데이터가 렌더링됐으나 card=null 자동 가시성 assertion은 통과로 기록하지 않는다. 공지는 앱 번들, 출처 카탈로그는 b8e5c6a 스냅샷, 실행 이력은 미연동 표시다.
- 임시 same-origin 검증 HTML로 브라우저가 자체 세션을 사용하게 했으며 결과에는 HTTP 상태·오류 코드·집계만 남겼다. 임시 파일을 삭제하고 권한 불일치 프로세스는 종료했다. 실제 읽기 서버는 localhost:3101에 유지한다.
- 실제 만료 토큰 refresh, 별도 비관리자 계정, 장시간 세션 및 Playwright 자동 E2E는 여전히 별도 검증 항목이다. 실제 계정/세션을 강제 폐기하거나 토큰 수명을 바꾸지 않았다.
- 사용자가 후속 운영을 용어 검수 전용으로 축소했다. [OPERATING_SCOPE.md](OPERATING_SCOPE.md)에 기록했고 기존 자동 콘텐츠 흐름은 변경하지 않았다.
