# 권리 검토 (A8) — 1차

작성 2026-10-27. HANDOFF 2장 A8(「HF 약관·초록 재게시·번역 권리 미결 → 권리 확인 전 외부 공개 보류」)의 1차 검토다.

> 이 문서는 공개된 약관·라이선스·법 조문을 읽고 정리한 **실무 검토**이며 법률 자문이 아니다.
> 결론은 「지인 베타(TestFlight, 소수, 무료)는 아래 조건을 지키면 진행 가능」, 「App Store 정식 출시 전에는 7장의 확인을 끝낸다」이다.

## 1. 앱이 보여 주는 것

| 출처 | 원문 그대로 보이는 것 | ROOTGIST가 만든 것 | 원문 링크 |
|---|---|---|---|
| arXiv 논문(HF Daily Papers 경유) | 제목, 저자, 초록 전문(S03 원문 모드) | 제목 번역, 요약, 핵심 내용, 문장별 번역, 용어 해설 | HF·arXiv |
| HF Daily Papers | 그날 목록·순서(upvote 순) | 상위 10편 선택, 주제 분류 | HF |
| 연구소 블로그·개발자 공지 | **없음**(원문 문장을 화면에 옮기지 않는다) | 제목 번역, AI 요약 1~2문장, 핵심 내용 최대 3개 | 글마다, 근거 문단 위치까지 |
| 릴리스 노트(SDK·Claude Code·Claude API) | 버전 범위(v1.16.0~v2.3.0 등) | 핵심 변경 최대 3개 | 릴리스 페이지 |
| HF 트렌딩 모델 | 모델 이름, 만든 곳, 과제·크기·라이선스·좋아요·다운로드(메타데이터), 제작사 측정 점수 | 한 줄 설명(메타데이터 조립), 강점 최대 3개·한계 1문장(모델 카드 요약) | 모델 카드·연결 논문 |
| 용어 표기 | — | 일부 대응어(Google ML Glossary CC BY 4.0, HF Transformers 용어집 Apache 2.0 바탕) | — |

화면에 쓰지 않는 것: HF 썸네일·논문 그림·동영상(`papers.thumbnail_url`, `media_urls`는 저장만), 회사 로고.

## 2. 논문 (arXiv 초록·제목·저자) — **문제없음**

- arXiv 라이선스 안내: 「A Creative Commons CC0 1.0 Universal Public Domain Dedication will apply to all metadata」. 제목·저자·초록은 메타데이터다. 원문 전문 게시, 번역, 요약 모두 자유롭다.
- **본문·그림은 다르다.** 논문마다 저자가 고른 라이선스(CC BY, CC BY-NC-ND, arXiv 비독점 라이선스 등)를 따른다. 지금처럼 그림·본문을 화면에 쓰지 않는다.
- 조치: 데이터 출처 화면에 「제목과 초록은 arXiv가 CC0으로 공개한 정보」라고 밝힌다(반영함).

## 3. HF Daily Papers 목록·순서 — **위험 낮음, 정식 출시 전 문의 권장**

- HF 이용약관(2022-09-15 시행) 「Proprietary Rights」: HF가 만든 자료(웹사이트, 디자인, 코드, 그래픽, 인터페이스, 상표, 로고)는 서면 허락 없이 「alter, reproduce, republish, license」할 수 없다.
- ROOTGIST가 쓰는 것은 그날 어떤 논문이 올라왔는지와 upvote 순서(사실 정보)뿐이다. HF의 화면·디자인·글은 옮기지 않는다. 공개 API(`/api/daily_papers`)를 하루 몇 번만 부르고, robots.txt는 전체 허용이다.
- 이미 하고 있는 것: 데이터 출처 화면의 「이 순서는 Hugging Face 이용자들의 반응이고, ROOTGIST가 논문을 평가한 결과가 아니에요」, 논문마다 HF 페이지 링크.
- 조치: 썸네일·그림은 계속 쓰지 않는다. 정식 출시 전에 legal@huggingface.co로 「Daily Papers 목록을 출처·링크와 함께 한국어 요약 앱에 쓴다」고 알리고 답을 받아 둔다(7장).

