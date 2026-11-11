# Fase 2 — Arquitectura y tecnologías

## Visión general

```
┌──────────────────────── iOS (Swift / SwiftUI, iOS 17+) ────────────────────────┐
│  NEX (app)                                                                     │
│   Vistas SwiftUI ── AppModel ── Servicios (ubicación, voz, almacenamiento)     │
│        │                           │                                           │
│        │              Proveedores (protocolos de NEXCore)                      │
│        │              ├─ MapKitRoutingProvider   (rutas + ETA con tráfico)     │
│        │              ├─ MapKitSearchProvider    (búsqueda / autocompletado)   │
│        │              └─ MapKitParkingProvider   (ubicación de aparcamientos)  │
│  NEXCore (paquete Swift puro, sin UI, con tests)                               │
│   geometría · seguimiento de ruta · guía por voz · proximidad de alertas ·     │
│   noche/día · rutas habituales · estadísticas · cliente HTTP del backend       │
└───────────────────────────────────┬────────────────────────────────────────────┘
                                    │ HTTPS / JSON  (docs/API.md)
┌───────────────────────────────────▼────────────────────────────────────────────┐
│  Backend (Node 22 · TypeScript · Fastify)                                      │
│   auth (scrypt + JWT + refresh rotatorio) · alertas · votos · reputación ·     │
│   política legal por país · limitación de frecuencia                           │
│  PostgreSQL 16                                                                 │
└────────────────────────────────────────────────────────────────────────────────┘
```

Frontend y backend son proyectos separados (`ios/`, `backend/`) que solo comparten el contrato HTTP.

## Decisiones

| Decisión | Elección | Motivo |
|---|---|---|
| Lenguaje / UI | Swift 5.9+, SwiftUI, `@Observable` | Nativo, mejor rendimiento y consumo que soluciones híbridas |
| iOS mínimo | 17.0 | API moderna de MapKit para SwiftUI (`Map`, `MapPolyline`, `MapCameraPosition`) y Observation |
| Lógica de navegación | Paquete `NEXCore` sin dependencias de UI | Testeable sin simulador; reutilizable en CarPlay y widgets |
| Mapa y rutas (v0) | MapKit + `MKDirections` | Sin coste por uso ni clave; ETA con tráfico; alternativas; capa de tráfico en el mapa |
| Backend | Fastify + PostgreSQL | Sencillo de operar, escalable horizontalmente (sin estado en proceso salvo el limitador) |
| Consulta geográfica | Caja delimitadora indexada + haversine en SQL | No requiere extensiones; migrable a PostGIS cuando el volumen lo pida |
| Autenticación | Email + contraseña (scrypt), JWT de 15 min, refresh opaco rotatorio guardado con hash | Sin dependencia de terceros; tokens en Keychain en iOS |
| Generación del proyecto Xcode | XcodeGen (`ios/project.yml`) | El `.xcodeproj` no se versiona; se evita mantener un `pbxproj` a mano |

## Proveedores: qué da cada uno y qué no

Los precios cambian con frecuencia. Las páginas oficiales de Mapbox y TomTom **no se pudieron abrir** desde el
entorno de trabajo; las cifras marcadas con (*) proceden de terceros o de resúmenes de búsqueda y hay que
confirmarlas antes de firmar nada.

| Proveedor | Mapa | Rutas | Tráfico en ruta | Incidencias | Sin conexión | Coste orientativo | Observaciones |
|---|---|---|---|---|---|---|---|
| **Apple MapKit** | Sí | Sí (`MKDirections`) | Sí en ETA y capa visual | **No hay API** | **No** para apps de terceros | Sin coste por uso; límites por dispositivo no publicados | No da límites de velocidad ni guiado de carril. Las condiciones de Apple para "real-time route guidance" exigen un aviso en el EULA: verificar el texto vigente del Program License Agreement |
| **Mapbox Navigation SDK** | Sí | Sí | Sí | Parcial | **Sí** | Por usuario activo mensual + viajes; (*) ~0,30 $/MAU tras 100 y ~0,08 $/viaje tras 1.000 | Opción natural si se quiere offline, carriles y límites de velocidad |
| **TomTom** | Sí | Sí | Sí | **Sí** (Traffic Incidents) | Con SDK de pago | 2.500 peticiones/día gratuitas compartidas; (*) ~0,75 €/1.000 después | Buen candidato para incidencias oficiales |
| **HERE** | Sí | Sí | Sí | Sí | Con SDK de pago | Freemium; (*) fuentes discrepan entre 30.000 y 250.000 transacciones/mes | Confirmar en su página de precios |
| **Google Navigation SDK** | Sí | Sí | Sí | — | No | De pago por uso | Condiciones estrictas de uso |

### Consecuencias para NEX v0 (solo MapKit)

Funciona de verdad: mapa, búsqueda, rutas con alternativas, ETA con tráfico, capa de tráfico, predicción de ETA
por hora de salida, giro a giro con voz, recálculo, aparcamientos como puntos de interés.

**No disponible hasta conectar otro proveedor** (la app lo indica y no lo simula):

- Mapas sin conexión.
- Incidencias de tráfico oficiales (las alertas vienen solo de la comunidad y del importador de radares).
- Límite de velocidad de la vía y guiado de carril.
- Disponibilidad de plazas de aparcamiento en tiempo real.

Cada capacidad está detrás de un protocolo (`RoutingProvider`, `PlaceSearchProvider`, `ParkingProvider`,
`TrafficIncidentProvider`) con un descriptor `ProviderCapabilities`; cambiar de proveedor es escribir un
adaptador nuevo y registrarlo en `AppModel`.

## Sistema comunitario (resumen)

Detalle en `backend/src/alerts/trust.ts`.

- Cada voto pesa según la reputación del usuario: 0,3 para cuentas de menos de 24 h, 1,0 de base, hasta 1,5.
- `confianza = 1 − e^(−puntuación / 1,5)`; niveles `low` / `medium` / `high`.
- Un reporte duplicado (mismo tipo, cerca) se convierte en confirmación.
- Caducidad por tipo; cada confirmación la prolonga con tope.
- Retirada cuando el peso de "ya no está" supera el umbral.
- Reputación: sube cuando otros confirman tus avisos; baja cuando se retiran por negativas sin confirmación.
- Antiabuso: límite de reportes por ventana, proximidad obligatoria para reportar y votar, un voto por usuario,
  cuentas con reputación muy negativa dejan de contar.

Limitación conocida: la proximidad se valida con la posición que envía el cliente, que puede falsificarse. La
mitigación prevista es App Attest de Apple (pendiente).

## Consumo y calor

- `CLLocationManager` solo activo con el mapa en primer plano (precisión reducida) o navegando (precisión máxima,
  segundo plano permitido). Al terminar la navegación se detiene.
- Sondeo de alertas: cada 30 s navegando, 60 s con el mapa abierto, nunca en segundo plano sin navegación; se
  duplica con batería baja o estado térmico alto.
- La cámara del mapa se actualiza como mucho una vez por segundo.

## Seguridad y privacidad

- Contraseñas con scrypt y sal por usuario; comparación en tiempo constante.
- Refresh tokens de un solo uso guardados como hash SHA-256.
- El historial de viajes y las estadísticas se guardan **solo en el dispositivo**.
- El backend no almacena trazas de ubicación: solo la coordenada de cada aviso.
- Borrado de cuenta desde la app (requisito de App Store 5.1.1(v)).
