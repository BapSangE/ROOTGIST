import Link from "next/link";
import { resolveEnvironment } from "@/lib/server/environment";
import { login } from "@/lib/server/login-actions";
import { AdminError } from "@/lib/server/errors";
export const dynamic = "force-dynamic";
export default async function Page({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  let fixture = false;
  let problem = "";
  try {
    fixture = resolveEnvironment(process.env).mode === "fixture";
  } catch (error) {
    problem =
      error instanceof AdminError
        ? error.message
        : "연결 설정을 확인해 주세요.";
  }
  const { error } = await searchParams;
  return (
    <main className="login-page">
      <section className="login-card">
        <div className="brand">
          ROOTGIST<span>EDITORIAL ADMIN</span>
        </div>
        <h1>관리자 로그인</h1>
        <p className="muted">콘텐츠를 정확하고 읽기 쉽게 다듬는 공간</p>
        {problem ? (
          <div className="callout" role="alert">
            {problem}
            <p>관리자 웹의 서버 환경을 먼저 설정해 주세요.</p>
          </div>
        ) : fixture ? (
          <>
            <div className="callout">
              가상 데이터 · 로컬 검토 환경이에요.
              <p>실제 계정과 데이터베이스에는 연결하지 않아요.</p>
            </div>
            <Link href="/admin" className="button primary">
              검토 화면 열기
            </Link>
          </>
        ) : (
          <form action={login}>
            <label className="field">
              이메일
              <input
                name="email"
                type="email"
                autoComplete="username"
                maxLength={254}
                required
              />
            </label>
            <label className="field">
              비밀번호
              <input
                name="password"
                type="password"
                autoComplete="current-password"
                maxLength={1024}
                required
              />
            </label>
            {error && (
              <p role="alert">
                {error === "admin"
                  ? "등록된 관리자 계정으로 로그인해 주세요."
                  : "로그인 정보를 확인해 주세요."}
              </p>
            )}
            <button className="button primary" type="submit">
              로그인
            </button>
            <p className="micro muted">
              사전에 등록된 관리자만 이용할 수 있어요.
            </p>
          </form>
        )}
      </section>
    </main>
  );
}
