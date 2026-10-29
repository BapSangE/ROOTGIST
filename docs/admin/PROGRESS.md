# ROOTGIST 관리자 웹 진행 기록

## 2026-10-28 — M0~M3 로컬 R0 구현

**상태:** 여섯 화면의 로컬 조회·미리보기 구현. 실제 Supabase Auth/DB·운영 환경 연결은 미검증. 쓰기·승인·게시는 모두 비활성. 최종 서비스 완성을 뜻하지 않는다.

### 범위와 변경

- 사용자: 작업계획 승인 후 순차 진행. 최초 범위는 M0~M3, 실행 방식은 직접 구현 후 독립 코드 리뷰.
- 기준 HEAD b8e5c6a. 기존 문서 변경 보존, 새 `admin/` 경로 사용. 별도 worktree·브랜치 생성·커밋·푸시·배포 없음.
- `admin/`: Next.js 16.4.3 / React 19.3.1 / TypeScript 6.0.3. Flutter 웹이 아니며 루트 Flutter web/은 변경하지 않음.
- M0: BASELINE, 패키지 버전/lockfile, local fixture/staging/production 경계와 기존 테스트·산출물 기준 기록.
- M1: 사전 등록 관리자용 Supabase 서버 로그인/로그아웃, getUser+UUID 검증, 비관리자 차단, private/no-store, server-only privileged GET 전송. fixture는 로컬 development/test만 허용하고 production/Vercel에서 차단.
- M2: 앱 통일 무채색 토큰·로컬 글꼴/라이선스·공통 shell/queue/문장/미리보기. firstHighlights/latexDisplay와 정규화 계약을 JS 순수 함수로 포팅.
- M3: 대시보드, 용어, 논문, 뉴스/모델, 공지, 출처·운영 화면. 가상 fixture와 기존 스키마 DTO 어댑터. 실제 데이터 연결은 하지 않음.
- 용어: 위험 작업 우선, 검색/필터, 원문·번역, sense/별칭/후보 구분, 논문별 ko_span 입력을 **메모리 내 미리보기**로만 비교. 저장되지 않으며 이동 시 초기화됨.
- 논문: A문장 근거 클릭 후 번역 탭 유지·원문/번역 위치 이동, 기존 노출/철회/AI 상태를 분리 표시.
- 뉴스: 출처/유형 필터, thin 소개문·release null 요약·관련 ID, 모델 card=null/제작사 점수 처리.
- 공지: 현재 앱 번들 snapshot을 읽기 표시. 원격 게시/새 앱 연결 전임을 명시.
- 운영: 코드 출처 카탈로그와 차단 URL 조회. 전체 배치/출처별 실행 이력은 미연동으로 표시. 예약 KST 04:17(2026-10-29부터 02:17)과 수집/성공 시각을 혼동하지 않음.
- 모든 capability=false. 모든 POST/PUT/PATCH/DELETE 요청은 인증 후 423. 실제 콘텐츠 변경 없음.

### 검증 결과

- Flutter 기준 검증: analyze 이상 없음, test 55 passed / 설정 의존 통합 1 skipped. 기존 lib/test/워커/DB 소스를 이후 변경하지 않았으므로 최종 보존은 파일 해시로 확인.
- Python 기준 검증: Python 3.12.15의 별도 작업 공간 venv, 기존 worker.test_worker 37 passed. 초기 jsonschema 미설치는 venv 설치 후 해결.
- 관리자 단위/통합: 인증 401/403/200·배포 fixture 차단·비밀 오류 제거, 강조 규칙·금지 원문·겹침·null/빈 값, 큐/커서/검색, 읽기 전송 차단. ADMIN_TEST_URL 실행에서는 실제 localhost GET/모든 쓰기 verb 차단까지 포함해 **28 passed**.
- 관리자 lint/typecheck/production build: 최종 실행 모두 exit 0으로 통과했다. 실제 명령은 admin/README.md에 기록.
- 로컬 production 모드 검사: fixture 강제 설정은 API 503, Supabase 모드의 미로그인 API는 401, /admin은 /login으로 307. 실제 자격 증명 없이 더미 URL과 공개 테스트 값만 사용. 응답은 private/no-store.
- 합성 서버 비밀값을 build env에 넣고 브라우저 .next/static JS에 포함되지 않는지 검사. 실제 비밀값을 사용하거나 로그로 출력하지 않음.
- 인앱 브라우저: 여섯 메뉴 실제 이동, 검색 0건/복귀, 번역 표기 수정에 따른 노란 강조, 입력 미선택 첫 진입, 직접 링크 선택 유지, 다음/첫 페이지, AI 실패 라벨, thin 0포인트, card=null 확인.
- 레이아웃: 1280×800 / 1440×900 / 1600×1000에서 가로 페이지 넘침 없음. 720×450 CSS 뷰포트(1440×900에서 200% 확대에 해당하는 레이아웃 폭)도 가로 넘침 없음. 브라우저 자체 줌 배율을 변경한 검증은 아님. 검색 키보드 포커스 3px·가림 없음 확인.
- Playwright E2E 스크립트 5개 작성. 이 환경의 Chromium 기동은 macOS MachPort 권한으로 실패했고, 샌드박스 밖 실행 요청도 현재 승인 정책에서 허용되지 않음. 자동 E2E 통과로 보고하지 않는다. 인앱 브라우저의 실제 검증과 별도 기록한다.

