-- LicitaControl: inicio de sesión con usuario y contraseña.
-- Pegar completo en Supabase > SQL Editor > Run, después de schema.sql y roles.sql.
-- Se puede ejecutar más de una vez sin error.

-- 1. Nombre de usuario (único sin importar mayúsculas)
alter table public.perfiles add column if not exists usuario text;
create unique index if not exists perfiles_usuario_uq on public.perfiles (lower(usuario)) where usuario is not null;

-- 2. El rol siempre empieza como 'usuario' (también corrige un default vacío)
alter table public.perfiles alter column rol set default 'usuario';

-- 3. Al crear la cuenta se guarda el usuario que la persona eligió
create or replace function public.crear_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (user_id, email, usuario, rol)
  values (
    new.id,
    coalesce(new.email, new.raw_user_meta_data->>'email', ''),
    nullif(lower(trim(new.raw_user_meta_data->>'usuario')), ''),
    'usuario'
  )
  on conflict (user_id) do update set email = excluded.email;
  return new;
end $$;

-- 4. Para entrar con usuario: devuelve el correo de ese usuario (la página lo usa para iniciar sesión).
create or replace function public.email_por_usuario(u text) returns text
language sql stable security definer set search_path = public as $$
  select email from public.perfiles where lower(usuario) = lower(trim(u)) limit 1
$$;
revoke all on function public.email_por_usuario(text) from public;
grant execute on function public.email_por_usuario(text) to anon, authenticated;
