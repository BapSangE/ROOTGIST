# ROOTGIST 관리자 웹 작업계획서

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 이 문서는 계획 검토용이며 제품 구현을 시작한 기록이 아니다.

**Goal:** 1인 관리자가 용어의 의미·표기·실제 번역문 적용 위치만 사람 검수·교정한다. 논문·뉴스·모델은 기존 워커의 자동 수집·요약·공개를 유지하고 관리자는 문맥·상태·오류를 조회한다.

**Architecture:** 저장소 루트의 별도 `admin/`에 Next.js 웹과 관리자 서버 경로를 둔다. 기존 Supabase 테이블과 공개 앱 RPC는 유지하고, 관리자 쓰기는 인증·충돌 감지·트랜잭션·워커 보호를 갖춘 전용 경로로 추가한다. 구현은 사용자와 Codex가 직접 진행하며 각 단계의 변경·검증·미완료 사항을 `docs/`에 기록한다.

**Tech Stack [계획 제안]:** Next.js App Router, React, TypeScript, CSS variables/CSS Modules, Supabase Auth + 서버 SDK, Vercel, Vitest, Playwright, 로컬 Supabase/PostgreSQL 통합 테스트. FastAPI 상시 서버와 새 수집 서버는 추가하지 않는다. 정확한 패키지·Node 버전은 M0에서 공식 지원 조합을 확인해 고정한다.

**Spec:** [관리자 웹 구현 명세서 v1.0](admin/ROOTGIST_Admin_Implementation_Spec.md). 같은 폴더의 `screens/`는 앞서 검토한 Ink & Paper V2 가상 시안이다. 사본의 과거 작성 범위 설명은 당시 상태이며, 최신 코드 사실은 이 계획서의 기준점을 함께 읽는다.

작성일: 2026-10-28 · 상태: **사용자 승인 / R0 실제 읽기 연결 검증 / M4 저장 기반 로컬 검증 / 운영 쓰기 비활성** · 실행 방식: 같은 작업 흐름에서 직접 구현, 단계별 검증 후 기록. 소요 일정은 스테이징·접근 권한·통합 난이도를 M0에서 확인한 뒤 산정하며 날짜를 임의 확약하지 않는다.

## 최신 운영 범위 — 2026-10-28 사용자 결정

**사람 검수는 용어만 한다.** [OPERATING_SCOPE.md](admin/OPERATING_SCOPE.md)가 아래 초기 전체 콘텐츠 편집 계획보다 우선한다. M4~M6은 용어 초안·이력·저장·배치 보호에 집중한다. M7/R2의 논문·뉴스·모델 수동 편집/승인은 현재 범위에서 제외하고, M8 공지 서버 게시·M9 출처 편집/차단 URL 쓰기는 보류한다. 논문·뉴스·모델 자동 공개에 수동 승인 관문을 추가하지 않는다. 기존 여섯 화면은 용어 문맥과 운영 조회 용도로 유지하며 비활성 콘텐츠 승인 버튼은 후속 UI 정리 대상이다.

기존 ROOTGIST_DB 하나에 실제 관리자 읽기 연결을 검증했다. 조회 200, 인증된 쓰기 423, 허용 UUID 불일치 403을 확인했다. 별도 검증 DB·테스트 계정은 만들지 않았다. 기존 기간의 기록과 제안은 아래에 보존한다.

## Global Constraints — 모든 단계의 공통 제약

- 한국어 우선, 관리자 1명, Desktop First. 1280×800 / 1440×900 / 1600×1000에서 검수한다.
- 앱과 같은 밝은 무채색·Pretendard·Source Serif 4·검정 버튼·노란 용어 강조를 유지한다. 관리자 밀도는 별도로 조정한다.
- 용어의 **실제 번역문 적용 위치 확인·교정**이 최우선이다. 후보 승인만으로 용어 검수 완료를 선언하지 않는다.
- Flutter용 루트 `web/`는 관리자 웹 경로로 사용하지 않는다. 기존 Flutter 디자인·읽기 RPC·캐시·북마크·PostHog 연동을 유지한다.
- 기존 테이블·문장 A01/A02·기존 마이그레이션은 전면 교체하거나 다시 작성하지 않는다. 추가 스키마와 워커 통합은 단계별 제안으로 구분한다.
- 계획서 최초 작성에서는 문서만 작성했다. 이후 사용자의 순차 진행 승인으로 M0~M3의 독립 웹 구현을 진행한다. 기존 앱·워커 수정, 운영 DDL 적용, 실제 콘텐츠 수정, 배포·푸시는 이 범위에서 수행하지 않는다.
- 계획 승인 후에도 최초 구현 범위는 M0~M3의 관리자 독립 영역과 로컬/fixture 검증이다. M4 이후 기존 DB·워커·앱 연결의 변경 패키지를 먼저 검토하고, 운영 적용·배포는 구체적인 검증 결과와 변경 목록을 확인한 뒤 별도로 진행한다.
- 공개 저장소의 예시·테스트·스크린샷은 가상 데이터만 사용한다. 실제 본문·번역·LLM 출력·API 키·운영 관리자 UUID는 기록하지 않는다.
- 실제 관리자 내용은 서버 인증을 거쳐 읽고 쓴다. 서버 secret/service key는 브라우저 번들·NEXT_PUBLIC_*·URL·로그에 넣지 않는다.
- 기존 TestFlight 심사 빌드·IPA·archive를 교체하지 않는다. 원격 공지 연결은 향후 새 앱 빌드에만 적용한다.
- 지원하지 않는 기능은 capability와 이유로 표시한다. 가상 수치·미연동 데이터를 운영 성공이나 0건으로 표시하지 않는다.