### 리뷰·수정 기록

- 독립 리뷰: 관리자 권한·fixture 배포 제한·server-only 읽기·앱 강조 호환에서 Critical 없음.
- 일반 목록의 50개 이후 접근 누락: generic queue에 next_cursor/첫 페이지 제어 추가. 작은 page size 검증 테스트 RED→GREEN 및 실제 브라우저 다음 페이지 확인.
- 처리 failed 항목의 대기 오표시: 잘못된 운영 상태이므로 중요 수정으로 취급, 실패 fixture에서 재현 후 별도 실패 라벨 표시를 브라우저로 확인.
- 직접 선택 항목이 검색 필터 밖일 때 다른 행으로 바뀌던 문제: 명시적 id 유지, 실제 브라우저 재현·수정 확인. 첫 로딩의 undefined 선택은 typecheck와 첫 진입/0건 흐름으로 검증.
- 문장 선택 URL이 목록을 다시 읽으며 번역 탭을 초기화하던 문제: 목록 query에서 id/paper/sentence 제외. 단위 테스트 RED→GREEN, 근거 클릭 후 번역 탭과 문장 표시 확인.

### 남은 작업과 다음 단계

1. 실제 분리된 환경에서 Supabase 관리자 계정·비관리자 계정·만료 세션, 실제 테이블/RLS/키·DTO 조회를 검증한다. 아직 없는 staging을 구성된 것으로 표시하지 않는다.
2. 일반 실행 환경/CI에서 Playwright 5개를 실행하고, 실제 200% 브라우저 줌·전체 키보드·긴 운영 데이터 스크롤을 추가 확인한다. 현재 시각 검수는 가상 데이터 중심이다.
3. R0 snapshot 어댑터는 표당 최대 10,000행, 여러 표의 단일 트랜잭션 snapshot이 아니다. 초과는 503이며 일부 데이터를 전체로 표시하지 않는다. 운영 연결 전 데이터 규모·비용·공개 응답 최소화를 재확인한다.
4. `source-catalog.json`/`notices-snapshot.json`은 기준 b8e5c6a의 참조본이다. 자동 최신 정보·원격 공지 게시가 아니다.
5. 후속 M4에서 관리자 초안/control/audit와 공통 잠금·버전·멱등 계약의 구체적 변경 패키지를 검토한다. M5 워커 보호까지 통합되기 전에는 term/occurrence 쓰기를 켜지 않는다.
6. 원격 공지/앱 연결, 실제 실행 계측, 배포 도메인·Vercel·운영 DDL은 아직 범위 밖이며 수행하지 않았다.

### 결정

승인된 Ink & Paper 시안 유지. UI/UX Pro Max의 부적합한 자동 스타일 추천은 미채택하고 확인된 포커스 UX 지침만 적용했다. 인증 프레임워크 검색은 0건이어서 공식 Supabase SSR 문서를 사용했다. 로컬 fixture는 실제 로그인 성공의 증거가 아니다. 현 checkout에 변경을 남겨 사용자가 검토할 수 있도록 한다.

## 2026-10-28 — 커밋·푸시 승인과 다음 순서

- 사용자 요청으로 R0 관리자 웹, 설계/진행 문서, 앞서 정리한 PostHog 인수인계를 `main`에서 커밋하고 `origin/main`에 일반 푸시한다. 강제 푸시·배포 명령·운영 DB 변경은 포함하지 않는다.
- 커밋 직전 검증을 다시 실행했다: lint/typecheck/build exit 0, 실제 localhost HTTP를 포함한 테스트 28 passed. 알려진 비밀키 패턴 검사에서 일치 항목 없음. `.env.example`만 포함하며 실제 환경 파일·node_modules·.next·테스트 산출물은 제외한다.
- Next dev가 생성한 `admin/AGENTS.md`도 개발 지침으로 포함한다.
- 다음 1: 남은 R0 검증 — 분리된 Supabase 환경의 실제 관리자/비관리자/만료 세션과 읽기 DTO를 검증하고, 실행 가능한 환경에서 자동 E2E를 확인한다. 자격 증명은 문서/채팅/저장소에 기록하지 않고 로컬 환경에 설정한다.
- 다음 2: M4 — 관리자 control/drafts/audit, 공통 트랜잭션·revision/hash·충돌 감지·operation_id 멱등성의 로컬 DB 구현 및 변경 패키지 검토.
- 다음 3: M5 배치 수정본 보호까지 연결한 뒤 M6 용어 적용 위치 저장을 활성화한다. 보호 통합 전에는 현재 쓰기 차단을 유지한다.

