# Estado del proyecto, pruebas pendientes y camino a App Store

## Cómo se ha verificado cada parte

| Parte | Verificación | Resultado |
|---|---|---|
| Backend | 18 tests automáticos contra PostgreSQL 16 real + arranque del servidor compilado | Pasan |
| NEXCore | Tests unitarios (`swift test`) en CI sobre macOS | Ver el último CI de la rama |
| App iOS | Compilación para simulador en CI sobre macOS | Ver el último CI de la rama |
| App iOS en ejecución | **No se ha ejecutado** ni en simulador ni en iPhone | Pendiente |

El desarrollo se ha hecho en un entorno Linux sin Xcode ni simulador. Todo lo que depende de ver la app
funcionando está en la lista de pendientes de abajo y no debe darse por comprobado.

## Qué hay implementado

**Navegación** — búsqueda de destinos, rutas con alternativas (rápida / corta / alternativa), ETA con tráfico,
giro a giro con voz en español, recálculo al desviarse, hora de llegada y distancia restante, opciones de evitar
peajes y autopistas, capa de tráfico, comparación de tiempo según hora de salida, aparcamientos cerca del destino.

**Avisos** — diez tipos; reporte en una pulsación; confirmación y "ya no está"; nivel de confianza; caducidad;
fusión de duplicados; reputación; política legal por país; aviso por voz con antelación según velocidad;
configuración por tipo.

**Resto** — bienvenida y permiso de ubicación, cuenta (registro, sesión, borrado), historial y estadísticas
locales, rutas habituales, modo noche automático por posición solar, ahorro de batería.

## Qué NO hay todavía

| Función pedida | Estado | Qué falta |
|---|---|---|
| Mapas sin conexión | No disponible | MapKit no lo permite; requiere otro proveedor (p. ej. Mapbox) |
| Incidencias oficiales de tráfico | No integrado | Contratar proveedor (TomTom / HERE) y escribir el adaptador de `TrafficIncidentProvider` |
| Radares fijos | Importador listo, sin datos | Obtener el conjunto de datos oficial y revisar su licencia |
| Límite de velocidad y guiado de carril | No disponible | MapKit no lo ofrece |
| Plazas de aparcamiento libres | No disponible | Proveedor de datos de aparcamiento |
| CarPlay | No implementado | Solicitar a Apple el entitlement `com.apple.developer.carplay-maps` y crear la escena CarPlay |
| Widgets y Live Activity | No implementado | Extensión WidgetKit / ActivityKit |
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
