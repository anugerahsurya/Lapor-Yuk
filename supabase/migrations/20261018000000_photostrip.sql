-- Lapor Yuk: Photostrip bareng. Satu orang mengajak 1-5 orang lain di DM/grup,
-- tiap orang mengisi satu kotak dengan kamera masing-masing, lalu hasilnya bisa
-- diunduh sebagai PNG 4R. Data dan foto dibersihkan setelah 3 hari.
-- Jalankan setelah migrasi 17 Okt. Aman diulang.

create table if not exists public.photostrips (
  id          bigint generated always as identity primary key,
  room        text not null check (room like 'dm:%' or room like 'grp:%'),
  creator     uuid not null default auth.uid() references public.users (id) on delete cascade,
  template    int not null default 0 check (template between 0 and 4),
  created_at  timestamptz not null default now()
);

create table if not exists public.photostrip_members (
  strip_id  bigint not null references public.photostrips (id) on delete cascade,
  user_id   uuid not null references public.users (id) on delete cascade,
  slot      int not null check (slot between 0 and 5),
  path      text check (char_length(path) <= 200),
  shot_at   timestamptz,
  primary key (strip_id, user_id),
  unique (strip_id, slot)
);

alter table public.chat add column if not exists strip_id bigint references public.photostrips (id) on delete set null;

-- Boleh membuka ruang ini: DM dengan teman, atau anggota grup.
create or replace function public.room_access(r text)
returns boolean language sql stable security definer set search_path = public as $$
  select (r like 'dm:%' and position(auth.uid()::text in r) > 0 and dm_friends(r))
      or (r like 'grp:%' and is_room_member(r));
$$;

alter table public.photostrips enable row level security;
alter table public.photostrip_members enable row level security;

drop policy if exists "strips: room members read" on public.photostrips;
create policy "strips: room members read"
  on public.photostrips for select to authenticated using (public.room_access(room));

drop policy if exists "strip members: room members read" on public.photostrip_members;
create policy "strip members: room members read"
  on public.photostrip_members for select to authenticated
  using (exists (select 1 from public.photostrips s where s.id = strip_id and public.room_access(s.room)));

-- Peserta hanya mengisi kotaknya sendiri; kolom lain dikunci lewat grant di bawah.
drop policy if exists "strip members: fill own slot" on public.photostrip_members;
create policy "strip members: fill own slot"
  on public.photostrip_members for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Membuat photostrip + kotak peserta + pesan ajakan di chat sekaligus.
-- Pembuat selalu kotak pertama. DM: lawan bicara. Grup: anggota yang sudah bergabung.
create or replace function public.create_photostrip(r text, tpl int, invitees uuid[])
returns bigint language plpgsql security definer set search_path = public as $$
declare sid bigint; others uuid[]; u uuid; i int := 1;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not room_access(r) then raise exception 'tidak punya akses ke ruang ini'; end if;
  if r like 'dm:%' then
    others := array(select distinct x from unnest(invitees) x
                    where x <> auth.uid() and position(x::text in r) > 0);
  else
    others := array(select distinct x from unnest(invitees) x
                    where x <> auth.uid() and exists (
                      select 1 from group_members m
                      where 'grp:' || m.group_id::text = r and m.user_id = x and m.status = 'member'));
  end if;
  if cardinality(others) < 1 then raise exception 'ajak minimal satu orang'; end if;
  if cardinality(others) > 5 then raise exception 'maksimal 6 orang termasuk kamu'; end if;

  insert into photostrips (room, creator, template) values (r, auth.uid(), least(greatest(tpl, 0), 4))
    returning id into sid;
  insert into photostrip_members (strip_id, user_id, slot) values (sid, auth.uid(), 0);
  foreach u in array others loop
    insert into photostrip_members (strip_id, user_id, slot) values (sid, u, i);
    i := i + 1;
  end loop;
  insert into chat (room, sender, body, strip_id) values (r, auth.uid(), 'Yuk foto bareng!', sid);
  return sid;
end $$;

-- Hapus photostrip lewat 3 hari; mengembalikan path foto untuk dihapus dari Storage.
create or replace function public.purge_photostrips()
returns setof text language plpgsql security definer set search_path = public as $$
begin
  return query
    select m.path from photostrip_members m join photostrips s on s.id = m.strip_id
    where s.created_at < now() - interval '3 days' and m.path is not null;
  delete from photostrips where created_at < now() - interval '3 days';
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photostrips', 'photostrips', true, 1048576, array['image/jpeg'])
on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['image/jpeg'];

drop policy if exists "photostrips upload own" on storage.objects;
create policy "photostrips upload own"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'photostrips' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "photostrips read" on storage.objects;
create policy "photostrips read"
  on storage.objects for select to authenticated using (bucket_id = 'photostrips');
-- Milik sendiri, atau sudah lewat 3 hari (siapa pun boleh membersihkan).
drop policy if exists "photostrips delete own or old" on storage.objects;
create policy "photostrips delete own or old"
  on storage.objects for delete to authenticated
  using (bucket_id = 'photostrips'
         and ((storage.foldername(name))[1] = (select auth.uid())::text
              or created_at < now() - interval '3 days'));

grant select on public.photostrips to authenticated;
grant select on public.photostrip_members to authenticated;
grant update (path, shot_at) on public.photostrip_members to authenticated;
revoke truncate, references, trigger on public.photostrips, public.photostrip_members from anon, authenticated;
revoke execute on function public.create_photostrip(text, int, uuid[]), public.purge_photostrips(),
  public.room_access(text) from anon, public;
grant execute on function public.create_photostrip(text, int, uuid[]), public.purge_photostrips(),
  public.room_access(text) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['photostrips', 'photostrip_members'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
