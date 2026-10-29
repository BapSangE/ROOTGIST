"""Local-only contract tests. Never accepts a connection URL or production secret."""
import concurrent.futures
import json
from pathlib import Path
import subprocess
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[3]
CONTAINER = "rootgist-term-contract-m4"
ACTOR = "11111111-1111-4111-8111-111111111111"


def sql(query, *, ok=True):
    result = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "psql", "-X", "-U", "postgres", "-d", "postgres", "-qAt", "-v", "ON_ERROR_STOP=1"],
        input=query, text=True, capture_output=True, check=False,
    )
    if ok and result.returncode:
        raise AssertionError(result.stderr)
    if not ok:
        if not result.returncode:
            raise AssertionError("query unexpectedly succeeded")
        return result.stderr
    return result.stdout.strip()


def literal(value):
    return "'" + json.dumps(value, ensure_ascii=False).replace("'", "''") + "'::jsonb"


def snapshot(kind="sense", key="S1"):
    return json.loads(sql(f"set role service_role; select public.admin_read_term_target('{kind}', '{key}');"))


def target(patch, kind="sense", key="S1"):
    state = snapshot(kind, key)
    return dict(entity_type=kind, entity_key=key, expected_revision=state["revision"], base_sha256=state["base_sha256"], patch=patch)


def command(targets, action="apply_patch", operation=None, actor=ACTOR, ok=True, reason="synthetic contract test"):
    request = dict(action=action, targets=targets, reason=reason)
    op = operation or str(uuid.uuid4())
    value = sql(f"set role service_role; select public.admin_execute_term_command('{actor}', '{op}', {literal(request)});", ok=ok)
    return json.loads(value) if ok else value


