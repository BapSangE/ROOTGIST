# 앱 디자인 변경 1차 검토 — 2026-11-04

## 작업 상태

- 브랜치: `codex/app-design-refresh`
- 기준 커밋: `73fab6f`
- 작업 폴더: `/Users/macrent/Documents/Codex/2026-10-28/rootgist-admin-ui-ux-0-rootgist/work/rootgist-app-design-refresh`
- 원본 `/Users/macrent/code/ROOTGIST`의 main은 clean 상태로 보존.
- **커밋·푸시·배포하지 않음. 현재는 사용자 시뮬레이터 1차 검토 단계.**

## 참고 자료와 반영 범위

사용자가 제공한 `/Users/macrent/Downloads/html/`의 화면 8종과 `/Users/macrent/Downloads/root/`의 PNG 10장을 기준으로 작업했다. 첨부 파일은 디자인 자료로만 사용했다. UI/UX Pro Max의 Flutter 레이아웃·접근성 지침을 참고했다.

| 화면 | 반영 사항 |
| --- | --- |
| 공통 | 흰 배경, 무채색 텍스트·경계, ROOTGIST 워드마크, 제공 Reicon SVG, 하단 탭바 |
| 홈 | 기존 콘텐츠 섹션 유지, 카드 경계·모서리·메타·아이콘 정리 |
| 탐색 논문 | 논문/소식/모델 텍스트 탭, 텍스트 카테고리 필터, 어두운 대표 카드, 간결한 목록 |
| 소식 | 발표/업데이트/HOT 밑줄 탭, 출처 필터, 날짜 그룹, 평면 목록·업데이트 묶음 |
| 모델 | 트렌딩/New 밑줄 탭, 순위·지표 카드, 변형 펼치기 유지 |
| 논문 상세 | 흰 본문, 제목·영문 부제·메타 알약, 회색 용어 강조, 원문 근거, 읽기·공유·저장 dock |

제공되지 않은 Fraunces 폰트는 기존 SourceSerif4로 대체했다. 한국어는 기존 Pretendard를 유지했다. iOS 상태바·홈 인디케이터를 HTML처럼 중복 그리지 않고 SafeArea를 사용했다. 작은 아이콘도 최소 44pt 터치 영역을 유지하고, 하단 탭은 큰 글자에서 높이가 늘도록 처리했다. 앱의 기존 어두운 모드 토큰도 유지했다.

## 보존한 기능

- Repository, Supabase RPC, Python 워커, DB·마이그레이션 변경 없음.
- 실제 제목·날짜·출처·수치를 기존 데이터에서 읽음. 첨부 시안의 예시 콘텐츠를 하드코딩하지 않음.
- 카테고리·출처 필터, 날짜별 탐색, 소식 정렬·묶음, 모델 변형, go_router 화면 이동 유지.
- 북마크, 읽기 화면의 원문·번역·글자 크기, 용어 설명, 근거 문장 연결 유지.
- 공통 용어 위젯에 선택 가능한 배경색만 추가. 논문 상세는 회색 강조, 기존 Reader는 노란 강조 유지.
- 논문 상세에는 일반 4개 하단 탭바를 중복 표시하지 않고 읽기 dock만 표시.

## 변경 파일

- `lib/app_shell.dart`: 논문 상세의 기본 탭바 래퍼 제거.
- `lib/design/tokens.dart`, `typography.dart`: 색·타이포·공통 토큰.
- `lib/design/widgets/rg_bottom_tab_bar.dart`, `rg_card.dart`, `rg_pressable.dart`: 탭바·경계·Reicon 매핑.
- `lib/features/home/home_screen.dart`, `home_sections.dart`: 홈·공통 카드와 행.
- `lib/features/explore/explore_screen.dart`, `date_groups.dart`, `official_news.dart`, `trending_models.dart`: 탐색 화면.
- `lib/features/paper/paper_screen.dart`, `lib/features/common/term_text.dart`: 논문 상세·dock·강조색.
- `assets/icons/`: 제공 SVG 18개 추가. 새 UI 패키지나 폰트 의존성 없음.
- `test/widget_test.dart`: 변경된 화면 요소 선택자·레이아웃 기대 갱신. 배율·이동·저장·필터 검증 유지.

## 검증

