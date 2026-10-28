# 관리자 웹 착수 기준 — M0

2026-10-28 · 기준 HEAD `b8e5c6a` · 사용자 계획 승인 후 M0~M3 실행.

현재 체크아웃의 기존 문서 변경을 보존하고 새 admin/ 안에서 구현한다. 별도 worktree 생성·브랜치 변경·커밋·푸시는 하지 않았다. 기존 앱·워커·DB 소스와 배포 IPA/아카이브 정보 파일의 SHA-256 기준을 작업 공간에 기록했다.

## 기준 검증

- Flutter 3.47.8 / Dart 3.13.7: analyze 이상 없음; test 55 passed, SDK 설정이 필요한 통합 테스트 1 skipped.
- Python 3.12.15 + workspace venv/jsonschema 4.26.0: `python -m unittest worker.test_worker` 37 passed.
- 초기 워커 실행은 jsonschema 미설치로 실패했고 별도 작업 공간 venv에 기존 requirements를 설치해 해결했다. Flutter 테스트 캐시 쓰기 권한을 허용받은 뒤 기준 테스트를 재실행했다.

## 관리자 도구 조합

Node 26.12.1 / npm 11.20.0, Next 16.4.3, React/React DOM 19.3.1, TypeScript 6.0.3, @supabase/ssr 0.12.7, @supabase/supabase-js 2.118.0, Vitest 5.0.5, Playwright 1.64.1. 설치 시 npm registry의 버전/engines와 공식 Next/Supabase 문서를 확인했다. package.json은 정확한 버전, package-lock.json을 함께 유지한다. 시스템 Node/npm/Python을 업그레이드하지 않았다.

## 환경과 적용 경계

1. local fixture: 명시적 ADMIN_DATA_MODE=fixture, development/test에서만 사용. Vercel 또는 production이면 차단. localhost 바인딩만 제공한다.
2. local Supabase: 미구성. DB 통합이 필요한 M4 이후 별도 준비.
3. staging: 미구성·미접속. 실제 읽기 연결도 관리자 UUID/환경 확인 후 검증한다.
4. production: 접근·데이터 수정·DDL 적용·배포 없음. 서버 비밀값은 env example에 넣지 않는다.

현재 확인한 workflow는 daily-batch의 schedule/workflow_dispatch와 batch/official-news 잡이다. README의 main push migration 자동 적용 설명을 입증하는 workflow는 찾지 못했다. 외부 배포 연결은 조회하지 않았으므로 운영 적용 절차는 미확인이다. 현재 예약은 UTC 19:17/KST 04:17.

공개 RPC 계약은 마이그레이션과 기존 SupabaseRepository 회귀 테스트를 기준으로 보존한다. 라이브 응답을 새로 조회한 결과로 주장하지 않는다.

## UI 지침

승인된 Ink & Paper V2 명세를 우선한다. UI/UX Pro Max의 design-system 검색 2회는 랜딩/유리 효과를 추천해 이 제품에 맞지 않아 미채택했다. 별도 UX 검색의 focus-not-obscured 지침은 유효하여 적용한다. Next auth stack 검색은 2회 모두 0건이어서 공식 Supabase SSR 문서를 사용한다. 검색 결과를 사용했다고 과장하거나 기존 브랜드 팔레트를 교체하지 않는다.

공식 참고: https://nextjs.org/docs/app/getting-started/installation · https://supabase.com/docs/guides/auth/server-side/creating-a-client?framework=nextjs&queryGroups=framework · https://supabase.com/changelog