## Review Focus — 반드시 테스트로 확인할 실패 조건

| 위험 입력·조건 | 기대 동작 | 담당 단계 |
|---|---|---|
| 미로그인·비관리자·만료 세션·직접 API 호출 | 비밀 조회·DB 쓰기 전에 401/403, 편집값 보존 | M1/M4 |
| 관리자 편집 사이 워커가 glossary를 교체하거나 원문이 변경됨 | revision/hash/expected_term 충돌, 기존 일관된 원문·문장·번역 세트 보존 | M4/M5/M6 |
| 같은 operation_id 동시 재전송·다른 payload 재사용 | 한 번만 반영, 다른 payload는 409, 부분 성공 없음 | M4 |
| null/빈 ko_span·겹침·조사·이모지·LaTeX | 현재 Flutter와 같은 폴백·강조 결과, 임의 두 번째 위치 저장 금지 | M2/M6 |
| 공지 앱 미연결·부분 배치 실패·권한 없는 출처 로그 | 앱 게시 완료/전체 성공으로 오표시하지 않음, 초안·비공개 유출 없음 | M3/M8/M9 |

---

## 1. 확인한 현재 상태와 기획의 차이

기준 저장소 HEAD는 `b8e5c6a` (`testflight연동_posthog세팅`)다. 기존 디자인 명세의 기준 `39774df…` 이후 PostHog가 추가됐다. 작업 시작 당시 `docs/ANALYTICS.md`, `docs/HANDOFF.md`에 이번 대화의 문서 변경이 남아 있어 보존한다. 라이브 DB·Auth·Vercel·배포 상태는 조회하지 않았다.

| 영역 | 코드에서 확인한 사실 | 구현에 미치는 영향 |
|---|---|---|
| 관리자 웹 | Next.js package와 관리자 서버 경로 없음 | 시안 HTML은 제품 앱이 아니다. `admin/`을 별도 생성해야 함 |
| Flutter | go_router, Supabase 공개 읽기 RPC, 로컬 저장/캐시, PostHog 연동 | 기존 읽기 계약과 분석 이벤트를 회귀 검증 |
| 용어 | terms/term_senses/term_aliases/term_candidates/paper_glossary 존재 | 기존 필드와 키를 재사용. 관리자 초안·이력·동시성 제어는 아직 없음 |
| 적용 위치 | paper_glossary의 sense_id/ko_span/sentence_ids/highlight, 앱 firstHighlights | 현재 강조 알고리즘을 웹 미리보기로 포팅해야 함 |
| 논문 저장 | `worker/db.py:save_paper_ai`가 하위 결과를 삭제 후 재삽입 | 수정 UI만 먼저 켜면 사람 수정이 사라질 수 있음 |
| 사전 동기화 | `worker/glossary.py:plan_links`가 현재 auto_match_allowed를 필터링하지 않음 | 스위치를 운영 제어로 제공하기 전에 승인 별칭 규칙을 통합해야 함 |
| 뉴스·모델 | official_news의 thin/related와 trending_models.card, 배치 upsert/목록 교체 | 타입별 예외와 사람 수정본 보존이 필요 |
| 공지 | `notices.dart`가 rootBundle의 `docs/notices.md`를 읽음 | 웹 저장만으로 현재 앱에 공지가 전달되지 않음 |
| 운영 | schedule `17 19 * * *` = KST 04:17. batch→official-news 순서 | 예약 시각·실행 시각·성공 시각 구분. 실행별 상세 계측은 신규 작업 |
| 마이그레이션 | README는 main push 적용을 설명하지만 확인한 워크플로에는 schedule/workflow_dispatch와 배치 잡만 있음 | 자동 적용 경로가 존재한다고 가정하지 않고 M0/M10에서 실제 절차 확인 |

공통 사실: AI ready는 사람 승인과 다르다. candidate.seen_count는 고유 논문 수가 아니다. is_exposed는 날짜별 목록 노출이며 withdrawn은 철회 정보다. 기존 노출 정책을 새 검수 상태와 임의로 연결하지 않는다.

## 2. 범위와 출고 단위

| 출고 단위 | 포함 단계 | 검토 가능한 결과 | 완료 조건 |
|---|---|---|---|
| R0 조회·미리보기 | M0~M3 | 여섯 화면, 로그인/권한, 용어 문맥·앱 미리보기, 읽기 전용 데이터 | 실제 조회 연동은 별도 검증. 쓰기/게시 버튼은 비활성. R0를 최종 완성으로 표시하지 않음 |
| R1 용어 검수 | M4~M6 | 논문별 적용 위치 저장, 사전 의미·별칭·후보 검수, 초안/이력 | term_writes와 occurrence_writes 모두 true. 전체 논문 저장·재생성 보호까지 통합됨 |
| R2 콘텐츠 검수 | M7 | 논문 요약·근거·번역, 뉴스·모델 편집/승인 | paper_writes/news_writes 조건과 워커 보호 테스트 충족 |
| R3 공지·운영 | M8~M9 | 공지 서버 게시/새 앱 연결, 출처 메모·차단 URL·실행 이력 | 서버 게시/앱 전달 구분, 계측 실제 수신과 읽음 호환 검증 |
| 운영 배포 | M10 | 검증 증거·적용 순서·복구 절차가 있는 배포 패키지 | 운영자 승인 및 환경별 실측 확인. 계획 작성은 배포 허가가 아님 |

