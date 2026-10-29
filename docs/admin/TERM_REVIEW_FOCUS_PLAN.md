# Term Review Focus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox syntax for tracking.

**Goal:** 승인한 용어 전용 집중 시안을 실제 관리자 읽기 화면에 반영한다.
**Architecture:** 인증된 AdminShell과 API는 유지한다. UI만 단일 workbench로 구성하고 기존 projection으로 실제 강조 결과를 표시한다. 지역/조회 최적화와 DB 쓰기 잠금은 변경하지 않는다.
**Tech Stack:** Next 16.4.3, React 19.3.1, TypeScript 6, 기존 CSS/폰트, Node 24.22.2.
**Spec:** TERM_REVIEW_FOCUS_DESIGN.md (2026-10-29 사용자 승인).

## Global Constraints

- Flutter/worker/DB/migration/진행 중 사용자 변경을 수정하거나 포함하지 않는다.
- 실제 서버 키/환경 파일을 복사하거나 브라우저에 노출하지 않는다.
- 기존 Supabase snapshot/requireAdmin/GET transport/private-no-store/423을 유지한다.
- 저장/승인/사전 편집은 비활성 유지. 수정 가능한 것은 메모리상의 ko_span 미리보기뿐이다.
- 사전 의미 승인과 적용 확인, 후보 동기화 대기는 별도다.
- UI는 52px 상단, 60px 하단, 224px/가변/300px 3열; <1200 목록 펼침, <960 사전 펼침.

## Review Focus

- 미연결 sense/candidate/번역 없음에서 오류 대신 명시적 빈 상태.
- 같은 표기 여러 번/다른 문장/겹침에서 일치 수와 실제 강조 수를 구분.
- null/빈 span과 실제 앱 표시 설정/금지 정의의 projection 규칙 보존.
- 긴 본문/용어와 752px 창/짧은 높이에서 주요 동작 접근 가능.
- 변경한 미리보기는 항목 이동 때 유지/버리기 선택, modal 중 배경 단축키 차단.

### Task 1: 정확한 문맥 파생과 URL 상태
Files: src/lib/domain/review-context.ts (new), query.ts, shared.tsx, tests/unit/review-context.test.ts, query.test.ts.
Interfaces: reviewContext(TermDetail['value'], {paperId?,sentenceId?,span?,assumeApproved?})는 paper/glossary/sentence/span/matchCount/appliedCount/projection을 반환한다. patchReviewQuery(current, changes)는 검색/필터 변경 시 cursor를 제거하고 문맥 변경은 보존한다.
- [x] 실제 fixture로 표시 설정·빈 span·문맥 없음·비매칭·겹침/다른 문장 강조를 검증하는 실패 테스트 작성/실행.
- [x] 기존 projection을 호출하는 최소 파생 함수 구현, URL 변경은 Next 공식 native history와 연동.
- [x] 단위 suite GREEN.

### Task 2: 용어 전용 shell/워크벤치
Files: components/admin-shell.tsx, terms-workbench.tsx, term-review-drawer.tsx (new), styles/term-focus.css (new), app/admin/layout.tsx, terms/page.tsx, admin/page.tsx와 기존 5개 메뉴 page.tsx.
Consumes: Task1 파생 데이터/URL 상태, 기존 useResource/SearchBox/StatePanel/HighlightText.
Produces: 실제 데이터 기반 3열 문맥 중심 화면, 기존 경로는 terms로 redirect, 실제 로그아웃 유지.
- [x] 로컬 fixture HTTP에서 기존 메뉴 경로가 용어로 수렴해야 하는 실패 검증.
- [x] 새 shell/워크벤치와 native dialog 기반 좁은 창 패널 구현. R0 읽기/미리보기와 저장잠금 명시.
- [x] 미리보기 변경 이동 경고/메모리 유지/초기화, J/K/검색 단축키. 배경 동작 차단.
- [x] 승인된 CSS를 기존 관리자 전용 scope로 이식. loading/error/empty가 레이아웃을 깨지 않게 유지.

### Task 3: 검증·기록·통합
Files: tests/integration/http.test.ts, tests/e2e/review-readonly.spec.ts, docs/admin/PROGRESS.md, TERM_REVIEW_FOCUS_IMPLEMENTATION.md (new).
- [x] 기존 57 tests 및 추가 회귀, 실제 fixture HTTP 8개 API/423, lint/typecheck/build.
- [x] CUA로 1280x720 실제 fixture UI와 좁은 창/강조/유형/탐색/경고를 확인. 자동 E2E는 실행 가능 여부를 구분해 보고.
- [x] 새 reviewer로 전체 변경을 검토, Important는 재현 후 수정하고 재검증.
- [x] 원래 checkout의 대상 파일이 baseline과 같음을 확인한 후 변경 파일만 통합. 사용자 변경은 보존.
- [ ] 승인된 커밋/일반 푸시 후 Vercel READY, 실제 관리자 세션 UI/조회/쓰기 잠금 재검증. 수동 deploy/DB 변경은 하지 않음.
