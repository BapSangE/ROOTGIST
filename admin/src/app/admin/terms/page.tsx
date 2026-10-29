import { Suspense } from "react";
import { TermsWorkbench } from "@/components/terms-workbench";
export default function Page() {
  return (
    <Suspense fallback={<p role="status">불러오는 중이에요.</p>}>
      <TermsWorkbench />
    </Suspense>
  );
}
