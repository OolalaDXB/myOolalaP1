-- =========================================================
-- myOolala — Supabase PostgreSQL Migration (Phase A)
-- Tables: profiles, views, aliases, blocks, socials
-- Triggers: citizen_id, default views, permanent_token immutability
-- RLS: owner CRUD + public read (limited columns via GRANT)
-- =========================================================

-- Extensions
create extension if not exists pgcrypto;

-- ---------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------

-- Generate an alphanumeric token of given length (default 10)
create or replace function public.generate_permanent_token(p_length int default 10)
returns text
language plpgsql
as $$
declare
  chars constant text := 'abcdefghijklmnopqrstuvwxyz0123456789';
  out text := '';
  i int;
begin
  if p_length is null or p_length < 6 or p_length > 32 then
    raise exception 'Invalid token length % (expected 6..32)', p_length;
  end if;
  for i in 1..p_length loop
    out := out || substr(chars, 1 + floor(random() * length(chars))::int, 1);
  end loop;
  return out;
end;
$$;

-- Generate a Citizen ID: #XXX-XXXXX, random, avoids reserved prefixes, retries up to 10
create or replace function public.generate_random_citizen_id()
returns text
language plpgsql
as $$
declare
  reserved_prefixes text[] := array[
    '000','001','002','003','004','005','006','007','008','009',
    '010','100','111','123','200','222','300','333','400','420',
    '444','500','555','600','666','700','777','800','888','900','999'
  ];
  prefix text;
  suffix text;
  candidate text;
  attempt int;
  exists_row boolean;
begin
  for attempt in 1..10 loop
    prefix := lpad(floor(random() * 1000)::int::text, 3, '0');
    if prefix = any(reserved_prefixes) then
      continue;
    end if;
    suffix := lpad(floor(random() * 100000)::int::text, 5, '0');
    candidate := '#' || prefix || '-' || suffix;
    select exists(select 1 from public.profiles p where p.citizen_id = candidate) into exists_row;
    if not exists_row then
      return candidate;
    end if;
  end loop;
  raise exception 'Failed to generate unique citizen_id after 10 attempts';
end;
$$;

-- ---------------------------------------------------------
-- Tables
-- ---------------------------------------------------------

-- PROFILES
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  handle varchar(20) unique not null,
  bio varchar(120),
  display_name varchar(50),
  avatar_url text,
  citizen_id varchar(12) unique,
  plan varchar(10) not null default 'free',
  origin_flags text[],
  based_in_flag text,
  based_in_city varchar(50),
  contact_email varchar(100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_handle_format check (handle ~ '^[a-z0-9][a-z0-9-]{1,18}[a-z0-9]$' or length(handle)=1),
  constraint profiles_citizen_id_format check (citizen_id is null or citizen_id ~ '^#[0-9]{3}-[0-9]{5}$')
);

-- VIEWS
create table if not exists public.views (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name varchar(20) not null,
  label varchar(30),
  visibility varchar(20) not null default 'public',
  permanent_token varchar(12) unique,
  theme varchar(20) not null default 'default',
  "order" int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint views_user_name_unique unique(user_id, name),
  constraint views_visibility_check check (visibility in ('public','private_link'))
);

-- ALIASES
create table if not exists public.aliases (
  id uuid primary key default gen_random_uuid(),
  view_id uuid not null references public.views(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  slug varchar(30) not null,
  status varchar(10) not null default 'active',
  note varchar(100),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  expires_at timestamptz,
  constraint aliases_status_check check (status in ('active','revoked')),
  constraint aliases_slug_format check (slug ~ '^[a-z0-9](?:[a-z0-9-]{1,28})[a-z0-9]$')
);

create unique index if not exists aliases_user_slug_unique on public.aliases(user_id, slug);

-- BLOCKS
create table if not exists public.blocks (
  id uuid primary key default gen_random_uuid(),
  view_id uuid not null references public.views(id) on delete cascade,
  type varchar(20) not null,
  title varchar(100),
  url text,
  icon varchar(50),
  "order" int not null default 0,
  data jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- SOCIALS
create table if not exists public.socials (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform varchar(20) not null,
  username varchar(100),
  url text,
  "order" int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint socials_user_platform_unique unique(user_id, platform)
);

-- ---------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------

-- Updated-at helper
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- 1) generate_citizen_id on profiles insert
create or replace function public.tg_profiles_generate_citizen_id()
returns trigger
language plpgsql
as $$
begin
  if new.citizen_id is null then
    new.citizen_id := public.generate_random_citizen_id();
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_generate_citizen_id on public.profiles;
create trigger profiles_generate_citizen_id
before insert on public.profiles
for each row
execute function public.tg_profiles_generate_citizen_id();

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

-- 2) create_default_views on profiles insert (4 views)
create or replace function public.tg_profiles_create_default_views()
returns trigger
language plpgsql
as $$
declare
  t1 text;
  t2 text;
  t3 text;
  t4 text;
