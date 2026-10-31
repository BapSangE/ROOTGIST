# ROOTGIST 사용 분석 — PostHog Flutter

2026-10-28 · 다음 빌드용 연동 · SDK `posthog_flutter: 5.57.1`


## 인수인계 요약

2026-10-28 문서 보완 시 확인한 저장소 HEAD는 `b8e5c6a` (`testflight연동_posthog세팅`)다. 아래 검증 결과는 이전 연동 작업 당시의 기록이며, 이번 문서 정리에서는 앱 코드·설정·배포를 변경하거나 테스트를 재실행하지 않았다.

| 구분 | 현재 상태 |
|---|---|
| 소스 연동 | 공식 Flutter SDK 설치, 화면/행동 이벤트, 수집 제어, 활성 독서 시간 연결 완료 |
| 수집 기본값 | OFF. 설정에서 사용자가 직접 켜고 유효한 빌드 설정이 있어야 전송 |
| 검증 | 정적 분석과 Flutter 회귀 테스트 완료. 상세 결과는 아래 검증 기록 참조 |
| 실제 PostHog 연결 | 연동 작업 당시 실제 토큰/Host가 제공되지 않아 운영 수신 확인 미실시 |
| 네이티브 실행 | iOS simulator 빌드가 환경 문제로 실패하여 실기기 검증 필요 |
| 개인정보 고지 | `privacy.md`는 다음 빌드용 개정 초안. 법정 항목(보유 기간 1년·파기·국외 이전·권리 행사·안전성 조치·보호책임자·아동)을 채웠다(2026-10-30). 남은 것: PostHog 프로젝트를 EU 리전으로 만들고 국가·리전을 5장에 확정, 프로젝트 데이터 보관을 1년으로 설정, 시행일 |
| 기존 심사 빌드 | 연동 작업에서 기존 IPA 교체·아카이브 재생성·업로드·배포·심사 취소하지 않음 |

다음 담당자는 **설정과 새 빌드 → 이벤트 명세 → 대시보드 설정 → 배포 전 체크리스트** 순서로 확인한다. 수집에 동의한 설치만 측정하므로 분석 결과를 전체 TestFlight 사용자의 유지율로 해석하지 않는다.

## 현재 구조와 변경 범위

분석한 기준 HEAD: `39774dfbbbd1aea22dd29d27d9576c75b292cfaa`. Flutter 3.47.8 / Dart 3.13.7, go_router 18.1.1. 앱은 Supabase 읽기 RPC와 로컬 캐시를 사용한다. Python 배치·DB·마이그레이션·Flutter 콘텐츠 파싱은 바꾸지 않았다. 북마크·설정은 기존 SharedPreferences 구조를 유지한다.

SDK 호출은 `lib/analytics/`에 한정한다. 앱 루트가 routerDelegate.state.uri의 실제 표시 경로와 탐색 하위 탭을 관찰한다. IndexedStack의 숨은 탭과 단순 rebuild로 화면 이벤트가 중복되지 않는다. 자동 PosthogObserver를 함께 넣지 않는다. 쿼리·원시 경로·날짜·URL 대신 허용된 화면 이름을 사용한다.

초기 설정은 수집 거부다. 설정 → 「분석 데이터 삭제 요청」은 수집을 끄고 `Posthog().reset()`으로 설치 식별자를 새로 바꾼 뒤, 이전 식별자를 적은 삭제 요청 메일을 연다(SDK를 시작한 적 없으면 보낸 기록이 없다고 알린다). 설정 → 사용 분석 → 사용 분석 데이터 수집에서 켜야 SDK가 초기화된다. 키는 `settings.analyticsConsent.v1`. SDK 시작도 optOut=true이며 수동 optIn 이후에만 전송한다. 토큰·Host 누락/개인 API 키(phx_)/잘못된 환경이면 수집하지 않는다. 초기화 중 발생한 동작은 버리고, 준비 완료 시 현재 화면만 기록한다. 초기화나 전송의 오류는 앱 호출자에게 전파하지 않는다. 초기화가 지연되어도 실행·탐색은 대기하지 않는다.


## 연동 변경 파일과 책임

