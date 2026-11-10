"""X 감시 명단(docs/X_WATCHLIST.md와 같은 내용). enabled=False는 명단에만 두고 받지 않는다.

비용은 받은 게시물 수에 비례한다(1개 약 $0.005). 글이 많은 계정을 켤 때는 X_DAILY_READ_CAP도 같이 본다.
1순위 13곳 + 3순위 3곳(@testingcatalog·@btibor91·@simonw)을 켠다(사용자 결정 2026-11-10: X 글을 혜택 알림만이
아니라 탐색 HOT 칸·발표 반응에도 쓴다). 일주일 쌓인 양을 보고 3순위를 더 켤지 정한다. 하루 상한(200개 ≈ $1)은 그대로.
핸들은 2026년 중반 기준이라 첫 실행 때 X가 찾지 못한 핸들은 로그에 나온다.
"""

# (핸들, 설명, 순위, 켜짐)
ACCOUNTS: list[tuple[str, str, int, bool]] = [
    # 1순위 — 한도·리셋·혜택을 직접 발표
    ("OpenAI", "OpenAI 공식", 1, True),
    ("OpenAIDevs", "OpenAI 개발자", 1, True),
    ("ChatGPTapp", "ChatGPT 공식 — 2026-11-10 X가 찾지 못함, 바뀐 핸들 확인 전까지 끔", 1, False),
    ("sama", "Sam Altman (OpenAI CEO)", 1, True),
    ("thsottiaux", "Tibo (Codex 책임자)", 1, True),
    ("embirico", "Alexander Embiricos (Codex 제품)", 1, True),
    ("AnthropicAI", "Anthropic 공식", 1, True),
    ("claudeai", "Claude 공식", 1, True),
    ("bcherny", "Boris Cherny (Claude Code)", 1, True),
    ("_catwu", "Cat Wu (Claude Code PM)", 1, True),
    ("GeminiApp", "Gemini 앱 공식", 1, True),
    ("GoogleAIStudio", "Google AI Studio", 1, True),
    ("OfficialLoganK", "Logan Kilpatrick (Google AI Studio·Gemini API)", 1, True),
    # 2순위 — 회사 공식(있으면 좋음)
    ("GoogleDeepMind", "Google DeepMind 공식", 2, False),
    ("xai", "xAI 공식", 2, False),
    ("cursor_ai", "Cursor 공식", 2, False),
    ("GitHubCopilot", "GitHub Copilot 공식", 2, False),
    ("perplexity_ai", "Perplexity 공식", 2, False),
    ("deepseek_ai", "DeepSeek 공식", 2, False),
    ("Alibaba_Qwen", "Qwen 공식", 2, False),
    # 3순위 — AI 소식 정리(글이 많은 계정이 섞여 있다)
    ("testingcatalog", "TestingCatalog News (출시 전 기능 포착)", 3, True),
    ("btibor91", "Tibor Blaho (미공개 기능·요금제 발견)", 3, True),
    ("rowancheung", "Rowan Cheung (The Rundown AI)", 3, False),
    ("_akhaliq", "AK (Hugging Face, 화제 논문)", 3, False),
    ("AndrewCurran_", "Andrew Curran (업계 소식)", 3, False),
    ("kimmonismus", "Chubby (루머·소식, 매우 많음)", 3, False),
    ("emollick", "Ethan Mollick (실사용 해설)", 3, False),
    ("karpathy", "Andrej Karpathy", 3, False),
    ("simonw", "Simon Willison (모델·도구 실사용)", 3, True),
    ("swyx", "swyx (Latent Space)", 3, False),
    ("lmarena_ai", "LMArena (모델 순위)", 3, False),
    ("ArtificialAnlys", "Artificial Analysis (성능·가격 비교)", 3, False),
]