초기 제외: 조직/역할 관리 UI, 광고·결제·매출 KPI, 콘텐츠 자동 일괄 치환, 임의 수집 URL 추가·프록시, 수동 배치/LLM 재생성 실행 버튼, 예약 게시, 원클릭 감사 이력 되돌림. 기존 논문/뉴스 공개 정책 변경도 별도 범위다.

## 3. 예정 디렉터리와 공통 계약

```text
admin/                               # 새 독립 Next.js 앱; 루트 Flutter 설정 유지
  src/app/login/page.tsx
  src/app/admin/{page,layout}.tsx
  src/app/admin/{terms,papers,news,notices,operations}/page.tsx
  src/app/api/admin/v1/               # 구현 명세 11장의 서버 API
  src/components/                    # shell, queue, sentence-pair, preview, action-bar
  src/lib/domain/                    # 순수 표시/검증 함수, 상태와 계약
  src/lib/server/                    # 인증, 데이터 읽기, command/draft 서비스
  src/lib/supabase/                   # 세션용 클라이언트와 server-only 클라이언트 분리
  src/styles/tokens.css
  tests/{unit,integration,e2e}/
  package.json / package-lock.json / .env.example
supabase/tests/admin/                # 향후 로컬 DB 계약·동시성·권한 테스트
worker/admin_store.py                # 향후 공통 DB 함수 호출 어댑터
worker/test_admin_store.py           # 향후 기존 배치와 보호본 공존 테스트
lib/data/notices_repository.dart      # M8에서만 제안하는 새 원격 공지 경로
```

모든 경로는 **예정 경로**다. 관리자 추가 테이블명·열은 구현 명세 10장의 제안이며 현재 DB에 존재한다고 가정하지 않는다. 마이그레이션 이름은 지금 가짜 시각으로 만들지 않고 실제 작성 시 CLI `migration new`로 생성한다. 관리자 기능마다 무관한 루트 package/workspace를 추가하지 않는다.

공통 인터페이스는 `admin/src/lib/domain/contracts.ts`에 정의한다.

```ts
type Capability = 'term_writes' | 'occurrence_writes' | 'paper_writes'
  | 'news_writes' | 'notice_publish' | 'notice_app_integration'
  | 'source_metadata_writes' | 'operations_history';
type Capabilities = Record<Capability, { enabled: boolean; reason: string | null }>;
type Revisioned<T> = { value: T; revision: number; base_sha256: string };
type PageResult<T> = { rows: T[]; next_cursor: string | null };
type ErrorCode = 'AUTH_REQUIRED' | 'ADMIN_ONLY' | 'ENTITY_NOT_FOUND'
  | 'VERSION_CONFLICT' | 'DRAFT_CONFLICT' | 'OPERATION_MISMATCH'
  | 'WRITES_NOT_READY' | 'VALIDATION_FAILED' | 'DEPENDENCY_UNAVAILABLE';
```

전체 action/entity/error 세부 집합은 명세 11장을 따른다. UI 검증을 통과해도 서버/DB 검증을 생략하지 않는다. hash는 DB 공통 canonical JSON 규칙으로 계산하고 클라이언트에는 불투명한 기준값으로 전달한다. 임의 JSON 키 순서나 문자열 연결을 버전 대신 쓰지 않는다. 공통 이름 변경 시 명세·이 계획·구현 타입을 함께 갱신한다.

## 4. 단계별 작업

### M0. 착수 기준과 환경 분리

**파일:** 신규 `docs/admin/BASELINE.md`, `docs/admin/PROGRESS.md`, `admin/.env.example`; 기존 `.github/workflows/daily-batch.yml`은 읽기 점검만 한다.

**입력:** 현재 저장소·마이그레이션·명세. **출력:** baseline 표, 환경 구분, 적용/배포 경로, 고정할 Node/패키지 조합과 테스트 명령.

- [ ] HEAD·기존 수정 파일·공개 RPC 응답·Flutter/worker 기준 테스트와 배포 산출물 보존 위치를 기록한다. 이미 수행한 PostHog 테스트 56개 결과를 새로운 웹 구현 검증으로 재사용하지 않는다.
- [ ] 로컬 fixture → 로컬 Supabase → 분리된 staging → production 순서로 환경을 정의한다. 아직 없는 staging을 있는 것으로 표시하지 않는다.
- [ ] 공식 문서로 Node/Next/React/Supabase SDK의 지원 조합을 확인하고 정확한 버전과 lockfile 정책을 BASELINE에 기록한다. npm 스크립트는 `lint`, `typecheck`, `test`, `test:integration`, `test:e2e`, `build`로 통일한다.
- [ ] 실제 마이그레이션 적용 경로를 확인한다. 자동 배포가 발견되면 M4 변경이 main push만으로 운영에 적용되지 않도록 배포 경계를 먼저 검토한다.
- [ ] `docs/admin/PROGRESS.md`에 단계·변경 파일·검증 명령/결과·남은 항목·다음 작업을 기록한다.

