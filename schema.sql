-- Run in a NEW Supabase project SQL editor. All browser access uses authenticated RLS.
create extension if not exists pgcrypto;
create table public.households(id uuid primary key default gen_random_uuid(),name text not null check(length(name) between 1 and 80),owner_id uuid not null references auth.users(id),created_at timestamptz default now());
create table public.household_members(household_id uuid not null references public.households(id) on delete cascade,user_id uuid not null references auth.users(id) on delete cascade,role text not null check(role in ('admin','member')),primary key(household_id,user_id));
create table public.family_profiles(id uuid primary key default gen_random_uuid(),household_id uuid not null references public.households(id) on delete cascade,name text not null check(length(name) between 1 and 70),emoji text not null default '👤',photo text,created_at timestamptz default now());
create table public.family_items(id uuid primary key default gen_random_uuid(),household_id uuid not null references public.households(id) on delete cascade,kind text not null check(kind in ('tasks','events','bills','groceries')),title text not null check(length(title) between 1 and 160),details text,category text not null default 'Other',assigned_to uuid references public.family_profiles(id) on delete set null,due_at timestamptz,remind_before_minutes integer,repeat_minutes integer,amount numeric(12,2) check(amount>=0),done boolean not null default false,created_at timestamptz default now());
create index family_items_household_due on public.family_items(household_id,due_at);
create index household_members_user on public.household_members(user_id,household_id);
create or replace function public.is_family_member(h uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.household_members m where m.household_id=h and m.user_id=(select auth.uid()))$$;
create or replace function public.is_family_admin(h uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.household_members m where m.household_id=h and m.user_id=(select auth.uid()) and m.role='admin')$$;
revoke all on function public.is_family_member(uuid) from public; revoke all on function public.is_family_admin(uuid) from public;
grant execute on function public.is_family_member(uuid),public.is_family_admin(uuid) to authenticated;
-- Atomic creation: the logged-in user becomes admin of a newly created family.
create or replace function public.create_my_family(family_name text) returns uuid language plpgsql security definer set search_path='' as $$declare hid uuid;begin
 if auth.uid() is null then raise exception 'Login required';end if;
 if length(trim(family_name))<1 or length(family_name)>80 then raise exception 'Invalid family name';end if;
 insert into public.households(name,owner_id) values(trim(family_name),auth.uid()) returning id into hid;
 insert into public.household_members(household_id,user_id,role) values(hid,auth.uid(),'admin');return hid;end$$;
revoke all on function public.create_my_family(text) from public;grant execute on function public.create_my_family(text) to authenticated;
alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.family_profiles enable row level security;
alter table public.family_items enable row level security;
create policy households_read on public.households for select to authenticated using(public.is_family_member(id));
create policy households_update on public.households for update to authenticated using(public.is_family_admin(id)) with check(public.is_family_admin(id) and owner_id=(select auth.uid()));
create policy members_read on public.household_members for select to authenticated using(public.is_family_member(household_id));
create policy profiles_read on public.family_profiles for select to authenticated using(public.is_family_member(household_id));
create policy profiles_add on public.family_profiles for insert to authenticated with check(public.is_family_admin(household_id));
create policy profiles_update on public.family_profiles for update to authenticated using(public.is_family_admin(household_id)) with check(public.is_family_admin(household_id));
create policy profiles_delete on public.family_profiles for delete to authenticated using(public.is_family_admin(household_id));
create policy items_read on public.family_items for select to authenticated using(public.is_family_member(household_id));
create policy items_add on public.family_items for insert to authenticated with check(public.is_family_admin(household_id) and (assigned_to is null or exists(select 1 from public.family_profiles p where p.id=assigned_to and p.household_id=family_items.household_id)));
create policy items_update on public.family_items for update to authenticated using(public.is_family_admin(household_id)) with check(public.is_family_admin(household_id) and (assigned_to is null or exists(select 1 from public.family_profiles p where p.id=assigned_to and p.household_id=family_items.household_id)));
create policy items_delete on public.family_items for delete to authenticated using(public.is_family_admin(household_id));
-- Future: authenticated invitation workflow to add other login accounts to a household.
-- Until then, only the creator account is a login member of its household.
