# ROOTGIST 관리자 웹 Vercel 배포 준비

2026-10-29 · Node 24 호환 조정

## 현재 상태

관리자 웹의 Node 요구 버전을 `24.x`로 바꾸고 로컬 `.node-version`을 `24.22.2`로 맞췄다. `@types/node`는 24.19.2, 관련 undici-types는 7.24.6이다. Next/React/Supabase 및 다른 패키지 버전은 변경하지 않았다. 설치 잠금파일에서 바뀐 package entry는 루트 metadata, @types/node, undici-types뿐이다. 시스템 Node/npm 설치는 변경하지 않았다.

공식 nodejs.org의 macOS arm64 Node 24.22.2를 SHA-256 검증 후 별도 작업 폴더에서 사용했다. 실제 서버 키나 `.env.local`을 검증 폴더에 복사하지 않았다.

기존 설정은 Node 24의 `npm ci --engine-strict`에서 EBADENGINE으로 실패하는 것을 확인했다. 변경 후 같은 런타임에서 깨끗한 `npm ci --engine-strict`, lint, typecheck, test, production build가 성공했다. Node 24로 실행한 localhost fixture 서버의 실제 HTTP GET/상세/쓰기 차단 테스트를 포함해 관리자 테스트 34개가 통과했다. 이 검증은 Vercel의 Linux 빌드 및 원격 배포 성공을 의미하지 않는다.

## 새 프로젝트 설정

1. Vercel에서 BapSangE/ROOTGIST의 main을 가져온다. 여러 앱이 표시되면 admin의 Import single project를 선택한다.
2. Root Directory=`admin`, Framework/Application Preset=Next.js, Node.js=24.x.
3. Install Command=`npm ci`, Build Command=`npm run build`, Output Directory=기본값. `package.json`의 engines도 24.x이므로 프로젝트 설정과 충돌하지 않는다.
4. 다음 환경변수를 Production에 설정한다. 로컬 `.env.local`은 Git에 포함되지 않아 자동 전달되지 않는다.

| 이름 | 값 |
|---|---|
| ADMIN_DATA_MODE | supabase |
| SUPABASE_URL | 기존 ROOTGIST_DB URL |
| SUPABASE_PUBLISHABLE_KEY | 해당 DB의 공개 키 |
| ADMIN_USER_ID | 이미 생성한 실제 관리자 UUID |
| SUPABASE_SECRET_KEY | 관리자 웹용 서버 전용 키, Secret 값으로 저장 |

서버 전용 키에 NEXT_PUBLIC_ 접두사를 붙이거나 채팅/문서/Git에 값을 넣지 않는다. Vercel에서는 fixture 모드를 거부하므로 `.env.example`의 fixture 값을 그대로 옮기지 않는다. 환경변수를 나중에 바꾸면 새 배포/재배포가 필요하다.

5. 실제 배포는 Vercel에서 수행하고 `/login`에서 기존 관리자 계정으로 로그인한다. 로그인/6개 조회 화면/미로그인 차단/읽기 전용 상태를 배포 URL에서 다시 확인한다.

## 운영 범위

이번 변경은 버전 호환 설정과 검증·문서뿐이며 Vercel 프로젝트 생성/배포·환경변수 원격 등록·운영 DB migration 적용을 하지 않았다. 새 관리자 migration을 Vercel Build Command에 넣지 않는다. 현재 배포 대상은 읽기 전용 R0이며 용어 저장은 M5 워커 보호와 M6 편집 화면 이후에 활성화한다. Flutter 앱, 워커 자동 수집·요약·공개, 기존 DB/마이그레이션은 변경하지 않았다.

## 공식 참고

- https://vercel.com/docs/functions/runtimes/node-js/node-js-versions
- https://vercel.com/docs/builds/configure-a-build
- https://vercel.com/docs/environment-variables
- https://nodejs.org/dist/v24.22.2/SHASUMS256.txt


### 함수 리전

admin/vercel.json의 regions=[bom1]을 사용한다. 기존 Supabase ROOTGIST_DB의 실제 ap-south-1과 맞춘 설정이며 DB 이전은 아니다. 리전을 바꿀 때는 [PERFORMANCE.md](PERFORMANCE.md)의 측정과 실제 DB 위치를 함께 확인한다.