**완료 기준:** 제품 코드 없이도 작업 환경과 운영에 영향을 줄 수 있는 경로가 설명된다. 실제 운영 UUID·키·권한은 별도 제공 사항으로 남긴다.

### M1. 독립 웹 골격과 관리자 인증

**파일:** 신규 `admin/package.json`, lockfile, `src/app/{layout,login/page,admin/layout}.tsx`, `src/lib/server/require-admin.ts`, `src/lib/supabase/{browser,server,privileged}.ts`, `src/lib/server/environment.ts`, `tests/integration/auth.test.ts`, `tests/e2e/auth.spec.ts`.

**인터페이스:** `requireAdmin(): Promise<{ user_id: string }>`는 서버 검증 신원과 서버 `ADMIN_USER_ID`를 비교한다. `getDataMode(): 'fixture'|'supabase'`와 server-only privileged client를 제공한다.

- [ ] 비로그인 요청 401, 로그인한 비관리자 403, 관리자 요청 200이며 앞의 두 경우 데이터 함수가 호출되지 않는 테스트를 먼저 작성·실패 확인한다.
- [ ] Next.js App Router를 `admin/` 안에 만들고, 공개 회원가입 없는 사전 등록 관리자 로그인을 연결한다. 페이지·API·쓰기 서비스 각각 권한을 검사한다. 쿠키의 세션 객체와 user_metadata만으로 승인하지 않는다.
- [ ] fixture 모드는 로컬 개발·테스트 전용으로 제한한다. 배포 환경의 설정 누락이나 Auth 장애는 인증 우회 대신 차단 상태로 처리한다. 개인 데이터가 포함된 응답은 private/no-store로 둔다.
- [ ] `npm --prefix admin run test:integration -- auth` 및 `test:e2e -- auth`를 실행해 위 상태와 로그아웃·만료·직접 URL 접근을 확인한다. 브라우저 번들/소스맵에 서버 키가 없는지도 검사한다.

**완료 기준:** 모든 관리자 경로의 접근이 일관되게 차단·허용되며, 인증이 붙기 전 실제 데이터 조회를 켜지 않는다.

### M2. 앱 통일 디자인과 강조 미리보기

**파일:** 신규 `admin/src/styles/tokens.css`, `src/components/{admin-shell,review-queue,sentence-pair,app-preview,review-action-bar}.tsx`, `src/lib/domain/{display,highlights,normalization}.ts`, `tests/unit/reader-parity.test.ts`, `tests/fixtures/reader-cases.json`.

**인터페이스:** `projectPaperForPreview(input: PreviewInput): PreviewProjection`. 입력은 명세의 문장·번역·glossary·표시 정책이고 출력은 안전한 EN/KO 표시 문자열과 강조 범위다. `normalizeTerm(value: string): string`은 worker normalize/variants와 동일한 계약을 갖는다.

- [ ] 명세 T01~T07/T13과 한국어 조사·이모지·LaTeX 사례를 가상 입력으로 작성한다. 예: 사전 ‘고정 디코더’/번역 ‘동결된 디코더’는 ko_span 수정 후 후자만 강조하고, 빈 span과 null의 DB 값은 구분하되 RPC 폴백 결과는 현재 앱과 같아야 한다. 기대 결과는 원본 Dart/Python 동작에서 독립적으로 얻는다.
- [ ] `test -- reader-parity`의 미구현 실패를 확인한 뒤 firstHighlights/latexDisplay/정규화 계약을 포팅한다. 강조는 안전한 텍스트 노드로 렌더링하고 임의 HTML을 사용하지 않는다.
- [ ] 기존 글꼴 파일을 관리자 경로에 라이선스와 함께 복사하고, 무채색 토큰·포커스·목록/중앙/우측 독립 스크롤·패널 내 작업 바를 만든다. 전역 의미와 이 논문 적용 범위를 항상 표시한다.
- [ ] `test -- reader-parity` 통과 후 Playwright로 3개 기준 해상도·200% 확대·키보드 포커스·긴 한영 텍스트를 확인하고 가상 데이터 스크린샷을 남긴다.

**완료 기준:** 보기 좋은 시안만이 아니라 앱과 같은 강조 결과를 확인할 수 있다. 이 단계에서는 데이터 쓰기를 제공하지 않는다.

### M3. 여섯 화면 조회와 R0 검토본

**파일:** 신규 여섯 admin page, `src/lib/server/read-models/{dashboard,terms,papers,news,notices,operations}.ts`, `src/app/api/admin/v1/**/route.ts`의 GET 경로, `tests/integration/read-models.test.ts`, `tests/e2e/review-readonly.spec.ts`.

