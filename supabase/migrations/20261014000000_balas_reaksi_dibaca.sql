-- Lapor Yuk: balas pesan, reaksi emoji, tanda dibaca, penonton story, dan
-- balas story lewat DM. Jalankan setelah 20261013000000_grup_story.sql. Aman diulang.

-- reply_to: pesan yang dibalas. story_path: story yang dibalas (file story
-- terhapus setelah 24 jam; aplikasi lalu menampilkan "story tidak tersedia").
alter table public.chat add column if not exists reply_to bigint references public.chat (id) on delete set null;
alter table public.chat add column if not exists story_path text check (char_length(story_path) <= 200);

-- Satu reaksi per orang per pesan; memilih emoji lain menggantinya.
create table if not exists public.chat_reactions (
  message_id  bigint not null references public.chat (id) on delete cascade,
  user_id     uuid not null default auth.uid() references public.users (id) on delete cascade,
  room        text not null,
  emoji       text not null check (char_length(emoji) between 1 and 8),
  created_at  timestamptz not null default now(),
  primary key (message_id, user_id)
);

create index if not exists chat_reactions_room_idx on public.chat_reactions (room);

alter table public.chat_reactions enable row level security;

-- Subquery ke chat tetap terkena RLS chat: hanya pesan yang boleh dibaca.
drop policy if exists "reactions: read visible messages" on public.chat_reactions;
create policy "reactions: read visible messages"
  on public.chat_reactions for select to authenticated
  using (exists (select 1 from public.chat c where c.id = message_id and c.room = chat_reactions.room));
drop policy if exists "reactions: add own" on public.chat_reactions;
create policy "reactions: add own"
  on public.chat_reactions for insert to authenticated
  with check (user_id = (select auth.uid())
              and exists (select 1 from public.chat c where c.id = message_id and c.room = chat_reactions.room));
drop policy if exists "reactions: change own" on public.chat_reactions;
create policy "reactions: change own"
  on public.chat_reactions for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists "reactions: remove own" on public.chat_reactions;
create policy "reactions: remove own"
  on public.chat_reactions for delete to authenticated using (user_id = (select auth.uid()));

-- Tanda dibaca: anggota DM/grup boleh melihat kapan anggota lain terakhir
-- membuka ruang itu. Ruang Umum tidak (terlalu banyak pembaca).
drop policy if exists "reads: room members see receipts" on public.chat_reads;
create policy "reads: room members see receipts"
  on public.chat_reads for select to authenticated
  using ((room like 'dm:%' and position((select auth.uid())::text in room) > 0)
         or (room like 'grp:%' and public.is_room_member(room)));

-- Penonton story. Hanya pemilik story (dan penonton itu sendiri) yang bisa melihat.
create table if not exists public.story_views (
  story_id   bigint not null references public.stories (id) on delete cascade,
  viewer     uuid not null default auth.uid() references public.users (id) on delete cascade,
  viewed_at  timestamptz not null default now(),
  primary key (story_id, viewer)
);

alter table public.story_views enable row level security;

drop policy if exists "views: author and viewer read" on public.story_views;
create policy "views: author and viewer read"
  on public.story_views for select to authenticated
  using (viewer = (select auth.uid())
         or exists (select 1 from public.stories s where s.id = story_id and s.author = (select auth.uid())));
drop policy if exists "views: record own view" on public.story_views;
create policy "views: record own view"
  on public.story_views for insert to authenticated
  with check (viewer = (select auth.uid())
              and exists (select 1 from public.stories s where s.id = story_id and s.author <> (select auth.uid())));

grant select, insert, update, delete on public.chat_reactions to authenticated;
grant select, insert on public.story_views to authenticated;
revoke truncate, references, trigger on public.chat_reactions, public.story_views from anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['chat_reactions', 'chat_reads', 'story_views'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
