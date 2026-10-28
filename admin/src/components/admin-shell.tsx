"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Icon, Badge } from "./shared";
import { logout } from "@/lib/server/login-actions";
const navigation = [
  ["/admin", "대시보드", "dashboard"],
  ["/admin/terms", "용어 검수", "terms"],
  ["/admin/papers", "논문 검수", "papers"],
  ["/admin/news", "공식 AI 소식", "news"],
  ["/admin/notices", "공지사항", "notices"],
  ["/admin/operations", "출처 · 운영", "operations"],
];
export function AdminShell({
  fixture,
  children,
}: {
  fixture: boolean;
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const active = navigation.find((x) => x[0] === pathname) ?? navigation[0];
  return (
    <div className="admin-shell">
      <a href="#content" className="skip-link">
        본문으로 이동
      </a>
      <aside className="sidebar">
        <Link href="/admin" className="brand" aria-label="ROOTGIST">
          ROOTGIST<span>EDITORIAL ADMIN</span>
        </Link>
        <nav aria-label="관리자 메뉴">
          {navigation.map(([href, label, icon], i) => (
            <div key={href}>
              {i === 1 && <p className="nav-group">콘텐츠 검수</p>}
              {i === 4 && <p className="nav-group">관리</p>}
              <Link
                href={href}
                aria-label={label}
                aria-current={pathname === href ? "page" : undefined}
                className={pathname === href ? "nav-item selected" : "nav-item"}
              >
                <Icon name={icon} />
                <span>{label}</span>
              </Link>
            </div>
          ))}
        </nav>
        <div className="sidebar-footer">
          <p>Ink & Paper · ROOTGIST</p>
          <div className="profile">
            <span className="avatar">RG</span>
            <div>
              관리자 1명
              <small>{fixture ? "로컬 검토 환경" : "인증된 관리자"}</small>
            </div>
          </div>
          {!fixture && (
            <form action={logout}>
              <button className="text-button">로그아웃</button>
            </form>
          )}
        </div>
      </aside>
      <div className="main-shell">
        <header className="topbar">
          <span>
            관리자 <span className="slash">/</span> {active[1]}
          </span>
          <Badge>조회 전용 · R0</Badge>
        </header>
        <div className="environment-banner">
          {fixture
            ? "가상 데이터 · 로컬 검토본"
            : "관리자 읽기 연결 · 실제 데이터"}
          <span>
            {fixture
              ? "모든 논문·소식 예시는 가상입니다."
              : "초안·승인·공개 변경은 아직 지원하지 않습니다."}
          </span>
        </div>
        <div className="small-screen-note">
          데스크톱 1280px 이상을 권장해요. 문맥 패널을 접어 볼 수 있어요.
        </div>
        <main id="content" className="main-content">
          {children}
        </main>
      </div>
    </div>
  );
}
