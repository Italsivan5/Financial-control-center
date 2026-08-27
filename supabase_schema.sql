-- Financial Control Center 1.0
-- Supabase / PostgreSQL schema, designed to match the PWA data model.
-- Run in a NEW Supabase project SQL editor.

create extension if not exists pgcrypto;

create table if not exists public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'המשפחה שלי',
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);

create table if not exists public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null,
  role text not null default 'member' check (role in ('owner','member')),
  created_at timestamptz not null default now(),
  primary key (household_id, user_id)
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
  txn_date date not null,
  kind text not null check (kind in ('income','expense')),
  amount numeric(16,2) not null check (amount >= 0),
  description text not null,
  category text not null default 'אחר',
  nature text not null default 'variable' check (nature in ('fixed','variable','oneoff')),
  is_saving boolean not null default false,
  status text not null default 'actual' check (status in ('actual','planned')),
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.accounts (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null,
  type text not null check (type in ('liquid','investment','provident','property','debt','pension','training')),
  value numeric(18,2) not null default 0,
  owner_name text,
  provider text,
  note text,
  monthly_payment numeric(16,2) not null default 0,
  interest_rate numeric(8,4) not null default 0,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.holdings (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  account_id uuid references public.accounts(id) on delete set null,
  ticker text not null,
  name text,
  units numeric(20,8) not null default 0,
  avg_cost numeric(20,6) not null default 0,
  current_price numeric(20,6) not null default 0,
  currency text not null default 'USD',
  fx_to_ils numeric(16,6) not null default 1,
  asset_class text,
  region text,
  sector text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.watchlist (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  ticker text not null,
  name text,
  current_price numeric(20,6) not null default 0,
  target_price numeric(20,6) not null default 0,
  status text not null default 'מחקר',
  thesis text,
  quality_score numeric(5,2) not null default 0 check (quality_score between 0 and 100),
  growth_score numeric(5,2) not null default 0 check (growth_score between 0 and 100),
  valuation_score numeric(5,2) not null default 0 check (valuation_score between 0 and 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.retirement_products (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null,
  owner_name text,
  provider text,
  balance numeric(18,2) not null default 0,
  monthly_deposit numeric(16,2) not null default 0,
  fee_assets numeric(8,4) not null default 0,
  fee_deposit numeric(8,4) not null default 0,
  track text,
  expected_return numeric(8,4),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.goals (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null,
  icon text default '🎯',
  target_amount numeric(18,2) not null default 0,
  saved_amount numeric(18,2) not null default 0,
  target_date date not null,
  priority text not null default 'בינונית' check (priority in ('גבוהה','בינונית','נמוכה')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Helpful indexes
create index if not exists transactions_household_date_idx on public.transactions(household_id, txn_date);
create index if not exists accounts_household_idx on public.accounts(household_id);
create index if not exists holdings_household_idx on public.holdings(household_id);
create index if not exists watchlist_household_idx on public.watchlist(household_id);
create index if not exists retirement_household_idx on public.retirement_products(household_id);
create index if not exists goals_household_idx on public.goals(household_id);

-- RLS
alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.financial_settings enable row level security;
alter table public.transactions enable row level security;
alter table public.accounts enable row level security;
alter table public.holdings enable row level security;
alter table public.watchlist enable row level security;
alter table public.retirement_products enable row level security;
alter table public.goals enable row level security;

-- Household policies
drop policy if exists households_select on public.households;
create policy households_select on public.households for select
using (
  created_by = auth.uid()
  or exists (
    select 1 from public.household_members hm
    where hm.household_id = id and hm.user_id = auth.uid()
  )
);

drop policy if exists households_insert on public.households;
create policy households_insert on public.households for insert
with check (created_by = auth.uid());

drop policy if exists households_update on public.households;
create policy households_update on public.households for update
using (created_by = auth.uid())
with check (created_by = auth.uid());

-- Membership policies
drop policy if exists members_select on public.household_members;
create policy members_select on public.household_members for select
using (
  user_id = auth.uid()
  or exists (
    select 1 from public.households h
    where h.id = household_id and h.created_by = auth.uid()
  )
);

drop policy if exists members_insert on public.household_members;
create policy members_insert on public.household_members for insert
with check (
  exists (
    select 1 from public.households h
    where h.id = household_id and h.created_by = auth.uid()
  )
);

drop policy if exists members_delete on public.household_members;
create policy members_delete on public.household_members for delete
using (
  exists (
    select 1 from public.households h
    where h.id = household_id and h.created_by = auth.uid()
  )
);

-- Reusable membership predicate is repeated explicitly to keep policies simple.
do $$
declare t text;
begin
  foreach t in array array[
    'financial_settings','transactions','accounts','holdings',
    'watchlist','retirement_products','goals'
  ]
  loop
    execute format('drop policy if exists %I_access on public.%I', t, t);
    execute format(
      'create policy %I_access on public.%I for all using (
        exists (select 1 from public.household_members hm
                where hm.household_id = %I.household_id and hm.user_id = auth.uid())
        or exists (select 1 from public.households h
                   where h.id = %I.household_id and h.created_by = auth.uid())
       ) with check (
        exists (select 1 from public.household_members hm
                where hm.household_id = %I.household_id and hm.user_id = auth.uid())
        or exists (select 1 from public.households h
                   where h.id = %I.household_id and h.created_by = auth.uid())
       )',
      t, t, t, t, t, t
    );
  end loop;
end $$;

-- Optional: automatically create owner membership after a household is created.
create or replace function public.add_household_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.household_members(household_id,user_id,role)
  values(new.id,new.created_by,'owner')
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists trg_add_household_owner on public.households;
create trigger trg_add_household_owner
after insert on public.households
for each row execute function public.add_household_owner();
