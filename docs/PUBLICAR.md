# Cómo probar y publicar NEX

Hay tres formas de probar la app, de menos a más esfuerzo.

## 1. En el navegador, sin Mac ni cuenta de Apple (gratis)

Sirve para ver la interfaz, buscar destinos, calcular rutas y navegar. Los avisos de la comunidad y las cuentas
solo funcionan si el backend está publicado (paso 3).

1. En GitHub, pestaña **Actions** ▸ último **CI** en verde ▸ sección *Artifacts* ▸ descarga **NEX-simulador**.
   Dentro hay `NEX-simulador.zip`.
2. Crea una cuenta gratuita en **appetize.io** y sube ese `.zip` (Upload ▸ iOS).
3. Abre el enlace que te da y elige un iPhone. La ubicación se fija desde el panel de Appetize.

Es la app real ejecutándose en un simulador de iPhone en la nube, no una maqueta. El GPS, la voz en segundo plano
y la Live Activity no se pueden valorar bien ahí.

## 2. En tu iPhone con TestFlight (requiere cuenta de Apple Developer, 99 €/año)

Una vez configurado, cada publicación es un botón en GitHub.

### Una sola vez

1. **Cuenta**: alta en el Apple Developer Program con tu Apple ID.
2. **Identificador de la app**: los identificadores son únicos en todo Apple y `app.nex.ios` puede estar
   ocupado. Elige uno tuyo, por ejemplo `com.tunombre.nex`, y guárdalo en GitHub ▸ *Settings* ▸ *Secrets and
   variables* ▸ *Actions* ▸ pestaña **Variables** como `NEX_BUNDLE_ID`.
3. **Ficha en App Store Connect** (appstoreconnect.apple.com ▸ Apps ▸ ＋ Nueva app): plataforma iOS, nombre
   (si «NEX» está cogido, prueba «NEX Navegación»), idioma español y el identificador del paso 2. Si no aparece
   en la lista, se registra solo la primera vez que se ejecute el workflow; vuelve a crear la ficha después.
4. **Clave de API**: App Store Connect ▸ *Usuarios y acceso* ▸ *Integraciones* ▸ *App Store Connect API* ▸
   genera una clave con rol **App Manager**. Descarga el archivo `.p8` (solo se puede una vez).
5. **Secretos en GitHub** (*Settings* ▸ *Secrets and variables* ▸ *Actions* ▸ **Secrets**):

   | Secreto | Dónde está |
   |---|---|
   | `APPLE_TEAM_ID` | developer.apple.com ▸ *Membership details* ▸ Team ID (10 caracteres) |
   | `ASC_KEY_ID` | Identificador de la clave del paso 4 |
   | `ASC_ISSUER_ID` | *Issuer ID*, encima de la lista de claves |
   | `ASC_KEY_P8` | Contenido completo del archivo `.p8`, incluidas las líneas `BEGIN` y `END` |

### Cada vez que quieras una versión nueva

1. GitHub ▸ **Actions** ▸ **TestFlight** ▸ **Run workflow**. En *api_url* pon la dirección del backend
   (paso 3) o déjala vacía.
2. Tarda unos 15 minutos más el procesado de Apple (otros 10–30).
3. App Store Connect ▸ tu app ▸ **TestFlight** ▸ añádete como probador interno.
4. En el iPhone instala **TestFlight** desde la App Store y acepta la invitación.

Los probadores internos (hasta 100 de tu equipo) no necesitan revisión de Apple. Para probadores externos
Apple hace una revisión breve.

## 3. Backend público (para avisos y cuentas)

1. Cuenta en **render.com** (plan gratuito).
2. *New* ▸ **Blueprint** ▸ conecta este repositorio. `render.yaml` crea la API y la base de datos y genera
   el secreto de sesiones.
3. Cuando termine, copia la URL del servicio (`https://nex-api-xxxx.onrender.com`) y comprueba que
   `…/health` responde `{"status":"ok"}`.
4. Guárdala en GitHub como variable `NEX_API_BASE_URL` para que la usen el CI y TestFlight.

Limitaciones del plan gratuito de Render: el servicio se duerme tras 15 minutos sin uso (la primera petición
tarda unos segundos) y la base de datos gratuita caduca a los 30 días. Para algo más que pruebas, plan de pago.

## Antes de publicar en la App Store

Ver la lista de `docs/ESTADO.md` (revisión legal de avisos de controles, política de privacidad, normas de la
comunidad, comprobación de las condiciones de MapKit para guía en tiempo real, pruebas en dispositivo).
