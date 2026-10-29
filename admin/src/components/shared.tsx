"use client";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import Link from "next/link";
import { patchReviewQuery } from "@/lib/domain/query";
import type { Highlight } from "@/lib/domain/display";
export function Icon({ name, size = 19 }: { name: string; size?: number }) {
  const paths: Record<string, React.ReactNode> = {
    dashboard: (
      <>
        <rect x="3" y="3" width="18" height="18" rx="2" />
        <path d="M3 9h18M9 9v12" />
      </>
    ),
    terms: (
      <>
        <rect x="3" y="3" width="18" height="18" rx="2" />
        <path d="M8 8h8M12 8v9" />
      </>
    ),
    papers: (
      <>
        <rect x="4" y="3" width="16" height="18" rx="2" />
        <path d="M8 8h8M8 12h8M8 16h5" />
      </>
    ),
    news: (
      <>
        <path d="M4 4h16v16H4zM8 8h8M8 12h8M8 16h4" />
      </>
    ),
    notices: (
      <>
        <path d="M4 6h16v14H4zM7 3v6M17 3v6M8 13h8M8 16h5" />
      </>
    ),
    operations: (
      <>
        <circle cx="12" cy="12" r="8" />
        <path d="m8 12 3 3 5-6" />
      </>
    ),
    search: (
      <>
        <circle cx="10.5" cy="10.5" r="6.5" />
        <path d="m16 16 4 4" />
      </>
    ),
    arrow: <path d="M4 12h16m-6-6 6 6-6 6" />,
    refresh: (
      <>
        <path d="M20 7v5h-5M4 17v-5h5" />
        <path d="M6 7a7 7 0 0 1 12-1l2 2M4 16l2 2a7 7 0 0 0 12-1" />
      </>
    ),
    external: (
      <>
        <path d="M14 4h6v6M20 4 10 14" />
        <path d="M10 4H4v16h16v-6" />
      </>
    ),
  };
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {paths[name] ?? paths.papers}
    </svg>
  );
}
export function Badge({ children }: { children: React.ReactNode }) {
  return <span className="badge">{children}</span>;
}
const labels: Record<string, string> = {
  pending: "! 검토 대기",
  approved: "✓ 의미 승인",
  rejected: "× 반려",
  deferred: "수정 필요",
  unreviewed: "적용 위치 확인",
  checked: "✓ 확인 완료",
  ready: "AI 처리 완료",
  failed: "AI 처리 실패",
  post: "공식 발표",
  notice: "공지",
  release: "릴리스",
  bundled: "앱 번들",
};
export function Status({ status }: { status: string }) {
  return <Badge>{labels[status] ?? status}</Badge>;
}
export function safeUrl(url: string): string | undefined {
  try {
    const u = new URL(url);
    return ["https:", "http:"].includes(u.protocol) ? u.href : undefined;
  } catch {
    return undefined;
  }
}
export function ExternalLink({
  url,
  children,
}: {
  url: string;
  children: React.ReactNode;
}) {
  const href = safeUrl(url);
  return href ? (
    <a
      className="external-link"
      href={href}
      target="_blank"
      rel="noopener noreferrer"
    >
      {children}
      <Icon name="external" size={14} />
    </a>
  ) : (
    <span className="muted">링크 확인 필요</span>
  );
}
export function HighlightText({
  text,
  highlights = [],
  focusIdx,
  names,
}: {
  text: string;
  highlights?: Highlight[];
  focusIdx?: number | null; // 있으면 지금 검토 중인 용어만 진하게, 다른 용어는 연하게(붙어 있어도 나뉘어 보이게)
  names?: Record<number, string>;
}) {
  let at = 0;
  const nodes: React.ReactNode[] = [];
  for (const h of highlights) {
    nodes.push(text.slice(at, h.start));
    const role = focusIdx === undefined ? undefined : h.idx === focusIdx ? "current" : "other";
    nodes.push(
      <mark
        key={`${h.idx}:${h.start}`}
        className={role}
        title={names?.[h.idx] ? `${role === "current" ? "검토 중 · " : "다른 용어 · "}${names[h.idx]}` : undefined}
      >
        {text.slice(h.start, h.end)}
      </mark>,
    );
    at = h.end;
  }
  nodes.push(text.slice(at));
  return <>{nodes}</>;
}
export function useResource<T>(url: string | null) {
  const [retryVersion, setRetryVersion] = useState(0);
  const [result, setResult] = useState<{
    key: string;
    url: string | null;
    data: T | null;
    error: string | null;
  }>({ key: "", url: null, data: null, error: null });
  const key = `${url}:${retryVersion}`;
  useEffect(() => {
    if (!url) return;
    const controller = new AbortController();
    fetch(url, { cache: "no-store", signal: controller.signal })
      .then(async (response) => {
        const body = await response.json();
        if (!response.ok)
          throw new Error(body.error?.message ?? "데이터를 불러오지 못했어요.");
        if (!controller.signal.aborted)
          setResult({ key, url, data: body, error: null });
      })
      .catch((error) => {
        if (!controller.signal.aborted)
          setResult({
            key,
            url,
            data: null,
            error:
              error instanceof Error
                ? error.message
                : "데이터를 불러오지 못했어요.",
          });
      });
    return () => controller.abort();
  }, [url, key]);
  const current = result.key === key;
  // 같은 주소를 다시 불러올 때(저장 뒤 새로 고침)는 이전 내용을 그대로 보여 목록이 깜빡이지 않게 한다
  const stale = !current && result.url === url && result.data !== null;
  return {
    data: current || stale ? result.data : null,
    error: current ? result.error : null,
    loading: !!url && !current && !stale,
    refreshing: !!url && stale,
    retry: () => setRetryVersion((v) => v + 1),
  };
}
export function useQuery() {
  const pathname = usePathname();
  const params = useSearchParams();
  return {
    params,
    change: (values: Record<string, string | null>) => {
      const next = patchReviewQuery(window.location.search, values);
      window.history.pushState(
        null,
        "",
        `${pathname}${next ? "?" + next : ""}`,
      );
    },
  };
}
export function SearchBox({
  label = "검색",
  query,
  onSearch,
}: {
  label?: string;
  query: string;
  onSearch: (q: string) => void;
}) {
  const input = useRef<HTMLInputElement>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    if (input.current && input.current.value !== query)
      input.current.value = query;
  }, [query]);
  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    [],
  );
  return (
    <label className="search-box">
      <span className="sr-only">{label}</span>
      <Icon name="search" size={16} />
      <input
        ref={input}
        defaultValue={query}
        maxLength={120}
        placeholder="영문·한국어 표기 검색"
        onChange={(e) => {
          const value = e.target.value;
          if (timer.current) clearTimeout(timer.current);
          timer.current = setTimeout(() => onSearch(value), 300);
        }}
      />
    </label>
  );
}
export function StatePanel({
  loading,
  error,
  empty,
  retry,
}: {
  loading?: boolean;
  error?: string | null;
  empty?: string;
  retry?: () => void;
}) {
  if (loading)
    return (
      <div className="state-panel" role="status">
        <div className="skeleton" />
        <div className="skeleton short" />
        <span className="sr-only">불러오는 중</span>
      </div>
    );
  return (
    <div className="state-panel" role={error ? "alert" : "status"}>
      <strong>
        {error ? "불러오지 못했어요" : (empty ?? "선택한 항목이 없어요")}
      </strong>
      {error && <p>{error}</p>}
      {retry && (
        <button onClick={retry} className="button secondary">
          다시 불러오기
        </button>
      )}
      {error?.includes("로그인") && <Link href="/login">로그인 화면으로</Link>}
    </div>
  );
}
export function ReadOnlyActions({
  specific = "적용 위치 저장",
}: {
  specific?: string;
}) {
  return (
    <footer className="review-actions">
      <span>
        조회 · 로컬 미리보기
        <br />
        <small>수정본 보호 연결 후 저장할 수 있어요.</small>
      </span>
      <div>
        <button disabled className="button secondary">
          임시 저장
        </button>
        <button disabled className="button primary">
          {specific}
        </button>
      </div>
    </footer>
  );
}
export function PageIntro({
  eyebrow,
  title,
  description,
  children,
}: {
  eyebrow: string;
  title: string;
  description: string;
  children?: React.ReactNode;
}) {
  return (
    <header className="page-intro">
      <div>
        <span className="eyebrow">{eyebrow}</span>
        <h1>{title}</h1>
        <p>{description}</p>
      </div>
      <div className="intro-actions">{children}</div>
    </header>
  );
}
export function formatDate(value: string | null) {
  if (!value) return "기록 없음";
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? value
    : new Intl.DateTimeFormat("ko-KR", {
        timeZone: "Asia/Seoul",
        month: "short",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
      }).format(date);
}

const queuePositions = new Map<string, number>();
export function ScrollList({
  ready = true,
  children,
}: {
  ready?: boolean;
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const params = useSearchParams();
  const key =
    pathname +
    ":" +
    ["type", "filter", "query", "cursor", "tab", "source", "kind"]
      .map((k) => k + "=" + (params.get(k) ?? ""))
      .join("&");
  const ref = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    if (ready && ref.current)
      ref.current.scrollTop = queuePositions.get(key) ?? 0;
  }, [key, ready]);
  return (
    <div
      ref={ref}
      className="queue-list"
      role="region"
      aria-label="목록 스크롤"
      tabIndex={0}
      onScroll={(e) => {
        if (ready) queuePositions.set(key, e.currentTarget.scrollTop);
      }}
    >
      {children}
    </div>
  );
}
