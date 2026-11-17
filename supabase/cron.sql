-- Revisa los avisos cada minuto, así cada aviso sale a la hora elegida (con menos de un minuto de diferencia). Antes de ejecutarlo:
--   1) Activa las extensiones pg_cron y pg_net en Supabase > Database > Extensions.
--   2) Cambia TU-PROYECTO por el identificador de tu proyecto y TU-CLAVE por la misma clave que guardaste como CRON_SECRET.
select cron.schedule(
  'avisos-licitaciones',
  '* * * * *',
  $$
  select net.http_post(
    url := 'https://ootvayyyfmndjcqsdfsd.supabase.co/functions/v1/send-alerts',
    headers := '{"Content-Type": "application/json", "x-cron-secret": "TU-CLAVE"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);