begin
  loop
    begin
      t1 := public.generate_permanent_token(10);
      insert into public.views(user_id, name, label, visibility, permanent_token, "order")
      values (new.id, 'social', 'Social', 'public', t1, 0);
      exit;
    exception when unique_violation then
    end;
  end loop;

  loop
    begin
      t2 := public.generate_permanent_token(10);
      insert into public.views(user_id, name, label, visibility, permanent_token, "order")
      values (new.id, 'work', 'Work', 'private_link', t2, 1);
      exit;
    exception when unique_violation then
    end;
  end loop;

  loop
    begin
      t3 := public.generate_permanent_token(10);
      insert into public.views(user_id, name, label, visibility, permanent_token, "order")
      values (new.id, 'events', 'Events', 'public', t3, 2);
      exit;
    exception when unique_violation then
    end;
  end loop;

  loop
    begin
      t4 := public.generate_permanent_token(10);
      insert into public.views(user_id, name, label, visibility, permanent_token, "order")
      values (new.id, 'exclusive', 'Exclusive', 'private_link', t4, 3);
      exit;
    exception when unique_violation then
    end;
  end loop;

  return new;
end;
$$;

drop trigger if exists profiles_create_default_views on public.profiles;
create trigger profiles_create_default_views
after insert on public.profiles
for each row
execute function public.tg_profiles_create_default_views();

-- Updated-at on views/blocks/socials/aliases
drop trigger if exists views_set_updated_at on public.views;
create trigger views_set_updated_at
before update on public.views
for each row
execute function public.set_updated_at();

drop trigger if exists blocks_set_updated_at on public.blocks;
create trigger blocks_set_updated_at
before update on public.blocks
for each row
execute function public.set_updated_at();

drop trigger if exists socials_set_updated_at on public.socials;
create trigger socials_set_updated_at
before update on public.socials
for each row
execute function public.set_updated_at();

drop trigger if exists aliases_set_updated_at on public.aliases;
create trigger aliases_set_updated_at
before update on public.aliases
for each row
execute function public.set_updated_at();

-- 3) permanent_token immutability
create or replace function public.tg_views_permanent_token_immutable()
returns trigger
language plpgsql
as $$
begin
  if new.permanent_token is distinct from old.permanent_token then
    raise exception 'permanent_token is immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists views_permanent_token_immutable on public.views;
create trigger views_permanent_token_immutable
before update on public.views
for each row
execute function public.tg_views_permanent_token_immutable();

-- ---------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------

create index if not exists profiles_created_at_idx on public.profiles(created_at);
create index if not exists views_user_order_idx on public.views(user_id, "order");
create index if not exists views_user_name_idx on public.views(user_id, name);
create index if not exists views_token_idx on public.views(permanent_token);
create index if not exists aliases_view_id_idx on public.aliases(view_id);
create index if not exists aliases_user_status_idx on public.aliases(user_id, status);
create index if not exists blocks_view_order_idx on public.blocks(view_id, "order");
create index if not exists socials_user_order_idx on public.socials(user_id, "order");

-- ---------------------------------------------------------
-- Row Level Security (RLS)
-- ---------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.views enable row level security;
alter table public.aliases enable row level security;
alter table public.blocks enable row level security;
alter table public.socials enable row level security;

-- PROFILES: owner CRUD
drop policy if exists profiles_owner_select on public.profiles;
create policy profiles_owner_select on public.profiles
for select to authenticated
using (id = auth.uid());

drop policy if exists profiles_owner_insert on public.profiles;
create policy profiles_owner_insert on public.profiles
for insert to authenticated
with check (id = auth.uid());

drop policy if exists profiles_owner_update on public.profiles;
create policy profiles_owner_update on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

drop policy if exists profiles_owner_delete on public.profiles;
create policy profiles_owner_delete on public.profiles
for delete to authenticated
using (id = auth.uid());

