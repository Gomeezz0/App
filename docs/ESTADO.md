# Estado del proyecto, pruebas pendientes y camino a App Store

## Cómo se ha verificado cada parte

| Parte | Verificación | Resultado |
|---|---|---|
| Backend | 18 tests automáticos contra PostgreSQL real, en local y en CI | Pasan |
| NEXCore | Tests unitarios (`swift test`) en CI sobre macOS | Pasan |
| App iOS | Compilación para simulador en CI sobre macOS (app, widgets y Live Activity) | Compila |
| App iOS en ejecución | Prueba de interfaz en simulador (iPhone, iOS en español) contra el backend real con avisos sembrados: bienvenida, permiso, mapa, búsqueda, rutas, favorito, previsión por hora de salida, inicio de navegación, inicio de sesión, reporte, voto, perfil, avisos, favoritos, historial y ajustes | Pasa; capturas en `docs/capturas/` |
| Guía en movimiento, llegada y guardado del viaje | Modo de conducción simulada (`-nexSimulatedDrive`, solo depuración) dentro de la prueba de interfaz | **Pendiente**: el código está subido pero GitHub no asignó runner de macOS a su ejecución; hay que relanzar el CI |
| iPhone físico | — | **No probado** |

El desarrollo se ha hecho en Linux sin Xcode; toda la verificación de iOS es la del CI en macOS de GitHub
(`.github/workflows/ci.yml`). El simulador no entrega cambios de posición a la app durante una prueba, por eso
la guía en movimiento se comprueba reproduciendo el trayecto dentro de la app y no con GPS real.

Fallos reales encontrados y corregidos gracias a la ejecución en simulador:

- La guía se quedaba en «Buscando señal GPS…» al iniciar con el vehículo parado.
- Bucle de recálculo al salir desde un punto alejado de la calzada (plaza, aparcamiento).
- Las indicaciones de giro salían en inglés porque la app no declaraba el español como idioma.

## Qué hay implementado

**Navegación** — búsqueda de destinos, rutas con alternativas (rápida / corta / alternativa), ETA con tráfico,
giro a giro con voz en español, recálculo al desviarse, hora de llegada y distancia restante, opciones de evitar
peajes y autopistas, capa de tráfico, comparación de tiempo según hora de salida, aparcamientos cerca del destino.

**Avisos** — diez tipos; reporte en una pulsación; confirmación y "ya no está"; nivel de confianza; caducidad;
fusión de duplicados; reputación; política legal por país; aviso por voz con antelación según velocidad;
configuración por tipo.

**Resto** — favoritos, widget de búsqueda y Live Activity de navegación, bienvenida y permiso de ubicación, cuenta (registro, sesión, borrado), historial y estadísticas
locales, rutas habituales, modo noche automático por posición solar, ahorro de batería.

## Qué NO hay todavía

| Función pedida | Estado | Qué falta |
|---|---|---|
| Mapa con estilo propio (negro y antracita, autopistas rojizas) | No disponible | MapKit no admite estilos; requiere cambiar de proveedor (ver `docs/DISENO.md`) |
| Mapas sin conexión | No disponible | MapKit no lo permite; requiere otro proveedor (p. ej. Mapbox) |
| Incidencias oficiales de tráfico | No integrado | Contratar proveedor (TomTom / HERE) y escribir el adaptador de `TrafficIncidentProvider` |
| Radares fijos | Importador listo, sin datos | Obtener el conjunto de datos oficial y revisar su licencia |
| Límite de velocidad y guiado de carril | No disponible | MapKit no lo ofrece |
| Plazas de aparcamiento libres | No disponible | Proveedor de datos de aparcamiento |
| CarPlay | No implementado | Solicitar a Apple el entitlement `com.apple.developer.carplay-maps` y crear la escena CarPlay |
| Widgets y Live Activity | Implementado y compila; **no probado en ejecución** | Probar en dispositivo (la Isla Dinámica y la pantalla bloqueada no se ven en la prueba automática) |
| Notificaciones push | No implementado | Clave APNs, registro de dispositivos en backend |
| Reporte por voz | No implementado | — |
| Desvío automático por vías cortadas confirmadas | No implementado | MapKit no admite zonas a evitar; requiere otro motor de rutas |
| Sign in with Apple | No implementado | Opcional mientras solo haya correo y contraseña |
| Recuperación de contraseña y verificación de correo | No implementado | Servicio de envío de correo |
| Protección frente a GPS falsificado | No implementado | App Attest |

