-- Lapor Yuk: foto chat tidak lagi dibatasi jumlah lihat, cukup tampil 2 hari
-- lalu terhapus. Grup bisa punya foto profil. Jalankan setelah migrasi 16 Okt. Aman diulang.

-- max_views tidak dipakai lagi oleh aplikasi baru; default supaya insert tanpa kolom ini lolos.
alter table public.chat_photos alter column max_views set default 2;

-- Foto lewat 2 hari langsung tidak terlihat, walau barisnya belum sempat dibersihkan.
drop policy if exists "photos: room members read" on public.chat_photos;
create policy "photos: room members read"
  on public.chat_photos for select to authenticated
  using (created_at > now() - interval '2 days'
         and ((room like 'dm:%' and position((select auth.uid())::text in room) > 0 and public.dm_friends(room))
              or (room like 'grp:%' and public.is_room_member(room))));

-- Foto profil grup: path di bucket group_photos, folder = id grup.
alter table public.groups add column if not exists photo text check (char_length(photo) <= 200);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('group_photos', 'group_photos', true, 307200, array['image/jpeg'])
on conflict (id) do update set public = true, file_size_limit = 307200, allowed_mime_types = array['image/jpeg'];

-- Hanya pembuat grup yang boleh mengganti fotonya (sama seperti ganti nama).
drop policy if exists "group_photos upload owner" on storage.objects;
create policy "group_photos upload owner"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'group_photos'
              and exists (select 1 from public.groups g
                          where g.id::text = (storage.foldername(name))[1] and g.owner = (select auth.uid())));
drop policy if exists "group_photos read" on storage.objects;
create policy "group_photos read"
  on storage.objects for select to authenticated using (bucket_id = 'group_photos');
drop policy if exists "group_photos delete owner" on storage.objects;
create policy "group_photos delete owner"
  on storage.objects for delete to authenticated
  using (bucket_id = 'group_photos'
         and exists (select 1 from public.groups g
                     where g.id::text = (storage.foldername(name))[1] and g.owner = (select auth.uid())));
