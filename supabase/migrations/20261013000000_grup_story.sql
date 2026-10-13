-- Lapor Yuk: grup dengan undangan (terima/tolak), status baca untuk badge,
-- dan story 24 jam. Jalankan setelah 20261010000000_chat.sql. Aman diulang.

create table if not exists public.groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 60),
  owner       uuid not null default auth.uid() references public.users (id) on delete cascade,
  created_at  timestamptz not null default now()
);

-- status 'invited' = undangan menunggu jawaban, 'member' = sudah menerima.
-- Menolak undangan / keluar grup = baris dihapus.
create table if not exists public.group_members (
  group_id    uuid not null references public.groups (id) on delete cascade,
  user_id     uuid not null references public.users (id) on delete cascade,
  status      text not null default 'invited' check (status in ('invited', 'member')),
  invited_by  uuid default auth.uid() references public.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index if not exists group_members_user_idx on public.group_members (user_id, status);

-- security definer supaya policy group_members tidak memanggil dirinya sendiri.
create or replace function public.is_member(gid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_members
                 where group_id = gid and user_id = auth.uid() and status = 'member');
$$;

create or replace function public.in_group(gid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_members where group_id = gid and user_id = auth.uid());
$$;

create or replace function public.is_room_member(r text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_members
                 where 'grp:' || group_id::text = r and user_id = auth.uid() and status = 'member');
$$;

alter table public.groups enable row level security;
alter table public.group_members enable row level security;

drop policy if exists "groups: members and invitees read" on public.groups;
create policy "groups: members and invitees read"
  on public.groups for select to authenticated
  using (owner = (select auth.uid()) or public.in_group(id));
drop policy if exists "groups: owner renames" on public.groups;
create policy "groups: owner renames"
  on public.groups for update to authenticated
  using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
drop policy if exists "groups: owner deletes" on public.groups;
create policy "groups: owner deletes"
  on public.groups for delete to authenticated using (owner = (select auth.uid()));

drop policy if exists "members: read own group" on public.group_members;
create policy "members: read own group"
  on public.group_members for select to authenticated
  using (user_id = (select auth.uid()) or public.is_member(group_id));
-- Anggota boleh mengundang orang lain (selalu berstatus 'invited').
drop policy if exists "members: member invites" on public.group_members;
create policy "members: member invites"
  on public.group_members for insert to authenticated
  with check (status = 'invited' and invited_by = (select auth.uid()) and public.is_member(group_id));
-- Yang diundang hanya bisa mengubah barisnya sendiri menjadi 'member' (terima).
drop policy if exists "members: accept own invite" on public.group_members;
create policy "members: accept own invite"
  on public.group_members for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()) and status = 'member');
-- Tolak / keluar sendiri, atau pemilik grup mengeluarkan anggota.
drop policy if exists "members: leave or owner removes" on public.group_members;
create policy "members: leave or owner removes"
  on public.group_members for delete to authenticated
  using (user_id = (select auth.uid())
         or exists (select 1 from public.groups g where g.id = group_id and g.owner = (select auth.uid())));

-- Buat grup + pemilik jadi anggota + undang beberapa orang sekaligus.
create or replace function public.create_group(group_name text, invitees uuid[])
returns uuid language plpgsql security definer set search_path = public as $$
declare gid uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into groups (name, owner) values (group_name, auth.uid()) returning id into gid;
  insert into group_members (group_id, user_id, status, invited_by) values (gid, auth.uid(), 'member', auth.uid());
  insert into group_members (group_id, user_id, status, invited_by)
    select gid, u, 'invited', auth.uid() from unnest(invitees) u
    where u <> auth.uid() and exists (select 1 from users where id = u)
  on conflict do nothing;
  return gid;
end $$;

-- Ruang grup: 'grp:<uuid>'.
alter table public.chat drop constraint if exists chat_room_check;
alter table public.chat add constraint chat_room_check check (
  room = 'umum'
  or room ~ '^dm:[0-9a-f-]{36}:[0-9a-f-]{36}$'
  or room ~ '^grp:[0-9a-f-]{36}$'
);

drop policy if exists "chat: read public room and own DMs" on public.chat;
create policy "chat: read public room and own DMs"
  on public.chat for select to authenticated
  using (room = 'umum'
         or (room like 'dm:%' and position((select auth.uid())::text in room) > 0)
         or (room like 'grp:%' and public.is_room_member(room)));

