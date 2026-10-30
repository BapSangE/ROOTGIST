"""Supabase 저장 (HANDOFF 4.4). PostgREST를 비밀 키로 호출한다. 비밀 키는 RLS를 우회하므로 배치에서만 쓴다."""
import json
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone


class Db:
    def __init__(self, url: str, secret_key: str):
        # .env에 /rest/v1/까지 넣어도 받아 준다
        self.base = url.rstrip("/").removesuffix("/rest/v1") + "/rest/v1"
        self.headers = {"apikey": secret_key, "Authorization": f"Bearer {secret_key}", "Content-Type": "application/json"}

    def _req(self, method: str, path: str, body=None, prefer: str | None = None):
        headers = dict(self.headers, **({"Prefer": prefer} if prefer else {}))
        data = None if body is None else json.dumps(body, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(f"{self.base}/{path}", data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"Supabase {method} {path}: HTTP {e.code} {e.read()[:500].decode('utf-8', 'replace')}") from e

    def upsert(self, table: str, rows: list[dict], on_conflict: str):
        if rows:
            self._req("POST", f"{table}?on_conflict={on_conflict}", rows, "resolution=merge-duplicates,return=minimal")

    def insert_ignore(self, table: str, rows: list[dict], on_conflict: str):
        """이미 있는 키는 그대로 두고 새 행만 넣는다."""
        if rows:
            self._req("POST", f"{table}?on_conflict={on_conflict}", rows, "resolution=ignore-duplicates,return=minimal")

    def delete(self, table: str, **eq):
        q = "&".join(f"{k}=eq.{urllib.parse.quote(str(v))}" for k, v in eq.items())
        self._req("DELETE", f"{table}?{q}", prefer="return=minimal")

    def select(self, table: str, query: str) -> list[dict]:
        return self._req("GET", f"{table}?{query}")

    def select_all(self, table: str, query: str, page: int = 1000) -> list[dict]:
        """PostgREST는 한 번에 최대 1000행이라 나눠 받는다. query에 order가 있어야 페이지가 안정적이다."""
        rows, offset = [], 0
        while True:
            got = self.select(table, f"{query}&limit={page}&offset={offset}")
            rows += got
            if len(got) < page:
                return rows
            offset += page

    def update(self, table: str, values: dict, **eq):
        q = "&".join(f"{k}=eq.{urllib.parse.quote(str(v))}" for k, v in eq.items())
        self._req("PATCH", f"{table}?{q}", values, "return=minimal")

    def rpc(self, fn: str, **args):
        return self._req("POST", f"rpc/{fn}", args)

    # --- 배치용 ---

    def digest_papers(self, digest_date: str) -> list[dict]:
        """그날 이미 저장된 목록(다음 날 보충 판단용)."""
        return self.select("digest_papers", f"digest_date=eq.{digest_date}&select=paper_id,rank,is_exposed,upvotes_at_batch&order=rank")

    def save_paper_ai(self, paper_id: str, sha: str, sentences: list[dict], detail: dict, raw: dict | None, model: str | None, meta: dict):
        """문장·해설 저장. 하위 표는 지우고 다시 넣는다(다시 만들 때 남는 행이 없게)."""
        self.upsert("paper_sentences", [
            {"paper_id": paper_id, "sentence_id": s["sentence_id"], "start_offset": s["start"], "end_offset": s["end"],
             "kind": s["kind"], "splitter_version": meta["sentence_splitter_version"]}
            for s in sentences
        ], "paper_id,sentence_id")
        ready = detail["ai_status"] == "ready"
        self.upsert("paper_ai", [{
            "paper_id": paper_id, "abstract_sha256": sha, "status": detail["ai_status"],
            "title_ko": detail["title_ko"], "summary_ko": detail["summary_ko"],
            "topic_primary": detail["topic_primary"], "topic_secondary": detail["topic_secondary"],
            "limitations": detail.get("limitations", []), "model_id": model,
            "prompt_version": meta["prompt_version"], "schema_version": meta["schema_version"],
            "generated_at": datetime.now(timezone.utc).isoformat() if ready else None, "raw_response": raw,
        }], "paper_id")
        for t in ("paper_key_points", "paper_translations", "paper_glossary"):
            self.delete(t, paper_id=paper_id)
        if not ready:
            return
        self.upsert("paper_key_points", [
            {"paper_id": paper_id, "idx": i, "claim_ko": k["claim_ko"], "evidence_sentence_ids": k["evidence_sentence_ids"]}
            for i, k in enumerate(detail["key_points"])
        ], "paper_id,idx")
        self.upsert("paper_translations", [
            {"paper_id": paper_id, "sentence_id": s["sentence_id"], "translation_ko": s["translation_ko"]}
            for s in detail["sentences"] if s["translation_ko"] is not None
        ], "paper_id,sentence_id")
        difficulty = {g["term"]: g.get("term_difficulty") for g in (raw or {}).get("glossary", [])}
        self.upsert("paper_glossary", [
            {"paper_id": paper_id, "idx": i, "term": g["term"], "definition_ko": g["definition_ko"],
             "context_ko": g["context_ko"], "sentence_ids": g["sentence_ids"],
             "term_difficulty": difficulty.get(g["term"]), "highlight": g["highlight"],
             "full_form_en": g.get("full_form_en")}
            for i, g in enumerate(detail["glossary"])
        ], "paper_id,idx")
