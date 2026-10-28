import type { Metadata } from "next";
import "@/styles/tokens.css";
export const metadata: Metadata = {
  title: "ROOTGIST 관리자",
  description: "ROOTGIST 콘텐츠 검수 도구",
  robots: { index: false, follow: false },
};
export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ko">
      <body>{children}</body>
    </html>
  );
}