| 파일 | 역할 |
|---|---|
| `pubspec.yaml`, `pubspec.lock` | 공식 SDK 5.57.1 고정 설치 |
| `lib/analytics/analytics.dart` | dart-define 검증, 동의 상태, 허용 이벤트 속성, 화면 분류, 활성 독서 시간 |
| `lib/analytics/posthog_sink.dart` | 공식 SDK 어댑터, 수동 초기화, 리플레이·자동 수집 제한 |
| `lib/main.dart` | 실제 표시 경로, 탐색 하위 탭, 앱 lifecycle, 30초 체크포인트 관찰 |
| `lib/data/storage.dart` | 기존 SharedPreferences에 `settings.analyticsConsent.v1` 저장 |
| `lib/data/repository.dart` | 중앙 북마크 추가·해제·되돌리기 이벤트 |
| `lib/features/home/home_screen.dart` | 논문 주제 칩 선택 이벤트 |
| `lib/features/reader/reader_screen.dart` | 리더 로딩 성공·종료 시점 연결 |
| `lib/features/reader/term_sheet.dart` | 용어 바텀 시트 열기 이벤트 |
| `lib/features/settings/settings_screen.dart` | 수집 제어 스위치와 간단한 고지 |
| `ios/Runner/Info.plist` | SDK 자동 초기화와 푸시 prewarm 차단 |
| `android/app/src/main/AndroidManifest.xml` | SDK 자동 초기화 차단 |
| `macos/Flutter/GeneratedPluginRegistrant.swift` | 의존성 설치가 생성한 플러그인 등록. macOS 분석은 활성화하지 않음 |
| `test/analytics_test.dart` | 설정·동의·실패 격리·속성 제한·화면·활성 시간 단위 테스트 |
| `test/analytics_integration_test.dart` | 공식 SDK Dart 호출부터 mock 네이티브 경계까지 실제 push/pop 흐름 검증 |
| `test/widget_test.dart` | 수집 스위치와 로컬 저장 회귀 테스트 |
| `docs/privacy.md` | 다음 빌드용 개인정보 처리방침 개정 초안 |
| `docs/ANALYTICS.md` | 이 인수인계 문서와 이벤트·빌드·운영 명세 |

기존 콘텐츠·북마크 저장 형식, Flutter 디자인 토큰, `worker/`, `supabase/`, `lib/data/supabase_repository.dart`는 연동 작업에서 변경하지 않았다. 작업 전부터 있던 Xcode 프로젝트 사용자 설정 변경, 디자인 미리보기, QA 스프레드시트도 보존했다.

## 설정과 새 빌드

프로젝트 설정의 **Project token**(`phc_…`)을 사용한다. Personal API key(`phx_…`)를 앱에 넣지 않는다. Host는 해당 프로젝트의 ingestion host다. US: `https://us.i.posthog.com`, EU: `https://eu.i.posthog.com`. 셀프호스팅은 HTTPS origin만 허용한다. URL 사용자 정보·쿼리·프래그먼트·경로는 허용하지 않는다.

```sh
flutter pub get
flutter run \
  --dart-define-from-file=.env.app.json \
  --dart-define=POSTHOG_PROJECT_TOKEN=phc_YOUR_PROJECT_TOKEN \
  --dart-define=POSTHOG_HOST=https://eu.i.posthog.com \
  --dart-define=POSTHOG_ENVIRONMENT=development
```

기존 `.env.app.json`의 Supabase 설정을 계속 전달한다. 이 파일을 분석 설정으로 덮어쓰지 않는다. 토큰·Host는 저장소에 작성하지 않았다. 환경값은 development(기본), testflight, production만 허용한다. release 여부로 TestFlight를 추정하지 않는다. 배포 채널을 빌드 명령에서 명시한다. 개발·베타의 프로젝트를 분리하면 데이터 격리가 더 쉽다.

자동 빌드 대비(2026-10-31): GitHub Secrets에 `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `POSTHOG_PROJECT_TOKEN`, `POSTHOG_HOST`가 등록돼 있다. 앱 빌드 워크플로는 아직 없다. 만들 때 위 값을 `--dart-define`으로 넘기고, iOS는 배포 인증서(.p12)·프로비저닝 프로파일·App Store Connect API 키를, Android는 업로드 키스토어를 Secrets에 추가해야 한다.

아래는 **향후 새 빌드의 명령 예시**이며 이번 작업에서는 실행하거나 업로드하지 않았다. `NEXT_BUILD_NUMBER`는 App Store Connect에서 기존 모든 빌드보다 큰 번호로 직접 정한다.

```sh
NEXT_BUILD_NUMBER=새로운_숫자
flutter build ipa --release --build-number="$NEXT_BUILD_NUMBER" \
  --dart-define-from-file=.env.app.json \
  --dart-define=POSTHOG_PROJECT_TOKEN=phc_YOUR_PROJECT_TOKEN \
  --dart-define=POSTHOG_HOST=https://eu.i.posthog.com \
  --dart-define=POSTHOG_ENVIRONMENT=testflight
