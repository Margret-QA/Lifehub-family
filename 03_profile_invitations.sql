-- LifeHub V6.1 incremental upgrade. Run AFTER 02_migrate.sql.
-- Existing family data and invitations are preserved.
begin;
alter table public.family_profiles add column if not exists linked_user_id uuid references auth.users(id) on delete set null;
create unique index if not exists one_profile_per_login on public.family_profiles(linked_user_id) where linked_user_id is not null;
alter table public.family_invitations add column if not exists profile_id uuid references public.family_profiles(id) on delete cascade;

-- Prevent client-side reassignment of profile login identities.
create or replace function public.protect_profile_link() returns trigger
language plpgsql set search_path = '' as $$
begin
 if new.linked_user_id is distinct from old.linked_user_id then
   if current_user <> 'postgres' then
     raise exception 'Profile login links can only be changed through verified invitation acceptance';
   end if;
 end if;
 return new;
end $$;
drop trigger if exists protect_profile_link_trigger on public.family_profiles;
create trigger protect_profile_link_trigger before update on public.family_profiles
for each row execute function public.protect_profile_link();

create or replace function public.create_profile_invite(target_email text,target_profile uuid) returns text
language plpgsql security definer set search_path = 'pg_catalog, extensions' as $$
declare hid uuid; normalized text; raw_token text;
begin
 if auth.uid() is null then raise exception 'Login required';end if;
 select m.household_id into hid from public.household_members m
 where m.user_id=auth.uid() and m.role='admin';
 if hid is null then raise exception 'Only family admins can invite members';end if;
 if not exists(select 1 from public.family_profiles p where p.id=target_profile and p.household_id=hid and p.linked_user_id is null) then
   raise exception 'Profile is already linked or not in your family';end if;
 normalized:=lower(trim(coalesce(target_email,'')));
 if length(normalized)<5 or length(normalized)>320 or position('@' in normalized)<2 then raise exception 'Enter a valid email';end if;
 if exists(select 1 from auth.users u join public.household_members m on m.user_id=u.id
 where m.household_id=hid and lower(u.email)=normalized) then
   raise exception 'This account already belongs to the family';end if;
 delete from public.family_invitations where household_id=hid and profile_id=target_profile and accepted_at is null;
 raw_token:=encode(gen_random_bytes(32),'hex');
 insert into public.family_invitations(household_id,profile_id,invited_email,token_hash,invited_by)
 values(hid,target_profile,normalized,encode(digest(raw_token,'sha256'),'hex'),auth.uid());
 return raw_token;
end $$;
revoke all on function public.create_profile_invite(text,uuid) from public,anon;
grant execute on function public.create_profile_invite(text,uuid) to authenticated;

create or replace function public.accept_profile_invite(invite_token text) returns uuid
language plpgsql security definer set search_path = 'pg_catalog, extensions' as $$
declare inv public.family_invitations%rowtype; actual_email text; linked uuid;
begin
 if auth.uid() is null then raise exception 'Login required';end if;
 select lower(email) into actual_email from auth.users where id=auth.uid() and email_confirmed_at is not null;
 if actual_email is null then raise exception 'Confirm your email first';end if;
 if exists(select 1 from public.household_members where user_id=auth.uid()) then raise exception 'Account already belongs to a family';end if;
 if invite_token !~ '^[0-9a-f]{64}$' then raise exception 'Invalid invitation code';end if;
 select * into inv from public.family_invitations
 where token_hash=encode(digest(invite_token,'sha256'),'hex') and accepted_at is null and expires_at>now()
 for update;
 if not found or inv.profile_id is null then raise exception 'Invalid, expired, or legacy invitation';end if;
 if inv.invited_email<>actual_email then raise exception 'Invitation belongs to another email';end if;
 select linked_user_id into linked from public.family_profiles
 where id=inv.profile_id and household_id=inv.household_id for update;
 if not found or linked is not null then raise exception 'Profile is no longer available';end if;
 insert into public.household_members(household_id,user_id,role) values(inv.household_id,auth.uid(),'member');
 update public.family_profiles set linked_user_id=auth.uid() where id=inv.profile_id;
 update public.family_invitations set accepted_at=now() where id=inv.id;
 return inv.household_id;
end $$;
revoke all on function public.accept_profile_invite(text) from public,anon;
grant execute on function public.accept_profile_invite(text) to authenticated;

-- Disable older generic invite RPCs so accounts must link to a specific profile.
revoke execute on function public.create_family_invite(text) from authenticated;
revoke execute on function public.accept_family_invite(text) from authenticated;
commit;
