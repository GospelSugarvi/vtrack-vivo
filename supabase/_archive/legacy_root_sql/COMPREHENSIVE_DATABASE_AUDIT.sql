-- =========================================================
-- COMPREHENSIVE DATABASE AUDIT (ALL PUBLIC TABLES)
-- Project: VTrack
-- Safe mode: READ-ONLY (no INSERT/UPDATE/DELETE on business tables)
-- =========================================================

-- 0) CONTEXT
select
  now() as audit_time,
  current_database() as db_name,
  current_user as db_user,
  version() as postgres_version;

-- 1) TABLE INVENTORY + SIZE + ESTIMATED ROWS
select
  n.nspname as schema_name,
  c.relname as table_name,
  c.reltuples::bigint as estimated_rows,
  pg_size_pretty(pg_total_relation_size(c.oid)) as total_size,
  pg_size_pretty(pg_relation_size(c.oid)) as table_size,
  pg_size_pretty(pg_total_relation_size(c.oid) - pg_relation_size(c.oid)) as index_size
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
order by pg_total_relation_size(c.oid) desc, c.relname;

-- 2) COLUMN STRUCTURE SUMMARY
select
  table_name,
  count(*) as total_columns,
  count(*) filter (where is_nullable = 'NO') as not_null_columns,
  count(*) filter (where column_default is not null) as columns_with_default
from information_schema.columns
where table_schema = 'public'
group by table_name
order by table_name;

-- 3) CONSTRAINT OVERVIEW (PK/FK/UNIQUE/CHECK)
select
  tc.table_name,
  tc.constraint_name,
  tc.constraint_type,
  string_agg(kcu.column_name, ', ' order by kcu.ordinal_position) as columns
from information_schema.table_constraints tc
left join information_schema.key_column_usage kcu
  on tc.constraint_name = kcu.constraint_name
 and tc.table_schema = kcu.table_schema
 and tc.table_name = kcu.table_name
where tc.table_schema = 'public'
group by tc.table_name, tc.constraint_name, tc.constraint_type
order by tc.table_name, tc.constraint_type, tc.constraint_name;

-- 4) RLS + POLICY COVERAGE
select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as rls_forced,
  coalesce(p.policy_count, 0) as policy_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join (
  select tablename, count(*) as policy_count
  from pg_policies
  where schemaname = 'public'
  group by tablename
) p on p.tablename = c.relname
where n.nspname = 'public'
  and c.relkind = 'r'
order by c.relname;

-- 5) INDEX OVERVIEW
select
  schemaname,
  tablename,
  indexname,
  indexdef
from pg_indexes
where schemaname = 'public'
order by tablename, indexname;

-- 6) TABLES WITHOUT SECONDARY INDEX (besides PK)
with idx as (
  select
    t.relname as table_name,
    count(*) filter (where i.indisprimary) as pk_indexes,
    count(*) filter (where not i.indisprimary) as secondary_indexes
  from pg_class t
  join pg_namespace n on n.oid = t.relnamespace
  left join pg_index i on i.indrelid = t.oid
  where n.nspname = 'public'
    and t.relkind = 'r'
  group by t.relname
)
select *
from idx
where coalesce(secondary_indexes, 0) = 0
order by table_name;

-- 7) UNSED / LOW-USE INDEX SIGNAL (requires pg_stat_user_indexes stats)
select
  schemaname,
  relname as table_name,
  indexrelname as index_name,
  idx_scan,
  idx_tup_read,
  idx_tup_fetch
from pg_stat_user_indexes
where schemaname = 'public'
order by idx_scan asc, relname, indexrelname;

-- 8) EMPTY TABLES
create temporary table if not exists tmp_empty_tables (
  table_name text,
  row_count bigint
) on commit drop;

do $$
declare
  r record;
  cnt bigint;
begin
  delete from tmp_empty_tables;
  for r in
    select tablename
    from pg_tables
    where schemaname = 'public'
    order by tablename
  loop
    execute format('select count(*) from public.%I', r.tablename) into cnt;
    if cnt = 0 then
      insert into tmp_empty_tables(table_name, row_count) values (r.tablename, cnt);
    end if;
  end loop;
end $$;

select * from tmp_empty_tables order by table_name;

-- 9) DUPLICATE CANDIDATE AUDIT (common unique-ish columns)
create temporary table if not exists tmp_duplicate_candidates (
  table_name text,
  column_name text,
  duplicate_value text,
  duplicate_count bigint
) on commit drop;

do $$
declare
  r record;
