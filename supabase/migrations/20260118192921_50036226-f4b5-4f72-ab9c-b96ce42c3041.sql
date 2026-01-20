-- Fix function search_path for security

-- 1. generate_permanent_token
create or replace function public.generate_permanent_token(p_length int default 10)
returns text
language plpgsql
set search_path = public
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

-- 2. generate_random_citizen_id
create or replace function public.generate_random_citizen_id()
returns text
language plpgsql
set search_path = public
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

-- 3. set_updated_at
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- 4. tg_profiles_generate_citizen_id
create or replace function public.tg_profiles_generate_citizen_id()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.citizen_id is null then
    new.citizen_id := public.generate_random_citizen_id();
  end if;
  return new;
end;
$$;

-- 5. tg_profiles_create_default_views
create or replace function public.tg_profiles_create_default_views()
returns trigger
language plpgsql
set search_path = public
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

-- 6. tg_views_permanent_token_immutable
create or replace function public.tg_views_permanent_token_immutable()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.permanent_token is distinct from old.permanent_token then
    raise exception 'permanent_token is immutable';
  end if;
  return new;
end;
$$;