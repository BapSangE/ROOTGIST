# ROOTGIST Admin — R0 로컬 검토본

Next.js + React + TypeScript로 만든 별도 관리자 웹입니다. Flutter 앱의 `web/`를 사용하지 않습니다. 현재 여섯 화면과 조회·문맥·앱 강조 미리보기를 제공합니다. **초안 저장·승인·게시는 지원하지 않으며 모든 쓰기 API는 차단합니다.**

## 실행

Node 26.12.1 / npm 11.20.0 기준으로 확인했습니다.

```sh
cd admin
npm ci
npm run dev:fixture
```

`http://127.0.0.1:3000/admin/terms`에서 가상 데이터를 확인합니다. 다른 포트는 `npm run dev:fixture -- --port 3100`처럼 지정합니다. 서버는 localhost에만 바인딩합니다. fixture는 development/test에서 명시적으로 켤 때만 허용하고 production/Vercel에서는 거부합니다. 실제 이메일·비밀번호를 fixture 화면에 입력할 필요가 없습니다.

## 실제 조회 연결

`.env.example`을 참고하여 별도 환경의 `.env.local`에 `ADMIN_DATA_MODE=supabase`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `ADMIN_USER_ID`, 서버 전용 `SUPABASE_SECRET_KEY`를 설정합니다. 계정은 사전 등록된 관리자 1명을 전제로 하며 공개 회원가입은 제공하지 않습니다. 실제 Auth/DB 연결은 이번 작업에서 검증하지 않았습니다. 운영 환경에 그대로 연결한 것으로 간주하지 마세요.

세션 검증은 Supabase `auth.getUser()`의 검증된 UUID를 서버 ADMIN_USER_ID와 비교합니다. 페이지·API 모두 확인하며 관리자 확인 뒤에만 privileged 읽기에 들어갑니다. secret key는 client/NEXT_PUBLIC_*에 넣지 않습니다. R0 전송기는 GET/HEAD 테이블 조회만 허용하고 RPC/POST/PUT/PATCH/DELETE는 거부합니다.

R0 Supabase 어댑터는 명시한 열만 읽고 표당 500행씩 최대 10,000행까지 읽습니다. 초과·불완전 읽기는 503이며 일부 결과를 전체 건수로 표시하지 않습니다. 여러 표를 하나의 DB snapshot 트랜잭션으로 읽는 것은 아니므로 revision=0/hash는 조회 기준값입니다. 저장·승인 근거로 사용하지 않습니다. 운영 조회 규모/비용/스키마 확인 후 전용 조회 API로 최적화할 수 있습니다.

## 검증

```sh
npm run lint
npm run typecheck
npm test
# dev:fixture 서버가 실행 중일 때 실제 로컬 HTTP 경계도 포함
ADMIN_TEST_URL=http://127.0.0.1:3100 npm test
npm run build
# 일반 Next.js production 서버; 실제 연결 설정이 필요합니다.
npm run start
```

기본 test에서는 외부 서버가 필요한 HTTP 테스트 하나를 제외합니다. 위 ADMIN_TEST_URL 실행에서는 28개 테스트를 모두 확인했습니다. 자동 브라우저 검증은 별도로 `npx playwright install chromium` 후 `npm run test:e2e`입니다. 현재 Codex 샌드박스에서는 Chromium의 macOS MachPort 기동이 거부되어 자동 E2E 통과를 확인하지 못했습니다. 인앱 브라우저로 실제 주요 흐름을 검증한 기록은 아래 진행 문서에 있습니다.

개발 모드는 환경의 FSEvent 제한을 피하기 위해 Webpack과 Watchpack polling을 사용합니다. Next telemetry는 dev/build에서 껐습니다. production build 성공은 운영 배포나 실제 Supabase 연결 성공을 뜻하지 않습니다.

## 범위와 기록

- [작업계획](../docs/ADMIN_WEB_PLAN.md)
- [착수 기준](../docs/admin/BASELINE.md)
- [구현·검증·미완료 기록](../docs/admin/PROGRESS.md)
- [디자인·데이터 계약](../docs/admin/ROOTGIST_Admin_Implementation_Spec.md)

기존 Flutter/워커/DB/마이그레이션/배포 빌드는 수정하지 않았습니다. 다음 R1은 DB 트랜잭션·초안·변경 이력과 배치 수정본 보호를 갖춘 뒤 쓰기를 활성화하는 단계입니다. source-catalog.json과 notices-snapshot.json은 기준 커밋 b8e5c6a의 공개 코드/번들 문서에서 만든 버전 있는 참조본이며 자동 최신 데이터나 원격 공지 게시가 아닙니다. 변경할 때 원본·기준 커밋과 함께 갱신해야 합니다.