**인터페이스:** 목록은 `PageResult<T>`, 상세는 `Revisioned<T>`와 capabilities를 반환한다. terms는 candidate/sense/occurrence를 구분하며 `paper_id+idx` 적용 위치 키와 원문·번역 문맥을 연결한다. 신규 control이 없을 때 revision=0은 읽기 계약의 가상 기준값이며 실제 수정 이력이 아니다. hash는 실제 원본에서 계산하고 쓰기는 금지한다. M4 연결 후 상세를 다시 조회해 DB의 기준 revision/hash를 받는다.

- [ ] 미연동·조회 실패·정상 0건을 별개로, cursor 50개와 검색 debounce 300ms·선택 URL/뒤로가기 복원을 테스트한다. 숨은 패널의 데이터를 성공 건수로 집계하지 않는 사례를 포함한다.
- [ ] 읽기 전용 DTO를 기존 테이블에 매핑한다. 용어는 위험 적용 위치 우선, 논문은 A문장 근거 연결, 뉴스는 thin/related/release nullable 요약, 모델은 card=null을 처리한다.
- [ ] 원격 공지 API가 없으면 기존 번들 공지의 명시적 snapshot/fixture만 읽고 ‘앱 번들 공지’로 표시한다. 출처는 Python 코드 정의에서 만든 버전 있는 읽기 카탈로그를 사용하며, 관리 웹에서 임의 수집 URL을 등록하지 않는다.
- [ ] 실제 실행 계측·관리자 검수 이력이 없는 지표는 ‘연동 필요’로 표시한다. 쓰기·승인·게시 버튼은 false capability의 이유와 함께 비활성화한다.
- [ ] `test:integration -- read-models`와 `test:e2e -- review-readonly`를 실행한다. 실제 조회 연결은 관리자 권한·별도 환경 확인 후에만 수행하고 fixture 화면과 구분해 기록한다.

**완료 기준:** R0 데모가 여섯 화면에서 동작한다. 수정·공개가 가능한 완성 제품이라고 표시하지 않는다.

### M4. 공통 초안·트랜잭션·동시성 기반

**현재 상태:** 용어에 한정한 저장 기반 구현·로컬 검증 완료, 운영 미적용. [검토 패키지](admin/TERM_STORAGE_PACKAGE.md)가 이 단계의 실제 범위·서명·검증 결과다. M5/M6 전에는 route/capability를 활성화하지 않는다. 아래 초기 범용 계획에서 paper/news/model 편집은 최신 운영 범위에 따라 제외한다.

**파일:** 신규 `src/lib/domain/{commands,validation}.ts`, `src/lib/server/{draft-service,command-service,capabilities}.ts`, `src/app/api/admin/v1/{drafts,commands,history}/**`, `supabase/tests/admin/{permissions,commands,concurrency}.sql`, 향후 additive 관리자 migration.

**인터페이스:** `saveDraft(input, actor)`는 draft_revision을, `executeCommand(input, actor)`는 명세 11장의 operation_id·targets·후속 작업을 반환한다. 검증된 actor는 서버가 넣는다. DB는 candidate/sense/paper/news/model/blocked_urls 단위로 revision/hash와 잠금을 공유한다.

- [ ] 로컬 DB 테스트를 먼저 작성한다. 같은 operation_id 동시 실행은 이력 1건/결과 1회, 같은 ID+다른 payload는 409, 중간 target 실패는 전체 rollback, stale hash는 409여야 한다. 일반 사용자/anon의 관리자 테이블 및 함수 접근은 거절해야 한다.
- [ ] 명세 10장의 control/drafts/audit 기반을 additive migration으로 작성·로컬 적용한다. human active 초안에만 조건부 유일 인덱스를 두고 과거 accepted/discarded 초안을 보존한다. 기존 마이그레이션은 고치지 않는다.
- [ ] operation_id advisory lock → 안정된 순서의 행 잠금 → hash/revision 재검사 → 허용 필드/참조 검증 → 원본/보호/검수/audit 갱신을 한 DB 트랜잭션으로 구현한다. JSON의 빠진 키/명시적 null을 구별하고 관리자가 수정하지 않은 행을 보존한다.
- [ ] 공개 역할의 관리자 함수 EXECUTE 권한을 제거하고 서버 역할만 허용한다. 내부 테이블 RLS, 고정 search_path와 허용 action×entity_type/필드 행렬, 동일 출처 쓰기 검증, 요청 크기 제한을 확인한다.
- [ ] `test:integration -- commands`와 로컬 SQL 테스트를 실행한다. SQL은 운영 DB에 적용하지 않고 변경·롤백·권한 패키지를 문서화한다.

**완료 기준:** UI 저장을 활성화하기 전 공통 계약을 증명한다. 이 단계만으로 term_writes/occurrence_writes를 true로 만들지 않는다.

### M5. 워커 수정본 보호와 재생성 제안

**파일:** 향후 `worker/admin_store.py`, `worker/test_admin_store.py`; 변경 후보 `worker/db.py`, `worker/glossary.py`, `worker/official_news.py`, 추가 DB 함수. 변경 패키지 검토 후 착수한다.

**인터페이스:** `AdminStore.save_paper_generation(paper_id, generation)`과 glossary/candidate/news/model 저장 경로가 M4와 같은 DB 잠금·revision·보호 계약을 사용한다. 보호된 새 생성물은 origin=worker/purpose=regenerate 초안으로 보존한다.

