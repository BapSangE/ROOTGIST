-- 용어 검수 저장 켜기(M5 수정본 보호 + M6 저장 연결, 2026-10-29).
-- 1) 워커 보호: 관리자가 검수한 용어 값은 배치(서비스 키 REST 쓰기)가 바꾸거나 지우지 못하게 DB 트리거로 막는다.
--    워커 코드가 어떤 경로로 쓰든 같은 규칙이 걸린다. 관리자 command는 같은 트랜잭션에서만 rootgist.admin_write를 켠다.
-- 2) 적용 위치 검수 표시: 논문 용어(paper_id, idx)마다 검수한 시각을 남긴다. 논문을 다시 만들어 그 행이 지워지면 표시도 지워져
--    다시 검수 대상으로 돌아간다(바뀐 번역에 옛 표기를 맹목적으로 다시 쓰지 않는다).
-- 3) 준비 상태: worker_contract_version=1, writes_enabled=true. 관리자 UUID는 저장소에 적지 않고, 서버가 처음 저장할 때
--    서버 환경값(ADMIN_USER_ID)으로 한 번만 등록한다(admin_claim_term_writer). 이미 등록돼 있으면 바꾸지 않는다.

create table rootgist_admin.occurrence_review (
  paper_id text not null,
  idx integer not null,
  term text not null,
  reviewed_by uuid not null,
  reviewed_at timestamptz not null default now(),
  primary key (paper_id, idx)
);
alter table rootgist_admin.occurrence_review enable row level security;
revoke all on rootgist_admin.occurrence_review from public, anon, authenticated;
grant select, insert, update, delete on rootgist_admin.occurrence_review to service_role;

-- 보호를 건너뛰는 경우: 관리자 command 안(rootgist.admin_write), 또는 서비스 키가 아닌 역할(마이그레이션·SQL 편집기의 수동 수정).
-- 배치 워커는 서비스 키(service_role)로 REST를 부르므로 늘 보호를 받는다.
create function rootgist_admin.admin_writing() returns boolean
language sql stable set search_path='' as $$
  select coalesce(current_setting('rootgist.admin_write', true), '') = 'on' or current_user <> 'service_role';
$$;

create function rootgist_admin.protected_entity(kind text, key text) returns boolean
language sql stable set search_path='' as $$
  select exists(select from rootgist_admin.control c where c.entity_type = kind and c.entity_key = key and c.protected);
$$;

-- 사전 의미: 사람이 손댄 의미의 표기·정의·검토 상태는 배치가 바꾸지 못한다. 지우기도 막는다.
create function rootgist_admin.guard_sense() returns trigger
language plpgsql set search_path='' as $$
begin
  if rootgist_admin.admin_writing() or not rootgist_admin.protected_entity('sense', old.sense_id) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'DELETE' then return null; end if;
  new.canonical_ko := old.canonical_ko; new.definition_ko := old.definition_ko; new.definition_kind := old.definition_kind;
  new.scope := old.scope; new.domain := old.domain; new.full_form_en := old.full_form_en;
  new.review_note_ko := old.review_note_ko; new.review_status := old.review_status;
  new.source_media_review_required := old.source_media_review_required;
  return new;
end;
$$;
create trigger guard_reviewed_sense before update or delete on public.term_senses
  for each row execute function rootgist_admin.guard_sense();

-- 별칭: 검수한 의미의 별칭은 배치가 고치거나 지우거나 새로 붙이지 못한다(사전 재수입이 지운 별칭을 되살리지 않게).
create function rootgist_admin.guard_alias() returns trigger
language plpgsql set search_path='' as $$
declare sense text := case when tg_op = 'INSERT' then new.sense_id else old.sense_id end;
begin
  if rootgist_admin.admin_writing() or not rootgist_admin.protected_entity('sense', sense) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  return case when tg_op = 'UPDATE' then old else null end;
end;
$$;
create trigger guard_reviewed_alias before insert or update or delete on public.term_aliases
  for each row execute function rootgist_admin.guard_alias();