## Pruebas pendientes

### En simulador (necesita un Mac)

- [ ] Flujo completo: bienvenida → permiso → mapa → búsqueda → vista previa → navegación → llegada → historial.
- [ ] Trayecto simulado (*Freeway Drive*): avance de la maniobra, voz, recálculo, llegada.
- [ ] **Momento exacto de cada indicación.** `MapKitRoutingProvider.convert` supone que la maniobra de cada paso
      de `MKRoute` ocurre al final de su tramo. Si las indicaciones sonaran un tramo antes o después, hay que
      cambiar esa función (está comentado dónde).
- [ ] El mapa cambia de claro a oscuro con el ajuste de aspecto y con el modo automático.
- [ ] Al arrastrar el mapa durante la navegación deja de seguir y aparece el botón de recentrar.
- [ ] Registro, inicio de sesión, renovación de token tras 15 minutos, cierre de sesión, borrado de cuenta.
- [ ] Reportar, confirmar y desmentir con dos cuentas; ver cómo cambia el distintivo en el mapa.
- [ ] Tamaños de pantalla: iPhone SE, estándar y Pro Max. Texto dinámico grande. VoiceOver.
- [ ] Sin red: búsqueda, cálculo de ruta, recálculo y lista de avisos muestran su mensaje y no se bloquean.

### En iPhone físico

- [ ] Precisión del GPS real y comportamiento en túneles y calles estrechas (falsos desvíos).
- [ ] Navegación con la pantalla bloqueada: la voz sigue y aparece el indicador azul de ubicación.
- [ ] La voz baja la música y la restaura; convivencia con llamadas y con Bluetooth del coche.
- [ ] Consumo de batería y temperatura en un trayecto de una hora, con Instruments (Energy Log), comparado con
      Apple Maps en el mismo trayecto.
- [ ] Que el GPS se detiene al terminar la navegación y al pasar a segundo plano sin navegación.
- [ ] Antelación de los avisos a velocidades de ciudad y de autopista.

### Backend

- [ ] Prueba de carga de `GET /v1/alerts` con muchos avisos en una ciudad.
- [ ] El limitador de peticiones está en memoria: con más de una instancia hay que moverlo a Redis.
- [ ] Copias de seguridad y monitorización.

## Preparación para App Store

- [ ] Cuenta de Apple Developer, identificador `app.nex.ios` (o el definitivo) y firma.
- [ ] Backend desplegado con HTTPS y `NEX_API_BASE_URL` de producción.
- [ ] Revisión jurídica de los avisos de controles y radares por país (`backend/src/alerts/policy.ts`).
- [ ] Comprobar en el Apple Developer Program License Agreement vigente las condiciones para apps de guía en
      tiempo real con MapKit y el aviso que exige en el acuerdo de licencia de usuario.
- [ ] Comprobar que el nombre "NEX" está libre en App Store y como marca en la categoría de navegación.
- [ ] Política de privacidad y ficha de privacidad: ubicación (funcionalidad de la app; no se usa para
      seguimiento), correo electrónico e identificador de cuenta.
- [ ] Términos de uso y normas de la comunidad; canal para denunciar abusos (directriz 1.2 de contenido
      generado por usuarios).
- [ ] Capturas, descripción, icono definitivo.
- [ ] TestFlight con conductores reales antes de publicar.

## Estado del CI el 13 de noviembre de 2026

- Ejecuciones de macOS (compilación para simulador, pruebas de NEXCore y prueba de interfaz): **sin resultado**.
  GitHub no asignó runner de macOS en las ejecuciones 43246682214, 43249914272 (intento 1 y 2); se cancelaron a
  los 15 minutos. No hay artefacto `NEX-simulador` ni capturas nuevas.
- Backend (tipos y 18 tests): **pasa** en la ejecución 43249914272.
- Por tanto, el mapa con velo negro, los ajustes con iconos, la entrada de marca y el trayecto simulado no están
  verificados en CI. Lo verificado en CI sobre macOS es la última ejecución completa anterior a estos cambios.
- Pendiente: relanzar el CI cuando haya runner de macOS y revisar capturas y artefacto. TestFlight no se ha lanzado
  porque requiere los secretos de la cuenta de Apple Developer.