- [ ] 보호된 paper와 신규 생성물을 준비한 로컬 통합 테스트를 먼저 만든다. 워커 저장·관리자 저장의 양방향 실행 순서에서도 수정본이 사라지거나 새 abstract와 옛 번역이 혼합되지 않아야 한다.
- [ ] save_paper_ai의 삭제/재삽입뿐 아니라 glossary의 sense 연결·span·약어 채움, 후보 정리/승격, 뉴스 upsert, 모델 목록 교체까지 전체 쓰기 경로를 공통 저장 함수로 연결한다. 일부 하위 쓰기만 보호하는 구현을 출고하지 않는다.
- [ ] 승인되고 auto_match_allowed=true인 별칭만 자동 연결한다. 다의어 경고·정규화 중복, 후보 승격 중복 방지, 보호/초안 후보의 stale 삭제 제외를 테스트한다. 순위에서 빠진 모델의 보호된 카드/검수 이력을 남긴다.
- [ ] 보호된 생성물과 새 제안 전체를 비교하는 재생성 조회/채택 경로를 만든다. 채택은 paper 트랜잭션, 기존 human 초안 충돌은 확인, 채택 후 pending, occurrence 확인은 초기화한다. idx만으로 과거 수정값을 재적용하지 않는다.
- [ ] `python -m unittest worker.test_worker worker.test_admin_store`와 로컬 DB 경합 테스트를 통과시킨다. 운영 배치 실행이나 LLM 실호출은 테스트로 대신하지 않는다.

**완료 기준:** 기존 배치 기능이 유지되고 관리자 보호본과 공존한다. 이 단계가 없으면 occurrence_writes는 반드시 false다.

### M6. 최우선 용어 검수 저장과 R1

**파일:** `admin/src/app/admin/terms/page.tsx`, `src/components/terms/{sense-editor,alias-editor,occurrence-editor,context-panel}.tsx`, `src/lib/domain/term-validation.ts`, `tests/e2e/terms.spec.ts`.

**인터페이스:** M3 상세와 M4 command/draft 서비스를 사용한다. 적용 위치는 paper target의 부분 glossary patch, 의미+별칭은 sense target, 후보는 normalized_form으로 처리한다. 필요 capability는 서버도 검사한다.

- [ ] T01~T13을 사용자 흐름 테스트로 먼저 작성한다. 없는 span은 422, 옛 idx/expected_term은 409, 바뀌지 않은 glossary 행은 보존, 다른 의미와 연결된 별칭은 자동 연결 불가, 의미 승인과 미확인 문맥은 독립이어야 한다.
- [ ] 좌측 목록→중앙 편집→우측 EN/KO·실제 강조→앱 미리보기→저장 순서를 연결한다. 드래그와 직접 문자열 입력을 함께 제공한다. null/빈 문자열·현재 앱/승인 가정 미리보기를 구분한다.
- [ ] 적용 위치 저장 → 사전 의미·별칭 → 후보 검수/승격 순서로 연결한다. 의미 승인 후에도 다른 논문의 미확인 작업을 남긴다. 후보 승인·사전 반영 대기를 구분하고 부분 성공을 허용하지 않는다.
- [ ] 명시적 임시 저장, 충돌 비교, 미저장 이동 경고, ⌘/Ctrl+S·Enter, J/K 입력 중 제외, 승인 후 다음을 검증한다. 2초 자동 저장은 명시적 저장과 충돌 계약이 완성된 다음 같은 단계의 후속 작업으로 켜며, 그 전에는 제공하지 않는다.
- [ ] `test:e2e -- terms`, 모든 domain/DB 테스트와 기존 Flutter 테스트를 실행한다. term_writes와 occurrence_writes가 함께 true일 때만 R1 완료로 기록한다.

**완료 기준:** 가상 데이터로 ‘동결된 디코더’ 실제 적용 위치를 교정하고, 보호된 실제 경로로 저장할 수 있다. 운영 검수 내용 자체는 공개 기록에 남기지 않는다.

### M7. 논문·뉴스·모델 검수와 R2

**파일:** admin papers/news pages와 전용 편집 컴포넌트, `src/lib/domain/{paper,news,model}-validation.ts`, `tests/e2e/content-review.spec.ts`; M4/M5 저장 경로 재사용.

**인터페이스:** paper 전체 편집은 paper_writes, news/model 편집은 news_writes를 요구한다. 공통 errors와 초안/검수/보호 계약을 그대로 사용한다.

- [ ] 다른 논문 근거 ID 422, 번역 변경 후 span 재검증, thin 0포인트, release null 요약, related의 자신/중복/없는 ID 거절, card=null, 보호 카드 보존을 먼저 테스트한다.
- [ ] 논문 제목·요약·핵심 내용·A문장별 번역·근거와 용어 적용을 연결한다. 원문 초록/offset/문장 식별자는 읽기 전용으로 유지한다.
- [ ] 뉴스 편집과 모델 card 폼을 분리한다. 원문 전문이 DB에 있는 것처럼 표시하지 않고 수집된 근거와 외부 링크를 제공한다. 제작사 벤치마크 점수/단위를 임의로 변환하지 않는다.
- [ ] 사람 검수 상태와 현재 앱 노출을 나란히 표시한다. paper_ai.status, withdrawn, is_exposed를 승인/비공개 토글로 바꾸지 않는다.
- [ ] `test:e2e -- content-review` 및 전체 웹/워커/공개 RPC 회귀 테스트로 R2 완료를 판정한다.

