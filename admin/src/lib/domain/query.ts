/** Detail/context state must not remount a queue or discard local panel state. */
export function listQuery(query: string): string {
  const params = new URLSearchParams(query);
  for (const key of ["id", "paper", "sentence"]) params.delete(key);
  return params.toString();
}
