-- Financial Control Center 1.2.3
-- Fixes error 42501 on first insert into public.households.
-- Run this once in Supabase > SQL Editor.

alter table public.households
  alter column created_by set default auth.uid();

create or replace function public.is_household_owner(hid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and exists (
       select 1 from public.households h
       where h.id = hid and h.created_by = auth.uid()
     );
$$;

create or replace function public.has_household_access(hid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and (
    exists (
      select 1 from public.households h
      where h.id = hid and h.created_by = auth.uid()
    )
    or exists (
      select 1 from public.household_members hm
      where hm.household_id = hid and hm.user_id = auth.uid()
    )
  );
$$;

revoke all on function public.is_household_owner(uuid) from public;
revoke all on function public.has_household_access(uuid) from public;
grant execute on function public.is_household_owner(uuid) to authenticated;
grant execute on function public.has_household_access(uuid) to authenticated;

-- Remove any old policies on the two bootstrap tables.
do $$
declare p record;
begin
  for p in
    select policyname, tablename
    from pg_policies
    where schemaname='public'
      and tablename in ('households','household_members')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

alter table public.households enable row level security;
alter table public.household_members enable row level security;

create policy households_select
on public.households
for select to authenticated
using (public.has_household_access(id));

create policy households_insert
on public.households
for insert to authenticated
with check (auth.uid() is not null and created_by = auth.uid());

create policy households_update
on public.households
for update to authenticated
using (public.is_household_owner(id))
with check (public.is_household_owner(id));

create policy households_delete
on public.households
for delete to authenticated
using (public.is_household_owner(id));

create policy members_select
on public.household_members
for select to authenticated
using (public.has_household_access(household_id));

create policy members_insert
on public.household_members
for insert to authenticated
with check (public.is_household_owner(household_id));

create policy members_update
on public.household_members
for update to authenticated
using (public.is_household_owner(household_id))
with check (public.is_household_owner(household_id));

create policy members_delete
on public.household_members
for delete to authenticated
using (public.is_household_owner(household_id));

grant select,insert,update,delete on public.households to authenticated;
grant select,insert,update,delete on public.household_members to authenticated;

-- Secure bootstrap RPC for the first household.
create or replace function public.create_my_household(
  p_name text default 'המשפחה שלי'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  hid uuid;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select h.id into hid
  from public.households h
  where h.created_by = uid
  order by h.created_at
  limit 1;

  if hid is null then
    insert into public.households(name, created_by)
    values (coalesce(nullif(trim(p_name),''),'המשפחה שלי'), uid)
    returning id into hid;
  end if;

  insert into public.household_members(household_id,user_id,role)
  values(hid,uid,'owner')
  on conflict (household_id,user_id)
  do update set role='owner';

  return hid;
end;
$$;

revoke all on function public.create_my_household(text) from public;
grant execute on function public.create_my_household(text) to authenticated;

notify pgrst, 'reload schema';

-- Diagnostic result: should show create_my_household.
select p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname='create_my_household';
