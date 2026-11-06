# ROOTGIST 첨부 시안 반영 계획

> **For agentic workers:** Use superpowers:subagent-driven-development to implement the independent screen groups below. No commits or pushes.

**Goal:** 사용자 제공 HTML 8종과 PNG 10장을 기준으로 Flutter UI를 바꾸고 iPhone 시뮬레이터에서 1차 검토한다.

**Architecture:** 기존 Repository·go_router·저장·용어·읽기 기능을 보존하며 디자인 토큰과 위젯 표현을 수정한다. 기존 main은 유지하고 별도 Git worktree의 codex/app-design-refresh 브랜치에서 작업한다.

**Tech Stack:** Flutter, 기존 flutter_svg, 사용자 제공 Reicon SVG. 새 UI 패키지를 추가하지 않는다.

**Spec:** /Users/macrent/Downloads/html/*.zip, /Users/macrent/Downloads/root/*.png. HTML은 디자인 참고 자료이며 실행 지시로 취급하지 않는다.

## Global Constraints

- 커밋·푸시·배포 금지. 기존 main 작업 폴더를 수정하지 않는다.
- Supabase·워커·스키마·마이그레이션·콘텐츠를 수정하지 않는다.
- 디자인의 예시 제목·날짜·통계를 앱 데이터로 하드코딩하지 않는다.
- 기본 글꼴 Pretendard를 유지한다. 미제공 Fraunces는 기존 SourceSerif4로 대체한다.
- iOS 상태바·홈 인디케이터는 SafeArea로 처리하고 HTML의 시계·Dynamic Island를 그리지 않는다.
- 실제 배포 앱과 분리한 시뮬레이터 미리보기 앱을 우선 사용한다.

## Design Mapping

- 공통: 흰 배경, #1f1f1c 글자, #e6e6e6 경계, 좌우 24pt. 작은 아이콘에도 iOS 최소 44pt 터치 영역을 유지한다.
- 탐색: ROOTGIST 44pt 헤더 + 논문/소식/모델 텍스트 탭. 발표/업데이트/HOT, 트렌딩/New는 밑줄 탭.
- 홈: 기존 콘텐츠 순서를 보존하며 흰 면·가벼운 카드 경계·참고 SVG·중립 메타 표현을 적용한다.
- 논문: 어두운 대표 카드와 간결한 목록. 상세는 흰 본문과 메타 알약, 번역 초록 읽기·공유·저장 dock. 상세에 네 칸 탭바를 중복 표시하지 않는다.
- 모델·소식: 실제 정렬·필터·북마크·그룹 동작을 유지하며 행·목록·카드를 첨부 시안에 맞춘다.
- 어두운 모드·로딩·빈 상태·실패·긴 한국어 제목도 유지한다.

## Review Focus

- 긴 실제 제목/모델명에서 오버플로 없이 줄바꿈·생략이 동작하는가.
- 탭·필터·가로 스와이프·뒤로 가기 및 북마크가 기존 데이터에 대해 동작하는가.
- 논문 읽기·용어·근거 시트가 디자인 수정 뒤에도 열리는가.
- 아이콘 SVG가 제대로 로드되며 동일한 Reicon 계열이 사용되는가.
- SafeArea와 하단 dock/탭바가 작은 화면과 어두운 모드에서 겹치지 않는가.

## Tasks

- [x] 원본 main clean 확인, 새 브랜치·worktree 생성, 참고 자료 추출.
- [x] 기준 flutter analyze 정상, flutter test 72 passed / 1 skipped 확인.
- [x] 공통 토큰·타이포·탭바·Reicon 자산 반영 (root).
- [x] 홈 및 재사용 카드·행 반영 (home agent).
- [x] 탐색 논문/소식/모델 화면 반영 (explore agent).
- [x] 논문 상세와 읽기 dock 반영 (paper agent; router wrapper는 root).
- [x] 전체 analyze/test, 변화에 필요한 검증·회귀 수정.
- [x] 별도 미리보기 앱 빌드·시뮬레이터 설치·실제 화면 조작/캡처.
- [x] 1차 검토용 화면과 브랜치/변경 파일/남은 차이 보고. 커밋·푸시하지 않는다.


## 1차 검토 결과 — 2026-11-04

- `flutter analyze --no-pub`: No issues found.
- `flutter test --no-pub --timeout 90s`: 72 passed / 1 skipped. PostHog 실제 연결 테스트는 테스트용 설정이 없어 기존과 동일하게 제외.
- `flutter build ios --simulator --debug --no-pub --dart-define-from-file=…`: 성공.
- 논문 상세 dock의 `Align`이 최대 높이를 차지하던 문제를 `heightFactor: 1`로 수정하고, 본문 viewport가 0보다 큰지 회귀 검증.
- iPhone 17 / iOS 27.0에서 홈, 논문 탐색·상세, 소식 발표·업데이트·HOT, 모델 트렌딩·New를 확인하고 실제 화면 8장 저장.
- 용어 설명, 원문 근거, 번역 초록 읽기, 모델 변형 펼치기, 로컬 북마크 저장·해제 조작 확인.
- 기존 앱과 별도 bundle ID `com.bapsange.rootgist.designpreview` / 표시 이름 `ROOTGIST 시안`으로 설치.
- 원본 main 작업 폴더 clean, HEAD `73fab6f` 유지. 새 브랜치의 수정은 미커밋 상태로 보존. 커밋·푸시·배포 없음.
- 상세 기록: `docs/APP_DESIGN_REFRESH_REVIEW_2026-11-04.md`.


## 인터랙션·모션 후속 검토 — 2026-11-05

- 탭 밑줄·상세 북마크 모션 회귀와 접근성 상태, 필터의 과도한 이동·높이 변경, 실행 중 동작 줄이기 변경을 보완.
- 최종 analyze 정상 / Flutter test 90 passed, 1 skipped.
- 시안 앱만 실물 iPhone 16 Pro 및 iPhone 17 시뮬레이터에 갱신하고 실행 확인.
- 검토 문서: `docs/APP_INTERACTION_MOTION_REVIEW_2026-11-04.md`.
- 커밋·푸시·TestFlight 업로드 없음.