### M8. 공지 서버 관리와 새 앱 연결

**파일:** admin notices page, notice API/DB 함수·admin_notices, `tests/e2e/notices.spec.ts`; 후속 `lib/data/notices_repository.dart`, `lib/features/settings/notices.dart`, `test/widget_test.dart` 변경 제안.

**인터페이스:** 서버 초안은 admin_drafts, 공개 버전은 admin_notices로 단일화한다. `notice_publish`와 `notice_app_integration`을 분리한다. 공개 RPC는 published+published_at<=now의 공개 버전만 반환한다.

- [ ] 게시된 공지의 초안 편집이 공개 본문을 바꾸지 않음, 비공개/미래 날짜 제외, 제목 변경에도 UUID 읽음 키 유지, legacy_key 매핑, XSS 입력 거절을 먼저 테스트한다.
- [ ] 현재 앱 Markdown 파서 지원 범위에 맞춰 제목·본문·미리보기·임시 저장·게시·비공개를 연결한다. 예약 실행이 없으므로 미래 게시 시각을 허용하지 않는다.
- [ ] 새 앱용 원격 공지 경로를 구현한다. 정상 응답은 빈 목록도 캐시하고, 이후 통신 실패에는 마지막 정상 원격 캐시만 사용한다. 정상 원격 응답을 한 번도 받은 적 없는 설치만 최초 실패 시 번들 공지를 ‘기기 포함 공지’로 표시한다. 정상 빈 목록을 번들로 대체하지 않는다. 오프라인 기기에는 서버의 비공개 전환을 즉시 전파할 수 없다는 한계를 명시하고 테스트한다.
- [ ] 서버 게시 기능과 실제 앱 반영을 별도 상태로 표시한다. 구버전 앱이 계속 번들 공지만 읽는 제약을 게시 확인에 명시한다.
- [ ] `test:e2e -- notices`, Flutter analyze/test와 원격 읽기·읽음 키 호환 테스트를 통과시킨다. 기존 심사 빌드에는 적용하지 않고 새 빌드 검증만 계획한다.

### M9. 출처 메모·차단 URL·실행 이력과 R3

**파일:** admin operations page, source/run API, admin_sources/admin_job_runs/admin_source_runs 추가 함수, `worker/ops.py`, `worker/test_ops.py`; 후속 `.github/workflows/daily-batch.yml` 계측 연결 제안.

**인터페이스:** 코드의 source_id 카탈로그+관리 메타데이터, 기존 worker_state.blocked_urls의 원자적 추가/제거, `(workflow_run_id, run_attempt, source_id, stage)` 실행 관측을 제공한다.

- [ ] 두 URL 동시 추가 시 둘 다 보존, 이미 저장된 뉴스 자동 삭제 없음, 운영 계측 없음은 ‘연동 필요’, 선택 단계 실패는 partial, 필수 주 수집 실패는 failed, 모든 대상 성공만 succeeded를 먼저 테스트한다.
- [ ] 출처 내부 메모·권리 검토·확인일·문의 링크만 편집한다. 새 수집 URL 추가나 앱 출처 라벨 변경을 포함하지 않는다.
- [ ] workflow/run_attempt별 실제 시작/종료·단계/출처 결과를 저장한다. skipped를 성공률 분모에서 제외하고 원시 LLM 출력·비밀키를 오류 기록에 넣지 않는다. 계측 실패가 기존 수집을 중단하지 않게 하고 관측 누락을 성공으로 바꾸지 않는다.
- [ ] `python -m unittest worker.test_worker worker.test_ops`와 운영 UI/DB 테스트를 통과시키고 staging 실행 이력을 실제 수신한 뒤 operations_history를 활성화한다. 쓰기 보호와 계측의 배포 여부를 별도로 기록한다.

### M10. 전체 검수·배포 패키지·인수인계

**파일:** 신규 `docs/admin/{RELEASE_CHECKLIST,ROLLBACK,OPERATIONS}.md`, 단계별 PROGRESS, 관리자 전용 CI workflow 제안. 실제 운영 배포는 별도 승인 후 실행한다.

**입력:** R0~R3 검증 결과와 활성 capability 목록. **출력:** 구체적인 적용 파일/SQL/환경·배포 순서, 변경 요약, 복구 경로, 알려진 제한.

