import { it, expect } from "vitest";
import { listQuery } from "@/lib/domain/query";
it("selection and sentence changes do not invalidate or remount the same list", () => {
  const initial = listQuery("query=decoder&cursor=abc&limit=1");
  expect(
    listQuery(
      "query=decoder&cursor=abc&limit=1&id=paper-1&sentence=A02&paper=paper-1",
    ),
  ).toBe(initial);
  expect(initial).toBe("query=decoder&cursor=abc&limit=1");
  expect(listQuery("query=encoder&cursor=abc&limit=1")).not.toBe(initial);
});