drop policy if exists "chat: send as yourself" on public.chat;
create policy "chat: send as yourself"
  on public.chat for insert to authenticated
  with check (
    sender = (select auth.uid())
    and (room = 'umum'
         or (room like 'dm:%' and position((select auth.uid())::text in room) > 0)
         or (room like 'grp:%' and public.is_room_member(room)))
  );

-- Kapan terakhir tiap pengguna membuka tiap ruang (untuk badge pesan baru).
create table if not exists public.chat_reads (
  user_id  uuid not null default auth.uid() references public.users (id) on delete cascade,
  room     text not null,
  read_at  timestamptz not null default now(),
  primary key (user_id, room)
);

alter table public.chat_reads enable row level security;
drop policy if exists "reads: own rows" on public.chat_reads;
create policy "reads: own rows"
  on public.chat_reads for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Pakai jam server, bukan jam HP, agar tidak meleset.
create or replace function public.mark_read(r text)
returns void language sql security invoker set search_path = public as $$
  insert into chat_reads (user_id, room, read_at) values (auth.uid(), r, now())
  on conflict (user_id, room) do update set read_at = excluded.read_at;
$$;

-- Jumlah pesan belum dibaca per ruang. RLS chat tetap berlaku (invoker).
-- Ruang yang belum pernah dibuka dihitung sejak pengguna pertama Sync.
create or replace function public.unread_counts()
returns table (room text, n bigint) language sql stable security invoker set search_path = public as $$
  select c.room, count(*)
  from chat c
  left join chat_reads r on r.room = c.room and r.user_id = auth.uid()
  where c.sender <> auth.uid()
    and c.created_at > coalesce(r.read_at, (select created_at from users where id = auth.uid()))
  group by c.room;
$$;

-- Story: foto terkompres, tampil 24 jam untuk semua pengguna.
create table if not exists public.stories (
  id          bigint generated always as identity primary key,
  author      uuid not null default auth.uid() references public.users (id) on delete cascade,
  path        text not null,
  caption     text check (char_length(caption) <= 200),
  size_kb     int,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '24 hours'
);

create index if not exists stories_expires_idx on public.stories (expires_at desc);

alter table public.stories enable row level security;
drop policy if exists "stories: read active" on public.stories;
create policy "stories: read active"
  on public.stories for select to authenticated using (expires_at > now());
drop policy if exists "stories: post own" on public.stories;
create policy "stories: post own"
  on public.stories for insert to authenticated
  with check (author = (select auth.uid()) and path like (select auth.uid())::text || '/%');
drop policy if exists "stories: delete own" on public.stories;
create policy "stories: delete own"
  on public.stories for delete to authenticated using (author = (select auth.uid()));

-- Menghapus baris story kedaluwarsa dan mengembalikan path filenya, supaya
-- aplikasi bisa ikut menghapus file di Storage.
create or replace function public.purge_stories()
returns setof text language sql security definer set search_path = public as $$
  delete from stories where expires_at <= now() returning path;
$$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('stories', 'stories', true, 1048576, array['image/jpeg'])
on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['image/jpeg'];

drop policy if exists "stories bucket: upload own folder" on storage.objects;
create policy "stories bucket: upload own folder"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'stories' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "stories bucket: read" on storage.objects;
create policy "stories bucket: read"
  on storage.objects for select to authenticated using (bucket_id = 'stories');
drop policy if exists "stories bucket: delete own or expired" on storage.objects;
create policy "stories bucket: delete own or expired"
  on storage.objects for delete to authenticated
  using (bucket_id = 'stories'
         and ((storage.foldername(name))[1] = (select auth.uid())::text
              or created_at < now() - interval '24 hours'));

grant select, update, delete on public.groups to authenticated;
grant select, insert, update, delete on public.group_members to authenticated;
grant select, insert, update, delete on public.chat_reads to authenticated;
grant select, insert, delete on public.stories to authenticated;
grant usage on all sequences in schema public to authenticated;
revoke truncate, references, trigger on public.groups, public.group_members, public.chat_reads, public.stories
  from anon, authenticated;
revoke execute on function public.create_group(text, uuid[]), public.purge_stories(),
  public.mark_read(text), public.unread_counts() from anon, public;
grant execute on function public.create_group(text, uuid[]), public.purge_stories(),
  public.mark_read(text), public.unread_counts(), public.is_member(uuid), public.in_group(uuid),
  public.is_room_member(text) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['groups', 'group_members', 'stories'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
