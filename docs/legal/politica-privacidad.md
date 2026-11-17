# Política de privacidad

*Última actualización: 2026-11-16 · Se aplica a Sonoglitch (todas las versiones).*

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

Las versiones publicadas en GitHub muestran un enlace opcional «Apoya el proyecto» a una página de Ko-fi; la versión de Google Play no lo tiene. Al tocarlo, el enlace se abre en otra app de tu dispositivo, normalmente tu navegador. La app en sí no envía nada, y no sabe si haces una donación.

## Si nos escribes

La app no envía nada. Si escribes a [sonoglitch@mainshai.com](mailto:sonoglitch@mainshai.com), el responsable de esos datos es el desarrollador de Sonoglitch, un particular que vive en España. Usamos tu dirección de correo, tu nombre si lo pones y lo que nos cuentes (incluido lo que adjuntes, como un informe de diagnóstico) solo para contestarte y resolver lo que nos preguntas. Por el camino intervienen estos proveedores:

- **Cloudflare** (Cloudflare, Inc., Estados Unidos) recibe el mensaje en nuestro dominio y lo reenvía al momento. No guarda el mensaje, pero sí un registro técnico del reenvío (remitente, destinatario, asunto, fecha y resultado). Lo conserva durante el plazo que fija su servicio, que no hemos podido confirmar, igual que las opciones para borrarlo; si nos pides la supresión, trasladaremos también la solicitud a Cloudflare y te informaremos del resultado. Cloudflare trata el correo también en Estados Unidos.
- **Google** (Gmail; Google Ireland Limited) es el buzón donde leemos tu mensaje, te respondemos y guardamos la conversación. Google puede tratar estos datos también en Estados Unidos.
- **Proton** (Proton AG, Suiza) guarda una copia de los mensajes que recibimos, como respaldo. Desde ahí no respondemos.
- **Brevo** (Sendinblue SAS, que opera como Brevo, Francia) envía nuestras respuestas, por lo que trata su contenido, y guarda un registro de cada envío (destinatario, asunto, fecha y si se entregó) y una copia de la respuesta (que puede incluir tu mensaje, si va citado debajo).

Brevo añade a cada respuesta una imagen invisible (un píxel) que registra si la abres, y cambia los enlaces por otros suyos que registran si los pulsas. No podemos quitarlo en el plan que usamos, así que tenemos activado el seguimiento anónimo de Brevo: según Brevo, cuenta las aperturas y los clics sin asociarlos a tu dirección de correo. Aun así, al cargar la imagen o pulsar un enlace, tu programa de correo se conecta a los servidores de Brevo, que reciben datos técnicos como tu dirección IP. Nosotros no consultamos ni usamos esa información. Si prefieres evitarlo, bloquea las imágenes externas en tu programa de correo y no abras los enlaces de la respuesta. Tampoco sirve copiarlos y pegarlos en el navegador, porque siguen pasando por Brevo: para ir a una página, escribe tú su dirección. La respuesta se lee igual. Brevo también añade una cabecera para darse de baja, así que tu programa de correo puede mostrar un botón de «cancelar suscripción»: no hay ninguna lista y puedes ignorarlo.

La base legal es nuestro interés legítimo en atender tu consulta. Tus datos no se añaden a ninguna lista ni se usan para nada más. Guardamos la conversación en Gmail, la copia en Proton y la copia y el registro de envío en Brevo como máximo un año desde el último mensaje de la conversación, salvo que necesitemos conservarlos más tiempo para atender una reclamación. Hacemos una limpieza cada tres meses y en cada una borramos lo que cumpliría el año antes de la siguiente. Si dejamos de usar alguno de esos servicios, borramos lo que haya en él. Si nos pides que borremos tus mensajes antes, los borramos de los tres sitios.

Cloudflare y Google pueden tratar datos en Estados Unidos. Cloudflare, Inc. y Google LLC están adheridas al Marco de Privacidad de Datos UE-EE. UU. (decisión de adecuación de la Comisión Europea de 10 de julio de 2023); el acuerdo de tratamiento de datos de Cloudflare incluye además cláusulas contractuales tipo. Proton está en Suiza, país con decisión de adecuación de la Comisión Europea. Brevo es una empresa francesa y, según su documentación, aloja los datos en la Unión Europea.

Puedes pedir una copia de tus datos, que se corrijan o se borren, u oponerte a su uso, escribiendo a la misma dirección. También puedes reclamar ante la Agencia Española de Protección de Datos.

Si abres una incidencia en GitHub, lo que escribas es público y se aplica la política de privacidad de GitHub.

## Menores

La app no recoge datos personales de nadie, incluidos los menores.

## Cambios y contacto

Los cambios en esta política aparecerán en este archivo y en las notas de cada versión. Si tienes dudas, escribe a [sonoglitch@mainshai.com](mailto:sonoglitch@mainshai.com) o [abre una incidencia en GitHub](https://github.com/dferrandizmont/sonoglitch/issues).