- [ ] 브라우저 → 관리자 인증 → 서버 → DB → 기존 공개 RPC → Flutter 표시까지 end-to-end로 검증한다. 각 capability가 true가 된 근거와 아직 false인 사유를 기록한다.
- [ ] `npm --prefix admin ci`, `lint`, `typecheck`, `test`, `test:integration`, `test:e2e`, `build`와 Flutter analyze/test, 변경한 Python 단위 테스트, 로컬 DB 권한/경합 테스트를 실행한다. 명령별 환경·종료 코드·실제 결과를 남긴다.
- [ ] 세 해상도·200% 확대·키보드·포커스·명암 대비·긴 한영 문장·에러/0건/미연동·중복 클릭·응답 유실 재시도를 확인한다. 공개 fixture/로그/스크린샷 권리 및 비밀값 노출도 점검한다.
- [ ] 운영 적용 순서는 additive DB 기반 → capability false 상태의 호환 워커 보호 → 관리자 서버/읽기 → 실제 검증 → 대상 쓰기 활성화 → 새 앱 공지 연결이다. 구 워커와 새 워커가 섞여 보호를 우회하지 않게 한다.
- [ ] 장애 복구는 해당 쓰기 capability를 먼저 끄고 편집본·초안·이력을 보존한다. 사람이 편집한 데이터가 존재하는 상태에서 보호 없는 구 워커로 단순 롤백하지 않는다. 호환 워커 복귀 또는 관련 쓰기 잡 정지를 선택하고, DB drop으로 되돌리지 않는다.
- [ ] 검토 가능한 배포 패키지를 사용자에게 제시한 뒤 승인된 환경에만 적용한다. Vercel 프로젝트/도메인 생성, 운영 DB 적용, App Store Connect 업로드는 실제 수행 시 각각 기록한다.

## 5. 의존성과 실행 순서

현재 순서: M0 → M1 → M2 → M3(R0 읽기 연결) → M4(용어 저장 기반) → M5(용어 수정본 보호) → M6(R1 용어 검수) → M10(해당 범위 검증·배포 패키지). M7/R2는 현재 제외, M8과 M9의 쓰기 기능은 보류한다.

가장 먼저 검토할 제품 결과는 **가상 데이터가 명시된 용어 워크벤치 R0**다. 가장 먼저 실사용 저장을 제공할 결과는 **보호가 완성된 적용 위치 검수 R1**이다. 개발 편의를 위해 보호 미완성 쓰기 기능을 먼저 출고하지 않는다. R2/R3는 R1을 지연시키지 않도록 후순위로 유지한다.

쓰기 capability는 서버가 준비 상태를 계산해 반환하고 DB도 필요한 전제조건을 검사한다. 브라우저 플래그나 임의 환경값 하나로 보호되지 않은 저장을 우회할 수 없어야 한다. M5 보호 통합이 완료돼도 대상 환경에 배포되지 않았다면 해당 환경은 false다.

## 6. 기록 양식과 다음 착수 조건

각 단계가 끝날 때 `docs/admin/PROGRESS.md`에 다음을 남긴다.

```text
날짜 / 단계 / 기준 커밋 / 작업 상태:
목적과 최종 동작:
변경 파일·추가 migration·대상 환경:
실제 데이터 연결 여부 / 가상 데이터 여부:
실행한 검증 명령·환경·결과:
활성/비활성 capability와 이유:
시안·명세와 달라진 점 및 근거:
미해결 문제 / 다음 작업 / 배포·복구 이력:
```

계획에서 채택할 제안은 `admin/` 독립 앱, 서버 전용 관리자 쓰기, 기본 관리자 1인 Auth UUID 확인, 수동 초안 저장 우선, 위 순서다. 이는 이번 계획의 기본안이며 사용자 요구를 이미 승인된 세부 구현으로 확대 해석하지 않는다.

2026-10-28 사용자가 계획을 승인해 M0~M3에 착수했다. 실제 진행·검증 범위는 [PROGRESS.md](admin/PROGRESS.md)에 기록한다. 후속 M4는 기존 DB·워커 변경 패키지를 검토한 뒤 진행한다. 지금 필요한 검토는 범위·우선순위·기술 기본안이며 실제 운영 자격 증명을 문서에 적을 필요는 없다. 관리자 UUID, staging/production 프로젝트, Vercel 소유 프로젝트·도메인은 실제 연결 단계 전에 확인한다. 운영 DB/워커/앱 변경 패키지와 배포는 각각 구체화한 결과를 검토한 뒤 진행한다.

## 7. 계획 작성 검증과 참고

이 작업에서는 저장소 코드·기존 명세를 읽고 계획 및 참조 사본만 작성했다. 웹 프로젝트 생성·패키지 설치·제품 테스트·DB 조회/변경·워커 실행·서버 배포는 수행하지 않았다. 참조 사본의 화면은 모두 가상 데이터다.

공식 문서는 2026-10-28에 확인했다. Next.js 설치 문서의 App Router 요구사항과 Supabase SSR/인증·캐시 지침을 M0/M1의 버전·인증 확인 출발점으로 삼는다. Supabase 변경 내역은 구현 착수 시 다시 확인한다. 이 문서 자체가 특정 환경의 SDK 호환·DB 적용을 검증한 증거는 아니다.

- [Next.js 설치와 시스템 요구사항](https://nextjs.org/docs/app/getting-started/installation)
- [Supabase 서버 클라이언트와 SSR](https://supabase.com/docs/guides/auth/server-side/creating-a-client?queryGroups=framework&framework=nextjs)
- [Supabase 변경 내역](https://supabase.com/changelog)
- 기존 코드 근거: `worker/db.py:save_paper_ai`, `worker/glossary.py:plan_links`, `worker/official_news.py:save_db`, `lib/features/reader/reader_screen.dart:firstHighlights`, `lib/features/settings/notices.dart:loadNotices`, `.github/workflows/daily-batch.yml`.
