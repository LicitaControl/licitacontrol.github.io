-- LicitaControl: fase "apertura realizada" de cada licitación.
-- Pegar completo en Supabase > SQL Editor > Run. Se puede ejecutar más de una vez sin error.

-- Cuándo se marcó la apertura como realizada (vacío = todavía por abrir).
alter table public.licitaciones add column if not exists abierta_en timestamptz;

-- Las licitaciones que ya existían y cuya apertura ya pasó se consideran abiertas,
-- para que no aparezcan todas como "por abrir".
update public.licitaciones
   set abierta_en = apertura::timestamptz
 where abierta_en is null and (apertura < current_date or estado = 'Entregada');

-- Permite al dueño marcar la apertura (la política "mis licitaciones" ya cubre update).
