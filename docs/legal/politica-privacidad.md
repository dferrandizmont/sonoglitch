# Política de privacidad

*Última actualización: 2026-10-27. Se aplica a Sonoglitch (todas las versiones).*

Sonoglitch es una app de cámara que distorsiona las fotos según el nivel de sonido, la luz y el movimiento que hay a tu alrededor. Es software gratuito y de código abierto, y funciona por completo en tu dispositivo.

## Qué hace la app con tus datos

| Datos | Para qué | Adónde van |
| --- | --- | --- |
| Imagen de la cámara | Vista previa en directo con el efecto y la toma de la foto | Se queda en tu dispositivo. Mientras trabajas con una foto, puede haber archivos temporales en la caché privada de la app (ninguna otra app puede leerlos) hasta que el sistema la vacíe o desinstales la app. Las fotos se guardan en tu galería solo cuando tocas Guardar. |
| Micrófono | Solo se miden números, en memoria, para alimentar el efecto: el **nivel de volumen** y la energía de **tres bandas de frecuencia** (graves, medios, agudos) | **No se graba, almacena ni envía audio.** Los búferes de audio del micrófono se procesan solo en memoria para calcular el volumen y la energía de las tres bandas, y después se descartan; solo se conservan, por poco tiempo, los números resultantes. |
| Sensores de movimiento (acelerómetro y giroscopio) | Medir cuánto se mueve y gira el teléfono | Se usan en memoria. Las lecturas pueden aparecer en el registro de diagnóstico local como simples números (consulta *Diagnóstico*); nunca se envían. |
| Análisis de imagen | El brillo, lo colorida que es la escena y la diferencia entre pequeños fotogramas consecutivos de la cámara, calculados para alimentar el efecto | Se usa en memoria. Las lecturas de brillo y movimiento pueden aparecer en el registro de diagnóstico local como simples números; nunca se envían. |
| Brújula (magnetómetro) y barómetro | La dirección hacia la que apunta el teléfono aporta una pequeña variación al efecto; la línea de contexto opcional también puede imprimir el rumbo y la presión atmosférica de una foto | Se leen en memoria en torno al momento del disparo; nunca se almacenan, se escriben en el registro ni se envían. La brújula es aproximada y magnética; no se consulta la ubicación. |
| Reloj y calendario | La hora del día, la fecha y la fase lunar aportan una pequeña variación al efecto; la línea de contexto opcional (desactivada por defecto) puede imprimirlas en la imagen exportada | Se calculan en memoria a partir del reloj del sistema. Solo lo que eliges exportar se escribe en la imagen que guardas o compartes. |
| Galería de fotos | Guarda la foto que eliges guardar | Se escribe en tu galería solo cuando tocas Guardar. |

## Lo que la app no hace

- No tiene cuentas, ni anuncios, ni analítica, ni rastreadores.
- Las compilaciones de publicación (release) no declaran el permiso `INTERNET` de Android, así que la app no tiene acceso a la red. (Las compilaciones de depuración y de perfilado (debug y profile) que hacen los desarrolladores sí lo incluyen, porque Flutter lo necesita para sus herramientas.)
- En Android no pide ningún permiso de almacenamiento: las fotos se guardan a través del almacén multimedia del sistema, y la app no lee los archivos de otras apps. En iOS el sistema te pide acceso a tu fototeca para que la app pueda guardar en su propio álbum.
- En Android, sus datos quedan excluidos de las copias de seguridad del dispositivo y en la nube.
- No comparte datos con nadie. Cuando tocas Compartir, la foto se pasa a la app que eliges a través del menú para compartir del sistema; a partir de ahí se aplica la política de privacidad propia de esa app.

## Diagnóstico

La app guarda un pequeño registro de texto en su almacenamiento privado, en tu dispositivo: eventos técnicos, tiempos, errores y las lecturas numéricas que se muestran en el panel de diagnóstico (nivel de volumen, brillo y movimiento, como simples números), además del modelo del dispositivo y la versión de Android. Nunca contiene audio ni fotos. Solo se comparte si tocas *Compartir registros* o *Copiar informe* y lo envías tú. Puedes eliminarlo borrando el almacenamiento de la app o desinstalando la app.

## Enlaces opcionales

Algunas versiones (F-Droid y las publicadas en GitHub) muestran un enlace opcional «Apoya el proyecto» a una página de Ko-fi; la versión de Google Play no lo tiene. Al tocarlo, el enlace se abre en otra app de tu dispositivo, normalmente tu navegador. La app en sí no envía nada, y no sabe si haces una donación.

## Menores

La app no recoge datos personales de nadie, incluidos los menores.

## Cambios y contacto

Los cambios en esta política aparecerán en este archivo y en las notas de cada versión. Preguntas: escribe a dev@mainshai.com o abre una incidencia (issue) en el repositorio del proyecto.
