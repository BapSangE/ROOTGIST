"use client";
import { createContext, useContext } from "react";
const FixtureContext = createContext(false);
export function useAdminFixture() {
  return useContext(FixtureContext);
}
export function AdminShell({
  fixture,
  children,
}: {
  fixture: boolean;
  children: React.ReactNode;
}) {
  return (
    <FixtureContext.Provider value={fixture}>
      <div className="term-admin">
        <a className="skip" href="#content">
          검수 본문으로 이동
        </a>
        {children}
      </div>
    </FixtureContext.Provider>
  );
}