## 2026-10-28 — 실제 연결 사전 점검

사용자 요청으로 실제 연결 검증에 착수했다. Supabase main 메타데이터에서 어댑터 16개 테이블·106개 열의 존재와 전체 public RLS 활성 상태를 확인했다. 별도 검증 브랜치·관리자 환경 설정은 없으며, 대상 환경 선택과 인증 설정이 필요하다. 실제 Auth·관리자 웹 조회 통과로 표시하지 않는다. 상세 결과와 검증 순서는 [CONNECTION_VALIDATION.md](CONNECTION_VALIDATION.md)에 기록했다.

### 연결 환경 결정 변경 — 기존 DB 하나 사용

사용자가 별도 검증 DB 준비를 철회하고 기존 ROOTGIST_DB의 읽기 전용 연결을 선택했다. 별도 DB/컨테이너/테스트 계정은 생성하지 않았다. Auth 사용자 0명 확인 후 사용자 본인이 실제 관리자 계정을 대시보드에서 생성하기로 했다. 로컬 ignored 환경 파일에 URL/공개 키만 준비했다. 실제 HTTPS health 및 공개 RLS 경계, 로컬 production 미로그인/위조 세션 차단을 확인했다. 실제 인증된 관리자 조회와 423은 아직 미검증이다. 상세 조건과 증거를 CONNECTION_VALIDATION.md에 갱신했다.

### 관리자 설정 후 실제 키 검증

사용자가 실제 관리자 UUID·서버 키를 로컬 환경에 설정했다. 계정 일치/이메일 확인 완료, 16개 테이블의 실제 열·HEAD count, 브라우저 전달물의 서버 키 미포함을 확인했다. 27 tests passed / fixture HTTP 1 skipped. localhost:3101 실제 모드 서버와 로그인 화면을 열었으며 실제 인증 후의 6개 화면 검증을 기다린다. 키·비밀번호·세션은 출력하거나 문서에 기록하지 않았다.

### 실제 관리자 연결 검증과 운영 범위 축소

사용자 직접 로그인 후 실제 데이터 여섯 화면을 확인했다. 실제 관리자 조회 200/fixture=false, POST·PUT·PATCH·DELETE 423, 허용 UUID만 다른 임시 서버에서 같은 인증 세션의 403을 확인했다. 임시 검증 페이지를 삭제하고 불일치 서버를 종료했다. 정상 읽기 서버는 localhost:3101에 유지한다. 만료 refresh/별도 비관리자/자동 E2E는 미완료로 남긴다. 상세는 CONNECTION_VALIDATION.md.

사용자는 사람 검수를 용어에 한정하고 논문·뉴스·모델은 기존 자동 처리를 유지하기로 했다. M4~M6은 용어 초안·이력·배치 보호·적용 위치 저장만 우선하고 M7 콘텐츠 수동 승인은 제외한다. 공지 원격 게시와 출처 쓰기도 보류한다. OPERATING_SCOPE.md가 초기 전체 콘텐츠 편집 시안보다 우선한다. 이번 단계에서 관리자 앱 코드·기존 Flutter·워커·DB·마이그레이션은 수정하지 않았다.

## 2026-10-28 — M4 용어 저장 기반 구현·로컬 검증

