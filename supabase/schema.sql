-- LicitaControl: tablas y permisos. Pegar completo en Supabase > SQL Editor > Run.

-- Perfil de cada usuario (guarda su correo para los avisos)
create table if not exists public.perfiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  created_at timestamptz not null default now()
);
alter table public.perfiles enable row level security;
create policy "ver mi perfil" on public.perfiles for select using (auth.uid() = user_id);

create or replace function public.crear_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (user_id, email)
  values (new.id, coalesce(new.email, new.raw_user_meta_data->>'email', ''))
  on conflict (user_id) do update set email = excluded.email;
  return new;
end $$;

drop trigger if exists al_crear_usuario on auth.users;
create trigger al_crear_usuario after insert on auth.users
  for each row execute function public.crear_perfil();

-- Licitaciones: cada persona ve y edita solo las suyas
create table if not exists public.licitaciones (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  num text not null,
  inst text not null,
  obj text not null,
  tipo text not null check (tipo in ('reducida', 'menor', 'mayor')),
  estado text not null default 'Activa' check (estado in ('Activa', 'Entregada')),
  apertura date not null,
  entrega date not null,
  al_apertura int[] not null default '{3}',
  hora_apertura time not null default '08:00',
  al_entrega int[] not null default '{3}',
  hora_entrega time not null default '08:00',
  editada_en timestamptz,
  entregada_en timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, num)
);
alter table public.licitaciones enable row level security;
create policy "mis licitaciones" on public.licitaciones
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Registro de avisos ya enviados, para no repetirlos. Sin políticas: solo lo usa el servidor.
create table if not exists public.avisos_enviados (
  id bigserial primary key,
  licitacion_id uuid not null references public.licitaciones(id) on delete cascade,
  tipo text not null,
  dias int not null,
  enviado_en timestamptz not null default now(),
  unique (licitacion_id, tipo, dias)
);
alter table public.avisos_enviados enable row level security;
