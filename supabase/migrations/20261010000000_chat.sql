-- Lapor Yuk: chat between users who connected their Google account.
-- Only chat data lives here; activities and evidence stay on each device.

create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 120),
  unit        text,
  position    text,
  avatar      text default 'sun',
  updated_at  timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles: signed-in users can read"
  on public.profiles for select to authenticated using (true);
create policy "profiles: insert own"
  on public.profiles for insert to authenticated with check ((select auth.uid()) = id);
create policy "profiles: update own"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

-- room = 'umum' (everyone) or 'dm:<uuid-a>:<uuid-b>' (sorted pair)
create table if not exists public.messages (
  id          bigint generated always as identity primary key,
  room        text not null check (room = 'umum' or room ~ '^dm:[0-9a-f-]{36}:[0-9a-f-]{36}$'),
  sender      uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 2000),
  created_at  timestamptz not null default now()
);

create index if not exists messages_room_created_idx on public.messages (room, created_at desc);
create index if not exists messages_sender_idx on public.messages (sender);

alter table public.messages enable row level security;

create policy "messages: read public room and own DMs"
  on public.messages for select to authenticated
  using (room = 'umum' or position((select auth.uid())::text in room) > 0);

create policy "messages: send as yourself"
  on public.messages for insert to authenticated
  with check (
    sender = (select auth.uid())
    and (room = 'umum' or position((select auth.uid())::text in room) > 0)
  );

create policy "messages: delete own"
  on public.messages for delete to authenticated using (sender = (select auth.uid()));

-- Live updates for the chat screen.
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.profiles;