```

기존 IPA·archive는 먼저 별도 보관한 다음 새 archive를 만든다. 이 명령은 나중에 동일한 build/ios 경로를 사용할 수 있다. 현재 심사 빌드 교체·심사 취소·배포는 하지 않는다. pubspec의 버전·빌드 번호도 그대로다. iOS는 기존 Swift Package Manager 연결을 사용한다(최소 대상 iOS 15, SDK 요구 13 이상 충족). 자동 초기화는 iOS Info.plist와 AndroidManifest에서 명시적으로 끈다. Web 분석은 대상 밖이며 JS snippet은 추가하지 않는다.

## 이벤트 명세 v1

모든 이벤트 공통: `environment`, `schema_version=1`, `$geoip_disable=true`. SDK의 임의 distinct_id로 같은 설치의 재방문을 연결하고 identify/alias/person profile은 쓰지 않는다. SDK가 OS·기기 종류·앱 버전 등 기본 기술 속성을 추가할 수 있다. 앱 콘텐츠 텍스트나 사용자 입력은 보내지 않는다.

| 이벤트 | 발생 시점 | 사용자 정의 속성 |
|---|---|---|
| `$screen` | go_router 표시 화면 변경, 초기화 완료 현재 화면 | `$screen_name` 고정 값 |
| `app_foregrounded` | 수집 준비 완료 시 활성 상태, 이후 resumed 전환 | 공통 속성만 |
| `paper_opened` | 논문 상세 경로 진입/뒤로 돌아옴 | `content_id` |
| `official_news_opened` | 공식 소식 상세 경로 진입 | `content_id` |
| `model_opened` | 모델 상세 경로 진입 | `content_id` |
| `reader_opened` | 초록 리더 경로 진입 | `content_id` |
| `term_opened` | 실제 용어 바텀 시트 열기 | `highlighted`, `has_translation` |
| `bookmark_added` | 로컬 북마크 저장/되돌리기 | `content_kind`, `content_id`, 되돌리기일 때 `restored=true` |
| `bookmark_removed` | 단일 북마크 해제 | `content_kind`, `content_id` |
| `category_selected` | 홈/지난 논문 주제 칩 선택 | `scope=paper_topic`, `category=all/llm/agent/multimodal/optimization` |
| `category_selected` | 탐색의 실제 표시 분류 변경/진입 | `scope=explore`, `category=papers/news/updates/models` |
| `reader_active_time` | 리더 화면 이탈, 활성 해제, 30초 체크포인트 | `content_id`, `active_ms`, `reason=navigation/background/checkpoint` |

화면 이름: home, explore_papers, explore_news, explore_updates, explore_models, digest_archive, library, settings, settings_reading, settings_source, settings_privacy, settings_notices, paper_detail, paper_reader, news_detail, model_detail. 개발 갤러리·알 수 없는 경로는 제외한다. 동일 경로의 문장 쿼리 변경은 재방문으로 세지 않는다.

`*_opened`는 상세를 **연 동작**이다. 서버 데이터 로딩 성공이나 끝까지 읽음을 뜻하지 않는다. content_id는 120자 이내의 영숫자와 `._/-`만 허용하며, URL fallback 등은 생략한다. 모델에 용어 ID가 없으므로 용어 텍스트·정의·문장·sense_id를 수집하지 않는다. 출처 칩 필터, 전체 북마크 비우기는 이번 명세의 별도 이벤트에 포함하지 않는다.

독서 시간은 Stopwatch의 단조 증가 시간으로 계산한다. 해당 리더 데이터 로딩 성공 + 표시 경로가 리더 + 앱 resumed + 수집 허용/SDK 준비일 때만 시작한다. inactive/hidden/paused/detached, 다른 화면, 수집 거부 동안은 계산하지 않는다. 수집 거부 시 미전송 진행 구간을 버린다. 30초 단위로 중복 없는 시간 조각을 보내므로 합계가 독서 시간이다. 종료 직전 체크포인트 이후 구간·오프라인 전송 실패는 유실될 수 있다. 실제 시선/집중을 측정하는 값은 아니다.

## PostHog 대시보드 설정

1. 프로젝트를 만들고 리전과 Project token/Host를 확인한다. Session Replay는 프로젝트에서도 끈다. 이 앱은 sessionReplay=false이며 PostHogWidget도 사용하지 않는다.
2. 개발 기기에서 수집을 켠 다음 Activity의 Live events에서 environment=development를 필터링한다. `$screen`, paper_opened, term_opened, bookmark_added/removed, category_selected가 도착하고 텍스트·이메일·URL이 없는지 이벤트 속성을 확인한다. 수집을 끈 뒤 추가 이벤트가 없는지도 확인한다.
3. TestFlight 대시보드의 **모든 인사이트**에 `environment = testflight` 필터를 넣는다. development를 내부 사용자로 제외하는 필터도 운영 프로젝트에서 사용할 수 있다. SDK 기본 앱 버전·빌드 속성은 실제 수신된 키를 확인한 뒤 새 빌드별 비교에 쓴다.
4. 재방문: Retention → 시작 `app_foregrounded`, 반환 `app_foregrounded`, Unique users, 첫 발생 기준, Day 단위, On(해당 날짜) 선택. D1/D7과 코호트 크기를 함께 본다. 주간 사용 패턴은 Week 단위로 별도 저장한다.
5. 콘텐츠 사용: Trends → paper_opened/official_news_opened/reader_opened/term_opened/bookmark_added를 Unique users와 Total events로 각각 본다. category_selected는 scope별로 나누고 category로 분해한다.
6. 읽기: reader_active_time의 active_ms를 합계 집계하여 1000으로 나눠 초 단위로 표시한다. 평균은 시간 조각 평균이 아니라 설치/콘텐츠별 합계를 기준으로 한다. 중단·백그라운드 구간은 들어 있지 않다.
7. 탐색→읽기 전환: `$screen`에서 `$screen_name=home` → paper_opened → reader_opened → bookmark_added 순서의 Funnel. 선택 단계는 탐색 질문에 맞춰 조정한다.

수집에 동의한 설치만 포함한다. 재설치·앱 저장소 초기화 시 새 식별자가 생길 수 있고 기기 간 동일 사용자를 합치지 않는다. D1/D7은 같은 설치가 돌아온 비율이며 전체 TestFlight 설치자의 유지율로 해석하지 않는다. personProfiles=never여도 이벤트 distinct_id 기준 분석을 사용한다.

## 개인정보 고지와 다음 배포 전 확정 사항

`docs/privacy.md`는 앱 번들과 GitHub Pages가 공유하므로 다음 빌드용 개정 초안으로 표시했다. **공개 웹 방침을 게시하거나 App Store Connect 정보를 수정하지 않았다.** 기존의 “분석 도구 없음/기기 식별자 미수집” 문구는 새 빌드에 맞지 않아 수정했다. 선택 수집 목적·항목·임의 설치 식별자·SDK 기술 정보·PostHog 처리·수집 철회와 이미 수신된 데이터의 차이를 설명한다.

운영자가 확정할 값: 실제 리전과 처리자 법인/연락처, 데이터 보관·삭제 기간과 실제 프로젝트 설정, 필요한 국외 이전 안내, 시행일. 현재 실제 프로젝트/자격 증명이 없어 해당 값을 임의로 만들지 않았다. 새 빌드 배포 전에 초안 표시를 제거하고 앱·공개 방침을 함께 맞춘다.

Apple App Privacy는 SDK가 수집하는 항목까지 실제 설정에 맞춰 답한다. 검토 항목은 Product Interaction(Usage Data), 임의 설치 식별자(Identifiers), 기기/OS 등 실제 수신 기술 속성, 목적 Analytics다. 로그인/이메일과 연결하지 않고 광고 추적에 쓰지 않는 현재 동작을 기준으로 연결·추적 여부를 검토한다. 선택 동의만으로 자동 공개 면제라고 가정하지 않는다. SDK PrivacyInfo.xcprivacy는 패키지에 포함되지만 App Store Connect 고지를 대신하지 않는다.


## 연동 작업의 검증 기록

2026-10-28 실행 결과이며, 아래 명령 절은 재검증 방법이다.

| 검증 | 결과 |
|---|---|
| 변경 전 `flutter analyze` / `flutter test` | 이상 없음 / 기존 46개 통과 |
| 변경 후 `flutter analyze` | No issues found |
| 설정 없는 `flutter test` | 55개 통과, 설정이 필요한 SDK 경계 통합 테스트 1개 skip |
| 테스트용 dart-define을 전달한 전체 테스트 | 56개 모두 통과. 네이티브 전송은 mock하여 외부 이벤트 전송 없음 |
| `git diff --check` | 통과 |
| iOS Info.plist / Android manifest | plist 및 XML 문법 검사 통과 |
| 기존 배포 산출물 보존 | 기존 IPA 및 archive Info.plist의 SHA-256이 작업 전 기록과 일치 |
| iOS simulator debug 빌드 | SwiftPM 캐시 쓰기 제한 및 CoreSimulator 서비스/런타임 문제로 실패. 네이티브 실행 검증으로 간주하지 않음 |

독립 코드 리뷰에서 `go_router`의 `currentConfiguration.uri`가 imperative `push()`에서 하위 상세 경로를 반영하지 않는 문제를 발견했다. 실제 **논문 push → 리더 push → pop → 논문 상세 → pop → 홈** 테스트로 이벤트 누락을 재현하고, `routerDelegate.state.uri`를 사용하도록 수정해 통과시켰다. 향후 라우터 수정 시 `go()`만으로 테스트하지 말고 이 흐름을 유지한다.

## 다음 빌드 배포 전 체크리스트

이 목록은 실제 실행 확인용이다. 토큰이 없던 연동 작업 당시 완료하지 않은 항목을 임의로 완료 표시하지 않는다.

- [ ] 실제 PostHog 프로젝트의 리전·Project token·ingestion Host를 확인한다. 저장소에 실제 값을 기록하지 않는다.
- [ ] development/testflight 환경을 각각 명시하고, 기존 Supabase dart-define을 함께 전달한다.
- [ ] 설정에서 수집을 켠 뒤 Live events에 화면·상세·용어·북마크·카테고리 이벤트가 도착하는지 확인한다.
- [ ] 수신 속성에 본문·번역·이메일·제목·원문 URL이 없는지 확인한다. SDK 기본 기술 속성도 함께 점검한다.
- [ ] 수집을 끈 뒤 새 이벤트가 발생하지 않고, 앱 재시작 후 거부 상태가 유지되는지 확인한다.
- [ ] 실기기에서 리더 활성/비활성/복귀, 다른 화면 이동, 재시작을 검증한다. 백그라운드 시간이 독서 시간에 더해지지 않아야 한다.
- [ ] iOS 네이티브 빌드·실행을 완료한다. 당시 환경 제한으로 실패한 simulator 빌드와 별도로 확인한다.
- [ ] 실제 처리 지역·처리자·보관/삭제 기간·국외 이전 안내·시행일을 확정하고, `privacy.md` 초안을 확정한다. 공개 웹 방침 및 App Store Connect 고지도 맞춘다.
- [ ] 프로젝트에서도 세션 리플레이를 비활성화하고, 모든 TestFlight 인사이트에 `environment=testflight` 필터를 적용한다.
- [ ] 기존 IPA·archive를 별도 보관하고 기존보다 큰 새 빌드 번호로 빌드한다. 기존 심사 빌드 변경과 새 빌드 배포를 혼동하지 않는다.
- [ ] 새 빌드에서 실제 수신을 확인한 뒤 D1/D7 코호트 집계와 지표 해석을 확인한다.

## 검증 명령

```sh
flutter analyze
flutter test
# 실제 공식 SDK의 platform channel 경계까지 검증하되, 테스트는 네이티브 전송을 mock하므로 외부 전송하지 않는다.
flutter test \
  --dart-define=POSTHOG_PROJECT_TOKEN=phc_test \
  --dart-define=POSTHOG_HOST=https://eu.i.posthog.com \
  --dart-define=POSTHOG_ENVIRONMENT=testflight
```

설정 없는 일반 테스트에서는 SDK 경계 통합 테스트 하나만 skip한다. 위 dart-define 테스트에서는 모든 테스트를 실행한다. 실제 토큰을 사용한 수신 확인, 실기기 비활성/복귀/재시작과 D1 집계는 운영 프로젝트를 설정한 뒤 추가 검증한다.

## 공식 근거

- Flutter 설치/수동 초기화/화면/동의: https://posthog.com/docs/libraries/flutter
- 패키지/SDK 소스: https://pub.dev/packages/posthog_flutter · https://github.com/PostHog/posthog-flutter
- Retention: https://posthog.com/docs/product-analytics/retention
- PostHog privacy: https://posthog.com/docs/privacy
- Apple App Privacy: https://developer.apple.com/app-store/app-privacy-details/
