# NEX

Navegador GPS para iOS con avisos comunitarios. Negro, antracita y rojo; sin publicidad.

| Carpeta | Contenido |
|---|---|
| `ios/NEXCore` | Paquete Swift sin interfaz: seguimiento de ruta, guía por voz, avisos, cliente HTTP. Con tests. |
| `ios/NEX` | App SwiftUI (iOS 17+). |
| `backend` | API en Node 22 + Fastify + PostgreSQL: cuentas y avisos comunitarios. Con tests. |
| `docs` | [Investigación](docs/INVESTIGACION.md) · [Arquitectura](docs/ARQUITECTURA.md) · [API](docs/API.md) · [Estado y pruebas pendientes](docs/ESTADO.md) |

## Backend

Requisitos: Node 22 y PostgreSQL 14 o superior.

```bash
cd backend
createdb nex && createdb nex_test
cp .env.example .env            # ajustar DATABASE_URL y JWT_SECRET
npm ci
npm run migrate
npm run dev                     # http://localhost:8080
npm test                        # usa TEST_DATABASE_URL o postgres://nex:nex@localhost:5432/nex_test
```

Radares fijos de una fuente oficial (CSV `lat,lon[,heading]`): `npm run import:cameras -- radares.csv ES`.

## App iOS

Requisitos: macOS con Xcode 16 o superior y [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd ios
brew install xcodegen
xcodegen generate
open NEX.xcodeproj
```

La app apunta a `http://localhost:8080` (ajuste `NEX_API_BASE_URL` en `ios/project.yml`). En el simulador
funciona tal cual con el backend local; en un iPhone físico hay que poner la IP del Mac o una URL pública con HTTPS.

Para simular un trayecto en el simulador: *Features ▸ Location ▸ Freeway Drive*.

Tests del núcleo: `cd ios/NEXCore && swift test`.
