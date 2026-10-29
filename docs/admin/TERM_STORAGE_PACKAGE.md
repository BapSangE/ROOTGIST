# 용어 저장 기반 M4 — 검토 패키지

> 2026-10-29 정정: 이 마이그레이션은 main 푸시 때 운영 DB에 적용돼 있었다(쓰기 준비값 false). M5·M6는 [TERM_REVIEW_WRITES.md](TERM_REVIEW_WRITES.md).

2026-10-28 · 기준 3a76540 · 작업 브랜치 codex/term-review-storage

## 결과와 범위

용어 전용 저장 기반을 로컬 구현했다. 운영 DB 적용·워커 변경·UI 저장 활성화는 하지 않았다. 기존 localhost:3101 실제 읽기 서버는 그대로이며 쓰기는 계속 423이다. 이 패키지는 M4이고 M5 수정본 보호와 M6 편집 화면이 완료된 R1이 아니다.

## 변경

- CLI 2.122.0으로 생성한 additive migration `20261028125014_admin_term_storage.sql`. 기존 8개 migration은 수정하지 않았다.
- private rootgist_admin.runtime/control/drafts/audit. 내부 표 RLS, anon/authenticated 권한 없음, service_role에도 runtime UPDATE 권한 없음.
- 서버 전용 SECURITY INVOKER RPC: 대상 조회, 상태 조회, 본인 초안 조회/저장, 대상별 이력, 원자적 용어 command. PUBLIC/anon/authenticated EXECUTE 제거.
- 지원 단위는 sense(별칭 포함), candidate, paper의 glossary 부분 patch뿐이다. 논문 본문/요약/번역·뉴스·모델·공지 편집 명령은 없다. paper 전체 승인은 지원하지 않는다.
- DB가 반환한 JSONB SHA-256과 revision을 재검사한다. 기존 R0의 JSON.stringify 해시를 DB 해시로 간주하지 않는다.
- 단일 관리자용 전체 쓰기 protocol 트랜잭션 advisory lock → operation_id lock → 정렬된 control 잠금, 관련 원본 행 잠금, 필드/참조/span 검증, 저장·보호 snapshot·감사 이력의 한 트랜잭션. 같은 ID+같은 요청은 저장된 응답, 다른 요청은 409. 실패하면 전체 rollback.
- 의미/별칭 검토 상태 변경, 의미 수정 시 승인 무효화, 메모만 바뀔 때 승인 유지. 후보 승인은 사전 동기화 대기로 응답하고 즉시 사전 반영 완료로 표시하지 않는다.
- ko_span은 null/빈 문자열을 구별하고 실제 번역문의 부분 문자열인지 검증한다. idx와 expected_term도 함께 검사한다.
- 초안은 관리자/대상당 활성 1개, draft_revision 충돌 검사. 원본 저장은 내용이 일치한 본인 초안만 accepted로 보존한다.
- 감사 이력은 편집한 용어 값의 전후/해시/버전/작업 ID만 기록한다. 논문 원문·번역·raw_response는 감사 이력에 복제하지 않는다.
- TypeScript 요청 parser와 서버 storage adapter는 새 파일로만 추가했다. 기존 route와 read-only transport/capability는 변경하지 않았다.

## 검증 환경과 실행

네트워크 none인 `postgres:17.11-alpine` 임시 컨테이너, 이름 rootgist-term-contract-m4, 라벨 rootgist.test=term-storage. 실제 데이터·키는 복사하지 않았다. 외부 DB URL을 받는 테스트 명령은 없다. 테스트는 이 라벨과 네트워크를 확인한 뒤 컨테이너 내부의 public/private 테스트 스키마를 초기화한다. 공유/운영 PostgreSQL에서는 실행하지 않는다.

```sh
docker run --rm -d --network none --name rootgist-term-contract-m4 --label rootgist.test=term-storage -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17.11-alpine
# pg_isready 성공 후
python3 -m unittest discover -s supabase/tests/admin -p 'test_*.py' -v
npm --prefix admin test
npm --prefix admin run lint
npm --prefix admin run typecheck
npm --prefix admin run build
docker stop rootgist-term-contract-m4
```

테스트는 함수를 구현하기 전 실패를 확인하고, 이후 동시 operation_id/다중 대상 rollback/동시 해시 변화/메모 승인 보존 등의 재현 테스트를 추가해 RED→GREEN으로 검증했다. 최종 결과: DB 18 tests passed, 관리자 웹 34 tests passed(실제 localhost fixture HTTP 포함), lint/typecheck/build exit 0. 기존 공개 get_paper RPC에서 수정된 용어 span만 반영되고 번역·요약은 유지되는 회귀도 통과했다. 단위 테스트 mock RPC를 실제 운영 command 성공으로 보고하지 않는다.

