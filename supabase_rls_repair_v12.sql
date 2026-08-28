-- Financial Control Center — Supabase RLS repair / diagnostics
-- Safe to run after supabase_schema_v12.sql.

select
  to_regclass('public.households') as households,
  to_regclass('public.household_members') as household_members,
  to_regclass('public.financial_settings') as financial_settings,
  to_regclass('public.transactions') as transactions,
  to_regclass('public.accounts') as accounts,
  to_regclass('public.holdings') as holdings,
  to_regclass('public.watchlist') as watchlist,
  to_regclass('public.retirement_products') as retirement_products,
  to_regclass('public.goals') as goals;

create or replace function public.is_household_owner(hid uuid)
returns boolean
language sql stable security definer set search_path=public
as $$
  select auth.uid() is not null
     and exists(select 1 from public.households h where h.id=hid and h.created_by=auth.uid());
$$;

create or replace function public.has_household_access(hid uuid)
returns boolean
language sql stable security definer set search_path=public
as $$
  select auth.uid() is not null and (
    exists(select 1 from public.households h where h.id=hid and h.created_by=auth.uid())
    or exists(select 1 from public.household_members hm where hm.household_id=hid and hm.user_id=auth.uid())
  );
$$;

revoke all on function public.is_household_owner(uuid) from public;
revoke all on function public.has_household_access(uuid) from public;
grant execute on function public.is_household_owner(uuid) to authenticated;
grant execute on function public.has_household_access(uuid) to authenticated;

alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.financial_settings enable row level security;
alter table public.transactions enable row level security;
alter table public.accounts enable row level security;
alter table public.holdings enable row level security;
alter table public.watchlist enable row level security;
alter table public.retirement_products enable row level security;
alter table public.goals enable row level security;

drop policy if exists households_select on public.households;
drop policy if exists households_insert on public.households;
drop policy if exists households_update on public.households;
drop policy if exists households_delete on public.households;
drop policy if exists members_select on public.household_members;
drop policy if exists members_insert on public.household_members;
drop policy if exists members_update on public.household_members;
drop policy if exists members_delete on public.household_members;

create policy households_select on public.households for select to authenticated using(public.has_household_access(id));
create policy households_insert on public.households for insert to authenticated with check(created_by=auth.uid());
create policy households_update on public.households for update to authenticated using(public.is_household_owner(id)) with check(public.is_household_owner(id));
create policy households_delete on public.households for delete to authenticated using(public.is_household_owner(id));

create policy members_select on public.household_members for select to authenticated using(public.has_household_access(household_id));
create policy members_insert on public.household_members for insert to authenticated with check(public.is_household_owner(household_id));
create policy members_update on public.household_members for update to authenticated using(public.is_household_owner(household_id)) with check(public.is_household_owner(household_id));
create policy members_delete on public.household_members for delete to authenticated using(public.is_household_owner(household_id));

do $$
declare t text;
begin
  foreach t in array array['financial_settings','transactions','accounts','holdings','watchlist','retirement_products','goals']
  loop
    execute format('drop policy if exists %I_access on public.%I',t,t);
    execute format('drop policy if exists %I_household_access on public.%I',t,t);
    execute format('create policy %I_household_access on public.%I for all to authenticated using(public.has_household_access(household_id)) with check(public.has_household_access(household_id))',t,t);
  end loop;
end $$;

grant usage on schema public to authenticated;
grant select,insert,update,delete on public.households,public.household_members,public.financial_settings,public.transactions,public.accounts,public.holdings,public.watchlist,public.retirement_products,public.goals to authenticated;

notify pgrst, 'reload schema';

select schemaname,tablename,policyname,roles,cmd
from pg_policies
where schemaname='public' and tablename in ('households','household_members','financial_settings','transactions','accounts','holdings','watchlist','retirement_products','goals')
order by tablename,policyname;
