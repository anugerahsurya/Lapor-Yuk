-- Lapor Yuk: chat between app users (anonymous Supabase auth, no Google needed).
-- Only chat data lives here; activities and evidence stay on each device.
-- Safe to re-run: drops nothing, creates what is missing.

-- One row per device identity. A device registers itself by pressing "Sync"
-- in the app; is_online is the user's own Online/Offline switch.
create table if not exists public.users (
  id          uuid primary key references auth.users (id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 120),
  unit        text,
  position    text,
  avatar      text default 'sun',
  is_online   boolean not null default true,
  last_seen   timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists users_online_idx on public.users (is_online, last_seen desc);

alter table public.users enable row level security;

drop policy if exists "users: signed-in can read" on public.users;
create policy "users: signed-in can read"
  on public.users for select to authenticated using (true);
drop policy if exists "users: insert own" on public.users;
create policy "users: insert own"
  on public.users for insert to authenticated with check ((select auth.uid()) = id);
drop policy if exists "users: update own" on public.users;
create policy "users: update own"
  on public.users for update to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
drop policy if exists "users: delete own" on public.users;
create policy "users: delete own"
  on public.users for delete to authenticated using ((select auth.uid()) = id);

-- room = 'umum' (everyone) or 'dm:<uuid-a>:<uuid-b>' (sorted pair)
create table if not exists public.chat (
  id          bigint generated always as identity primary key,
  room        text not null check (room = 'umum' or room ~ '^dm:[0-9a-f-]{36}:[0-9a-f-]{36}$'),
  sender      uuid not null default auth.uid() references public.users (id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 2000),
  created_at  timestamptz not null default now()
);

create index if not exists chat_room_created_idx on public.chat (room, created_at desc);
create index if not exists chat_sender_idx on public.chat (sender);

alter table public.chat enable row level security;

drop policy if exists "chat: read public room and own DMs" on public.chat;
create policy "chat: read public room and own DMs"
  on public.chat for select to authenticated
  using (room = 'umum' or position((select auth.uid())::text in room) > 0);

drop policy if exists "chat: send as yourself" on public.chat;
create policy "chat: send as yourself"
  on public.chat for insert to authenticated
  with check (
    sender = (select auth.uid())
    and (room = 'umum' or position((select auth.uid())::text in room) > 0)
  );

drop policy if exists "chat: delete own" on public.chat;
create policy "chat: delete own"
  on public.chat for delete to authenticated using (sender = (select auth.uid()));

-- Live updates for the chat screens.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat') then
    alter publication supabase_realtime add table public.chat;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'users') then
    alter publication supabase_realtime add table public.users;
  end if;
end $$;