## 운영 적용 전 조건

현재 migration의 기본값은 writes_enabled=false, worker_contract_version=0, admin_user_id=null이다. service key를 입력하거나 서버 환경값을 바꾸는 것만으로 쓰기가 켜지지 않는다. 이 파일을 운영에 적용하지 않았고 runtime을 활성화하는 SQL도 실행하지 않았다.

1. M5: 모든 관련 워커 경로(전체 glossary 교체·sense 연결·span/full_form 채움·후보 갱신/삭제/승격·사전 재수입)가 동일 보호 계약에 참여해야 한다. 기존 워커는 아직 참여하지 않는다. 이 조건이 없으면 이 패키지의 command를 실사용하면 안 된다.
2. M5에서는 논문/뉴스 자동 수집·요약·공개를 동결하지 않는다. 새 원문·번역이 들어오면 옛 idx/span을 맹목적으로 재적용하지 않는 용어 수정본 보존·재검토 계약을 마련한다.
3. M6: 인증된 서버에서만 readiness/DB target hash를 읽고, 요청 body에서 actor/role/origin을 받지 않는 경로와 UI를 연결한다. 기존 R0 GET-only 전송기는 command에 그대로 사용할 수 없다. 별도의 제한된 RPC 경로가 필요하다.
4. 실제 서비스에서의 충돌·권한·회귀 검증과 운영 적용/호환 워커/복구 순서를 구체화한 후에만 적용·활성화한다. API key 자체의 권한은 읽기 전용 역할이 아니라는 기존 경계도 유지한다.

## 복구

쓰기 전에는 적용하지 않는 것이 현재 상태다. 향후 적용 후 문제가 생기면 writes_enabled를 먼저 끄고, 원본·보호 snapshot·초안·감사 이력을 보존한다. 사람 데이터가 생긴 뒤 private schema DROP/과거 migration 재적용으로 되돌리지 않는다. 보호에 참여하지 않는 구 워커를 쓰기 활성 상태로 돌리지 않는다.

## 남은 구현

M5 워커 보호·M6 실제 용어 편집 UI·문맥 검수 완료 이력은 아직 없다. UI 승인 버튼을 켜거나 운영 DB에 시험 데이터를 넣지 않았다. 논문·뉴스·모델의 수동 승인은 계속 범위 밖이다.

## 독립 리뷰와 수정

독립 리뷰의 Important 4건을 모두 로컬 DB에서 재현한 다음 한 번의 수정 패스로 해결했다.

1. 다른 의미의 동일 alias_id 동시 생성: 실제 INSERT ON CONFLICT에서도 sense 소유권을 검사하고 불일치는 전체 rollback.
2. sentence_ids만 바뀌는 요청: 누락된 ko_span은 기존 값을 상속한 최종 상태로 검증. 명시적 null/빈 값과 구분한다.
3. 승인·반려 이유 소실: action/reason/전후 review_state를 immutable audit changes에 저장해 이후 메모에 덮이지 않게 한다.
4. 여러 paper/sense의 교차 잠금: 대상에 없는 공유 의미 의존성으로 교착이 나던 요청을 전체 용어 쓰기 protocol lock으로 직렬화. 단일 관리자 환경에 맞춘 선택이며 쓰기 처리량을 제한한다. M5 워커도 같은 lock을 먼저 잡아야 한다.

### 결정과 비용

- 용어 전용 계약을 우선하므로 논문·뉴스·모델 편집은 제공하지 않는다. 기존 자동 처리 흐름을 보존한다.
- private schema/SECURITY INVOKER/서버 전용 RPC와 DB readiness를 유지한다. M5/M6 전에는 사용자가 저장할 수 없다는 비용을 받아들이고 수정본 유실을 방지한다.
- 운영 프로젝트를 추가하지 않고 network-none 임시 PG만 사용했다. 실제 Supabase/PostgREST 권한 기본값·운영 부하·배포 적합성을 검증한 것은 아니다.
- 커밋 전 변경은 working-tree 전체 새 파일을 포함한 diff로 리뷰했다. 커밋 범위가 비어 있는 상태에서 완료된 커밋 리뷰로 오표시하지 않았다. 사용자의 후속 커밋·푸시 요청에 따라 최종 커밋한다.

리뷰에서 판단을 유보한 M5/M6·운영 migration 호환·실제 Supabase privilege default는 쓰기 활성화 전 별도 검증 대상이라는 결정이다. 빌드는 리뷰 이후 최종 로그에서 성공을 확인했다. 미룬 Minor는 없다.
