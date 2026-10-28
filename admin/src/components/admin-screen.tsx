"use client";
import { TermsWorkbench } from "./terms-workbench";
import {
  DashboardScreen,
  PaperScreen,
  NewsScreen,
  NoticesScreen,
  OperationsScreen,
} from "./content-screens";
export function AdminScreen({ view }: { view: string }) {
  switch (view) {
    case "terms":
      return <TermsWorkbench />;
    case "papers":
      return <PaperScreen />;
    case "news":
      return <NewsScreen />;
    case "notices":
      return <NoticesScreen />;
    case "operations":
      return <OperationsScreen />;
    default:
      return <DashboardScreen />;
  }
}
