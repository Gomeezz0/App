# Fase 1 — Investigación y análisis competitivo

Fecha: noviembre de 2026.

## Alcance y límites de esta investigación

- Se ha hecho con búsqueda web sobre prensa tecnológica, foros (Apple Community, MacRumors, foros de marcas de
  coche), Trustpilot y artículos que recopilan reseñas de App Store / Google Play / Reddit.
- **No se ha probado Waze en un dispositivo** ni se han leído reseñas directamente dentro de App Store, Google Play
  o Reddit (no accesibles desde el entorno de trabajo). Lo que se atribuye a esas tiendas procede de artículos
  que las citan.
- La "frecuencia aparente" es una estimación cualitativa según cuántas fuentes independientes repiten el
  problema. No es una medición estadística.
- Varias quejas de CarPlay proceden de hilos de 2021–2022; pueden estar corregidas en versiones actuales.

## Qué ofrece Waze (funcionalidad general usada como referencia)

| Área | Funcionalidad |
|---|---|
| Navegación | Giro a giro con voz, rutas alternativas, ETA con tráfico, recálculo, guiado de carril, sugerencias de ruta según viajes anteriores (desactivable) |
| Alertas | Policía, radares fijos y de semáforo, accidentes, retenciones, vehículos detenidos, objetos, obras, cortes, meteorología; más recientes: badenes, cambios de límite, rotondas, zonas escolares, vehículos de emergencia detenidos |
| Comunidad | Reporte por menú y, desde 2025, por voz en lenguaje natural ("Conversational Reporting"); confirmación de avisos; editores de mapa voluntarios |
| Personalización | Voces, sonidos de alerta, modo "menos hablador" (2026), modo moto |
| Restricciones legales | El reporte de policía está desactivado en países que lo prohíben (p. ej. Suiza) |
| Modelo de negocio | Gratuita con publicidad sobre el mapa |

## Problemas detectados y respuesta de NEX

Gravedad: **A** = afecta a la seguridad o inutiliza la navegación · **M** = degrada el uso · **B** = molestia.

| # | Categoría | Problema descrito por usuarios | Frecuencia aparente | Grav. | Cómo lo aborda NEX | Estado en NEX |
|---|---|---|---|---|---|---|
| 1 | Batería | Consumo superior al de otros navegadores, también en segundo plano | Alta | M | Precisión GPS máxima solo durante navegación; sin actualizaciones de ubicación fuera de ella; sondeo de alertas adaptativo; sin SDK de publicidad ni analítica | Implementado (pendiente de medir en dispositivo) |
| 2 | Calor | El teléfono se calienta en trayectos largos | Media | M | Monitor de estado térmico de iOS: al subir a `serious` se reduce frecuencia de cámara, sondeo y animaciones | Implementado (pendiente de medir) |
| 3 | Publicidad | Anuncios que tapan el mapa, también en marcha | Alta | M/A | Sin publicidad sobre el mapa. Monetización prevista por suscripción opcional | Decisión de producto |
| 4 | Rutas | Atajos agresivos por calles residenciales que no ahorran tiempo; rutas más largas de lo normal | Alta | M | Tres perfiles explícitos (rápida / corta / alternativa) con diferencia de tiempo visible; nunca se cambia de ruta en marcha sin mostrar el ahorro | Implementado sobre el motor de rutas del proveedor; la calidad de ruta depende de él |
| 5 | Rutas | Un único aviso erróneo de carretera cortada provoca desvíos | Media | A | Los cortes reportados por un solo usuario no alteran la ruta; hace falta confianza alta (varias confirmaciones ponderadas) | Motor de confianza implementado; el desvío automático por cortes aún no |
| 6 | Alertas | Avisos de policía/peligros que ya no existen | Alta | M | Caducidad por tipo, voto "ya no está", peso por reputación, retirada automática por negativas | Implementado |
| 7 | Alertas | Avisos que llegan tarde | Media | A | Distancia de aviso proporcional a la velocidad (segundos de antelación, no metros fijos) | Implementado |
| 8 | Alertas | Pocas alertas en zonas con pocos usuarios | Media | M | Problema inherente a cualquier red comunitaria nueva; NEX lo tendrá también al principio. Mitigación: importar fuentes oficiales (radares fijos, incidencias de tráfico de proveedor) | Importador de radares fijos implementado; proveedor de incidencias pendiente de contrato |
| 9 | CarPlay | Congelaciones, pantalla en negro, posición bloqueada | Media (fuentes antiguas) | A | CarPlay se abordará como escena independiente con la misma sesión de navegación; requiere entitlement de Apple | No implementado (Fase posterior) |
| 10 | GPS | Posición saltando o detenida | Media | A | Filtro de lecturas por precisión y antigüedad; ajuste a la ruta con histéresis antes de declarar desvío | Implementado |
| 11 | Búsqueda | No encuentra ruta tras elegir destino; errores genéricos | Media | M | Errores explícitos con reintento; búsqueda con autocompletado sesgado a la zona | Implementado |
| 12 | Interfaz | Demasiados elementos y avisos sonoros | Media | M | Mapa primero; durante la navegación solo maniobra, ETA y dos botones grandes; voz configurable en tres niveles | Implementado |
| 13 | Conexión | Fallos con cobertura mala | Media | M | La guía giro a giro continúa sin red una vez calculada la ruta; las alertas se conservan en caché; el recálculo sí necesita red | Implementado; mapas sin conexión no disponibles con MapKit |
| 14 | Personalización | Poco control sobre qué avisa | Media | B | Ajuste por tipo de alerta: mostrar, avisar por voz, o ignorar | Implementado |

