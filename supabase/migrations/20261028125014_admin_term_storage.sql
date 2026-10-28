-- M4 foundation only. NOT applied to production; worker/UI integration is required.
-- No SECURITY DEFINER, no public client access, and readiness defaults to false.
create schema rootgist_admin;
revoke all on schema rootgist_admin from public, anon, authenticated;
grant usage on schema rootgist_admin to service_role;

create table rootgist_admin.runtime (
  singleton boolean primary key default true check (singleton),
  schema_version integer not null default 1 check (schema_version = 1),
  admin_user_id uuid,
  worker_contract_version integer not null default 0,
  writes_enabled boolean not null default false
);
insert into rootgist_admin.runtime(singleton) values (true);
create table rootgist_admin.control (
  entity_type text not null check (entity_type in ('sense','candidate','paper')),
  entity_key text not null check (length(entity_key) between 1 and 300),
  revision bigint not null default 0 check (revision >= 0),
  review_state text not null default 'pending' check (review_state in ('pending','approved','needs_changes','rejected')),
  protected boolean not null default false,
  managed_fields text[] not null default '{}',
  protected_snapshot jsonb,
  reviewed_sha256 text,
  reviewed_by uuid,
  reviewed_at timestamptz,
  note text,
  updated_at timestamptz not null default now(),
  primary key(entity_type,entity_key)
);
create table rootgist_admin.drafts (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null,
  entity_type text not null,
  entity_key text not null,
  draft_revision bigint not null check (draft_revision > 0),
  base_revision bigint not null,
  base_sha256 text not null,
  payload jsonb not null,
  state text not null default 'active' check (state in ('active','accepted','discarded')),
  updated_at timestamptz not null default now(),
  foreign key(entity_type,entity_key) references rootgist_admin.control
);
create unique index admin_term_active_draft on rootgist_admin.drafts(actor_id,entity_type,entity_key) where state='active';
create table rootgist_admin.audit (
  operation_id uuid primary key,
  actor_id uuid not null,
  request_sha256 text not null,
  changes jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default now()
);
alter table rootgist_admin.runtime enable row level security;
alter table rootgist_admin.control enable row level security;
alter table rootgist_admin.drafts enable row level security;
alter table rootgist_admin.audit enable row level security;
revoke all on all tables in schema rootgist_admin from public, anon, authenticated;
grant select on rootgist_admin.runtime to service_role;
grant select,insert,update on rootgist_admin.control,rootgist_admin.drafts to service_role;
grant select,insert on rootgist_admin.audit to service_role;

create function rootgist_admin.fail(code text, message text) returns void
language plpgsql set search_path='' as $$
begin raise exception using errcode=code, message=message; end;
$$;
create function rootgist_admin.hash(value jsonb) returns text
language sql immutable strict set search_path='' as $$
  select encode(sha256(convert_to(value::text,'UTF8')),'hex');
$$;
create function rootgist_admin.require_writer(actor uuid) returns void
language plpgsql set search_path='' as $$
declare config rootgist_admin.runtime;
begin
  select * into strict config from rootgist_admin.runtime where singleton;
  if actor is null or actor is distinct from config.admin_user_id then
    perform rootgist_admin.fail('PT403','ADMIN_ONLY');
  end if;
  if not config.writes_enabled or config.worker_contract_version <> 1 then
    perform rootgist_admin.fail('PT423','WRITES_NOT_READY');
  end if;
end;
$$;

-- One human administrator: serialize the write protocol before any operation
-- or source lock. Paper display contexts can share senses outside their own
-- target sets. M5 worker transactions must acquire this SAME lock first.
create function rootgist_admin.lock_write_protocol() returns void
language sql volatile set search_path='' as $$
  select pg_advisory_xact_lock(hashtextextended('rootgist:term-storage:v1',0));
$$;

