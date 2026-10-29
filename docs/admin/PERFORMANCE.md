# 관리자 로그인·목록 조회 성능 점검

2026-10-29. 사용자 지연 제보에 따라 읽기 전용 범위에서 개선한다. Flutter·워커·DB/마이그레이션·실제 콘텐츠·환경변수 값은 변경하지 않는다.

## 확인한 원인과 변경

1. 모든 API가 같은 전체 snapshot을 구성해 모델 한 개의 목록에도 16개 테이블과 모든 논문 문장/번역/용어를 읽었다. API의 리소스 이름을 전달해 아래 의존 테이블만 읽도록 제한한다. 기존 조회 결과와 cursor/hash/문장 ID/하이라이트 규칙은 유지한다.
2. 실제 Supabase 프로젝트는 ap-south-1(뭄바이), 기존 Vercel 배포는 iad1(미국)이었다. admin/vercel.json에 regions=[bom1]을 명시한다. 서버와 DB를 가까이 두는 변경이며 DB를 이전하거나 새로 만들지 않는다.
3. 로그인 성공 직후 signInWithPassword에 이어 getUser를 호출했다. Auth 서버가 검증해 반환한 signInWithPassword의 data.user.id를 관리자 UUID와 직접 대조해 왕복 한 번을 줄인다. 비관리자는 기존처럼 signOut 후 거부한다. 보호된 API/레이아웃의 requireAdmin/getUser 검증은 그대로 유지한다.

| 요청 | 이전 테이블 수 | 변경 후 테이블 수 |
| --- | ---: | ---: |
| 모델, 공식 뉴스 | 16 | 2 |
| 앱 포함 공지 | 16 | 1 |
| 출처, 운영 이력 표시 | 16 | 각 1 |
| 논문 | 16 | 10 |
| 용어 | 16 | 12 |
| 대시보드 | 16 | 14 |

테이블 수는 데이터 조회 범위이며 인증 요청과 표당 500행 pagination을 포함한 총 HTTP 요청 수가 아니다. app_config를 쓰는 화면은 함께 조회한다. 공지/출처 참조본과 운영 이력 미연결 상태는 그대로다.

## 검증

- 실제 배포 관리자 세션으로 개선 전 모델 목록 약 5.60초, 용어 목록 약 9.37초를 관측했다. 브라우저 reload/goto 시작부터 JSON DOM 확인까지의 벽시계 시간이며 네트워크/도구 오버헤드를 포함한다. 각 1회이므로 평균/p95나 순수 서버 응답 시간으로 해석하지 않는다. 첫 모델 탭 생성은 약 14초였지만 측정 방법이 달라 비교 수치에서 제외한다.
- 실제 Supabase SDK query builder와 GET 전용 transport는 유지하고 HTTP만 가상화한 테스트에서 불필요한 테이블 조회를 재현했다(RED). 로그인 중복 요청 실패도 재현했다.
- 화면별 조회와 전체 snapshot의 응답 동등성, 논문 A01 번역/용어 문맥 의존성, 실제 GET handler의 범위 전달을 검증했다.
- Node 24.22.2에서 실제 로컬 fixture HTTP 포함 57 tests passed. 8개 조회 경로 200, capabilities 모두 false, 모든 쓰기 verb 423 확인. lint/typecheck/build 성공.
- 독립 코드 리뷰에서 Critical/Important 없음. 제안된 응답 동등성 검증도 추가했다.
- 커밋 632a18b3f81e3d5b01f561c6889563a2d97010d9의 Production 배포 dpl_HR9z8x8R7WsthgqySg3dDCsAiSZm READY, regions=[bom1], rootgist.vercel.app alias를 확인했다. 운영 측정은 다음과 같다.

## 보안·한계

인증/권한 결과를 캐시하거나 서버 데이터를 공개 캐시에 저장하지 않는다. private/no-store, 관리자 UUID 대조, 서버 전용 키 경계, GET/HEAD 전용 transport와 쓰기 423을 유지한다. 따라서 조회 결과는 매 요청 실제 DB에서 읽는다.

용어/논문은 여전히 관련 테이블 전체를 읽고 메모리에서 연결한다. 여러 표의 단일 트랜잭션 snapshot은 아니며 표당 10,000행 제한도 유지한다. 추후 양이 늘거나 지연이 남으면 목록/선택 항목 전용 조회와 연결 비용을 따로 최적화한다. Proxy와 보호된 handler의 Auth 확인도 이번에는 유지했다. 비밀번호를 취급하지 않았으므로 실제 비밀번호 제출부터 완료까지의 전후 시간은 측정하지 않았다.

## 공식 근거

- [Vercel 함수 리전 설정](https://vercel.com/docs/functions/configuring-functions/region): 데이터 소스에 가까운 함수 리전 권장, vercel.json regions 설정.
- [Vercel 리전 코드](https://vercel.com/docs/regions): bom1 = ap-south-1 Mumbai.
- [Supabase signInWithPassword](https://supabase.com/docs/reference/javascript/auth-signinwithpassword): 서버 인증 응답의 data/error 사용.
- [Supabase SSR 인증](https://supabase.com/docs/guides/auth/server-side/creating-a-client?queryGroups=framework&framework=nextjs): getUser의 서버 사용자 검증과 캐시 주의사항. 이번에는 requireAdmin에서 getUser를 유지한다.
- Supabase changelog의 관련 breaking change를 확인했다. 최근 TLS 1.2 CBC 제한 예고는 최신 Node 24 클라이언트/이번 조회 범위 변경을 막는 사항이 아니다.


## 운영 배포 후 관측

| 요청 | 개선 전 | 개선 후 관측 |
| --- | ---: | ---: |
| 모델 목록(limit=1) | 5.60초 | 2.06초, 반복 1.10초 |
| 용어 적용 위치 목록(limit=1) | 9.37초 | 배포 직후 첫 요청 8.33초, 이후 2.29초 |

같은 관리자 브라우저 세션, 동일 URL과 탐색+JSON DOM 확인 방식으로 측정했다. 응답은 모두 fixture=false이고 모델 10개/용어 적용 위치 476개였다. 서버의 순수 처리 시간이나 로그인 폼 제출 시간은 아니며 소수 표본이다. 첫 요청/워밍업·네트워크 영향을 분리한 벤치마크도 아니므로 cold start가 단독 원인이라고 단정하지 않는다. 배포 직후 첫 요청 지연은 남아 있다.

실제 용어 화면 새로고침 후 사전 의미·논문 문맥·강조 표기 입력과 저장 버튼 잠금을 확인했다. 오류 alert 없음. API뿐 아니라 화면의 상세 조회도 이어서 동작했다. 별도 미로그인 요청은 /login 200(약 421ms), 용어 API 401(약 383ms), private/no-store였다. 선택한 최근 15분 런타임 오류 조회는 보고 0건이며 전체 기간의 무오류 보장이 아니다.

사용자에게 반복 조회 개선과 첫 요청의 한계를 함께 보고한다. 느린 첫 요청과 용어/논문 전체 의존 데이터 조회는 추가 최적화 여지로 남긴다. 운영 DB 쓰기·테스트 데이터 삽입·마이그레이션 적용·수동 배포 명령은 실행하지 않았다.
