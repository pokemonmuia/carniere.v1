-- ============================================================
-- Carniere: database condiviso delle catture
-- Da incollare una volta sola in Supabase → SQL Editor → Run.
-- ============================================================

-- Profili: il nome con cui ti vedono gli altri
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  nickname text not null check (char_length(nickname) between 2 and 30),
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
drop policy if exists "profili leggibili dagli iscritti" on public.profiles;
create policy "profili leggibili dagli iscritti" on public.profiles
  for select to authenticated using (true);
drop policy if exists "modifica il tuo profilo" on public.profiles;
create policy "modifica il tuo profilo" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Alla registrazione crea il profilo col nome scelto
create or replace function public.crea_profilo()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, nickname)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data->>'nickname'), ''), 'Pescatore'))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists crea_profilo on auth.users;
create trigger crea_profilo after insert on auth.users
  for each row execute function public.crea_profilo();

-- Catture complete: le vede SOLO chi le ha registrate (fa anche da backup)
create table if not exists public.catches (
  id text primary key check (char_length(id) between 6 and 64),
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  visibility text not null default 'privata' check (visibility in ('esatta','zona','privata')),
  t timestamptz not null,
  lat double precision not null check (lat between -90 and 90),
  lon double precision not null check (lon between -180 and 180),
  data jsonb not null default '{}'::jsonb,
  photo_path text,
  updated_at timestamptz not null default now()
);
create index if not exists catches_user_idx on public.catches (user_id);
alter table public.catches enable row level security;
drop policy if exists "leggi le tue catture" on public.catches;
create policy "leggi le tue catture" on public.catches
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "aggiungi le tue catture" on public.catches;
create policy "aggiungi le tue catture" on public.catches
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "modifica le tue catture" on public.catches;
create policy "modifica le tue catture" on public.catches
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "cancella le tue catture" on public.catches;
create policy "cancella le tue catture" on public.catches
  for delete to authenticated using (user_id = auth.uid());

-- Catture condivise: copia pubblica per gli iscritti, compilata solo dal database.
-- "zona": posizione arrotondata a circa 1 km, senza nome dello spot e note.
-- "privata": non compare qui.
create table if not exists public.shared_catches (
  id text primary key references public.catches(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  precise boolean not null,
  t timestamptz not null,
  lat double precision not null,
  lon double precision not null,
  data jsonb not null,
  photo_path text,
  updated_at timestamptz not null default now()
);
create index if not exists shared_t_idx on public.shared_catches (t desc);
alter table public.shared_catches enable row level security;
drop policy if exists "catture condivise leggibili dagli iscritti" on public.shared_catches;
create policy "catture condivise leggibili dagli iscritti" on public.shared_catches
  for select to authenticated using (true);
-- nessuna policy di scrittura: solo il trigger qui sotto può scriverci

create or replace function public.aggiorna_condivisa()
returns trigger language plpgsql security definer set search_path = public as $$
declare d jsonb;
begin
  if new.visibility = 'privata' then
    delete from public.shared_catches where id = new.id;
    return new;
  end if;
  -- mai la posizione esatta dentro i dati del meteo
  d := new.data #- '{cond,lat}' #- '{cond,lon}';
  if new.visibility = 'zona' then
    d := d - 'spot' - 'notes' - 'place';
  end if;
  insert into public.shared_catches (id, user_id, precise, t, lat, lon, data, photo_path, updated_at)
  values (
    new.id, new.user_id, new.visibility = 'esatta', new.t,
    case when new.visibility = 'esatta' then new.lat else round(new.lat::numeric, 2)::double precision end,
    case when new.visibility = 'esatta' then new.lon else round(new.lon::numeric, 2)::double precision end,
    d, new.photo_path, now())
  on conflict (id) do update set
    precise = excluded.precise, t = excluded.t, lat = excluded.lat, lon = excluded.lon,
    data = excluded.data, photo_path = excluded.photo_path, updated_at = now();
  return new;
end $$;
drop trigger if exists aggiorna_condivisa on public.catches;
create trigger aggiorna_condivisa after insert or update on public.catches
  for each row execute function public.aggiorna_condivisa();

-- Foto: cartella pubblica in lettura, ognuno scrive solo nella propria
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('foto', 'foto', true, 2097152, array['image/jpeg'])
on conflict (id) do update set public = true, file_size_limit = 2097152, allowed_mime_types = array['image/jpeg'];
drop policy if exists "carica le tue foto" on storage.objects;
create policy "carica le tue foto" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'foto' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "sostituisci le tue foto" on storage.objects;
create policy "sostituisci le tue foto" on storage.objects
  for update to authenticated
  using (bucket_id = 'foto' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "cancella le tue foto" on storage.objects;
create policy "cancella le tue foto" on storage.objects
  for delete to authenticated
  using (bucket_id = 'foto' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "leggi le tue foto" on storage.objects;
create policy "leggi le tue foto" on storage.objects
  for select to authenticated
  using (bucket_id = 'foto' and (storage.foldername(name))[1] = auth.uid()::text);