- 기준 3a76540, 분리 작업 브랜치 codex/term-review-storage에서 구현하고 검증된 새 파일만 원래 체크아웃에 반영한다. 실제 자격 증명은 복사하지 않았다.
- 추가 파일: migration 20261028125014_admin_term_storage.sql, private control/drafts/audit/runtime 및 서버 전용 RPC 6종, TypeScript term command parser/storage adapter, DB/서버 경계 테스트, TERM_STORAGE_PLAN/PACKAGE. 기존 migration·Flutter·워커·관리자 화면/route는 수정하지 않았다.
- 저장은 원자적 트랜잭션·DB source hash/revision·draft revision·operation_id 멱등성을 검사한다. 별칭 소유권·span 유효성·승인 상태/이력·후보 동기화 대기를 구분한다.
- 단일 관리자용 global write protocol lock을 operation/row lock보다 먼저 잡아 공유 source 의존성 교착을 피한다. 향후 워커도 같은 계약이 필요하다.
- 테스트: 실제 network-none PostgreSQL 17.11에서 18 passed. 원본 8개 migration 적용 후 새 migration을 검증했고 공개 get_paper RPC 회귀도 통과. 관리자 34 passed(기존 localhost fixture HTTP 포함), lint/typecheck/build exit 0.
- 독립 리뷰 Important 4건(동시 별칭 소유권, 상속 span 검증, 감사 이력의 검토 결정/이유, 공유 source 교착)을 각각 재현 RED→GREEN 후 전체 suite 통과. Minor 보류 없음.
- 운영 DB 적용·테스트 데이터·클라우드 프로젝트·워크플로 실행·배포 없음. 쓰기 기본값 false, worker contract 0, 관리자 ID null. 기존 실제 읽기 서버와 423 차단 유지.
- 다음 단계는 M5 용어 수정본 보호의 워커 통합 패키지, 그 뒤 M6 용어 편집·저장 UI다. 이 M4만으로 실사용 저장이나 R1 전체 완료로 표시하지 않는다.
- 사용자 요청에 따라 수정사항/진행상황을 기록한 뒤 커밋·일반 푸시한다. 상세 변경·적용 전 조건·복구·결정은 TERM_STORAGE_PACKAGE.md에 기록했다.

## 2026-10-29 — Vercel Node 24 호환 조정

사용자 요청으로 관리자 engines를 24.x, .node-version을 24.22.2, @types/node를 24.19.2로 조정했다. lock 변경은 루트와 Node/undici 타입 entry 3개뿐이다. 공식 Node 바이너리를 별도 공간에 설치해 기존 Node 26 요구의 EBADENGINE을 재현한 뒤 Node 24 clean install(engine-strict)/lint/typecheck/test/build 및 Node 24 fixture HTTP를 검증했다. 총 34 tests passed. 기존 Next/React/Supabase·앱 로직·Flutter·워커·DB/migration 변경 없음. VERCEL_DEPLOYMENT.md에 단일 admin 프로젝트/환경변수/읽기 전용 한계를 기록했다. 커밋·푸시는 기존 사용자 요청에 따라 진행하며 실제 Vercel 배포·DB 적용은 하지 않는다.

## 2026-10-29 — 사용자 Vercel 재배포 검증

사용자가 환경변수 2개 추가 후 재배포했다. rootgist Production이 READY이며 커밋 5acc85d/main임을 확인했다. https://rootgist.vercel.app/login 200과 실제 로그인 form, 미로그인 관리자 307/API 401, private/no-store를 확인했다. 초기 응답 지연은 후속 요청에서 정상 표시로 재확인했으며 원인을 단정하지 않는다. 실제 로그인 후 데이터 조회는 사용자 로그인 완료 대기 중이다. VERCEL_VERIFICATION.md에 증거·한계를 남겼고 코드/DB/원격 설정/재배포는 변경하지 않았다.


### 배포 관리자 로그인 후 확인과 모델 상세 수정

사용자 직접 로그인으로 fixture=false 실제 데이터 조회를 확인했다. 용어 문맥/강조 미리보기·의미/후보, 논문·공식 뉴스, 앱 포함 공지, 출처/운영 표시를 확인했다. 대시보드 capabilities 모두 false이며 저장/게시·DB 변경은 수행하지 않았다. 논문 첫 진입의 일시적 Failed to fetch는 재진입 후 정상화됐지만 원인은 미확정이다.

모델 목록 ID의 슬래시가 상세 경로에서 처리되지 않아 ENTITY_NOT_FOUND가 되는 오류를 재현했다. 모델 리소스에만 분할/인코딩 ID 처리를 추가했다. 실패 회귀 테스트를 먼저 확인했고 Node 24.22.2 lint/typecheck/build와 실제 fixture HTTP 포함 38 tests passed. 운영 자동 배포 후 다시 검증한다. 최신 사용자 배치 예약/Flutter 커밋과 별도 디자인 작업은 유지한다. 상세와 남은 검증은 VERCEL_VERIFICATION.md.


수정 a015e45의 Production 배포 dpl_4Y8VQNmeRgUmqy168yc3GWNCLpyP READY 후 실제 모델 상세 API(fixture=false)와 모델 정보 화면의 제목/메타데이터/카드 없음 안내를 재확인했다. 모델 경로 오류 수정·배포 검증 완료. 전체 운영 무오류나 저장 기능 완료를 의미하지 않는다. 최종 검증 기록도 사용자 요청에 따라 커밋·푸시한다.
