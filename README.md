# ROOTGIST

Hugging Face Daily Papers에서 매일 상위 10편을 골라, 초록만 근거로 한 한국어 요약·핵심 내용·문장별 번역·용어 해설을 보여 주는 읽기 앱(Flutter, iOS·Android). MVP 개발 중.

- 구현 출발점: [`docs/HANDOFF.md`](docs/HANDOFF.md)
- 화면 시안: [`docs/design/ui_v2.1/`](docs/design/ui_v2.1/)
- 개발용 데이터: [`fixtures/`](fixtures/). 모든 텍스트는 가상이며 실제 논문과 관계없다.

## 이 레포에 넣지 않는 것

- 실제 논문 초록·번역·LLM 생성 결과(권리 검토 전)
- API 키, Supabase service key, `.env`

## 상태

M5(Supabase 연동·응답 캐시) 완료. 다음은 M6 QA(실기기). 진행 단계는 `docs/HANDOFF.md` 11장.
앱은 기본으로 fixture를 쓰고, `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`(공개 키)를 주면 Supabase 읽기 함수를 쓴다. 공개 키도 레포에 넣지 않는다(권리 검토 전 실데이터).
배치는 `.github/workflows/daily-batch.yml`이 매일 KST 05:00에 돌린다(Repository secrets: `NVIDIA_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`). DB 스키마는 `supabase/migrations/`를 main에 push하면 적용된다.
배치 워커(`worker/`, Python): `pip install -r worker/requirements.txt` 후 레포 루트에서 `python -m worker.run --limit 1`. 결과는 `worker/out/`(git 제외, 실제 초록·번역 포함이라 공유 금지).
디버그 빌드의 설정 화면 맨 아래 「개발용 · fixture 상태」로 로딩·오류·오프라인·지연·없음 상태를 띄울 수 있다.
