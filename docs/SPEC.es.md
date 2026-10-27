> **Enmiendas (2026-10-24).** Prevalecen sobre lo que contradiga este documento.
>
> - **Nombre:** Sonoglitch (Murmur está ocupado en Google Play).
> - **Licencia y modelo:** Apache-2.0. App gratuita, sin compras ni anuncios y con donaciones opcionales. Se eliminan la sección *Monetización* y la fase 4 de compras (sin `in_app_purchase`).
> - **Marca de agua:** pequeña y desactivable en ajustes.
> - **Distribución:** GitHub Releases, F-Droid y, opcionalmente, Google Play.
> - **Fase 0 (nueva):** prueba de viabilidad cámara a shader en un Pixel 10 Pro, antes del prototipo de ruido.
> - **Captura:** por defecto se aplica el shader a la foto a resolución completa; no se captura el widget del visor.
> - **Ruido:** los dB se muestran como nivel aproximado, con normalización adaptativa por dispositivo.
> - **Movimiento:** se usa el promedio o el pico de 1 a 2 s previos al disparo.
> - **Depuración:** panel de valores en pantalla y logs exportables en las compilaciones de prueba.

> **Enmiendas (2026-10-26).** Prevalecen sobre lo que contradiga este documento.
>
> - **Estilos:** hoy se pueden elegir seis estilos: Static, Tape, Phosphor, Ripple, Thermal y Prism. El registro del código tiene más recetas, pero todavía no se ofrecen en la app.
> - **Resolución de exportación:** la foto se exporta en PNG o JPEG con un nivel de calidad (Estándar hasta 2048 px, Alta hasta 4096 px, Máxima hasta el tamaño nativo del sensor). El tope de 24 megapíxeles se aplica a la foto recortada; la banda de sonido y el póster añaden su banda o su marco, así que el archivo exportado puede ser algo mayor.
> - **Bandas de frecuencias:** se miden en memoria y se imprimen en las composiciones de exportación, pero los seis estilos no las leen, así que no cambian el efecto de la foto.

# Especificación de producto: foto que se oye

## Visión

Una app de cámara que convierte cada foto en un retrato del ambiente: el ruido, la luz y el movimiento del momento deforman la imagen de forma visible. Una calle con tráfico sale muy distorsionada pero reconocible; una playa tranquila sale limpia.

El objetivo es artístico y social: que la gente publique en Instagram no solo lo que veía, sino cómo se sentía y sonaba el lugar, usando solo una imagen.

**Principios de diseño**

- El sujeto siempre se reconoce, por mucho que se distorsione.
- Cada variable del ambiente tiene un efecto propio y legible, no una distorsión genérica.
- La foto es el producto: debe verse bien sin explicación y llevar una firma discreta de la app.
- No se guarda audio: solo se mide el nivel de ruido.

## Alcance del MVP

El MVP valida una sola cosa: que ver el ambiente reflejado en la foto resulta atractivo y compartible.

**Entra**

- Visor de cámara en vivo con el efecto aplicado en tiempo real.
- Tres variables: ruido (micrófono), luz (análisis de la imagen) y movimiento (acelerómetro).
- Tres estilos visuales gratuitos.
- Captura, guardado en la galería y compartir a Instagram con firma de la app.
- Android primero; iOS con la misma base de código.

> **Nota (2026-10-26).** Este es el alcance original del MVP. Los tres estilos del MVP (Static, Tape y Prism) siguen entre los seis estilos que se pueden elegir, y la exportación con la firma de la app también, pero hoy se exporta en PNG o JPEG, en cuatro proporciones y con tres composiciones.

**Queda fuera (versiones posteriores)**

- Modo revelar con el audio original.
- Hora del día y estación del año como variables.
- Cuentas de usuario, galería en la nube y feed social.
- Vídeo.

## Pantallas y flujo

El flujo es lineal y corto: abrir, ver el ambiente actuar sobre el visor, disparar, compartir.

1. **Inicio y permisos.** Pantalla breve que explica la idea en una frase y pide cámara y micrófono, aclarando que no se graba audio.
2. **Visor.** Cámara a pantalla completa con el efecto en vivo. Muestra un indicador discreto del nivel de ruido, luz y movimiento. Selector de estilo en la parte inferior y botón de disparo.
3. **Resultado.** La foto procesada, con los valores medidos en ese instante (por ejemplo, 72 dB, luz baja, movimiento alto). Botones para guardar, compartir o repetir.
4. **Compartir.** Exporta la imagen en formato cuadrado y vertical, con la firma de la app en una esquina, y abre el menú de compartir del sistema.
5. **Estilos.** Lista de estilos disponibles; los de pago muestran un candado y una vista previa.

## Variables y efectos

Cada variable del ambiente controla un efecto distinto, para que la imagen se pueda "leer". Todos los valores se normalizan de 0 a 1 y se suavizan en el tiempo para evitar parpadeos.