begin
  delete from tmp_duplicate_candidates;

  for r in
    select c.table_name, c.column_name
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.column_name in ('email', 'imei', 'phone', 'username', 'code')
  loop
    execute format(
      'insert into tmp_duplicate_candidates(table_name, column_name, duplicate_value, duplicate_count)
       select %L, %L, %I::text, count(*)
       from public.%I
       where %I is not null
       group by %I
       having count(*) > 1',
      r.table_name, r.column_name, r.column_name, r.table_name, r.column_name, r.column_name
    );
  end loop;
end $$;

select *
from tmp_duplicate_candidates
order by duplicate_count desc, table_name, column_name;

-- 10) ORPHAN FK AUDIT (single-column foreign keys)
create temporary table if not exists tmp_orphan_fk (
  table_name text,
  fk_column text,
  ref_table text,
  ref_column text,
  orphan_count bigint
) on commit drop;

do $$
declare
  r record;
  cnt bigint;
begin
  delete from tmp_orphan_fk;

  for r in
    select
      c.conrelid::regclass::text as table_name,
      a.attname as fk_column,
      c.confrelid::regclass::text as ref_table,
      af.attname as ref_column
    from pg_constraint c
    join pg_attribute a
      on a.attrelid = c.conrelid
     and a.attnum = c.conkey[1]
    join pg_attribute af
      on af.attrelid = c.confrelid
     and af.attnum = c.confkey[1]
    where c.contype = 'f'
      and array_length(c.conkey, 1) = 1
      and array_length(c.confkey, 1) = 1
      and c.connamespace = 'public'::regnamespace
  loop
    execute format(
      'select count(*) from %s t
       where t.%I is not null
         and not exists (
           select 1 from %s r where r.%I = t.%I
         )',
      r.table_name, r.fk_column, r.ref_table, r.ref_column, r.fk_column
    ) into cnt;

    insert into tmp_orphan_fk(table_name, fk_column, ref_table, ref_column, orphan_count)
    values (r.table_name, r.fk_column, r.ref_table, r.ref_column, cnt);
  end loop;
end $$;

select *
from tmp_orphan_fk
where orphan_count > 0
order by orphan_count desc, table_name;

-- 11) TIMESTAMP ANOMALY AUDIT (created_at in future > 1 day)
create temporary table if not exists tmp_future_created_at (
  table_name text,
  future_rows bigint
) on commit drop;

do $$
declare
  r record;
  cnt bigint;
begin
  delete from tmp_future_created_at;
  for r in
    select table_name
    from information_schema.columns
    where table_schema = 'public'
      and column_name = 'created_at'
  loop
    execute format(
      'select count(*) from public.%I where created_at > now() + interval ''1 day''',
      r.table_name
    ) into cnt;

    if cnt > 0 then
      insert into tmp_future_created_at(table_name, future_rows)
      values (r.table_name, cnt);
    end if;
  end loop;
end $$;

select * from tmp_future_created_at order by future_rows desc, table_name;

-- 12) SOFT-DELETE CONSISTENCY (if table has deleted_at and status)
create temporary table if not exists tmp_soft_delete_conflict (
  table_name text,
  conflict_rows bigint
) on commit drop;

do $$
declare
  r record;
  cnt bigint;
begin
  delete from tmp_soft_delete_conflict;
  for r in
    select c1.table_name
    from information_schema.columns c1
    join information_schema.columns c2
      on c1.table_schema = c2.table_schema
     and c1.table_name = c2.table_name
    where c1.table_schema = 'public'
      and c1.column_name = 'deleted_at'
      and c2.column_name = 'status'
  loop
    execute format(
      'select count(*) from public.%I where deleted_at is not null and status = ''active''',
      r.table_name
    ) into cnt;

    if cnt > 0 then
      insert into tmp_soft_delete_conflict(table_name, conflict_rows)
      values (r.table_name, cnt);
    end if;
  end loop;
end $$;

select * from tmp_soft_delete_conflict order by conflict_rows desc, table_name;

-- 13) QUICK SUMMARY
select
  (select count(*) from pg_tables where schemaname = 'public') as total_public_tables,
  (select count(*) from tmp_empty_tables) as empty_tables,
  (select count(*) from tmp_duplicate_candidates) as duplicate_signals,
  (select count(*) from tmp_orphan_fk where orphan_count > 0) as fk_orphan_signals,
  (select count(*) from tmp_future_created_at) as future_timestamp_signals,
  (select count(*) from tmp_soft_delete_conflict) as soft_delete_conflicts;

-- END
