# X 감시 명단 (초안, 2026-11-06)

X API 쓴 만큼 내기(게시물 1개 읽기 약 $0.005)로 **계정 새 글만** 받는다는 전제.
`since_id`로 새 글만 받고, 자동 충전은 끄고 선불 크레딧으로 상한을 둔다.
핸들은 2026년 중반 기준 기억으로 적은 것이라 x.com에서 하나씩 확인 필요.

수집기: `worker/x_posts.py`, 명단(켜고 끄기): `worker/x_accounts.py`, 테이블: `x_posts`
(`supabase/migrations/20261106180000_x_posts.sql`), 예약: `.github/workflows/x-posts.yml`(30분마다).
지금 켠 계정: 1순위 13곳(@ChatGPTapp은 X가 못 찾아 끔) + 3순위 @testingcatalog·@btibor91·@simonw(2026-11-10). 일주일 쌓인 양을 보고 더 켤지 정한다.

앱에서 쓰는 곳(2026-11-10, 읽기 함수 `list_x_posts` = 최근 3일)
- 탐색 › 소식 › 커뮤니티: 「Hacker News | X」 두 쪽(2026-11-13, 「전체」 뺌, 옆으로 밀어 넘김). X는 최신순(기본)·좋아요순. 발표 소식을 단 X 글은 뺀다.
- 탐색 › 소식 › 발표: 같은 주소를 단 X 글이 있으면 행 아래 「X 좋아요 N · @핸들」(누르면 X 글).
- 홈 맨 위 「혜택·한도 소식」: 최근 48시간 perk 글, 좋아요 순 2개. 없으면 칸이 없다.
- X 표시 규정: 원문·작성자 이름·@핸들·시각·원문 링크를 늘 같이. 번역(text_ko)은 원문 위 + 「AI 번역」 표시. X에서 지운 글은 반응 다시 받기 때 DB에서도 지운다.
- 반응 수: 30분마다 받는 새 글은 좋아요가 거의 0이라, 올라온 지 4~30시간 된 글을 한 번 다시 받는다(글마다 읽기 1번, 하루 상한에 포함).
- 번역: 30분 수집 실행이 끝나면 최근 3일 글 중 번역 없는 것만 바로 옮긴다(2026-11-10). 공식 소식 배치도 같은 일을 해 빠진 것을 다시 채운다.

시작 순서
1. developer.x.com 가입 → 카드 등록 → 크레딧 최소 금액 구매(첫 결제 보너스 $20), **자동 충전 끔**
2. 앱의 Bearer Token을 레포 루트 `.env`에 `X_BEARER_TOKEN=…`로, GitHub 저장소 Secrets에도 `X_BEARER_TOKEN`으로
3. Supabase에 마이그레이션 적용
4. 로컬 확인(Python 3.10 이상): `python3.12 -m worker.x_posts --no-db` → 받은 글·혜택 낱말·추정 비용이 나온다

## 1순위 — 한도·리셋·혜택을 직접 발표

| 핸들 | 누구 | 왜 |
|---|---|---|
| @OpenAI | OpenAI 공식 | 큰 발표 |
| @OpenAIDevs | OpenAI 개발자 | API·Codex 변경, 크레딧 |
| @ChatGPTapp | ChatGPT 공식 | 무료 개방, 기능 출시 |
| @sama | Sam Altman (OpenAI CEO) | 한도 2배·리셋을 직접 올림 |
| @thsottiaux | Tibo (Codex 책임자) | Codex 사용량 리셋 공지가 잦음 |
| @embirico | Alexander Embiricos (Codex 제품) | Codex 혜택·변경 |
| @AnthropicAI | Anthropic 공식 | 큰 발표 |
| @claudeai | Claude 공식 | 한도 변경, 프로모션 |
| @bcherny | Boris Cherny (Claude Code) | Claude Code 한도·변경 |
| @_catwu | Cat Wu (Claude Code PM) | Claude Code 공지 |
| @GeminiApp | Gemini 앱 공식 | 무료 개방, 한도 |
| @GoogleAIStudio | Google AI Studio | 무료 할당량 변경 |
| @OfficialLoganK | Logan Kilpatrick (Google AI Studio·Gemini API) | 무료 혜택을 가장 먼저 흘림 |

## 2순위 — 있으면 좋음

| 핸들 | 누구 | 비고 |
|---|---|---|
| @GoogleDeepMind | DeepMind 공식 | 모델 출시 |
| @xai | xAI 공식 | Grok 무료 개방 |
| @cursor_ai | Cursor 공식 | 요금제·한도 변경 잦음 |
| @GitHubCopilot | GitHub Copilot 공식 | 무료 등급 변경 |
| @perplexity_ai | Perplexity 공식 | 무료 Pro 프로모션 잦음 |
| @deepseek_ai | DeepSeek 공식 | 가격 인하·할인 시간대 |
| @Alibaba_Qwen | Qwen 공식 | 무료 API 할당량 |

## 3순위 후보 — AI 트렌드·소식 정리 계정 (검토 중)

글이 많은 계정이 섞여 있어 비용 확인 후 고른다. "글 양"은 대략적인 인상.

| 핸들 | 누구 | 성격 | 글 양 |
|---|---|---|---|
| @testingcatalog | TestingCatalog News | 출시 전 기능·한도 변경을 먼저 포착 | 많음 |
| @btibor91 | Tibor Blaho | 앱 코드에서 미공개 기능·요금제 발견 | 많음 |
| @rowancheung | Rowan Cheung (The Rundown AI) | 하루 AI 소식 정리 | 보통 |
| @_akhaliq | AK (Hugging Face) | 화제 논문·데모 | 많음 |
| @AndrewCurran_ | Andrew Curran | 업계 소식 빠른 정리 | 많음 |
| @kimmonismus | Chubby | 루머·소식 빠름, 잡음도 있음 | 매우 많음 |
| @emollick | Ethan Mollick (와튼 교수) | 실사용 관점 해설 | 보통 |
| @karpathy | Andrej Karpathy | 화제성 높은 글 | 적음 |
| @simonw | Simon Willison | 새 모델·도구 실사용 정리 | 많음 |
| @swyx | swyx (Latent Space) | 업계 흐름 정리 | 많음 |
| @lmarena_ai | LMArena | 모델 순위 변동 | 보통 |
| @ArtificialAnlys | Artificial Analysis | 모델 성능·가격 비교 | 보통 |

## 일부러 뺀 계정

- @elonmusk — 하루 수십~수백 개, 혼자 예산을 다 먹음. xAI 소식은 @xai로 충분.
- @AravSrinivas — 글이 많고 잡담 비율 높음.
- @demishassabis, @gdb — 좋은 소식이지만 혜택·한도 공지는 드묾.