-- PROFILES: public read
drop policy if exists profiles_public_read on public.profiles;
create policy profiles_public_read on public.profiles
for select to anon
using (true);

-- VIEWS: owner CRUD
drop policy if exists views_owner_select on public.views;
create policy views_owner_select on public.views
for select to authenticated
using (user_id = auth.uid());

drop policy if exists views_owner_insert on public.views;
create policy views_owner_insert on public.views
for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists views_owner_update on public.views;
create policy views_owner_update on public.views
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists views_owner_delete on public.views;
create policy views_owner_delete on public.views
for delete to authenticated
using (user_id = auth.uid());

-- VIEWS: public read only for public visibility
drop policy if exists views_public_read on public.views;
create policy views_public_read on public.views
for select to anon
using (visibility = 'public');

-- ALIASES: owner CRUD
drop policy if exists aliases_owner_select on public.aliases;
create policy aliases_owner_select on public.aliases
for select to authenticated
using (user_id = auth.uid());

drop policy if exists aliases_owner_insert on public.aliases;
create policy aliases_owner_insert on public.aliases
for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists aliases_owner_update on public.aliases;
create policy aliases_owner_update on public.aliases
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists aliases_owner_delete on public.aliases;
create policy aliases_owner_delete on public.aliases
for delete to authenticated
using (user_id = auth.uid());

-- BLOCKS: owner CRUD (through view ownership)
drop policy if exists blocks_owner_select on public.blocks;
create policy blocks_owner_select on public.blocks
for select to authenticated
using (
  exists (
    select 1 from public.views v
    where v.id = blocks.view_id
      and v.user_id = auth.uid()
  )
);

drop policy if exists blocks_owner_insert on public.blocks;
create policy blocks_owner_insert on public.blocks
for insert to authenticated
with check (
  exists (
    select 1 from public.views v
    where v.id = blocks.view_id
      and v.user_id = auth.uid()
  )
);

drop policy if exists blocks_owner_update on public.blocks;
create policy blocks_owner_update on public.blocks
for update to authenticated
using (
  exists (
    select 1 from public.views v
    where v.id = blocks.view_id
      and v.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.views v
    where v.id = blocks.view_id
      and v.user_id = auth.uid()
  )
);

drop policy if exists blocks_owner_delete on public.blocks;
create policy blocks_owner_delete on public.blocks
for delete to authenticated
using (
  exists (
    select 1 from public.views v
    where v.id = blocks.view_id
      and v.user_id = auth.uid()
  )
);

-- BLOCKS: public read only for blocks belonging to public views
drop policy if exists blocks_public_read on public.blocks;
create policy blocks_public_read on public.blocks
for select to anon
using (
  exists (
    select 1 from public.views v
    where v.id = blocks.view_id
      and v.visibility = 'public'
  )
);

-- SOCIALS: owner CRUD
drop policy if exists socials_owner_select on public.socials;
create policy socials_owner_select on public.socials
for select to authenticated
using (user_id = auth.uid());

drop policy if exists socials_owner_insert on public.socials;
create policy socials_owner_insert on public.socials
for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists socials_owner_update on public.socials;
create policy socials_owner_update on public.socials
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists socials_owner_delete on public.socials;
create policy socials_owner_delete on public.socials
for delete to authenticated
using (user_id = auth.uid());

-- SOCIALS: public read
drop policy if exists socials_public_read on public.socials;
create policy socials_public_read on public.socials
for select to anon
using (true);

-- ---------------------------------------------------------
-- Grants (anon limited columns on profiles)
-- ---------------------------------------------------------

revoke all on table public.profiles from anon;
revoke all on table public.views from anon;
revoke all on table public.aliases from anon;
revoke all on table public.blocks from anon;
revoke all on table public.socials from anon;

grant select (handle, display_name, bio, avatar_url, citizen_id, origin_flags, based_in_flag, based_in_city, created_at)
on table public.profiles to anon;

grant select on table public.views to anon;
grant select on table public.blocks to anon;
grant select on table public.socials to anon;

grant select, insert, update, delete on table public.profiles to authenticated;
grant select, insert, update, delete on table public.views to authenticated;
grant select, insert, update, delete on table public.aliases to authenticated;
grant select, insert, update, delete on table public.blocks to authenticated;
grant select, insert, update, delete on table public.socials to authenticated;