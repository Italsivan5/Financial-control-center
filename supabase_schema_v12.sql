-- Financial Control Center 1.2 — Supabase
-- Run once in Supabase Dashboard > SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.households (
 id uuid primary key default gen_random_uuid(),
 name text not null default 'המשפחה שלי',
 created_by uuid not null default auth.uid(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.household_members (
 household_id uuid not null references public.households(id) on delete cascade,
 user_id uuid not null,
 role text not null default 'member' check(role in('owner','member')),
 created_at timestamptz not null default now(),
 primary key(household_id,user_id)
);
create table if not exists public.financial_settings (
 household_id uuid primary key references public.households(id) on delete cascade,
 target_savings_rate numeric not null default 20,
 emergency_months numeric not null default 4,
 current_age integer,
 retirement_age integer not null default 67,
 low_return numeric not null default 3,
 base_return numeric not null default 5,
 high_return numeric not null default 7,
 inflation numeric not null default 2.5,
 updated_at timestamptz not null default now()
);
create table if not exists public.transactions (
 id uuid primary key default gen_random_uuid(),
 household_id uuid not null references public.households(id) on delete cascade,
 txn_date date not null,kind text not null check(kind in('income','expense')),
 amount numeric(16,2) not null check(amount>=0),description text not null,
 category text not null default 'אחר',
 nature text not null default 'variable' check(nature in('fixed','variable','oneoff')),
 is_saving boolean not null default false,
 status text not null default 'actual' check(status in('actual','planned')),
 created_by uuid not null default auth.uid(),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.accounts (
 id uuid primary key default gen_random_uuid(),
 household_id uuid not null references public.households(id) on delete cascade,
 name text not null,type text not null check(type in('liquid','investment','provident','property','debt','pension','training')),
 value numeric(18,2) not null default 0,owner_name text,provider text,note text,
 monthly_payment numeric(16,2) not null default 0,interest_rate numeric(8,4) not null default 0,
 created_by uuid not null default auth.uid(),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.holdings (
 id uuid primary key default gen_random_uuid(),
 household_id uuid not null references public.households(id) on delete cascade,
 account_id uuid references public.accounts(id) on delete set null,
 ticker text not null,name text,units numeric(20,8) not null default 0,
 avg_cost numeric(20,6) not null default 0,current_price numeric(20,6) not null default 0,
 currency text not null default 'USD',fx_to_ils numeric(16,6) not null default 1,
 asset_class text,region text,sector text,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.watchlist (
 id uuid primary key default gen_random_uuid(),
 household_id uuid not null references public.households(id) on delete cascade,
 ticker text not null,name text,current_price numeric(20,6) not null default 0,
 target_price numeric(20,6) not null default 0,status text not null default 'מחקר',thesis text,
 quality_score numeric(5,2) not null default 0 check(quality_score between 0 and 100),
 growth_score numeric(5,2) not null default 0 check(growth_score between 0 and 100),
 valuation_score numeric(5,2) not null default 0 check(valuation_score between 0 and 100),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.retirement_products (
 id uuid primary key default gen_random_uuid(),
 household_id uuid not null references public.households(id) on delete cascade,
 name text not null,owner_name text,provider text,balance numeric(18,2) not null default 0,
 monthly_deposit numeric(16,2) not null default 0,fee_assets numeric(8,4) not null default 0,
 fee_deposit numeric(8,4) not null default 0,track text,expected_return numeric(8,4),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists public.goals (
 id uuid primary key default gen_random_uuid(),
 household_id uuid not null references public.households(id) on delete cascade,
 name text not null,icon text default '🎯',target_amount numeric(18,2) not null default 0,
 saved_amount numeric(18,2) not null default 0,target_date date not null,
 priority text not null default 'בינונית' check(priority in('גבוהה','בינונית','נמוכה')),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);

create index if not exists transactions_household_date_idx on public.transactions(household_id,txn_date);
create index if not exists accounts_household_idx on public.accounts(household_id);
create index if not exists holdings_household_idx on public.holdings(household_id);
create index if not exists watchlist_household_idx on public.watchlist(household_id);
create index if not exists retirement_household_idx on public.retirement_products(household_id);
create index if not exists goals_household_idx on public.goals(household_id);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$begin new.updated_at=now();return new;end;$$;

do $$declare t text;begin
 foreach t in array array['households','financial_settings','transactions','accounts','holdings','watchlist','retirement_products','goals']
 loop
  execute format('drop trigger if exists trg_%I_updated_at on public.%I',t,t);
  execute format('create trigger trg_%I_updated_at before update on public.%I for each row execute function public.set_updated_at()',t,t);
 end loop;
end$$;

create or replace function public.add_household_owner()
returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.household_members(household_id,user_id,role)
values(new.id,new.created_by,'owner') on conflict do nothing;return new;end;$$;
drop trigger if exists trg_add_household_owner on public.households;
create trigger trg_add_household_owner after insert on public.households
for each row execute function public.add_household_owner();

create or replace function public.is_household_owner(hid uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select auth.uid() is not null and exists(select 1 from public.households h where h.id=hid and h.created_by=auth.uid());
$$;
create or replace function public.has_household_access(hid uuid)
returns boolean language sql stable security definer set search_path=public as $$
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
create policy households_select on public.households for select using(public.has_household_access(id));
create policy households_insert on public.households for insert with check(auth.uid() is not null and created_by=auth.uid());
create policy households_update on public.households for update using(public.is_household_owner(id)) with check(public.is_household_owner(id));
create policy households_delete on public.households for delete using(public.is_household_owner(id));

drop policy if exists members_select on public.household_members;
drop policy if exists members_insert on public.household_members;
drop policy if exists members_update on public.household_members;
drop policy if exists members_delete on public.household_members;
create policy members_select on public.household_members for select using(public.has_household_access(household_id));
create policy members_insert on public.household_members for insert with check(public.is_household_owner(household_id));
create policy members_update on public.household_members for update using(public.is_household_owner(household_id)) with check(public.is_household_owner(household_id));
create policy members_delete on public.household_members for delete using(public.is_household_owner(household_id));

do $$declare t text;begin
 foreach t in array array['financial_settings','transactions','accounts','holdings','watchlist','retirement_products','goals']
 loop
  -- Remove both the old v1 policy name and the current v1.2 name.
  execute format('drop policy if exists %I_access on public.%I',t,t);
  execute format('drop policy if exists %I_household_access on public.%I',t,t);
  execute format('create policy %I_household_access on public.%I for all using(public.has_household_access(household_id)) with check(public.has_household_access(household_id))',t,t);
 end loop;
end$$;

grant usage on schema public to authenticated;
grant select,insert,update,delete on public.households,public.household_members,public.financial_settings,
 public.transactions,public.accounts,public.holdings,public.watchlist,public.retirement_products,public.goals to authenticated;

do $$declare t text;begin
 foreach t in array array['financial_settings','transactions','accounts','holdings','watchlist','retirement_products','goals']
 loop
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
   execute format('alter publication supabase_realtime add table public.%I',t);
  end if;
 end loop;
end$$;
