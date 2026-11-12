# API del backend de NEX

Base: `https://<host>/v1`. JSON en ambos sentidos. Las rutas marcadas con 🔒 requieren
`Authorization: Bearer <accessToken>`.

Errores: `{ "error": { "code": "…", "message": "…" } }`. El `message` está en español y se puede mostrar tal cual.

## Cuenta

| Método | Ruta | Cuerpo | Respuesta |
|---|---|---|---|
| POST | `/auth/register` | `email`, `password` (≥ 10), `displayName` (2–40) | 201 · sesión + `user` · 409 `email_taken` |
| POST | `/auth/login` | `email`, `password` | 200 · sesión + `user` · 401 `invalid_credentials` |
| POST | `/auth/refresh` | `refreshToken` | 200 · sesión nueva · 401 `invalid_refresh_token` |
| POST | `/auth/logout` | `refreshToken` | 204 |
| GET 🔒 | `/me` | — | perfil |
| PATCH 🔒 | `/me` | `displayName` | perfil |
| DELETE 🔒 | `/me` | `password` | 204 · 403 `invalid_credentials` |

Sesión: `{ accessToken, refreshToken, expiresIn }`. El token de acceso dura 15 minutos. El refresh token es de
**un solo uso**: cada renovación devuelve uno nuevo e invalida el anterior.

Perfil: `{ id, email, displayName, reputation, createdAt, stats: { reports, confirmationsReceived, votesCast } }`.

## Avisos

### `GET /alerts?lat&lon&radius`

Pública. `radius` en metros (100–50 000; por defecto 10 000). Devuelve hasta 300 avisos activos ordenados por
distancia. Con sesión, `mine` y `myVote` vienen rellenos.

```json
{ "alerts": [ {
  "id": "uuid", "type": "accident", "lat": 40.4168, "lon": -3.7038, "heading": 90,
  "approximate": false, "zoneRadiusM": null, "source": "community",
  "confidence": 0.736, "level": "medium", "confirmations": 1, "denials": 0,
  "createdAt": "2026-11-11T10:00:00.000Z", "expiresAt": "2026-11-11T11:00:00.000Z",
  "mine": false, "myVote": null
} ] }
```

- `type`: `police`, `speed_camera`, `accident`, `traffic_jam`, `stopped_vehicle`, `road_object`, `roadworks`,
  `road_closed`, `weather`, `hazard`.
- `level`: `low` (< 0,35), `medium`, `high` (≥ 0,75). La app no anuncia por voz los `low`.
- `approximate: true`: por política legal del país la posición es el centro de una celda de ~1 km y
  `zoneRadiusM` indica el radio a dibujar.
- `source: "official"`: dato importado de una fuente oficial; confianza 1, sin caducidad y sin votos.

### `POST /alerts` 🔒

`{ type, lat, lon, heading?, country?, reporterLat, reporterLon }` — `country` es el código ISO de dos letras.

- 201 `{ alert, merged: false }` — aviso creado.
- 200 `{ alert, merged: true }` — ya había uno del mismo tipo cerca; cuenta como confirmación.
- 422 `too_far` — el punto está a más de 2 km de quien reporta.
- 429 `too_many_reports` — más de 10 avisos en 10 minutos.
- 451 `not_available_in_region` — tipo de aviso desactivado en ese país.

### `POST /alerts/:id/votes` 🔒

`{ vote: "confirm" | "deny", lat, lon }` → `{ alert, removed }`. `alert` es `null` si el aviso se ha retirado o
ha dejado de ser visible.

- 404 `not_found` · 409 `own_alert` · 409 `official_alert` · 422 `too_far` (a más de 3 km).

## Reglas por tipo

| Tipo | Vida inicial | Vida máxima | Radio de fusión |
|---|---|---|---|
| police | 45 min | 3 h | 300 m |
| speed_camera (comunidad) | 30 días | 1 año | 150 m |
| accident | 60 min | 4 h | 200 m |
| traffic_jam | 30 min | 3 h | 500 m |
| stopped_vehicle, road_object, hazard | 45 min | 3 h | 150 m |
| roadworks | 24 h | 30 días | 200 m |
| road_closed | 6 h | 14 días | 200 m |
| weather | 2 h | 12 h | 1 km |

Cada confirmación prolonga la caducidad medio periodo inicial desde ese momento, sin superar la vida máxima.

## Servicios externos

| Servicio | Uso en NEX | Clave | Estado |
|---|---|---|---|
| Apple MapKit | Mapa, búsqueda, rutas, ETA con tráfico, aparcamientos | No | Integrado |
| Backend NEX | Cuentas y avisos comunitarios | — | Implementado y testeado |
| APNs | Notificaciones push | Clave .p8 de Apple | **No integrado** |
| Proveedor de incidencias (TomTom / HERE) | Incidencias oficiales de tráfico | Sí, de pago según uso | **No integrado** (existe el protocolo `TrafficIncidentProvider`) |
| Fuente oficial de radares | Radares fijos | Según fuente | Importador listo (`npm run import:cameras`); **sin datos incluidos** |