| 항목 | 결과 |
| --- | --- |
| 변경 전 기준 테스트 | 72 passed / 1 skipped |
| 변경 후 `flutter analyze --no-pub` | No issues found |
| 변경 후 `flutter test --no-pub --timeout 90s` | 72 passed / 1 skipped |
| iOS 시뮬레이터 debug 빌드 | 성공 |
| `git diff --check` | 통과 |
| 시뮬레이터 주요 화면 | 홈·탐색 6종·논문 상세 표시 확인 |
| 실제 조작 | 용어 설명, 원문 근거, 번역 초록 읽기, 모델 변형, 로컬 북마크 저장·해제 확인 |

PostHog 실제 연결 테스트 1개는 테스트용 정의 값이 없어 기존과 동일하게 건너뛰었다. 디자인 미리보기에는 PostHog 토큰을 전달하지 않았다. Supabase는 기존 앱의 공개 읽기 설정으로 콘텐츠를 표시하며 서버 데이터는 변경하지 않았다. 북마크 검증은 미리보기 앱의 로컬 저장소에서 수행한 뒤 해제했다.

검증 중 논문 상세 dock의 Align이 화면 전체 높이를 차지하던 문제를 발견해 `heightFactor: 1`로 수정했고, 본문 높이가 0이 아닌지 회귀 검증을 남겼다.

## 시뮬레이터 미리보기

- 기기: iPhone 17 / iOS 27.0
- UDID: `41D38F9C-54D6-4BC8-9488-4B6CDBD60E84`
- 표시 이름: **ROOTGIST 시안**
- 미리보기 bundle ID: `com.bapsange.rootgist.designpreview`
- 원본 앱 `com.bapsange.rootgist`와 별도로 설치. 소스 프로젝트의 bundle ID는 변경하지 않음.

빌드 방법(프로젝트 폴더에서 실행):

```sh
/Users/macrent/development/flutter/bin/flutter build ios --simulator --debug --no-pub \
  --dart-define-from-file=/Users/macrent/code/ROOTGIST/.env.app.json
```

위 명령의 산출물은 원래 bundle ID를 사용하므로 바로 설치하면 기존 시뮬레이터 앱이 교체된다. 이번 미리보기는 생성된 `Runner.app`을 별도 outputs 폴더에 복사한 뒤 복사본의 Info.plist에만 위 bundle ID·표시 이름을 적용하고 ad-hoc 재서명하여 설치했다. 환경 설정 파일이나 키 값은 문서·Git에 복사하지 않았다.

산출물 기본 폴더:
`/Users/macrent/Documents/Codex/2026-10-28/rootgist-admin-ui-ux-0-rootgist/outputs/app-redesign-2026-11-04/`

- `simulator/ROOTGISTPreview.app`: 별도 설치용 빌드 복사본.
- `screenshots/01-home.png`
- `screenshots/02-explore-papers.png`
- `screenshots/03-paper-detail.png`
- `screenshots/04-news-announcements.png`
- `screenshots/05-news-updates.png`
- `screenshots/06-news-hot.png`
- `screenshots/07-models-trending.png`
- `screenshots/08-models-new.png`

8개 PNG는 가상 목업이 아닌 실제 시뮬레이터 캡처(1206×2622)다. 캡처의 콘텐츠는 검토 시점의 실제 공개 데이터라 시간이 지나면 달라질 수 있다.

## 다음 검토

사용자가 시뮬레이터에서 글자 크기·여백·탭·카드·아이콘을 확인한 뒤 피드백을 반영한다. 추가 승인 전 커밋·푸시·main 병합·TestFlight 업로드는 진행하지 않는다. 전체 화면·Android 기기·실물 iPhone의 최종 QA는 후속 단계다.


## 실물 iPhone 설치 — 2026-11-04

- 연결된 iPhone 16 Pro에 `ROOTGIST 시안` 설치 및 실행 완료.
- 앱 ID `com.bapsange.rootgist.designpreview`, 버전 1.0.0 (2).
- 기존 `com.bapsange.rootgist` 1.0.0 (7)은 별도 앱으로 그대로 설치되어 있음을 기기 목록에서 확인.
- 휴대폰에서 단독 실행할 수 있도록 Release/AOT 빌드에 Apple Development 서명을 적용.
- 원본 iOS 프로젝트를 수정하지 않고 `outputs/app-redesign-2026-11-04/device-preview/ios`의 복사본에서 시안 앱 ID·표시 이름만 변경하여 빌드.
- 실제 앱 서명 ID, 프로비저닝 프로필 허용 범위, 대상 기기 등록, codesign 검증 통과 후 설치 결과 확인. `devicectl`의 앱 실행 성공 확인.
- App Store Connect·TestFlight 업로드, 기존 배포 교체, 커밋·푸시 없음. 실물 기기의 화면·조작 세부 QA는 사용자 검토 후 진행.
