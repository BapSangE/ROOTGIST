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

import { patchReviewQuery } from "@/lib/domain/query";
it("filter edits clear the old cursor while sentence changes preserve it", () => {
  expect(
    patchReviewQuery("type=occurrence&cursor=old&id=x", {
      query: "한국어",
      id: null,
    }),
  ).toBe("type=occurrence&query=%ED%95%9C%EA%B5%AD%EC%96%B4");
  expect(patchReviewQuery("cursor=old&id=x", { sentence: "A02" })).toBe(
    "cursor=old&id=x&sentence=A02",
  );
});
