-- Memorial wall setup for Supabase
-- Run once in Supabase: SQL Editor > New query > paste all > Run
-- BEFORE running: change the passcode on the line marked ">>> CHANGE THIS <<<"

-- 1) Posts table
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null check (char_length(trim(name)) between 1 and 80),
  message text check (message is null or char_length(message) <= 5000),
  photos text[] not null default '{}' check (cardinality(photos) <= 3),
  constraint posts_has_content check (
    coalesce(char_length(trim(message)), 0) > 0 or cardinality(photos) > 0
  )
);

alter table public.posts enable row level security;

drop policy if exists "Anyone can read posts" on public.posts;
create policy "Anyone can read posts"
  on public.posts for select to anon, authenticated using (true);

drop policy if exists "Anyone can add posts" on public.posts;
create policy "Anyone can add posts"
  on public.posts for insert to anon, authenticated with check (true);
-- No update or delete policies: visitors cannot edit or delete posts.

-- 2) Admin passcode (hidden from visitors; no policies = no public access)
create table if not exists public.admin_settings (
  id int primary key default 1 check (id = 1),
  admin_key text not null
);
alter table public.admin_settings enable row level security;

insert into public.admin_settings (id, admin_key)
values (1, 'CHANGE-ME-to-a-long-passcode')   -- >>> CHANGE THIS <<<
on conflict (id) do update set admin_key = excluded.admin_key;

-- 3) Functions used by the "Manage" mode on the page
create or replace function public.is_admin(p_key text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (select 1 from public.admin_settings where admin_key = p_key);
$$;

create or replace function public.delete_post(p_post_id uuid, p_key text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.admin_settings where admin_key = p_key) then
    raise exception 'not authorized';
  end if;
  delete from public.posts where id = p_post_id;
  return found;
end;
$$;

grant execute on function public.is_admin(text) to anon, authenticated;
grant execute on function public.delete_post(uuid, text) to anon, authenticated;

-- 4) Photo storage (public bucket, anyone can upload)
insert into storage.buckets (id, name, public)
values ('memorial-photos', 'memorial-photos', true)
on conflict (id) do nothing;

drop policy if exists "Anyone can upload memorial photos" on storage.objects;
create policy "Anyone can upload memorial photos"
  on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'memorial-photos');