create function rootgist_admin.source(kind text, key text) returns jsonb
language plpgsql stable set search_path='' as $$
declare value jsonb;
begin
  if kind='sense' then
    select jsonb_build_object('sense',jsonb_build_object(
      'sense_id',s.sense_id,'term_id',s.term_id,'canonical_ko',s.canonical_ko,
      'definition_ko',s.definition_ko,'definition_kind',s.definition_kind,
      'review_status',s.review_status,'ai_review_status',s.ai_review_status,
      'scope',s.scope,'domain',s.domain,'full_form_en',s.full_form_en,
      'source_media_review_required',s.source_media_review_required,'review_note_ko',s.review_note_ko),
      'aliases',coalesce((select jsonb_agg(to_jsonb(a) order by a.alias_id) from public.term_aliases a where a.sense_id=s.sense_id),'[]'::jsonb))
      into value from public.term_senses s where s.sense_id=key;
  elsif kind='candidate' then
    select jsonb_build_object('normalized_form',c.normalized_form,'surface_form',c.surface_form,
      'canonical_ko',c.canonical_ko,'definition_ko',c.definition_ko,'review_status',c.review_status,
      'sense_id',c.sense_id,'first_paper_id',c.first_paper_id,'full_form_en',c.full_form_en,
      'canonical_ko_draft',c.canonical_ko_draft,'full_form_en_draft',c.full_form_en_draft,
      'seen_count',c.seen_count,'draft_model',c.draft_model)
      into value from public.term_candidates c where c.normalized_form=key;
  elsif kind='paper' then
    select jsonb_build_object('paper_id',p.paper_id,'abstract_en',p.abstract_en,'abstract_sha256',p.abstract_sha256,
      'sentences',coalesce((select jsonb_agg(to_jsonb(s) order by s.sentence_id) from public.paper_sentences s where s.paper_id=key),'[]'::jsonb),
      'translations',coalesce((select jsonb_agg(to_jsonb(t) order by t.sentence_id) from public.paper_translations t where t.paper_id=key),'[]'::jsonb),
      'glossary',coalesce((select jsonb_agg(to_jsonb(g) order by g.idx) from public.paper_glossary g where g.paper_id=key),'[]'::jsonb),
      'display_senses',coalesce((select jsonb_agg(jsonb_build_object('sense_id',s.sense_id,'canonical_ko',s.canonical_ko,
        'definition_kind',s.definition_kind,'review_status',s.review_status,'ai_review_status',s.ai_review_status) order by s.sense_id)
        from public.term_senses s where s.sense_id in(select g.sense_id from public.paper_glossary g where g.paper_id=key)),'[]'::jsonb),
      'show_ai_reviewed_terms',(select c.value from public.app_config c where c.key='show_ai_reviewed_terms'))
      into value from public.papers p where p.paper_id=key;
  else perform rootgist_admin.fail('PT422','VALIDATION_FAILED');
  end if;
  if value is null then perform rootgist_admin.fail('PT404','ENTITY_NOT_FOUND'); end if;
  return value;
end;
$$;

-- Lock order for one unit. All commands first lock controls in sorted order.
-- This is not a substitute for the M5 worker transaction integration.
create function rootgist_admin.lock_source(kind text,key text) returns void
language plpgsql set search_path='' as $$
begin
  if kind='sense' then
    perform 1 from public.term_senses where sense_id=key for update;
    perform 1 from public.term_aliases where sense_id=key order by alias_id for update;
  elsif kind='candidate' then
    perform 1 from public.term_candidates where normalized_form=key for update;
  elsif kind='paper' then
    perform 1 from public.papers where paper_id=key for update;
    perform 1 from public.paper_ai where paper_id=key for update;
    perform 1 from public.paper_sentences where paper_id=key order by sentence_id for update;
    perform 1 from public.paper_translations where paper_id=key order by sentence_id for update;
    perform 1 from public.paper_glossary where paper_id=key order by idx for update;
    perform 1 from public.term_senses where sense_id in(select g.sense_id from public.paper_glossary g where g.paper_id=key) order by sense_id for update;
    perform 1 from public.app_config where public.app_config.key='show_ai_reviewed_terms' for share;
  end if;
end;
$$;

create function public.admin_read_term_target(entity_type text,entity_key text) returns jsonb
language plpgsql set search_path='' as $$
declare value jsonb; rev bigint;
begin
  value:=rootgist_admin.source(entity_type,entity_key);
  select revision into rev from rootgist_admin.control c where c.entity_type=admin_read_term_target.entity_type and c.entity_key=admin_read_term_target.entity_key;
  return jsonb_build_object('value',value,'revision',coalesce(rev,0),'base_sha256',rootgist_admin.hash(value));
