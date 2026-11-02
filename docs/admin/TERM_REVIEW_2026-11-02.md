# 일괄 승인 용어 검토 목록

작성: 2026-11-02 KST

## 배경

미검토 사전 의미 942개를 일괄 승인했다. 이 가운데 AI 1차 검토를 거치지 않은 717개는 대부분 Google ML 용어집을 기계 번역해 들어온 것이다. 그래서 한국어 이름이 틀린 항목이 섞여 있다. 예를 들어 temperature가 「기온」, weight가 「무게」로 들어가 있다.

다음 두 곳에는 717개를 쓰지 않도록 막았다. 둘 다 2026-11-02에 바꿨다.

- **소식 하이라이트·키워드 칩**: `list_terms`가 1차 검토를 마친 255개만 돌려준다.
- **해설 번역 선호 표기**: `worker.glossary.preferred_terms`도 같은 기준을 쓴다.

717개는 지금 논문 용어 시트에만 나온다. 논문에 이미 연결된 것은 14개다. 다만 새 논문에 그 영어 용어가 나오면 이 한국어 이름으로 연결된다. 그래서 **A의 이름 수정만 먼저 하면 된다.** B는 소식에서 이미 빠졌으니 손댈 필요가 없다. C는 소식에도 보이게 할 후보다.

## A. 한국어 이름이 틀린 항목 — 관리자 웹에서 대표 한국어명 수정

| 원어 | 지금 | 제안 |
|---|---|---|
| temperature | 기온 | 온도 |
| weight | 무게 | 가중치 |
| outliers | 연구 | 이상치 |
| state | 주 | 상태 |
| condition | 상태 | 조건(결정 트리) |
| distribution | 배포 | 분포 |
| neural network | 출력은 | 신경망 |
| ensemble | 자동화 | 앙상블 |
| representation | 벡터 표현이 | 표현 |
| reward | 리워드가 | 보상 |
| feature engineering | 특성 추출 단계를 포함합니다 | 특성 공학 |
| generative AI | 생성형 AI의 | 생성형 AI |
| feedback | 의견 보내기 | 피드백 |
| tower | 높이 | 타워 |
| Saver | 알뜰 | Saver |
| Fiddle | 바이올린 | Fiddle |
| noise | 소음 | 노이즈 |
| reflection | 사색 | 리플렉션 |
| broadcasting | 방송 | 브로드캐스팅 |
| confabulation | 혼동 | 작화(지어내기) |
| batch | 일괄 | 배치 |
| leaf | 잎 | 리프 노드 |
| return | 리턴 | 리턴(누적 보상) |
| step size | 보폭 | 스텝 크기 |
| step | 단계별 방법 | 스텝 |
| forget gate | 게이트 삭제 | 망각 게이트 |
| data parallelism | 데이터 동시 로드 | 데이터 병렬 처리 |
| dimensions | 측정기준 | 차원 |
| discriminative model | 분류 모델 | 판별 모델 |
| discriminator | 분류자 | 판별자 |
| federated learning | 제휴 학습 | 연합 학습 |
| agentic | 대리적/대리자적 | 에이전틱 |
| action space | action space(작업 공간) | 행동 공간 |
| constituency parsing | 선거구 파싱 | 구성 성분 파싱 |
| co-adaptation | 모방 적응 | 공적응 |
| predictive rate parity | 예측 요금 동등성 | 예측 비율 동등성 |
| proxy labels | 유추 라벨 | 대리 라벨 |
| exact match | 일치검색 | 정확 일치 |
| citation recall | 인용 회상 | 인용 재현율 |
| historical bias | 이전 편향 | 역사적 편향 |

다음은 표기 정리만 필요한 항목이다.

- attention의 「Attention,」, bucketing의 「버킷팅,」: 끝의 쉼표를 지운다.
- BERT, eCDF: 이름 안의 줄바꿈을 지운다.
- 「평가」(evals·evaluation), 「그라운딩」(grounding·groundedness), 「분류 모델」(classification·discriminative)은 이름이 겹친다.

## B. 흔한 낱말 — 소식에 넣지 않음(이미 빠짐, 할 일 없음)

모델, 평가, 작업, 작업 (op), 테스트, 학습, 응답, 예측, 비용, 기기, 환경, 구성, 목표, 관찰, 요약, 확장, 항목, 예시, 클래스, 그래프, 호스트, 인스턴스, 플러그인, 지연 시간, 인공지능, 머신러닝, 데이터 분석, 오프라인, online, performance, reason, target, validation, iteration, action, root

## C. 소식에도 보이게 할 만한 용어(후보)

일반 독자가 AI 소식에서 자주 마주치고 설명이 도움이 되는 용어다. 고르면 ai_review_status를 first_pass_complete로 올려 소식 하이라이트에 넣는다.

LLM, RAG(검색 증강 생성), 할루시네이션, 세부 조정(fine-tuning), 컨텍스트 윈도우, 에이전트 루프, 에이전트형 워크플로, 바이브 코딩, 체크포인트, 프롬프트 엔지니어링, 양자화, 증류, 과적합, 파운데이션 모델, 가드레일, 멀티모달 모델, mixture of experts, 지침 조정, 퓨샷 프롬프팅, 제로샷 프롬프팅, 연쇄적 사고(CoT) 프롬프팅, 인간 피드백 기반 강화 학습(RLHF), TPU

## 논문에 이미 연결된 새 용어 14개

정책, 양자화, 벡터 표현이(→ A에서 수정), 강화 학습 (RL), 자체 학습, 검증 손실, 제로샷 프롬프팅, 증류, 파운데이션 모델, 그라운딩, 정답(ground truth), IoU, mixture of experts, modality. 이름이 틀린 것은 「벡터 표현이」 하나다.
