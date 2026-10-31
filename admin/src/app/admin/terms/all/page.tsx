import { Suspense } from "react";
import { TermsGlossary } from "@/components/terms-glossary";
export default function Page() {
  return (
    <Suspense fallback={<p role="status">불러오는 중이에요.</p>}>
      <TermsGlossary />
    </Suspense>
  );
}
