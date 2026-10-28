import { Suspense } from "react";
import { AdminScreen } from "@/components/admin-screen";
export default function Page() {
  return (
    <Suspense fallback={<p role="status">불러오는 중이에요.</p>}>
      <AdminScreen view="papers" />
    </Suspense>
  );
}
