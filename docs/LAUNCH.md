# 출시 체크리스트

2026-11-12 처음 정리. TestFlight 외부 베타 → App Store 정식 출시 두 단계로 간다.
근거 문서: [RIGHTS.md](RIGHTS.md) 7장, [ANALYTICS.md](ANALYTICS.md) 「다음 빌드 배포 전 체크리스트」, [PROPOSALS.md](PROPOSALS.md).
상태는 「완료 · 남음 · 결정 필요」로 적고, 확인한 날짜와 방법을 함께 남긴다.

## 1. 지금 빌드

| 항목 | 상태 |
|---|---|
| TestFlight 빌드 13(1.0.0, 커밋 b6d33a2: 가운데 공지 팝업·글자 크기 확대 포함) | 아카이브 완료(2026-11-12). 업로드는 사용자가 Xcode Organizer에서 |
| 공지·설정 안내 문구 점검(공지사항, AI 생성 안내, 데이터 출처, 사용 방법, 이용 안내) | 고침(2026-11-12). 빌드 13에는 없고 다음 빌드부터 들어간다 |

## 2. 외부 베타 전 (지인 범위를 넘기기 전)

| 항목 | 상태 | 메모 |
|---|---|---|
| AI 제공처를 DeepSeek 공식 API로 | 완료 | 코드 전환 2026-10-27. 운영 `paper_ai.model_id`가 170건 모두 `deepseek-flash`(2026-11-12 확인) |
| NVIDIA로 만든 옛 결과 다시 만들기 | 논문 완료, 용어 확인 불가 | 논문 해설은 위처럼 모두 DeepSeek. 공식 소식은 캐시 제공처가 다르면 워커가 자동으로 다시 만든다. 용어(`term_senses`)는 만든 모델 기록이 없어 확인할 수 없다. 972개 중 278개만 AI 1차 검토 완료 |
| `app_config.show_ai_reviewed_terms` | 결정함: `true` 유지 | 2026-11-12 사용자 결정. 외부 베타에서도 AI 대응어를 그대로 보여 준다(마이그레이션 주석의 「외부 공개 전 false」를 따르지 않음) |
| PostHog 실제 수신 확인 | 남음 | Live events 도착, 수집 끄기 후 미전송, 재시작 후 유지, 본문·이메일 미포함(ANALYTICS.md) |
| 개인정보 처리방침 확정 | 남음 | 처리 지역·처리자·보관/삭제 기간·국외 이전 안내를 실제 PostHog 프로젝트 기준으로 맞추고 App Store 개인정보 라벨과 일치시킨다 |
| 서버 공지(앱 업데이트 없이 공지·팝업) | 완료 | 2026-11-12. Supabase Table Editor의 `notices`에 한 줄 추가 |

## 3. 정식 출시 전

| 항목 | 상태 | 메모 |
|---|---|---|
| Hugging Face에 Daily Papers 목록 이용 문의 | 남음 | legal@huggingface.co, RIGHTS.md 3장 |
| 블로그 요약 방식 변호사 확인 | 남음 | 광고·유료화 전에 꼭. RIGHTS.md 4장 |
| X 게시물 표시·번역 방식 확인 | 남음 | X 개발자 약관·표시 규정(작성자·원문 함께, 「X에서 보기」). 정식 출시 때 X API 요금제도 다시 본다 |
| NVIDIA·Meta·xAI 브랜드 가이드 확인 | 남음 | 출처 배지 색(RIGHTS.md 4장) |
| App Store 자료 | 남음 | 스크린샷(6.9"·6.5"), 앱 설명·키워드, 개인정보 라벨, 연령 등급, 지원 URL(`https://bapsange.github.io/ROOTGIST/`), 미리보기 영상(design-export/promo 녹화 활용 가능) |
| 실기기 QA | 남음 | 작은 화면(iPhone mini)·다크 모드·글자 크기 「아주 크게」 한 바퀴(IOS_QA.md) |
| 용어 사람 검토 | 남음 | HANDOFF 「외부 공개 전」 |

## 4. 출시 후

- 출처 약관·robots.txt를 반년마다 다시 본다(RIGHTS.md 7장).
- 수집 실패는 GitHub Actions에서 본다. 2026-11-12 05:30 x-posts `startup_failure`는 GitHub 장애(같은 시각 Actions 장애 공지)였고 다음 실행이 since_id로 채웠다.
