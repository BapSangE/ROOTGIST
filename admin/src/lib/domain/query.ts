/** Detail/context state must not remount a queue or discard local panel state. */
export function listQuery(query: string): string {
  const params = new URLSearchParams(query);
  for (const key of ["id", "paper", "sentence"]) params.delete(key);
  return params.toString();
}

export function patchReviewQuery(
  current: string,
  changes: Record<string, string | null>,
): string {
  const next = new URLSearchParams(current);
  if (
    Object.keys(changes).some((k) =>
      ["query", "type", "filter", "tab", "source", "kind"].includes(k),
    )
  )
    next.delete("cursor");
  for (const [key, value] of Object.entries(changes))
    if (value === null || value === "") next.delete(key);
    else next.set(key, value);
  return next.toString();
}
