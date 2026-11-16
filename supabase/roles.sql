-- LicitaControl: roles (usuario, jefe, admin), prioridades y comentarios.
-- Pegar completo en Supabase > SQL Editor > Run, DESPUÉS de schema.sql.
-- Se puede ejecutar más de una vez sin error.

-- 1. Rol de cada persona. Todos empiezan como 'usuario'.
alter table public.perfiles add column if not exists rol text not null default 'usuario';
alter table public.perfiles drop constraint if exists perfiles_rol_check;
alter table public.perfiles add constraint perfiles_rol_check check (rol in ('usuario', 'jefe', 'admin'));

-- 2. Funciones para saber el rol de quien consulta (security definer evita ciclos con las políticas).
create or replace function public.mi_rol() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select rol from public.perfiles where user_id = auth.uid()), 'usuario')
$$;
create or replace function public.es_jefe() returns boolean
language sql stable security definer set search_path = public as $$
  select public.mi_rol() in ('jefe', 'admin')
$$;
create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select public.mi_rol() = 'admin'
$$;

-- 3. Perfiles: los jefes ven a todos; solo el admin cambia roles (y nunca el suyo).
drop policy if exists "jefes ven perfiles" on public.perfiles;
create policy "jefes ven perfiles" on public.perfiles for select using (public.es_jefe());
drop policy if exists "admin cambia roles" on public.perfiles;
create policy "admin cambia roles" on public.perfiles for update
  using (public.es_admin() and user_id <> auth.uid())
  with check (public.es_admin() and user_id <> auth.uid());

-- Solo se permite cambiar la columna rol (no el correo ni otros datos).
create or replace function public.solo_rol() returns trigger
language plpgsql as $$
begin
  if new.user_id <> old.user_id or new.email <> old.email then
    raise exception 'Solo se puede cambiar el rol';
  end if;
  return new;
end $$;
drop trigger if exists proteger_perfil on public.perfiles;
create trigger proteger_perfil before update on public.perfiles
  for each row execute function public.solo_rol();

-- 4. Licitaciones: los jefes pueden VER las de todos (editar sigue siendo solo del dueño).
drop policy if exists "jefes ven licitaciones" on public.licitaciones;
create policy "jefes ven licitaciones" on public.licitaciones for select using (public.es_jefe());

-- 5. Licitaciones prioritarias
create table if not exists public.prioridades (
  licitacion_id uuid primary key references public.licitaciones(id) on delete cascade,
  marcada_por uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.prioridades enable row level security;
drop policy if exists "jefes manejan prioridades" on public.prioridades;
create policy "jefes manejan prioridades" on public.prioridades for all
  using (public.es_jefe()) with check (public.es_jefe());
drop policy if exists "ver prioridades de mis licitaciones" on public.prioridades;
create policy "ver prioridades de mis licitaciones" on public.prioridades for select
  using (exists (select 1 from public.licitaciones l where l.id = licitacion_id and l.user_id = auth.uid()));

-- 6. Comentarios del jefe hacia el usuario
create table if not exists public.comentarios (
  id uuid primary key default gen_random_uuid(),
  licitacion_id uuid not null references public.licitaciones(id) on delete cascade,
  autor_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  texto text not null check (char_length(texto) between 1 and 1000),
  leido boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.comentarios enable row level security;
drop policy if exists "jefes manejan comentarios" on public.comentarios;
create policy "jefes manejan comentarios" on public.comentarios for all
  using (public.es_jefe()) with check (public.es_jefe() and autor_id = auth.uid());
drop policy if exists "ver comentarios de mis licitaciones" on public.comentarios;
create policy "ver comentarios de mis licitaciones" on public.comentarios for select
  using (exists (select 1 from public.licitaciones l where l.id = licitacion_id and l.user_id = auth.uid()));

-- El usuario solo puede marcar como leídos los comentarios de sus licitaciones.
create or replace function public.marcar_leido(cid uuid) returns void
language sql security definer set search_path = public as $$
  update public.comentarios c set leido = true
  where c.id = cid and exists (select 1 from public.licitaciones l where l.id = c.licitacion_id and l.user_id = auth.uid())
$$;

-- 7. Tú como admin (cambia el correo por el tuyo, ya con tu cuenta creada al iniciar sesión una vez):
-- update public.perfiles set rol = 'admin' where email = 'TU-CORREO';