## 4. 연구소 블로그·개발자 공지 — **위험 낮음~중간, 지금 방식 유지가 조건**

출처: OpenAI 뉴스(RSS), Anthropic(사이트맵), Google DeepMind 블로그(RSS), Google Research 블로그(RSS), Hugging Face 블로그(RSS), Meta 엔지니어링 블로그(RSS), NVIDIA 블로그·개발자 블로그(RSS·Atom), OpenAI 개발자 커뮤니티 공지 게시판(RSS).

추가 출처 검토(2026-10-29):

- **Hugging Face 블로그의 회사 계정 글**(`/blog/<계정>/<글>`): 그 회사가 HF에 직접 올린 발표라 다른 회사 블로그와 같은 기준이다. 누구나 쓸 수 있는 자리라 알려진 회사 계정만 받는다(`HF_BLOG_ORGS`). 칩은 그 회사, 분류 자리에 「Hugging Face 블로그」.
- **Meta**: ai.meta.com은 RSS가 없고 robots.txt 머리에 「서면 허락 없이 자동 수집 금지」가 적혀 있어 받지 않는다. engineering.fb.com은 RSS를 공개하고 robots.txt가 전체 허용이라 「AI Research」 분류 글만 받는다. Llama GitHub 릴리스는 2025년 이후 없어 넣지 않았다.
- **NVIDIA**: blogs.nvidia.com·developer.nvidia.com 모두 RSS 공개, robots.txt가 피드를 막지 않는다. 홍보·행사 글이 많아 분류로 거른다(회사 블로그는 오픈소스·연구만, 개발자 블로그는 생성형 AI·연구만, GTC·게임 글 제외).
- **xAI**: x.ai는 자동 접근을 막아(403) 뉴스를 받지 않는다(우회하지 않는다). docs.x.ai는 robots.txt 전체 허용이지만 화면이 스크립트로 그려져 지금 수집기로 읽을 수 없다. GitHub `xai-org/xai-sdk-python` 릴리스(Apache-2.0)만 받는다.

- 글은 각 회사의 저작물이다. 별도 재사용 라이선스가 없어 저작권법의 일반 원칙(제28조 인용, 제35조의5 공정이용)으로 판단한다.
- 공정이용 네 가지 고려 사항(목적·성격, 저작물의 종류, 이용 비중, 시장 영향)에 지금 방식을 대 보면 이렇다.
  - **양과 비중:** 원문 문장을 화면에 옮기지 않는다. AI가 쓴 짧은 요약(1~2문장)과 핵심 내용 3개뿐이고, 근거 구절(3~10단어)은 원문의 그 자리로 여는 링크 주소(`#:~:text=`)에만 쓴다.
  - **시장 대체:** 글 전체를 옮기지 않고 「자세한 내용은 원문에서」로 원문 방문을 늘리는 쪽이다. 한국어 안내 성격이다.
  - **저작물의 성격:** 제품·연구 발표 같은 사실 정보가 중심이라 창작성이 높은 글보다 이용의 폭이 넓은 편이다.
- 약관:
  - OpenAI 이용약관의 자동 추출 금지(「use any automated or programmatic method to extract data or output from the Services」)는 ChatGPT·API 같은 서비스를 향한 조항이다. 공개 RSS 피드를 읽는 것에 그대로 해당한다고 보기는 어렵다. 그래도 OpenAI 글 페이지는 자동 접근이 막혀 있어(403) 읽지 않고, 피드 소개문만 근거로 쓴다. 이 방식을 유지한다.
  - robots.txt(2026-10-27 확인): anthropic.com·openai.com·deepmind.google·research.google·huggingface.co 전체 허용, community.openai.com은 /admin/ 등만 금지(검색엔진 일부 차단).
  - robots.txt(2026-10-29 확인): engineering.fb.com 전체 허용, blogs.nvidia.com·developer.nvidia.com 피드 허용. ai.meta.com은 자동 수집 금지 안내, x.ai는 자동 접근 차단.
