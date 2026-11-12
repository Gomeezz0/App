# Sistema de diseño de NEX

Todo el aspecto visual sale de `ios/NEX/Design/Theme.swift`. Las pantallas no definen colores ni tamaños propios.

## Color

| Uso | Valor |
|---|---|
| Fondo | `#090A0D` negro profundo |
| Superficies y paneles | `#191B20` antracita |
| Campos y superficies elevadas | `#23252B` (derivado) |
| Bordes marcados, pistas, inactivos | `#34363D` gris medio |
| Texto principal | `#F5F5F7` blanco frío |
| Texto secundario | `#A5A7AE` gris claro |
| Acción, ruta, alertas graves | `#F32635` rojo |
| Estado (solo semántico) | ámbar, naranja y verde |

No hay azul en la interfaz: el punto de posición del sistema se sustituye por un indicador propio y los avisos
de control y radar usan blanco frío. El rojo se limita a la acción principal de cada pantalla, la ruta activa,
el icono de maniobra y los avisos graves.

## Tipografía

Se usa **SF Pro**, la fuente del sistema, en lugar de incrustar Inter o Manrope:

- iOS cambia sola a SF Pro Display en tamaños grandes y ajusta el espaciado óptico.
- Tiene variante ancha (marca y etiquetas) y redondeada (cifras), así que da personalidad sin añadir archivos.
- No añade peso a la app ni licencias que gestionar.

Seis estilos: `nexDisplay` (34, ancha), `nexTitle` (24), `nexHeadline` (17), `nexBody` (16), `nexCaption` (13),
`nexLabel` (11, ancha, mayúsculas) y `nexNumber` (redondeada, para ETA, velocidad y distancias).

Limitación conocida: los tamaños son fijos y todavía no siguen el ajuste de «Texto más grande» del sistema.

## Componentes

`NEXPrimaryButtonStyle`, `NEXSecondaryButtonStyle`, `NEXRowButtonStyle`, `MapButton`, `nexCard()`, `nexPanel()`
(panel translúcido con desenfoque para flotar sobre el mapa), `NEXField`, `NEXIconTile`, `NEXTag`,
`NEXSectionLabel`, `NEXLoader`, `NEXNotice`, `AlertBadge`, `VehiclePuck`, `DestinationPin`, `RouteLine`.

## Movimiento

Tres curvas (`NEXMotion.quick`, `.standard`, `.panel`), sin rebote. Con **Reducir movimiento** activado los
desplazamientos pasan a ser fundidos breves y el trazado animado de la ruta se omite. Con ahorro de batería,
bajo consumo o el teléfono caliente, la cámara del mapa se mueve sin animación.

Dónde hay animación: aparición escalonada de listas y paneles, respuesta al pulsar en todos los botones,
apertura del buscador, cambio de ruta seleccionada y de encuadre, trazado de la ruta al iniciar y tras un
recálculo, entrada y salida de la navegación, banner de aviso, cifras que cambian (distancia, ETA, velocidad),
cambio de icono de maniobra, halo del indicador de posición, aparición de avisos en el mapa, indicador de carga.

## El mapa: qué se puede y qué no con el proveedor actual

NEX usa **Apple MapKit**. MapKit **no tiene estilos personalizables**: no se puede definir el color de calles,
autopistas, edificios ni textos. Solo permite elegir tipo de mapa, esquema claro u oscuro, énfasis normal o
atenuado, relieve y qué puntos de interés mostrar.

Lo aplicado con sus opciones nativas:

- Esquema oscuro por defecto, énfasis atenuado (menos color de fondo), sin puntos de interés, relieve plano.
- Capa de tráfico de Apple (colores diferenciados sobre las vías).
- Ruta activa en rojo con borde negro; tramo recorrido y alternativas en gris.
- Indicador de vehículo, avisos, zonas y destino propios de NEX.
- Cámara inclinada que sigue al vehículo y gira con el rumbo; aleja el encuadre con la velocidad.

Lo que **no** se puede conseguir con MapKit: fondo casi negro con calles antracita, autopistas con matiz
rojizo y textos blancos a medida. No se simula con capas dibujadas encima.

### Alternativas para un mapa con estilo propio

| Opción | Estilo propio | Tráfico | Sin conexión | Coste y requisitos | Riesgo |
|---|---|---|---|---|---|
| **Mapbox** (Maps + Navigation SDK) | Sí, total (Mapbox Studio) | Sí | Sí | Cuenta y token; de pago por usuario activo pasado el tramo gratuito | Dependencia de un proveedor; hay que sustituir también rutas y guía |
| **MapLibre** + teselas vectoriales (MapTiler, o propias con OpenFreeMap/Protomaps) | Sí, total (JSON de estilo) | **No** incluye tráfico | Posible | Renderizador libre; teselas gratuitas o baratas | Sin tráfico; las rutas habría que obtenerlas de otro servicio |
| **Google Maps SDK** | Sí (estilos en la nube) | Sí | No | Clave y facturación por uso | Condiciones de uso estrictas para navegación |

Aviso legal a tener en cuenta: las condiciones de Apple limitan mostrar datos de MapKit (rutas de
`MKDirections`) fuera de un mapa de Apple. Por eso no basta con cambiar solo el dibujo del mapa y seguir
usando las rutas de Apple: el cambio de mapa implica cambiar también el proveedor de rutas.

**Recomendación:** Mapbox. Es la única opción que da a la vez estilo totalmente propio, tráfico, mapas sin
conexión, límites de velocidad y guiado de carril, y la arquitectura de NEX ya está preparada (los proveedores
están detrás de protocolos). Requiere que el titular del proyecto cree la cuenta, acepte sus condiciones y
aporte el token; por eso no se ha cambiado todavía.
