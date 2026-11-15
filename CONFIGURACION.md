# Configurar inicio de sesión con Outlook y avisos por correo

Todo es gratis para empezar. Necesitas cuatro cosas: un proyecto de Supabase, una app registrada en Microsoft, un servicio de correo y pegar dos datos en `index.html`.

## 1. Crear el proyecto en Supabase
1. Entra a supabase.com y crea una cuenta.
2. Toca **New project**, ponle un nombre y una contraseña de base de datos. Elige la región más cercana.
3. Cuando termine, ve a **Project Settings → API** y copia:
   - **Project URL** (algo como `https://abcd1234.supabase.co`).
   - **anon public key**. Esta clave es pública y puede ir en la página. Nunca copies la `service_role`.
4. Ve a **SQL Editor**, pega todo el archivo `supabase/schema.sql` y toca **Run**.

## 2. Registrar la app en Microsoft (para el botón "Iniciar sesión con Outlook")
1. Entra a portal.azure.com con tu cuenta Outlook y abre **Microsoft Entra ID → App registrations → New registration**.
2. Nombre: `LicitaControl`. En **Supported account types** elige la opción que incluye **cuentas personales de Microsoft**.
3. En **Redirect URI** elige **Web** y pega `https://TU-PROYECTO.supabase.co/auth/v1/callback`.
4. Toca **Register** y copia el **Application (client) ID**.
5. Ve a **Certificates & secrets → New client secret**, créalo y copia el **Value** enseguida (después ya no se ve).
6. En Supabase ve a **Authentication → Providers → Azure**, actívalo y pega:
   - Client ID y Client Secret.
   - **Azure Tenant URL**: `https://login.microsoftonline.com/consumers` (solo cuentas personales).
7. En **Authentication → URL Configuration** pon como **Site URL** `https://kxv17.github.io/LicitaControl/` y agrégala también en **Redirect URLs**.

## 3. Servicio de correo
Elige uno:
- **Brevo** (recomendado para empezar, sin dominio propio): crea la cuenta en brevo.com, ve a **Senders** y verifica un correo remitente, y crea una **API key** en **SMTP & API**. Plan gratis: 300 correos al día.
- **Resend**: crea la cuenta y una API key. Con el correo de pruebas solo puede enviar a tu propio correo. Para varias personas necesitas verificar un dominio tuyo.

## 4. Publicar la función de avisos
1. En Supabase ve a **Edge Functions → Create function**, llámala exactamente `send-alerts` y pega el contenido de `supabase/functions/send-alerts/index.ts`.
2. En los ajustes de la función desactiva **Verify JWT** (la función valida el acceso por su cuenta).
3. En **Edge Functions → Secrets** agrega:

| Secreto | Valor |
|---|---|
| `CRON_SECRET` | Una clave larga inventada por ti |
| `SITE_URL` | `https://kxv17.github.io/LicitaControl/` |
| `MAIL_FROM` | El correo remitente verificado |
| `MAIL_FROM_NAME` | `LicitaControl` |
| `BREVO_API_KEY` o `RESEND_API_KEY` | La clave del servicio elegido |

## 5. Programar la revisión cada 15 minutos
1. En **Database → Extensions** activa `pg_cron` y `pg_net`.
2. Abre `supabase/cron.sql`, cambia `TU-PROYECTO` y `TU-CLAVE` (la misma de `CRON_SECRET`) y ejecútalo en el SQL Editor.

## 6. Conectar la página
En `index.html` busca esta línea y pega tus dos datos:

```js
var SB_URL='', SB_KEY='';
```

Sube el cambio a GitHub. Al abrir la página aparece el botón **Iniciar sesión con Outlook**. Ya dentro, en **Licitaciones** hay un botón **Enviarme un correo de prueba** para confirmar que todo llega.

## Cómo funcionan los avisos
- Cada persona ve solo sus licitaciones.
- Se envía un correo por cada fecha de apertura y de entrega, según los días de anticipación y la hora que elegiste al agregarla. La hora se respeta con un margen de hasta 15 minutos.
- Si una entrega vence sin marcarse como entregada, llega un aviso de entrega vencida (solo durante los primeros 3 días).
- No se repiten avisos ya enviados.
