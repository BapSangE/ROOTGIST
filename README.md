# ROOTGIST

Hugging Face Daily Papers에서 매일 상위 10편을 골라, 초록만 근거로 한 한국어 요약·핵심 내용·문장별 번역·용어 해설을 보여 주는 읽기 앱(Flutter, iOS·Android). MVP 개발 중.

- 구현 출발점: [`docs/HANDOFF.md`](docs/HANDOFF.md)
- 화면 시안: [`docs/design/ui_v2.1/`](docs/design/ui_v2.1/)
- 개발용 데이터: [`fixtures/`](fixtures/). 모든 텍스트는 가상이며 실제 논문과 관계없다.

## 이 레포에 넣지 않는 것

- 실제 논문 초록·번역·LLM 생성 결과(권리 검토 전)
- API 키, Supabase service key, `.env`

## 상태

M3(예외 상태·로컬 저장) 완료. 다음은 M4 백엔드(Supabase·배치 워커). 진행 단계는 `docs/HANDOFF.md` 11장.
디버그 빌드의 설정 화면 맨 아래 「개발용 · fixture 상태」로 로딩·오류·오프라인·지연·없음 상태를 띄울 수 있다.
