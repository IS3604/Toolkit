-- ============================================================
-- EditSimple Toolkit — Supabase schema (single-file HTML version)
-- Run once in Supabase → SQL Editor. Safe to re-run.
-- ============================================================

create extension if not exists "pgcrypto";

-- ---------- Tables ----------
create table if not exists public.categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text not null unique,
  icon_name   text default 'folder',
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists public.resources (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  description      text not null default '',
  details          text,                                   -- optional long-form info for the detail panel
  url              text not null,
  category_id      uuid references public.categories(id) on delete set null,
  status           text not null default 'active'
                   check (status in ('active','beta','under_development')),
  icon_name        text default 'box',                     -- lucide icon key (fallback)
  icon_url         text,                                   -- uploaded icon, stored as a small data: URL
  tags             text[] not null default '{}',
  is_pinned        boolean not null default false,          -- admin-pinned to top
  open_in_new_tab  boolean not null default true,
  sort_order       int not null default 0,
  click_count      int not null default 0,
  last_opened_at   timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists resources_category_idx on public.resources(category_id);
create index if not exists resources_sort_idx on public.resources(sort_order);

create table if not exists public.announcements (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  body        text,
  kind        text not null default 'info' check (kind in ('launch','maintenance','info')),
  resource_id uuid references public.resources(id) on delete set null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.resource_clicks (
  id          bigint generated always as identity primary key,
  resource_id uuid not null references public.resources(id) on delete cascade,
  clicked_at  timestamptz not null default now()
);
create index if not exists resource_clicks_res_idx on public.resource_clicks(resource_id, clicked_at desc);

-- Admins = Supabase Auth users listed here
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- ---------- Helpers ----------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists resources_touch on public.resources;
create trigger resources_touch before update on public.resources
for each row execute function public.touch_updated_at();

-- Usage tracking: callable by anyone (anon), only increments counters
create or replace function public.track_click(rid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.resource_clicks(resource_id) values (rid);
  update public.resources
     set click_count = click_count + 1, last_opened_at = now()
   where id = rid;
end; $$;
grant execute on function public.track_click(uuid) to anon, authenticated;
grant execute on function public.is_admin() to anon, authenticated;

-- ---------- Row Level Security ----------
alter table public.categories      enable row level security;
alter table public.resources       enable row level security;
alter table public.announcements   enable row level security;
alter table public.resource_clicks enable row level security;
alter table public.admins          enable row level security;

-- Read: everyone. Write: admins only.
do $$
declare t text;
begin
  foreach t in array array['categories','resources','announcements'] loop
    execute format('drop policy if exists "%1$s_read" on public.%1$s', t);
    execute format('drop policy if exists "%1$s_admin_write" on public.%1$s', t);
    execute format('create policy "%1$s_read" on public.%1$s for select using (true)', t);
    execute format('create policy "%1$s_admin_write" on public.%1$s for all using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

drop policy if exists "clicks_admin_read" on public.resource_clicks;
create policy "clicks_admin_read" on public.resource_clicks for select using (public.is_admin());

drop policy if exists "admins_self_read" on public.admins;
create policy "admins_self_read" on public.admins for select using (user_id = auth.uid() or public.is_admin());

-- ---------- Realtime: push edits to open Toolkit pages ----------
do $$ begin
  alter publication supabase_realtime add table public.resources, public.categories, public.announcements;
exception when duplicate_object then null; end $$;

-- ============================================================
-- Seed data (only inserted if tables are empty)
-- ============================================================
do $$
declare c_tools uuid; c_dash uuid; c_lib uuid; c_admin uuid; c_other uuid;
begin
  if exists (select 1 from public.categories) then return; end if;

  insert into public.categories(name, slug, icon_name, sort_order) values ('Tools','tools','wrench',1) returning id into c_tools;
  insert into public.categories(name, slug, icon_name, sort_order) values ('Dashboards','dashboards','layout-dashboard',2) returning id into c_dash;
  insert into public.categories(name, slug, icon_name, sort_order) values ('Libraries','libraries','library',3) returning id into c_lib;
  insert into public.categories(name, slug, icon_name, sort_order) values ('Admin Panels','admin-panels','shield',4) returning id into c_admin;
  insert into public.categories(name, slug, icon_name, sort_order) values ('Other Resources','other','globe',5) returning id into c_other;

  insert into public.resources(name, description, url, category_id, status, icon_name, tags, is_pinned, sort_order) values
  ('Caption & Title Generator', 'Generate transcripts, titles, captions, thumbnail text and burned-in subtitles for videos.', 'https://captiontitlegenerator.editsimple.in/', c_tools, 'active', 'captions', '{video,captions,subtitles,titles,transcript}', true, 1),
  ('EditSimple Invoices', 'Create and manage client invoices.', 'https://is3604.github.io/Invoice.Dev/', c_tools, 'active', 'receipt', '{invoice,billing,finance}', false, 2),
  ('EditSimple Studio', 'Workspace for researching, drafting, designing and delivering social posts for doctor and law-firm clients.', 'https://editsimple.vercel.app/dashboard', c_dash, 'active', 'layout-dashboard', '{social,content,clients,posts}', true, 3),
  ('EditSimple CAS — Leads', 'Staff portal for tracking and managing leads.', 'https://editsimple-cass.vercel.app/leads', c_dash, 'active', 'users', '{leads,crm,sales}', false, 4),
  ('EditSimple Libraries', 'Royalty-free stock videos for lawyers, doctors and professional practices, browsable by practice area.', 'http://libraries.editsimple.in', c_lib, 'active', 'library', '{stock,video,assets,b-roll}', true, 5),
  ('Caption Generator Admin', 'Admin panel for the Caption & Title Generator.', 'https://captiontitlegenerator.editsimple.in/admin.html', c_admin, 'active', 'settings', '{admin,captions}', false, 6),
  ('Libraries Admin', 'Admin panel for managing EditSimple Libraries content.', 'http://libraries.editsimple.in/admin.html', c_admin, 'active', 'settings', '{admin,library,stock}', false, 7),
  ('HR Portal', 'Employee portal — sign in with your EditSimple work email.', 'https://editsimple-hr.vercel.app/', c_other, 'active', 'briefcase', '{hr,employees,people}', false, 8),
  ('EditSimple Website', 'Public site: YouTube channel management for dermatology and aesthetic practices.', 'https://is3604.github.io/EDS-Web/', c_other, 'active', 'globe', '{website,marketing,youtube}', false, 9);

  insert into public.announcements(title, body, kind) values
  ('Welcome to EditSimple Toolkit', 'Every EditSimple tool, dashboard and library — one click away. Press ⌘K / Ctrl K to quick-launch.', 'launch');
end $$;

-- ============================================================
-- Make yourself an admin (run after creating your user in
-- Authentication → Users):
--   insert into public.admins(user_id)
--   select id from auth.users where email = 'you@editsimple.in';
-- ============================================================