## Requisitos de calidad derivados

1. Ninguna interacción obligatoria con el conductor en marcha; todo aviso se descarta solo.
2. Objetivos táctiles ≥ 60 pt durante la navegación.
3. Cero actualizaciones de ubicación en segundo plano fuera de una navegación activa.
4. La guía debe continuar sin red.
5. Un aviso de un solo usuario nunca se presenta como hecho confirmado.
6. Ninguna función se muestra como disponible si su proveedor no está conectado.

## Marco legal de avisos de radares y controles

Resumen de fuentes periodísticas; **no es asesoramiento jurídico** y debe revisarlo un abogado antes de publicar.

- **España**: avisar de radares fijos es legal (ubicaciones publicadas por la DGT). Los detectores e inhibidores
  son ilegales. Avisar de controles policiales no se sanciona hoy en la norma de tráfico, pero la DGT prepara una
  reforma para limitarlo siguiendo el modelo francés.
- **Francia**: no se permite señalar con precisión controles; se usan "zonas".
- **Suiza**: prohibidos los avisos de controles; Waze desactiva allí el reporte de policía.
- **Alemania**: uso restringido de avisadores durante la conducción.

Decisión de NEX: política por país configurable en servidor (`exact` / `zone` / `disabled`), con valor
conservador por defecto (`zone`: ubicación aproximada, sin voz que incite a frenar o acelerar). Ver
`backend/src/alerts/policy.ts`.

## Fuentes

- https://supercarblondie.com/new-features-added-to-waze-in-2026
- https://betanews.com/2025/10/08/waze-is-rolling-out-voice-controlled-conversational-reporting-of-hazards/
- https://www.neowin.net/news/googles-waze-is-finally-learning-to-stop-yapping-so-much/
- https://www.bgr.com/2262583/why-does-waze-drain-so-much-battery/
- https://www.bgr.com/2222297/reasons-users-dislike-waze/
- https://www.phonearena.com/news/waze-users-say-that-routing-no-longer-reliable_id168661
- https://www.phonearena.com/news/waze-one-star-reviews-play-store_id151357
- https://www.trustpilot.com/review/www.world.waze.com
- https://www.autoevolution.com/news/waze-navigation-app-once-again-wreaking-havoc-on-carplay-144293.html
- https://discussions.apple.com/thread/254748869
- https://9to5google.com/2022/08/05/waze-carplay-android-auto-lag
- https://www.slashgear.com/2243446/common-problems-with-waze-how-to-fix-them/
- https://www.xataka.com/movilidad/dgt-lleva-presionando-lustro-waze-google-maps-su-solucion-pasa-copiar-modelo-frances
- https://www.motorpasion.com/seguridad/te-puede-multar-dgt-avisar-radar-control-no-estan-intentando
