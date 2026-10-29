import "@/styles/term-focus.css";
import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/server/require-admin";
import { AdminError } from "@/lib/server/errors";
import { AdminShell } from "@/components/admin-shell";
export const dynamic = "force-dynamic";
export default async function Layout({
  children,
}: {
  children: React.ReactNode;
}) {
  let actor;
  try {
    actor = await requireAdmin();
  } catch (error) {
    if (error instanceof AdminError && error.status === 401) redirect("/login");
    return (
      <main className="login-page">
        <div className="login-card">
          <div className="brand">ROOTGIST</div>
          <h1>관리자 연결 확인</h1>
          <p role="alert">
            {error instanceof AdminError
              ? error.message
              : "관리자 연결을 확인해 주세요."}
          </p>
          <a className="button secondary" href="/login">
            로그인 화면
          </a>
        </div>
      </main>
    );
  }
  return <AdminShell fixture={actor.fixture}>{children}</AdminShell>;
}
