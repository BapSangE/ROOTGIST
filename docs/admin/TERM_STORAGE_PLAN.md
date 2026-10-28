# Term storage M4 implementation plan

Spec: docs/admin/OPERATING_SCOPE.md overrides the original full-content specification.
Global constraints: no production DB writes or cloud project; no Flutter/worker behavior changes in M4; no writes enabled until M5 protection and M6 integration. Existing checkout credentials stay in the original checkout.

## Task 1: Transactional term storage foundation

Files: one additive CLI-generated migration; supabase/tests/admin/test_term_storage.py.
Interface: private term control/drafts/audit; public service-only RPCs read, draft, command. Entities sense/candidate/paper (glossary only). Revision plus database-computed content hash; source snapshot explicit, no raw_response.
Write failing local PostgreSQL tests first. Verify rejected role, readiness gate, draft conflict, stale source hash, unknown fields, sense+aliases atomic patch, candidate approval pending sync, glossary span validation and idx/term conflict, duplicate operation ID concurrency, payload reuse conflict, rollback of multiple targets, approval invalidation.
Run: python3 -m unittest discover -s supabase/tests/admin -p 'test_*.py' -v
Expected: green; Docker isolated, no external DB URL accepted.

## Task 2: Server contract without enabling production writes

Files: admin/src/lib/domain/term-commands.ts, admin/src/lib/server/term-storage.ts, admin/tests/integration/term-storage.test.ts.
Interface: strict request validation and sanitized RPC errors; authenticated identity required; existing route remains 423 and capability=false. Never reuse R0 JSON.stringify hash as DB command hash.
Test first, then implement. Run npm test/lint/typecheck/build.
Expected: all pass, existing read-only behavior preserved.

## Task 3: Reviewable deployment package

Files: docs/admin/TERM_STORAGE_PACKAGE.md, progress.
Document migration, private privileges, rollback, readiness false, M5/M6 prerequisites and tests. Fresh independent whole-change review; important fixes RED to GREEN. No commit, push, deployment or production apply in this phase.
Expected: tested concrete M4 package for review before worker integration.