- 조건(지키지 않으면 위험이 커진다):
  1. 원문 문장·문단을 화면에 옮기지 않는다. 번역도 전문이 아니라 요약만.
  2. 출처 이름과 원문 링크를 항목마다 붙인다.
  3. 회사 로고·이미지를 쓰지 않는다. 출처 배지는 Pretendard 머리글자 + 회사 대표 색 한 가지만 쓴다(2026-10-29, 아래 「출처 배지 색」).
  4. 「AI가 원문을 보고 정리했다」는 안내를 유지한다(목록·상세 안내 문구, 데이터 출처 화면).
  5. 권리자 요청이 오면 바로 내린다(6장).

### 출처 배지 색 (2026-10-29)

공식 소식 출처 배지(OA·An·GD·GR·HF·CC·CA, 2026-10-29부터 NVIDIA·Meta·xAI)와 모델을 발표한 회사 칩에 회사 대표 색을 한 가지씩 쓴다(`RgBrand`, `lib/design/tokens.dart`). 법률 판단이 아니라 공개 자료 기준의 정리다.

- 색 하나만으로는 보통 상표 보호를 받기 어렵다. 한국은 단일 색채에 사용에 의한 식별력을 요구한다(국내 1호 하리보 골드, 2016). 미국은 secondary meaning과 비기능성이 있어야 한다(Qualitex, 1995).
- Anthropic 상표 가이드: 로고의 색·글꼴·비율 변경 금지, 후원·보증·제휴 암시 금지. 팔레트 규정은 없다. 로고를 쓰지 않으니 색 변경 조항과는 무관하다.
- Google 브랜드 가이드: 시각적 아이덴티티(「distinctive color combinations」 포함)를 흉내 내지 말 것. → 4색 조합 대신 파랑 하나만.
- Hugging Face 브랜드 페이지: 로고·브랜드 색을 프로젝트에 쓰라고 공개한다.
- OpenAI 브랜드 페이지는 자동 접근이 막혀(403) 원문을 읽지 못했다. 요약 자료상 로고를 자기 브랜딩에 섞지 말 것. 브랜드가 흑백이라 검정을 쓴다.
- NVIDIA·Meta·xAI(2026-10-29): NVIDIA 초록(#76B900)은 흰 글자 대비가 2.4:1이라 검정 글자를 쓴다. Meta는 파랑(#0866FF, 흰 글자 4.8:1)으로 Google 파랑과 비슷해 이름 글자로 구분한다. xAI는 흑백 브랜드라 검정. 세 회사 모두 로고는 쓰지 않는다. 각 회사 브랜드 가이드를 자동으로 읽지는 않았으니 정식 출시 전에 확인한다.

지키는 조건: 회사당 한 색(정확한 브랜드 HEX가 아니라 흰 글자 대비 4.5:1 이상의 앱용 색), Pretendard 머리글자, 로고 모양·글꼴을 따라 하지 않음, 출처 이름을 글자로 함께 표시, 데이터 출처 화면에 「각 소유자의 상표, 제휴·후원 없음」 안내. 권리자가 요청하면 그 출처는 회색 배지로 되돌린다.

## 5. 릴리스 노트·모델 카드 — **위험 낮음**

- `anthropic-sdk-python`, `openai-python`, `xai-sdk-python`: Apache-2.0. 요약·번역에 제한이 없다(라이선스 고지는 코드를 다시 배포할 때의 의무).
- `anthropics/claude-code` 저장소와 Claude API 릴리스 노트(docs.claude.com): 별도 라이선스 표기가 없다. 4장의 블로그와 같은 기준(요약 3줄 + 링크)으로 다룬다. docs.claude.com robots.txt는 /api/만 금지한다.
- HF 모델 카드: 업로더의 글이고, 모델 라이선스와 카드 글의 권리는 별개다. ROOTGIST는 강점 최대 3개·한계 1문장 요약과 제작사가 밝힌 점수를 보여 준다. 점수는 사실(숫자)이라 보호 대상이 아니다. 「제작사가 밝힌 내용이고 독립 검증이 아니다」는 안내가 이미 있다. 메타데이터(과제·크기·라이선스·좋아요·다운로드)는 HF 공개 API의 사실 정보다.
- 용어집 출처 표시 의무(Google ML Glossary CC BY 4.0, HF Transformers 용어집 Apache 2.0): 데이터 출처 화면에 이미 적혀 있다.

## 6. 삭제 요청 처리

1. 문의 메일(help.rootgist@gmail.com)로 요청을 받는다. 데이터 출처 화면에 창구를 밝혔다.
2. 그 주소를 차단 목록에 넣는다. 다음 배치부터 다시 모으지 않는다(`worker/official_news.py`).

   ```sql
   insert into public.worker_state (key, value) values ('blocked_urls', '{"urls": []}') on conflict (key) do nothing;
   update public.worker_state set value = jsonb_set(value, '{urls}', (value->'urls') || '"<원문 주소>"'), updated_at = now()
   where key = 'blocked_urls';
   ```
3. 이미 저장된 항목을 지운다. 앱은 다음 새로고침부터 보이지 않는다.

   ```sql
   delete from public.official_news where url = '<원문 주소>';
   delete from public.trending_models where url = '<원문 주소>';
   ```
4. 논문(arXiv)은 CC0이라 삭제 의무는 없다. 저자가 요청하면 `papers.withdrawn = true`로 내린다(읽기 함수가 제외한다).

## 7. 공개 단계별로 남은 일

| 단계 | 할 일 | 상태 |
|---|---|---|
| 지인 베타 전 | AI 제공처를 NVIDIA 무료 등급(개발·평가용)에서 DeepSeek 공식 API로 바꾼다. DeepSeek 이용약관은 출력의 권리를 이용자에게 두고, 입력을 서비스 개선에 쓸 수 있다고 적는다. 보내는 것은 공개 자료뿐이라 문제없다 | 코드 전환함(2026-10-27). GitHub secret `DEEPSEEK_API_KEY` 등록 필요 |
| 지인 베타 전 | NVIDIA로 만든 기존 결과를 DeepSeek로 다시 만든다. NVIDIA 시험 약관 4.2조가 생성 결과를 다른 사람에게 제공하는 것을 막는다. 공식 소식은 캐시의 제공처 표시가 달라 자동으로 다시 만든다. 논문 해설은 날짜마다 `python -m worker.run --date D --regenerate`, 용어 초안도 다시 | 남음 |
| 지인 베타 전 | `app_config.show_ai_reviewed_terms`를 정한다(사람 검토 전 AI 대응어 표시 여부. 마이그레이션 주석은 「지인 베타 포함 외부 공개 전 false」) | 남음 |
| 지인 베타 전 | 데이터 출처 화면에 공식 소식·모델 출처, AI 정리 안내, 삭제 요청 창구 | 반영함 |
| 정식 출시 전 | HF에 Daily Papers 목록 이용 문의(3장) | 남음 |
| 정식 출시 전 | 블로그 요약 방식(4장)을 변호사에게 한 번 확인. 특히 수익화(광고·유료)를 하면 공정이용 판단에서 불리해지므로 그 전에 | 남음 |
| 정식 출시 후 | 출처 약관·robots.txt를 반년마다 다시 확인. 출처를 새로 넣을 때는 이 문서의 표에 먼저 넣는다 | — |

## 참고

- arXiv 라이선스: https://info.arxiv.org/help/license/index.html
- Hugging Face 이용약관: https://huggingface.co/terms-of-service
- OpenAI 이용약관: https://openai.com/policies/terms-of-use
- DeepSeek Open Platform 이용약관: https://cdn.deepseek.com/policies/en-US/deepseek-open-platform-terms-of-service.html
- 저작권법 제28조·제35조의5: https://www.law.go.kr/법령/저작권법