-- 후보: 검수한 후보의 표기·정의·검토 상태를 지키고, 「더 이상 안 보이는 후보」 정리로 지워지지 않게 한다.
-- 사전 승격(sense_id 연결)·출현 수 갱신은 그대로 받는다.
create function rootgist_admin.guard_candidate() returns trigger
language plpgsql set search_path='' as $$
begin
  if rootgist_admin.admin_writing() or not rootgist_admin.protected_entity('candidate', old.normalized_form) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'DELETE' then return null; end if;
  new.canonical_ko := old.canonical_ko; new.definition_ko := old.definition_ko; new.full_form_en := old.full_form_en;
  new.review_status := old.review_status; new.surface_form := old.surface_form;
  return new;
end;
$$;
create trigger guard_reviewed_candidate before update or delete on public.term_candidates
  for each row execute function rootgist_admin.guard_candidate();

-- 논문 용어: 검수한 행(occurrence_review)의 적용 값은 배치가 바꾸지 못한다.
-- 논문을 다시 만들며 행을 지우는 것은 막지 않는다(자동 처리를 멈추지 않는다). 대신 검수 표시를 지워 다시 검수 대상이 된다.
create function rootgist_admin.guard_glossary() returns trigger
language plpgsql set search_path='' as $$
begin
  if rootgist_admin.admin_writing() then return case when tg_op = 'DELETE' then old else new end; end if;
  if tg_op = 'DELETE' then
    delete from rootgist_admin.occurrence_review r where r.paper_id = old.paper_id and r.idx = old.idx;
    return old;
  end if;
  if exists(select from rootgist_admin.occurrence_review r where r.paper_id = old.paper_id and r.idx = old.idx and r.term = old.term)
     and new.term = old.term then
    new.ko_span := old.ko_span; new.sense_id := old.sense_id; new.sentence_ids := old.sentence_ids;
    new.highlight := old.highlight; new.definition_ko := old.definition_ko; new.full_form_en := old.full_form_en;
  end if;
  return new;
end;
$$;
create trigger guard_reviewed_glossary before update or delete on public.paper_glossary
  for each row execute function rootgist_admin.guard_glossary();

