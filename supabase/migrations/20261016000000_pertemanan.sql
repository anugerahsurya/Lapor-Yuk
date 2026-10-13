-- Lapor Yuk: pertemanan. User tidak lagi otomatis saling terhubung; harus
-- Connect dan diterima dulu. Hanya teman yang bisa saling DM, lihat story, dan
-- saling diundang ke grup. Jalankan setelah migrasi 15 Okt. Aman diulang.

-- Satu baris per permintaan: requester -> addressee. Berteman = ada baris
-- 'accepted' di salah satu arah.
create table if not exists public.connections (
  requester     uuid not null default auth.uid() references public.users (id) on delete cascade,
  addressee     uuid not null references public.users (id) on delete cascade,
  status        text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at    timestamptz not null default now(),
  responded_at  timestamptz,
  primary key (requester, addressee),
  check (requester <> addressee)
);

create index if not exists connections_addressee_idx on public.connections (addressee, status);

alter table public.connections enable row level security;

drop policy if exists "connections: read own" on public.connections;
create policy "connections: read own"
  on public.connections for select to authenticated
  using (requester = (select auth.uid()) or addressee = (select auth.uid()));

grant select on public.connections to authenticated;
revoke truncate, references, trigger on public.connections from anon, authenticated;

create or replace function public.is_friend(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from connections where status = 'accepted'
    and ((requester = auth.uid() and addressee = other) or (requester = other and addressee = auth.uid()))
  );
$$;

-- Kedua uuid DM ada di nama ruang dan keduanya berteman (dipakai policy chat).
create or replace function public.dm_friends(r text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from connections c where c.status = 'accepted'
    and (c.requester = auth.uid() or c.addressee = auth.uid())
    and position(c.requester::text in r) > 0 and position(c.addressee::text in r) > 0
  );
$$;

-- Kirim permintaan. Bila lawan sudah mengirim duluan, langsung jadi teman.
create or replace function public.request_connection(other uuid)
returns text language plpgsql security definer set search_path = public as $$
begin
  if other = auth.uid() then raise exception 'tidak bisa menambah diri sendiri'; end if;
  if not exists (select 1 from users where id = other) then raise exception 'pengguna tidak ada'; end if;
  if is_friend(other) then return 'accepted'; end if;
  if exists (select 1 from connections where requester = other and addressee = auth.uid() and status = 'pending') then
    update connections set status = 'accepted', responded_at = now()
      where requester = other and addressee = auth.uid();
    return 'accepted';
  end if;
  insert into connections (requester, addressee, status) values (auth.uid(), other, 'pending')
    on conflict (requester, addressee) do nothing;
  return 'pending';
end $$;

-- Terima / tolak permintaan yang masuk ke saya.
create or replace function public.respond_connection(other uuid, accept boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if accept then
    update connections set status = 'accepted', responded_at = now()
      where requester = other and addressee = auth.uid() and status = 'pending';
  else
    delete from connections where requester = other and addressee = auth.uid();
  end if;
end $$;

-- Batalkan permintaan, tolak, atau putus pertemanan (kedua arah).
create or replace function public.remove_connection(other uuid)
returns void language sql security definer set search_path = public as $$
  delete from connections
  where (requester = auth.uid() and addressee = other) or (requester = other and addressee = auth.uid());
$$;

revoke execute on function public.request_connection(uuid), public.respond_connection(uuid, boolean),
  public.remove_connection(uuid), public.is_friend(uuid), public.dm_friends(text) from anon, public;
grant execute on function public.request_connection(uuid), public.respond_connection(uuid, boolean),
  public.remove_connection(uuid), public.is_friend(uuid), public.dm_friends(text) to authenticated;

-- DM sekarang butuh berteman. Ruang Umum tetap terbuka; grup lewat keanggotaan.
drop policy if exists "chat: read public room and own DMs" on public.chat;
create policy "chat: read public room and own DMs"
  on public.chat for select to authenticated
  using (room = 'umum'
         or (room like 'dm:%' and position((select auth.uid())::text in room) > 0 and public.dm_friends(room))
         or (room like 'grp:%' and public.is_room_member(room)));

drop policy if exists "chat: send as yourself" on public.chat;
create policy "chat: send as yourself"
  on public.chat for insert to authenticated
  with check (
    sender = (select auth.uid())
    and (room = 'umum'
         or (room like 'dm:%' and position((select auth.uid())::text in room) > 0 and public.dm_friends(room))
         or (room like 'grp:%' and public.is_room_member(room)))
  );

-- Story hanya terlihat oleh teman (dan diri sendiri).
drop policy if exists "stories: read active" on public.stories;
create policy "stories: read active"
  on public.stories for select to authenticated
  using (expires_at > now() and (author = (select auth.uid()) or public.is_friend(author)));

-- Hanya teman yang bisa diundang ke grup.
drop policy if exists "members: member invites" on public.group_members;
create policy "members: member invites"
  on public.group_members for insert to authenticated
  with check (status = 'invited' and invited_by = (select auth.uid())
              and public.is_member(group_id) and public.is_friend(user_id));

-- create_group hanya mengundang yang sudah berteman.
create or replace function public.create_group(group_name text, invitees uuid[])
returns uuid language plpgsql security definer set search_path = public as $$
declare gid uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into groups (name, owner) values (group_name, auth.uid()) returning id into gid;
  insert into group_members (group_id, user_id, status, invited_by) values (gid, auth.uid(), 'member', auth.uid());
  insert into group_members (group_id, user_id, status, invited_by)
    select gid, u, 'invited', auth.uid() from unnest(invitees) u
    where u <> auth.uid() and is_friend(u)
  on conflict do nothing;
  return gid;
end $$;

-- DM photo juga butuh berteman (grup lewat keanggotaan).
drop policy if exists "photos: room members read" on public.chat_photos;
create policy "photos: room members read"
  on public.chat_photos for select to authenticated
  using ((room like 'dm:%' and position((select auth.uid())::text in room) > 0 and public.dm_friends(room))
         or (room like 'grp:%' and public.is_room_member(room)));
drop policy if exists "photos: send own" on public.chat_photos;
create policy "photos: send own"
  on public.chat_photos for insert to authenticated
  with check (sender = (select auth.uid()) and path like (select auth.uid())::text || '/%'
              and ((room like 'dm:%' and position((select auth.uid())::text in room) > 0 and public.dm_friends(room))
                   or (room like 'grp:%' and public.is_room_member(room))));

do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'connections') then
    alter publication supabase_realtime add table public.connections;
  end if;
end $$;