class TermStorage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        metadata = json.loads(subprocess.check_output(["docker", "inspect", CONTAINER], text=True))[0]
        assert metadata["HostConfig"]["NetworkMode"] == "none"
        assert metadata["Config"]["Labels"].get("rootgist.test") == "term-storage"
        sql("drop schema if exists rootgist_admin cascade; drop schema public cascade; create schema public; "
            "do $$ begin if not exists(select from pg_roles where rolname='anon') then create role anon; create role authenticated; create role service_role bypassrls; end if; end $$;")
        for migration in sorted((ROOT / "supabase/migrations").glob("*.sql")):
            sql(migration.read_text())
        sql("grant usage on schema public to anon, authenticated, service_role; grant select,insert,update,delete on all tables in schema public to service_role;")
        status=json.loads(sql("set role service_role; select public.admin_term_storage_status();"))
        # 20261029150000: 워커 보호가 DB 트리거로 들어가 쓰기 준비는 켜져 있고, 관리자 UUID는 서버가 처음 저장할 때 등록한다
        assert status==dict(schema_version=1,worker_contract_version=1,writes_enabled=True,administrator_configured=False)

    def setUp(self):
        sql("truncate rootgist_admin.audit, rootgist_admin.drafts, rootgist_admin.control, rootgist_admin.occurrence_review; "
            f"update rootgist_admin.runtime set admin_user_id='{ACTOR}', writes_enabled=true, worker_contract_version=1; "
            "truncate public.papers,public.terms,public.term_candidates cascade; "
            "insert into public.papers(paper_id,title_en,abstract_en,abstract_sha256,published_at) values('P1','Synthetic paper','Alpha term.','synthetic-sha',now()); "
            "insert into public.paper_ai(paper_id,abstract_sha256,status) values('P1','synthetic-sha','ready'); "
            "insert into public.paper_sentences values('P1','A01',0,11,'text','test'); "
            "insert into public.paper_translations values('P1','A01','알파 용어를 설명해요.'); "
            "insert into public.terms(term_id,canonical_en) values('T1','alpha'),('T2','beta'); "
            "insert into public.term_senses(sense_id,term_id,canonical_ko,definition_ko,definition_kind,ai_review_status,review_status) values('S1','T1','알파','가상 정의','ai_rewritten','first_pass_complete','approved'),('S2','T2','베타','가상 정의','ai_rewritten','first_pass_complete','pending'); "
            "insert into public.term_aliases(alias_id,sense_id,surface_form,relation_type,review_status,auto_match_allowed) values('A1','S1','alpha','canonical','approved',true),('A2','S2','beta','canonical','approved',true); "
            "insert into public.paper_glossary(paper_id,idx,term,definition_ko,context_ko,sentence_ids,highlight,sense_id,ko_span) values('P1',0,'alpha','가상 정의','가상 문맥',array['A01'],true,'S1','알파'); "
            "insert into public.term_candidates(normalized_form,surface_form,definition_ko,first_paper_id) values('gamma','gamma','가상 정의','P1');")

    def test_worker_cannot_overwrite_reviewed_sense_or_alias(self):
        command([target({"canonical_ko": "사람 표기"})], action="approve")
        # 배치 워커(서비스 키 REST): 검수한 의미의 표기·상태는 그대로, 검수 안 한 의미는 바뀐다
        sql("set role service_role; update public.term_senses set canonical_ko='배치 값', review_status='pending' where sense_id in ('S1','S2');")
        self.assertEqual(sql("select canonical_ko||'/'||review_status from public.term_senses where sense_id='S1';"), "사람 표기/approved")
        self.assertEqual(sql("select canonical_ko from public.term_senses where sense_id='S2';"), "배치 값")
        sql("set role service_role; insert into public.term_aliases(alias_id,sense_id,surface_form,relation_type,review_status,auto_match_allowed) values('A9','S1','alfa','alias','approved',true);")
        sql("set role service_role; delete from public.term_aliases where alias_id='A1';")
        self.assertEqual(sql("select string_agg(alias_id, ',' order by alias_id) from public.term_aliases where sense_id='S1';"), "A1")
        # 사람이 SQL 편집기로 고치는 것(서비스 키가 아닌 역할)은 막지 않는다
        sql("update public.term_senses set canonical_ko='수동 수정' where sense_id='S1';")
        self.assertEqual(sql("select canonical_ko from public.term_senses where sense_id='S1';"), "수동 수정")

    def test_worker_keeps_reviewed_candidate_but_can_promote(self):
        command([target({"canonical_ko": "감마", "definition_ko": "사람 정의"}, "candidate", "gamma")], action="approve")
        sql("set role service_role; update public.term_candidates set definition_ko='배치 정의', review_status='pending', seen_count=9 where normalized_form='gamma';")
        self.assertEqual(sql("select definition_ko||'/'||review_status||'/'||seen_count from public.term_candidates where normalized_form='gamma';"), "사람 정의/approved/9")
        sql("set role service_role; delete from public.term_candidates where normalized_form='gamma';")  # 안 보이는 후보 정리
        self.assertEqual(sql("select count(*) from public.term_candidates where normalized_form='gamma';"), "1")
        sql("set role service_role; update public.term_candidates set sense_id='S2' where normalized_form='gamma';")  # 사전 승격 연결
        self.assertEqual(sql("select sense_id from public.term_candidates where normalized_form='gamma';"), "S2")

    def test_reviewed_occurrence_survives_worker_but_regeneration_resets_it(self):
        base = dict(idx=0, expected_term="alpha", ko_span="알파 용어")
        command([target({"glossary": [base]}, "paper", "P1")])
        marks = json.loads(sql("set role service_role; select public.admin_term_review_marks();"))
        self.assertEqual([(m["paper_id"], m["idx"]) for m in marks["occurrences"]], [("P1", 0)])
        sql("set role service_role; update public.paper_glossary set ko_span='배치 표기', sense_id=null where paper_id='P1';")
        self.assertEqual(sql("select ko_span||'/'||sense_id from public.paper_glossary where paper_id='P1';"), "알파 용어/S1")
        # 논문을 다시 만들면(지우고 다시 넣기) 막지 않고, 검수 표시만 지워 다시 검수 대상으로
        sql("set role service_role; delete from public.paper_glossary where paper_id='P1'; "
            "insert into public.paper_glossary(paper_id,idx,term,definition_ko,context_ko,sentence_ids,highlight) values('P1',0,'alpha','새 정의','새 문맥',array['A01'],true);")
        self.assertEqual(sql("select count(*) from rootgist_admin.occurrence_review;"), "0")
        sql("set role service_role; update public.paper_glossary set ko_span='알파' where paper_id='P1';")
        self.assertEqual(sql("select ko_span from public.paper_glossary where paper_id='P1';"), "알파")

    def test_writer_claim_is_one_time(self):
        sql("update rootgist_admin.runtime set admin_user_id=null;")
        other = str(uuid.uuid4())
        self.assertEqual(sql(f"set role service_role; select public.admin_claim_term_writer('{ACTOR}');"), "t")
        self.assertEqual(sql(f"set role service_role; select public.admin_claim_term_writer('{other}');"), "f")
        self.assertEqual(sql("select admin_user_id from rootgist_admin.runtime;"), ACTOR)
        for role in ["anon", "authenticated"]:
            self.assertIn("permission denied", sql(f"set role {role}; select public.admin_claim_term_writer('{other}');", ok=False))
            self.assertIn("permission denied", sql(f"set role {role}; select public.admin_term_review_marks();", ok=False))

    def test_private_permissions_and_false_readiness(self):
        for role in ["anon", "authenticated"]:
            self.assertIn("permission denied", sql(f"set role {role}; select public.admin_read_term_target('sense','S1');", ok=False))
            self.assertIn("permission denied", sql(f"set role {role}; select * from rootgist_admin.audit;", ok=False))
        sql("update rootgist_admin.runtime set writes_enabled=false;")
        self.assertIn("WRITES_NOT_READY", command([target({"canonical_ko": "바뀐 값"})], ok=False))
        sql("update rootgist_admin.runtime set writes_enabled=true, worker_contract_version=0;")
        self.assertIn("WRITES_NOT_READY", command([target({"canonical_ko": "바뀐 값"})], ok=False))
        sql("update rootgist_admin.runtime set worker_contract_version=1;")
        self.assertIn("ADMIN_ONLY", command([target({"canonical_ko": "바뀐 값"})], actor=str(uuid.uuid4()), ok=False))

    def test_atomic_sense_alias_patch_and_review_invalidation(self):
        aliases = [dict(alias_id="A1",surface_form="alpha",normalized_form="alpha",relation_type="canonical",review_status="approved",auto_match_allowed=True)]
        result = command([target({"canonical_ko": "알파 수정", "aliases": aliases})])
        self.assertEqual(result["targets"][0]["revision"], 1)
        self.assertEqual(snapshot()["value"]["sense"]["review_status"], "pending")
        self.assertEqual(sql("select protected from rootgist_admin.control where entity_key='S1';"), "t")
        self.assertEqual(sql("select count(*) from rootgist_admin.audit;"), "1")
        self.assertEqual(sql("select changes->0->'before_values'->>'canonical_ko' from rootgist_admin.audit;"), "알파")
        command([target({"review_note_ko": "메모만"})], action="approve")
        command([target({"review_note_ko": "메모 변경"})])
        self.assertEqual(snapshot()["value"]["sense"]["review_status"], "approved")

    def test_unknown_fields_alias_ownership_and_unapproved_auto_match_rejected(self):
        for patch in [{"title_ko":"forbidden"}, {"aliases":[dict(alias_id="A2",surface_form="beta",relation_type="alias",review_status="approved",auto_match_allowed=True)]}, {"aliases":[dict(alias_id="A3",surface_form="x",relation_type="alias",review_status="pending",auto_match_allowed=True)]}]:
            self.assertIn("VALIDATION_FAILED", command([target(patch)], ok=False))
        self.assertEqual(sql("select count(*) from rootgist_admin.audit;"), "0")

    def test_candidate_approval_is_dictionary_sync_pending(self):
        result = command([target({"canonical_ko":"감마"}, "candidate", "gamma")], action="approve")
        self.assertTrue(result["dictionary_sync_pending"])
        self.assertEqual(snapshot("candidate", "gamma")["value"]["review_status"], "approved")
        self.assertEqual(sql("select count(*) from public.term_senses;"), "2")

    def test_occurrence_span_validation_and_stale_term(self):
        base = dict(idx=0,expected_term="alpha",ko_span="용어",sentence_ids=["A01"],sense_id="S1",highlight=True)
        command([target({"glossary":[base]}, "paper", "P1")])
        self.assertEqual(sql("select ko_span from public.paper_glossary where paper_id='P1';"), "용어")
        for changes, error in [({"ko_span":"없는 표기"}, "VALIDATION_FAILED"), ({"sentence_ids":["A99"]}, "VALIDATION_FAILED"), ({"expected_term":"different"}, "REVISION_CONFLICT")]:
            self.assertIn(error, command([target({"glossary":[dict(base,**changes)]}, "paper", "P1")], ok=False))
        command([target({"glossary":[dict(base,ko_span="")]}, "paper", "P1")])
        self.assertEqual(sql("select ko_span='' from public.paper_glossary where paper_id='P1';"), "t")
        command([target({"glossary":[dict(base,ko_span=None)]}, "paper", "P1")])
        self.assertEqual(sql("select ko_span is null from public.paper_glossary where paper_id='P1';"), "t")

    def test_stale_source_hash_and_revision(self):
        stale = target({"canonical_ko":"최종"})
        sql("update public.term_senses set definition_ko='direct DB change' where sense_id='S1';")
        self.assertIn("REVISION_CONFLICT", command([stale], ok=False))
        current = target({"canonical_ko":"새 값"})
        command([current])
        self.assertIn("REVISION_CONFLICT", command([current], ok=False))

    def test_operation_id_concurrency_and_payload_reuse(self):
        targets=[target({"canonical_ko":"한 번만"})]
        operation=str(uuid.uuid4())
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(lambda _:command(targets,operation=operation),range(2)))
        self.assertEqual(results[0],results[1])
        self.assertEqual(snapshot()["revision"],1)
        self.assertEqual(sql("select count(*) from rootgist_admin.audit;"),"1")
        changed=dict(targets[0],patch={"canonical_ko":"다른 요청"})
        self.assertIn("OPERATION_ID_REUSED",command([changed],operation=operation,ok=False))

    def test_multi_target_rollback_and_duplicate_targets(self):
        before=snapshot()
        self.assertIn("VALIDATION_FAILED",command([target({"canonical_ko":"반영 안 됨"}),target({"illegal":True},key="S2")],ok=False))
        self.assertEqual(snapshot(),before)
        self.assertEqual(sql("select count(*) from rootgist_admin.audit;"),"0")
        t=target({"canonical_ko":"중복"})
        self.assertIn("VALIDATION_FAILED",command([t,t],ok=False))

    def test_multi_target_result_hashes_include_all_changes(self):
        targets=[target({"canonical_ko":"알파 새 표기"}),target({"glossary":[dict(idx=0,expected_term="alpha",ko_span="용어")]},"paper","P1")]
        result=command(targets)
        for item in result["targets"]:
            self.assertEqual(item["base_sha256"],snapshot(item["entity_type"],item["entity_key"])["base_sha256"])

    def test_invalid_scalar_types_are_validation_errors(self):
        for patch in [{"aliases":[dict(alias_id="X",surface_form=12,relation_type="alias",review_status="approved",auto_match_allowed=False)]}, {"canonical_ko":True}]:
            self.assertIn("VALIDATION_FAILED",command([target(patch)],ok=False))

    def test_first_note_only_edit_preserves_existing_approval(self):
        command([target({"review_note_ko":"첫 메모"})])
        self.assertEqual(snapshot()["value"]["sense"]["review_status"],"approved")

    def test_concurrent_alias_creation_cannot_mutate_another_sense(self):
        def alias(surface):
            return dict(alias_id="NEW",surface_form=surface,relation_type="alias",review_status="pending",auto_match_allowed=False)
        first=dict(action="apply_patch",targets=[target({"aliases":[alias("first")]})],reason="first")
        second=[target({"aliases":[alias("second")]},key="S2")]
        query=f"begin; set role service_role; select public.admin_execute_term_command('{ACTOR}','{uuid.uuid4()}',{literal(first)}); select pg_sleep(0.7); commit;"
        process=subprocess.Popen(["docker","exec","-i",CONTAINER,"psql","-X","-U","postgres","-qAt","-v","ON_ERROR_STOP=1"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        process.stdin.write(query);process.stdin.close()
        self.assertIn('operation_id',process.stdout.readline())
        try:
            error=command(second,ok=False)
        finally:
            process.wait(timeout=5)
            stderr=process.stderr.read()
            process.stdout.close();process.stderr.close()
        self.assertEqual(process.returncode,0,stderr)
        self.assertTrue('REVISION_CONFLICT' in error or 'VALIDATION_FAILED' in error)
        self.assertEqual(sql("select sense_id||':'||surface_form from public.term_aliases where alias_id='NEW';"),'S1:first')

    def test_sentence_change_revalidates_inherited_span(self):
        sql("insert into public.paper_sentences values('P1','A02',0,11,'text','test'); insert into public.paper_translations values('P1','A02','다른 문장이에요.');")
        patch={"glossary":[dict(idx=0,expected_term="alpha",sentence_ids=["A02"])]}
        self.assertIn('VALIDATION_FAILED',command([target(patch,'paper','P1')],ok=False))
        patch['glossary'][0]['ko_span']=None
        command([target(patch,'paper','P1')])
        self.assertEqual(sql("select ko_span is null from public.paper_glossary where paper_id='P1';"),'t')

    def test_audit_retains_review_decision_and_reason_after_later_edit(self):
        first=command([target({},key='S2')],action='approve',reason='approval reason')
        command([target({},key='S2')],action='needs_changes',reason='later reason')
        history=json.loads(sql("set role service_role; select public.admin_term_history('sense','S2');"))
        change=next(r for r in history['rows'] if r['operation_id']==first['operation_id'])['changes'][0]
        self.assertEqual(change.get('action'),'approve')
        self.assertEqual(change.get('reason'),'approval reason')
        self.assertEqual(change.get('before_review_state'),'pending')
        self.assertEqual(change.get('after_review_state'),'approved')

    def test_shared_source_dependencies_cannot_deadlock_reverse_batches(self):
        sql("update public.paper_glossary set sense_id='S2' where paper_id='P1'; insert into public.papers select 'P2',title_en,abstract_en,abstract_sha256,authors,org_name,published_at,withdrawn,thumbnail_url,media_urls from public.papers where paper_id='P1'; insert into public.paper_ai(paper_id,abstract_sha256,status) values('P2','synthetic-sha','ready'); insert into public.paper_sentences select 'P2',sentence_id,start_offset,end_offset,kind,splitter_version from public.paper_sentences where paper_id='P1'; insert into public.paper_translations select 'P2',sentence_id,translation_ko from public.paper_translations where paper_id='P1'; insert into public.paper_glossary(paper_id,idx,term,definition_ko,context_ko,sentence_ids,highlight,sense_id,ko_span) values('P2',0,'alpha','가상 정의','가상 문맥',array['A01'],true,'S1','알파');")
        targets=[]
        for paper,sense in [('P1','S1'),('P2','S2')]:
            targets.append([target({'glossary':[dict(idx=0,expected_term='alpha',ko_span='용어')]},'paper',paper),target({'canonical_ko':'changed '+sense},key=sense)])
        # Delay only inside this disposable test DB to force the lock interleaving.
        sql("alter function rootgist_admin.lock_source(text,text) rename to lock_source_without_delay; create function rootgist_admin.lock_source(kind text,key text) returns void language plpgsql as $$ begin perform rootgist_admin.lock_source_without_delay(kind,key); if kind='paper' then perform pg_sleep(0.4); end if; end $$; grant execute on function rootgist_admin.lock_source(text,text) to service_role;")
        def run(items):
            try:return command(items)
            except AssertionError as e:return str(e)
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool: results=list(pool.map(run,targets))
        finally:
            sql("drop function rootgist_admin.lock_source(text,text); alter function rootgist_admin.lock_source_without_delay(text,text) rename to lock_source;")
        self.assertTrue(any(isinstance(r,dict) for r in results))
        for result in results:
            if isinstance(result,str):self.assertIn('REVISION_CONFLICT',result)

    def test_draft_revision_and_source_conflict(self):
        state=snapshot()
        # First save at revision 0, second stale revision 0 conflicts.
        query=f"set role service_role; select public.admin_save_term_draft('{ACTOR}','sense','S1',0,'{state['base_sha256']}',0,{literal({'canonical_ko':'초안'})});"
        first=json.loads(sql(query))
        self.assertEqual(first["draft_revision"],1)
        self.assertEqual(json.loads(sql(f"set role service_role; select public.admin_read_term_draft('{ACTOR}','sense','S1');"))["draft_revision"],1)
        self.assertIn("DRAFT_CONFLICT",sql(query,ok=False))
        command([target({"canonical_ko":"새 원본"})])
        self.assertIn("REVISION_CONFLICT",sql(query.replace(",0,",",1,",1),ok=False))

    def test_history_is_scoped_paginated_and_has_no_original_paper_body(self):
        for value in ['첫 수정','다음 수정']:
            command([target({"canonical_ko":value})])
        history=json.loads(sql("set role service_role; select public.admin_term_history('sense','S1',null,null,1);"))
        self.assertEqual(len(history["rows"]),1)
        cursor=history["next_cursor"]
        second=json.loads(sql(f"set role service_role; select public.admin_term_history('sense','S1','{cursor['at']}','{cursor['id']}',1);"))
        self.assertEqual(len(second["rows"]),1)
        self.assertNotEqual(history['rows'][0]['operation_id'],second['rows'][0]['operation_id'])
        command([target({"glossary":[dict(idx=0,expected_term="alpha",ko_span="용어")]},"paper","P1")])
        paper=json.loads(sql("set role service_role; select public.admin_term_history('paper','P1');"))
        self.assertNotIn('Alpha term.',json.dumps(paper))
        self.assertNotIn('알파 용어를 설명해요.',json.dumps(paper,ensure_ascii=False))

    def test_existing_app_read_rpc_stays_compatible(self):
        before=json.loads(sql("set role anon; select public.get_paper('P1');"))
        command([target({'glossary':[dict(idx=0,expected_term='alpha',ko_span='용어')]},'paper','P1')])
        after=json.loads(sql("set role anon; select public.get_paper('P1');"))
        self.assertEqual(after['glossary'][0]['term_ko_span'],'용어')
        self.assertEqual(after['sentences'],before['sentences'])
        self.assertEqual(after['summary_ko'],before['summary_ko'])


if __name__ == "__main__":
    unittest.main()