| Variable | Cómo se mide | Efecto visual | Efecto en 0 | Efecto en 1 |
| --- | --- | --- | --- | --- |
| Ruido | Nivel en dB del micrófono, de unos 30 a 100 dB | Ondulación y desplazamiento de píxeles, más aberración cromática | Imagen limpia | Distorsión fuerte, sujeto aún reconocible |
| Luz | Luminosidad media de la imagen de la cámara | Contraste, temperatura de color y viñeta | Tonos fríos, bajo contraste | Tonos cálidos, alto contraste |
| Movimiento | Acelerómetro | Desenfoque direccional y estela | Nítida | Estelas visibles |

**Reglas**

- El efecto total tiene un tope: la distorsión máxima nunca debe hacer ilegible el sujeto. Hay que ajustarlo probando en una calle ruidosa real.
- El ruido se mapea de forma lineal en dB, que ya es una escala logarítmica, y se ignora todo lo que quede por debajo de 35 dB.
- Cada estilo es un conjunto distinto de shaders con los mismos tres controles, de modo que cambiar de estilo no cambia el significado de las variables.

## Stack técnico

Flutter para Android e iOS, con los efectos en shaders de fragmento (GLSL) ejecutados en la GPU. No hace falta IA ni servidor.

| Pieza | Opción |
| --- | --- |
| Cámara | Paquete `camera`, con previsualización en textura |
| Ruido | Paquete `noise_meter` o `record` para leer solo la amplitud, sin guardar audio |
| Movimiento | Paquete `sensors_plus` (acelerómetro) |
| Efectos | `FragmentProgram` de Flutter, un shader por estilo |
| Captura | Renderizar el widget del visor a imagen y guardarla con `gal` o `image_gallery_saver` |
| Compartir | Paquete `share_plus` |
| Compras | Paquete `in_app_purchase` (Google Play Billing y StoreKit) |
| Estado | Riverpod o Provider, lo que ya uses en Mochila |

**Arquitectura**

- Un servicio por sensor que emite valores normalizados de 0 a 1 y suavizados.
- Un controlador de ambiente que combina los tres valores y los pasa como uniformes al shader en cada fotograma.
- Un registro de estilos: cada estilo declara su shader, su nombre y si es gratuito o de pago.

**Riesgos técnicos**

- Pasar el fotograma de la cámara a un shader en tiempo real es lo más delicado. Si en gama baja va justo, bajar la resolución de previsualización y aplicar el efecto completo solo al capturar.
- Los nombres y versiones de los paquetes deben comprobarse al empezar, porque pueden haber cambiado.

## Privacidad y permisos

La app pide cámara y micrófono, y el segundo es el que genera desconfianza. Por eso el diseño evita guardar nada sensible.

- **Micrófono:** solo se lee el nivel de volumen en memoria; no se graba, no se guarda ni se envía.
- **Sin servidor:** todo ocurre en el dispositivo; el MVP no tiene cuentas ni subida de datos.
- **Explicación previa:** antes de pedir el permiso, la pantalla de inicio dice en una frase para qué se usa el micrófono.
- **Ficha de la tienda:** la declaración de seguridad de datos de Google Play indica que no se recopilan datos.
- **Política de privacidad:** una página breve pública, necesaria para publicar en las tiendas.

## Monetización

La app es gratuita, con compras dentro de la app para desbloquear más estilos. No hay anuncios, para no romper la experiencia de cámara.

| Elemento | Propuesta |
| --- | --- |
| Gratis | 3 estilos y exportación con firma de la app |
| Packs de estilos | Compra única por pack (por ejemplo ciudad, naturaleza, noche), a un precio bajo de micropago |
| Quitar la firma | Compra única opcional |
| Precios | Por definir tras probar con usuarios reales |

Crecimiento sin vídeos ni influencers: la foto compartida lleva la firma de la app y es reconocible por su estilo, así que cada publicación en Instagram actúa como canal de difusión.

## Fases y criterios de aceptación

Cada fase termina con algo que se puede probar en el móvil antes de pasar a la siguiente.

1. **Prototipo de ruido.** Visor de cámara con un shader controlado solo por el nivel de ruido. *Se acepta si* en una calle ruidosa la imagen se distorsiona claramente, el sujeto sigue reconocible y en un lugar silencioso queda limpia.
2. **Tres variables.** Se suman luz y movimiento, cada una con su efecto propio. *Se acepta si* un observador distingue qué variable causa cada efecto sin explicación.
3. **Captura y compartir.** Guardar en galería y compartir con firma. *Se acepta si* la foto exportada se ve igual que en el visor y se publica bien en Instagram.
4. **Estilos y compras.** Tres estilos gratuitos y un primer pack de pago. *Se acepta si* la compra y su restauración funcionan en un dispositivo de prueba.
5. **Publicación.** Ficha de Google Play, política de privacidad y pruebas cerradas. *Se acepta si* la app pasa la revisión de la tienda.

> **Nota (2026-10-26).** La fase 4 no se hará como estaba prevista: no hay compras. En su lugar hay seis estilos gratuitos y seis recetas más registradas en el código que todavía no se pueden elegir.

**Preguntas abiertas**

- Nombre de la app.
- Precios de los packs y de quitar la firma.
- Si en gama baja el efecto en vivo va fluido o hay que aplicarlo solo al capturar.