-- 관리자 command의 원본 수정: 같은 트랜잭션 안에서만 보호를 건너뛰고, 논문 용어는 검수 표시를 남긴다.
-- 본문은 20261028125014의 apply_patch와 같다(앞의 set_config, 끝의 occurrence_review만 더했다).
create or replace function rootgist_admin.apply_patch(kind text,key text,patch jsonb) returns void
language plpgsql set search_path='' as $$
declare item jsonb;
begin
  perform set_config('rootgist.admin_write', 'on', true);
  if kind='sense' then
    update public.term_senses s set
      canonical_ko=case when patch?'canonical_ko' then patch->>'canonical_ko' else s.canonical_ko end,
      definition_ko=case when patch?'definition_ko' then patch->>'definition_ko' else s.definition_ko end,
      definition_kind=coalesce(patch->>'definition_kind',s.definition_kind),
      scope=case when patch?'scope' then patch->>'scope' else s.scope end,
      domain=case when patch?'domain' then patch->>'domain' else s.domain end,
      full_form_en=case when patch?'full_form_en' then patch->>'full_form_en' else s.full_form_en end,
      review_note_ko=case when patch?'review_note_ko' then patch->>'review_note_ko' else s.review_note_ko end,
      source_media_review_required=coalesce((patch->>'source_media_review_required')::boolean,s.source_media_review_required)
      where sense_id=key;
    if patch?'aliases' then
      delete from public.term_aliases where sense_id=key and alias_id not in(select x->>'alias_id' from jsonb_array_elements(patch->'aliases') x);
      for item in select * from jsonb_array_elements(patch->'aliases') loop
        insert into public.term_aliases(alias_id,sense_id,surface_form,normalized_form,relation_type,review_status,auto_match_allowed)
        values(item->>'alias_id',key,item->>'surface_form',item->>'normalized_form',item->>'relation_type',item->>'review_status',(item->>'auto_match_allowed')::boolean)
        on conflict(alias_id) do update set surface_form=excluded.surface_form,normalized_form=excluded.normalized_form,
          relation_type=excluded.relation_type,review_status=excluded.review_status,auto_match_allowed=excluded.auto_match_allowed
          where public.term_aliases.sense_id=excluded.sense_id;
        if not found then perform rootgist_admin.fail('PT409','REVISION_CONFLICT'); end if;
      end loop;
    end if;
  elsif kind='candidate' then
    update public.term_candidates c set canonical_ko=case when patch?'canonical_ko' then patch->>'canonical_ko' else c.canonical_ko end,
      definition_ko=case when patch?'definition_ko' then patch->>'definition_ko' else c.definition_ko end,
      full_form_en=case when patch?'full_form_en' then patch->>'full_form_en' else c.full_form_en end where normalized_form=key;
  else
    for item in select * from jsonb_array_elements(patch->'glossary') loop
      update public.paper_glossary g set ko_span=case when item?'ko_span' then item->>'ko_span' else g.ko_span end,
        sense_id=case when item?'sense_id' then item->>'sense_id' else g.sense_id end,
        sentence_ids=case when item?'sentence_ids' then array(select jsonb_array_elements_text(item->'sentence_ids')) else g.sentence_ids end,
        highlight=case when item?'highlight' then (item->>'highlight')::boolean else g.highlight end,
        definition_ko=case when item?'definition_ko' then item->>'definition_ko' else g.definition_ko end,
        full_form_en=case when item?'full_form_en' then item->>'full_form_en' else g.full_form_en end
        where paper_id=key and idx=(item->>'idx')::integer;
      insert into rootgist_admin.occurrence_review(paper_id, idx, term, reviewed_by)
        select key, (item->>'idx')::integer, item->>'expected_term', r.admin_user_id from rootgist_admin.runtime r where r.singleton
        on conflict (paper_id, idx) do update set term = excluded.term, reviewed_by = excluded.reviewed_by, reviewed_at = now();
    end loop;
  end if;
end;
$$;

-- 서버가 처음 저장할 때 관리자 UUID를 한 번만 등록한다. 이미 다른 값이 있으면 바꾸지 않고 false.
create function public.admin_claim_term_writer(actor uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare current uuid;
begin
  if actor is null then return false; end if;
  update rootgist_admin.runtime set admin_user_id = actor where singleton and admin_user_id is null;
  select admin_user_id into current from rootgist_admin.runtime where singleton;
  return current = actor;
end;
$$;

-- 목록 표시용: 검수한 적용 위치와 검수 상태(control). 원문·번역은 담지 않는다.
create function public.admin_term_review_marks() returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object(
    'occurrences', coalesce((select jsonb_agg(jsonb_build_object('paper_id', r.paper_id, 'idx', r.idx, 'term', r.term, 'reviewed_at', r.reviewed_at))
      from rootgist_admin.occurrence_review r), '[]'::jsonb),
    'controls', coalesce((select jsonb_agg(jsonb_build_object('entity_type', c.entity_type, 'entity_key', c.entity_key,
      'revision', c.revision, 'review_state', c.review_state, 'note', c.note, 'updated_at', c.updated_at))
      from rootgist_admin.control c), '[]'::jsonb));
$$;

revoke all on function rootgist_admin.admin_writing(), rootgist_admin.protected_entity(text,text) from public, anon, authenticated;
revoke all on function public.admin_claim_term_writer(uuid), public.admin_term_review_marks() from public, anon, authenticated;
grant execute on function public.admin_claim_term_writer(uuid), public.admin_term_review_marks() to service_role;
grant execute on function rootgist_admin.admin_writing(), rootgist_admin.protected_entity(text,text) to service_role;

update rootgist_admin.runtime set worker_contract_version = 1, writes_enabled = true where singleton;