end;
$$;

create function rootgist_admin.validate_patch(kind text,key text,patch jsonb,strict boolean default true) returns void
language plpgsql set search_path='' as $$
declare field text; value jsonb; a jsonb; g jsonb; old public.paper_glossary; allowed text[]; effective_span text;
begin
  if jsonb_typeof(patch) is distinct from 'object' or octet_length(patch::text)>65536 then
    perform rootgist_admin.fail('PT422','VALIDATION_FAILED');
  end if;
  allowed:=case kind when 'sense' then array['canonical_ko','definition_ko','definition_kind','scope','domain','full_form_en','review_note_ko','aliases','source_media_review_required']
    when 'candidate' then array['canonical_ko','definition_ko','full_form_en']
    when 'paper' then array['glossary'] else '{}' end;
  for field,value in select * from jsonb_each(patch) loop
    if not field=any(allowed) then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
    if field='source_media_review_required' then
      if jsonb_typeof(value)<>'boolean' then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
    elsif field not in('aliases','glossary') then
      if jsonb_typeof(value) not in('string','null') or length(value#>>'{}')>20000 then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
      if field='definition_ko' and kind='candidate' and value='null'::jsonb then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
      if field='definition_kind' and coalesce(value#>>'{}','') not in('ai_rewritten','paper_glossary') then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
    end if;
  end loop;
  if patch ? 'aliases' then
    if jsonb_typeof(patch->'aliases')<>'array' or jsonb_array_length(patch->'aliases')>50 then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
    if (select count(*) from jsonb_array_elements(patch->'aliases'))<>(select count(distinct x->>'alias_id') from jsonb_array_elements(patch->'aliases') x) then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
    for a in select * from jsonb_array_elements(patch->'aliases') loop
      if jsonb_typeof(a)<>'object' or exists(select from jsonb_object_keys(a) f where f not in('alias_id','surface_form','normalized_form','relation_type','review_status','auto_match_allowed'))
        or exists(select from jsonb_each(a) f where f.key not in('normalized_form','auto_match_allowed') and jsonb_typeof(f.value)<>'string')
        or (a?'normalized_form' and jsonb_typeof(a->'normalized_form') not in('string','null'))
        or coalesce(a->>'alias_id','')='' or coalesce(a->>'surface_form','')='' or coalesce(a->>'relation_type','')=''
        or coalesce(a->>'review_status','') not in('pending','approved','rejected','deferred')
        or jsonb_typeof(a->'auto_match_allowed') is distinct from 'boolean'
        or ((a->>'auto_match_allowed')::boolean and a->>'review_status'<>'approved')
        or exists(select from public.term_aliases t where t.alias_id=a->>'alias_id' and t.sense_id<>key) then
        perform rootgist_admin.fail('PT422','VALIDATION_FAILED');
      end if;
    end loop;
  end if;
  if patch ? 'glossary' then
    if jsonb_typeof(patch->'glossary')<>'array' or jsonb_array_length(patch->'glossary') not between 1 and 50 then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
    if (select count(*) from jsonb_array_elements(patch->'glossary'))<>(select count(distinct x->>'idx') from jsonb_array_elements(patch->'glossary') x) then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
    for g in select * from jsonb_array_elements(patch->'glossary') loop
      if jsonb_typeof(g)<>'object' or exists(select from jsonb_object_keys(g) f where f not in('idx','expected_term','ko_span','sense_id','sentence_ids','highlight','definition_ko','full_form_en'))
        or coalesce(g->>'idx','')!~'^[0-9]+$' or length(g->>'idx')>8 or coalesce(g->>'expected_term','')='' then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
      select * into old from public.paper_glossary where paper_id=key and idx=(g->>'idx')::integer;
      if not found or old.term<>g->>'expected_term' then perform rootgist_admin.fail('PT409','REVISION_CONFLICT'); end if;
      if g ? 'sense_id' and jsonb_typeof(g->'sense_id')<>'null' and not exists(select from public.term_senses where sense_id=g->>'sense_id') then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
      if g ? 'highlight' and jsonb_typeof(g->'highlight')<>'boolean' then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
      if g ? 'sentence_ids' then
        if jsonb_typeof(g->'sentence_ids')<>'array' or jsonb_array_length(g->'sentence_ids')=0 or exists(
          select from jsonb_array_elements(g->'sentence_ids') id where jsonb_typeof(id)<>'string' or not exists(
            select from public.paper_sentences s where s.paper_id=key and s.kind='text' and s.sentence_id=id#>>'{}')) then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
      end if;
      for field in select unnest(array['ko_span','definition_ko','full_form_en']) loop
        if g ? field and (jsonb_typeof(g->field) not in('string','null') or length(g->>field)>20000 or (field='definition_ko' and g->field='null'::jsonb)) then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
      end loop;
      effective_span:=case when g?'ko_span' then g->>'ko_span' else old.ko_span end;
      if strict and coalesce(effective_span,'')<>'' and not exists(
        select from public.paper_translations t where t.paper_id=key and t.sentence_id in(
          select jsonb_array_elements_text(coalesce(g->'sentence_ids',to_jsonb(old.sentence_ids)))) and position(effective_span in t.translation_ko)>0) then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
    end loop;
  end if;
end;
$$;

create function rootgist_admin.apply_patch(kind text,key text,patch jsonb) returns void
language plpgsql set search_path='' as $$
declare item jsonb;
begin
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
    end loop;
  end if;
end;
$$;

create function public.admin_save_term_draft(actor uuid,entity_type text,entity_key text,
  expected_revision bigint,base_sha256 text,expected_draft_revision bigint,payload jsonb) returns jsonb
language plpgsql set search_path='' as $$
declare state jsonb; draft rootgist_admin.drafts;
begin
  perform rootgist_admin.require_writer(actor);
  perform rootgist_admin.lock_write_protocol();
  insert into rootgist_admin.control(entity_type,entity_key) values(entity_type,entity_key) on conflict do nothing;
  perform 1 from rootgist_admin.control c where c.entity_type=admin_save_term_draft.entity_type and c.entity_key=admin_save_term_draft.entity_key for update;
  perform rootgist_admin.lock_source(entity_type,entity_key);
  state:=public.admin_read_term_target(entity_type,entity_key);
  if expected_revision is distinct from (state->>'revision')::bigint or base_sha256 is distinct from state->>'base_sha256' then perform rootgist_admin.fail('PT409','REVISION_CONFLICT'); end if;
  perform rootgist_admin.validate_patch(entity_type,entity_key,payload,false);
  select * into draft from rootgist_admin.drafts d where actor_id=actor and d.entity_type=admin_save_term_draft.entity_type and d.entity_key=admin_save_term_draft.entity_key and d.state='active' for update;
  if expected_draft_revision is distinct from coalesce(draft.draft_revision,0) then perform rootgist_admin.fail('PT409','DRAFT_CONFLICT'); end if;
  if draft.id is null then
    insert into rootgist_admin.drafts(actor_id,entity_type,entity_key,draft_revision,base_revision,base_sha256,payload)
    values(actor,entity_type,entity_key,1,expected_revision,base_sha256,payload) returning * into draft;
  else
    update rootgist_admin.drafts d set draft_revision=d.draft_revision+1,payload=admin_save_term_draft.payload,base_revision=expected_revision,base_sha256=admin_save_term_draft.base_sha256,updated_at=now() where id=draft.id returning * into draft;
  end if;
  return jsonb_build_object('draft_id',draft.id,'draft_revision',draft.draft_revision,'saved_at',draft.updated_at);
end;
$$;

-- Audit only edited term values. Paper abstracts/translations/raw_response are
-- represented by hashes, never copied into the audit trail.
create function rootgist_admin.audit_values(kind text,source jsonb,patch jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare result jsonb; row jsonb; edit jsonb;
begin
  if kind='paper' then
    result:='[]';
    for edit in select * from jsonb_array_elements(patch->'glossary') loop
      select x into row from jsonb_array_elements(source->'glossary') x where x->'idx'=edit->'idx';
      result:=result||jsonb_build_array(jsonb_build_object('idx',row->'idx','term',row->'term','values',
        coalesce((select jsonb_object_agg(f.key,f.value) from jsonb_each(row) f where edit?f.key),'{}'::jsonb)));
    end loop;
    return jsonb_build_object('glossary',result);
  end if;
  select coalesce(jsonb_object_agg(f.key,f.value),'{}'::jsonb) into result from jsonb_each(case kind when 'sense' then source->'sense' else source end) f where patch?f.key;
  if patch?'aliases' then result:=result||jsonb_build_object('aliases',source->'aliases'); end if;
  return result;
end;
$$;

create function public.admin_execute_term_command(actor uuid,operation_id uuid,request jsonb) returns jsonb
language plpgsql set search_path='' as $$
declare requested_hash text; audit rootgist_admin.audit; target jsonb; before jsonb; after jsonb;
  rev bigint; kind text; key text; action text; patch jsonb; next_state text; before_state text; meaningful boolean;
  changes jsonb:='[]'; results jsonb:='[]'; result jsonb; pending_sync boolean:=false;
begin
  perform rootgist_admin.require_writer(actor);
  if operation_id is null or jsonb_typeof(request) is distinct from 'object' or octet_length(request::text)>65536
    or exists(select from jsonb_object_keys(request) f where f not in('action','targets','reason'))
    or coalesce(request->>'action','') not in('apply_patch','approve','reject','needs_changes')
    or jsonb_typeof(request->'targets') is distinct from 'array'
    or jsonb_array_length(request->'targets') not between 1 and 10
    or coalesce(length(request->>'reason'),0)>2000 then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
  action:=request->>'action'; requested_hash:=rootgist_admin.hash(jsonb_build_object('actor',actor,'request',request));
  perform rootgist_admin.lock_write_protocol();
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text,0));
  select * into audit from rootgist_admin.audit a where a.operation_id=admin_execute_term_command.operation_id;
  if audit.operation_id is not null then
    if audit.request_sha256<>requested_hash then perform rootgist_admin.fail('PT409','OPERATION_ID_REUSED'); end if;
    return audit.result;
  end if;
  if (select count(*) from jsonb_array_elements(request->'targets'))<>(select count(distinct (x->>'entity_type',x->>'entity_key')) from jsonb_array_elements(request->'targets') x) then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
  -- Validate all target envelopes before inserting or locking controls.
  for target in select * from jsonb_array_elements(request->'targets') loop
    if jsonb_typeof(target)<>'object' or exists(select from jsonb_object_keys(target) f where f not in('entity_type','entity_key','expected_revision','base_sha256','patch'))
      or jsonb_typeof(target->'entity_type') is distinct from 'string' or jsonb_typeof(target->'entity_key') is distinct from 'string'
      or jsonb_typeof(target->'expected_revision') is distinct from 'number' or jsonb_typeof(target->'base_sha256') is distinct from 'string'
      or coalesce(target->>'entity_type','') not in('sense','candidate','paper') or coalesce(length(target->>'entity_key'),0) not between 1 and 300
      or coalesce(target->>'expected_revision','')!~'^[0-9]{1,15}$' or coalesce(target->>'base_sha256','')!~'^[0-9a-f]{64}$'
      or jsonb_typeof(target->'patch') is distinct from 'object' or (target->>'entity_type'='paper' and action<>'apply_patch') then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
  end loop;
  for target in select x from jsonb_array_elements(request->'targets') x order by x->>'entity_type',x->>'entity_key' loop
    kind:=target->>'entity_type'; key:=target->>'entity_key';
    insert into rootgist_admin.control(entity_type,entity_key) values(kind,key) on conflict do nothing;
    perform 1 from rootgist_admin.control c where c.entity_type=kind and c.entity_key=key for update;
  end loop;
  for target in select x from jsonb_array_elements(request->'targets') x order by x->>'entity_type',x->>'entity_key' loop
    kind:=target->>'entity_type'; key:=target->>'entity_key'; patch:=target->'patch';
    perform rootgist_admin.lock_source(kind,key);
    before:=rootgist_admin.source(kind,key);
    select revision,review_state into rev,next_state from rootgist_admin.control c where c.entity_type=kind and c.entity_key=key;
    if rev=0 and kind in('sense','candidate') then
      next_state:=case coalesce(case kind when 'sense' then before#>>'{sense,review_status}' else before->>'review_status' end,'pending')
        when 'approved' then 'approved' when 'rejected' then 'rejected' when 'deferred' then 'needs_changes' else 'pending' end;
    end if;
    before_state:=next_state;
    if rev<>(target->>'expected_revision')::bigint or rootgist_admin.hash(before)<>target->>'base_sha256' then perform rootgist_admin.fail('PT409','REVISION_CONFLICT'); end if;
    perform rootgist_admin.validate_patch(kind,key,patch);
    perform rootgist_admin.apply_patch(kind,key,patch);
    after:=rootgist_admin.source(kind,key);
    meaningful:=case when kind='sense' then (before#-'{sense,review_note_ko}') is distinct from (after#-'{sense,review_note_ko}') else before is distinct from after end;
    if action='approve' then
      if (kind='sense' and (coalesce(after#>>'{sense,canonical_ko}','')='' or coalesce(after#>>'{sense,definition_ko}','')='' or after#>>'{sense,definition_kind}'='source_machine_translation_verbatim'))
        or (kind='candidate' and coalesce(after->>'canonical_ko','')='') then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
      next_state:='approved';
    elsif action='reject' then next_state:='rejected';
    elsif action='needs_changes' then next_state:='needs_changes';
    elsif meaningful then next_state:='pending';
    end if;
    if kind='sense' then
      update public.term_senses set review_status=case next_state when 'needs_changes' then 'deferred' else next_state end where sense_id=key;
    elsif kind='candidate' then
      update public.term_candidates set review_status=case next_state when 'needs_changes' then 'pending' else next_state end where normalized_form=key;
      pending_sync:=pending_sync or next_state='approved';
    end if;
    after:=rootgist_admin.source(kind,key);
    update rootgist_admin.control c set revision=rev+1,protected=true,review_state=next_state,
      managed_fields=array(select distinct f from unnest(c.managed_fields || array(select jsonb_object_keys(patch))) f order by f),
      protected_snapshot=case kind when 'paper' then jsonb_build_object('glossary',after->'glossary','context_sha256',rootgist_admin.hash(after-'glossary')) else after end,
      reviewed_sha256=case when next_state='approved' then rootgist_admin.hash(after) end,
      reviewed_by=case when next_state='approved' then actor end,reviewed_at=case when next_state='approved' then now() end,
      note=request->>'reason',updated_at=now() where c.entity_type=kind and c.entity_key=key;
    -- Keep accepted draft history; never silently discard another actor's work.
    update rootgist_admin.drafts d set state='accepted',updated_at=now() where d.actor_id=actor and d.entity_type=kind and d.entity_key=key and d.state='active' and d.base_revision=rev and d.base_sha256=target->>'base_sha256' and d.payload=patch;
    changes:=changes||jsonb_build_array(jsonb_build_object('entity_type',kind,'entity_key',key,'action',action,'reason',request->>'reason','before_review_state',before_state,'after_review_state',next_state,'patch',patch,'before_values',rootgist_admin.audit_values(kind,before,patch),'after_values',rootgist_admin.audit_values(kind,after,patch),'before_sha256',rootgist_admin.hash(before),'after_sha256',rootgist_admin.hash(after),'from_revision',rev,'to_revision',rev+1));
    results:=results||jsonb_build_array(jsonb_build_object('entity_type',kind,'entity_key',key,'revision',rev+1,'base_sha256',rootgist_admin.hash(after)));
  end loop;
  -- A sense edited in the same transaction can change a paper's display hash.
  -- Recompute every returned hash/protection snapshot after ALL target patches.
  results:='[]';
  for target in select x from jsonb_array_elements(request->'targets') x order by x->>'entity_type',x->>'entity_key' loop
    kind:=target->>'entity_type'; key:=target->>'entity_key'; after:=rootgist_admin.source(kind,key);
    update rootgist_admin.control c set
      protected_snapshot=case kind when 'paper' then jsonb_build_object('glossary',after->'glossary','context_sha256',rootgist_admin.hash(after-'glossary')) else after end,
      reviewed_sha256=case when c.review_state='approved' then rootgist_admin.hash(after) end
      where c.entity_type=kind and c.entity_key=key returning revision into rev;
    results:=results||jsonb_build_array(jsonb_build_object('entity_type',kind,'entity_key',key,'revision',rev,'base_sha256',rootgist_admin.hash(after)));
  end loop;
  select jsonb_agg(c || jsonb_build_object('after_sha256',rootgist_admin.hash(rootgist_admin.source(c->>'entity_type',c->>'entity_key')))) into changes from jsonb_array_elements(changes) c;
  result:=jsonb_build_object('operation_id',operation_id,'committed_at',now(),'targets',results,'dictionary_sync_pending',pending_sync);
  insert into rootgist_admin.audit(operation_id,actor_id,request_sha256,changes,result) values(operation_id,actor,requested_hash,changes,result);
  return result;
end;
$$;

create function public.admin_term_storage_status() returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object('schema_version',schema_version,'worker_contract_version',worker_contract_version,
    'writes_enabled',writes_enabled,'administrator_configured',admin_user_id is not null)
    from rootgist_admin.runtime where singleton;
$$;

create function public.admin_read_term_draft(actor uuid,entity_type text,entity_key text) returns jsonb
language plpgsql stable set search_path='' as $$
begin
  if actor is null or actor is distinct from (select admin_user_id from rootgist_admin.runtime where singleton) then perform rootgist_admin.fail('PT403','ADMIN_ONLY'); end if;
  return (select jsonb_build_object('draft_id',id,'draft_revision',draft_revision,'base_revision',base_revision,
    'base_sha256',base_sha256,'payload',payload,'saved_at',updated_at)
    from rootgist_admin.drafts d where d.actor_id=actor and d.entity_type=admin_read_term_draft.entity_type and d.entity_key=admin_read_term_draft.entity_key and state='active');
end;
$$;

create function public.admin_term_history(entity_type text,entity_key text,before_at timestamptz default null,before_id uuid default null,lim integer default 20) returns jsonb
language plpgsql stable set search_path='' as $$
declare page jsonb; shown jsonb; cursor jsonb;
begin
  if lim is null or lim not between 1 and 50 or ((before_at is null)<>(before_id is null)) then perform rootgist_admin.fail('PT422','VALIDATION_FAILED'); end if;
  perform rootgist_admin.source(entity_type,entity_key);
  select coalesce(jsonb_agg(jsonb_build_object('operation_id',a.operation_id,'actor_id',a.actor_id,'created_at',a.created_at,
    'changes',(select jsonb_agg(c) from jsonb_array_elements(a.changes) c where c->>'entity_type'=admin_term_history.entity_type and c->>'entity_key'=admin_term_history.entity_key)) order by a.created_at desc,a.operation_id desc),'[]') into page
    from (select * from rootgist_admin.audit a where (before_at is null or (a.created_at,a.operation_id)<(before_at,before_id))
      and exists(select from jsonb_array_elements(a.changes) c where c->>'entity_type'=admin_term_history.entity_type and c->>'entity_key'=admin_term_history.entity_key)
      order by a.created_at desc,a.operation_id desc limit lim+1) a;
  select coalesce(jsonb_agg(x),'[]') into shown from jsonb_array_elements(page) with ordinality p(x,n) where n<=lim;
  if jsonb_array_length(page)>lim then cursor:=jsonb_build_object('at',shown->(lim-1)->'created_at','id',shown->(lim-1)->'operation_id'); end if;
  return jsonb_build_object('rows',shown,'next_cursor',cursor);
end;
$$;

-- Invoker RPCs use the server role's existing table permissions and bypassrls.
revoke all on all functions in schema rootgist_admin from public,anon,authenticated;
grant execute on all functions in schema rootgist_admin to service_role;
revoke all on function public.admin_read_term_target(text,text),public.admin_save_term_draft(uuid,text,text,bigint,text,bigint,jsonb),public.admin_execute_term_command(uuid,uuid,jsonb),public.admin_term_storage_status(),public.admin_read_term_draft(uuid,text,text),public.admin_term_history(text,text,timestamptz,uuid,integer) from public,anon,authenticated;
grant execute on function public.admin_read_term_target(text,text),public.admin_save_term_draft(uuid,text,text,bigint,text,bigint,jsonb),public.admin_execute_term_command(uuid,uuid,jsonb),public.admin_term_storage_status(),public.admin_read_term_draft(uuid,text,text),public.admin_term_history(text,text,timestamptz,uuid,integer) to service_role;
