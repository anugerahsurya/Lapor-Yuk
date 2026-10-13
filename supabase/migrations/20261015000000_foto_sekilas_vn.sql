-- Lapor Yuk: foto sekilas (jumlah lihat terbatas lalu terhapus) dan pesan suara
-- (VN) yang hanya bertahan 3 hari. Jalankan setelah migrasi 14 Oktober. Aman diulang.

-- Foto sekilas: tiap penerima boleh melihat maksimal 2 kali. Jatah total =
-- 2 (DM) atau 2 x jumlah anggota (grup). Lewat itu, foto dihapus.
create table if not exists public.chat_photos (
  id           bigint generated always as identity primary key,
  room         text not null,
  sender       uuid not null default auth.uid() references public.users (id) on delete cascade,
  path         text not null,
  max_views    int not null check (max_views between 1 and 200),
  total_views  int not null default 0,
  created_at   timestamptz not null default now()
);

create index if not exists chat_photos_room_idx on public.chat_photos (room);

create table if not exists public.chat_photo_views (
  photo_id  bigint not null references public.chat_photos (id) on delete cascade,
  user_id   uuid not null default auth.uid() references public.users (id) on delete cascade,
  views     int not null default 0,
  primary key (photo_id, user_id)
);

alter table public.chat_photos enable row level security;
alter table public.chat_photo_views enable row level security;

drop policy if exists "photos: room members read" on public.chat_photos;
create policy "photos: room members read"
  on public.chat_photos for select to authenticated
  using ((room like 'dm:%' and position((select auth.uid())::text in room) > 0)
         or (room like 'grp:%' and public.is_room_member(room)));
drop policy if exists "photos: send own" on public.chat_photos;
create policy "photos: send own"
  on public.chat_photos for insert to authenticated
  with check (sender = (select auth.uid()) and path like (select auth.uid())::text || '/%'
              and ((room like 'dm:%' and position((select auth.uid())::text in room) > 0)
                   or (room like 'grp:%' and public.is_room_member(room))));
drop policy if exists "photos: sender deletes" on public.chat_photos;
create policy "photos: sender deletes"
  on public.chat_photos for delete to authenticated using (sender = (select auth.uid()));

drop policy if exists "photo views: own rows" on public.chat_photo_views;
create policy "photo views: own rows"
  on public.chat_photo_views for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Referensi dari pesan chat ke media. ON DELETE SET NULL supaya saat media
-- habis/kedaluwarsa, pesannya tetap ada tapi menampilkan "tidak tersedia".
alter table public.chat add column if not exists photo_id bigint references public.chat_photos (id) on delete set null;
alter table public.chat add column if not exists voice_path text check (char_length(voice_path) <= 200);
alter table public.chat add column if not exists voice_secs int;

-- Satu kali buka foto. Pengirim tidak memakai jatah. Mengembalikan apakah boleh
-- dilihat, dan bila jatah habis, path file untuk dihapus aplikasi dari Storage.
create or replace function public.view_photo(pid bigint)
returns table (allowed boolean, deleted boolean, gone_path text)
language plpgsql security definer set search_path = public as $$
declare ph chat_photos; v int; tv int;
begin
  select * into ph from chat_photos where id = pid;
  if not found then
    return query select false, false, null::text; return;
  end if;
  if ph.sender = auth.uid() then
    return query select true, false, null::text; return;
  end if;
  select views into v from chat_photo_views where photo_id = pid and user_id = auth.uid();
  v := coalesce(v, 0);
  if v >= 2 then
    return query select false, false, null::text; return;
  end if;
  insert into chat_photo_views (photo_id, user_id, views) values (pid, auth.uid(), 1)
    on conflict (photo_id, user_id) do update set views = chat_photo_views.views + 1;
  update chat_photos set total_views = total_views + 1 where id = pid returning total_views into tv;
  if tv >= ph.max_views then
    delete from chat_photos where id = pid;
    return query select true, true, ph.path; return;
  end if;
  return query select true, false, null::text;
end $$;

-- Sisa lihat untuk badge "sisa N" (untuk penerima: 2 - sudah dilihat).
create or replace function public.photo_left(pid bigint)
returns int language sql stable security invoker set search_path = public as $$
  select greatest(0, 2 - coalesce((select views from chat_photo_views
                                   where photo_id = pid and user_id = auth.uid()), 0));
$$;

-- Buang foto sekilas yang terlanjur menggantung > 2 hari (cadangan bila jatah
-- tak pernah habis). Mengembalikan path untuk dihapus dari Storage.
create or replace function public.purge_chat_photos()
returns setof text language sql security definer set search_path = public as $$
  delete from chat_photos where created_at < now() - interval '2 days' returning path;
$$;

-- VN hanya bertahan 3 hari: hapus file lalu kosongkan voice_path (pesannya tetap
-- ada, menampilkan "VN kedaluwarsa").
create or replace function public.purge_voice()
returns setof text language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select id, voice_path from chat where voice_path is not null and created_at < now() - interval '3 days' loop
    update chat set voice_path = null where id = r.id;
    return next r.voice_path;
  end loop;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat_media', 'chat_media', true, 1048576, array['image/jpeg'])
on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['image/jpeg'];

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat_voice', 'chat_voice', true, 5242880, array['audio/mp4', 'audio/aac', 'audio/mpeg'])
on conflict (id) do update set public = true, file_size_limit = 5242880,
  allowed_mime_types = array['audio/mp4', 'audio/aac', 'audio/mpeg'];

do $$
declare b text;
begin
  foreach b in array array['chat_media', 'chat_voice'] loop
    execute format($f$drop policy if exists "%1$s upload own" on storage.objects$f$, b);
    execute format($f$create policy "%1$s upload own" on storage.objects for insert to authenticated
      with check (bucket_id = %1$L and (storage.foldername(name))[1] = (select auth.uid())::text)$f$, b);
    execute format($f$drop policy if exists "%1$s read" on storage.objects$f$, b);
    execute format($f$create policy "%1$s read" on storage.objects for select to authenticated
      using (bucket_id = %1$L)$f$, b);
    execute format($f$drop policy if exists "%1$s delete own" on storage.objects$f$, b);
    execute format($f$create policy "%1$s delete own" on storage.objects for delete to authenticated
      using (bucket_id = %1$L and (storage.foldername(name))[1] = (select auth.uid())::text)$f$, b);
  end loop;
end $$;

grant select, insert, delete on public.chat_photos to authenticated;
grant select, insert, update, delete on public.chat_photo_views to authenticated;
revoke truncate, references, trigger on public.chat_photos, public.chat_photo_views from anon, authenticated;
revoke execute on function public.view_photo(bigint), public.photo_left(bigint),
  public.purge_chat_photos(), public.purge_voice() from anon, public;
grant execute on function public.view_photo(bigint), public.photo_left(bigint),
  public.purge_chat_photos(), public.purge_voice() to authenticated;

do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_photos') then
    alter publication supabase_realtime add table public.chat_photos;
  end if;
end $$;
