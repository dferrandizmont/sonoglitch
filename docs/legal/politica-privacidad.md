# Política de privacidad

*Última actualización: 2026-11-20 · Se aplica a Sonoglitch (todas las versiones).*

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

La app no envía nada. El responsable del tratamiento es Daniel Mont Ferrandiz (DanielMF), España. Si escribes a [sonoglitch@mainshai.com](mailto:sonoglitch@mainshai.com), usamos tu dirección de correo, tu nombre si lo pones y lo que nos cuentes (incluido lo que adjuntes, como un informe de diagnóstico) para contestarte y resolver lo que nos preguntas. Si ejerces un derecho de protección de datos, tratamos tu solicitud para cumplir las obligaciones que nos impone el RGPD (art. 6.1.c). Si necesitamos conservar una conversación por una reclamación, lo hacemos por nuestro interés legítimo en formularla, ejercerla o defendernos frente a ella (art. 6.1.f), durante el tiempo necesario para ello. Por el camino intervienen estos proveedores:

- **Cloudflare** (Cloudflare, Inc., Estados Unidos) recibe el mensaje en nuestro dominio y lo reenvía al momento. No guarda el mensaje, pero sí un registro técnico del reenvío (remitente, destinatario, asunto, fecha y resultado). Lo conserva durante el plazo que fija su servicio, que no hemos podido confirmar, igual que las opciones para borrarlo; si nos pides la supresión, trasladaremos también la solicitud a Cloudflare y te informaremos del resultado. Cloudflare trata el correo también en Estados Unidos.
- **Google** (Gmail; Google Ireland Limited) es el buzón donde leemos tu mensaje, te respondemos y guardamos la conversación. Google puede tratar estos datos también en Estados Unidos.
- **Proton** (Proton AG, Suiza) guarda una copia de los mensajes que recibimos, como respaldo. Desde ahí no respondemos.
- **Resend** (Plus Five Five, Inc., Estados Unidos) envía nuestras respuestas, por lo que trata su contenido. Las envía desde sus servidores de Irlanda, pero guarda los datos en Estados Unidos: una copia de cada respuesta (que puede incluir tu mensaje, si va citado debajo) y su registro de envío (destinatario, asunto, fecha y si se entregó). Según Resend, conserva cada respuesta y su registro de envío durante 30 días desde el envío, y sus copias de seguridad se conservan durante siete días. Tenemos desactivado el seguimiento de aperturas y de clics: nuestras respuestas no llevan ninguna imagen de seguimiento y sus enlaces no se cambian. Resend usa sus propios subencargados (por ejemplo, Amazon Web Services para el envío), en Estados Unidos; la lista está en https://resend.com/legal/subprocessors. Resend trata las respuestas como encargado del tratamiento, con el acuerdo de tratamiento de datos (art. 28 del RGPD) que se aplica a todas sus cuentas (https://resend.com/legal/dpa).

**Brevo, hasta el 20 de noviembre de 2026.** Hasta esa fecha, esta política decía que las respuestas salían por Brevo (Sendinblue SAS, que opera como Brevo, Francia), que añade a los correos una imagen invisible (un píxel) que registra si se abren y cambia los enlaces por otros suyos que registran si se pulsan. Antes del cambio a Resend, desde sonoglitch@mainshai.com solo se enviaron por Brevo pruebas del titular, ninguna respuesta a quien nos escribiera; esas pruebas llevaban también una cabecera para darse de baja, aunque no hay ninguna lista. Brevo conserva el registro de esas pruebas y lo borra automáticamente doce meses después de cada envío (el borrado puede tardar hasta un día más). Vamos a pedir a Brevo que borre antes ese historial y a cerrar la cuenta.

Para las consultas ordinarias, la base es nuestro interés legítimo en responderte. No añadimos tu dirección a listas de distribución. Guardamos la conversación en Gmail y la copia en Proton como máximo un año desde el último mensaje de la conversación, salvo que necesitemos conservarlas más tiempo para atender una reclamación. Hacemos una limpieza cada tres meses y en cada una borramos lo que cumpliría el año antes de la siguiente. Según Resend, conserva cada respuesta y su registro de envío durante 30 días desde el envío, y sus copias de seguridad se conservan durante siete días. Si nos pides que borremos tus mensajes antes y procede la supresión, borramos los mensajes de Gmail y Proton y pedimos a Resend que elimine las respuestas y los registros de envío que aún conserve (solo se puede pidiéndoselo a su servicio de ayuda). Si debemos conservar algún dato, te explicaremos cuál y por qué. Sobre lo que queda en Brevo, ver el párrafo anterior.

Cloudflare, Google y Resend pueden tratar datos en Estados Unidos. Cloudflare, Inc. y Google LLC están adheridas al Marco de Privacidad de Datos UE-EE. UU. (decisión de adecuación de la Comisión Europea de 10 de julio de 2023); el acuerdo de tratamiento de datos de Cloudflare incluye además cláusulas contractuales tipo. Proton está en Suiza, país con decisión de adecuación de la Comisión Europea. Resend (Plus Five Five, Inc.) guarda en Estados Unidos las respuestas y su registro, aunque el envío salga de Irlanda; esa transferencia se ampara en la adhesión de Resend al Marco de Privacidad de Datos UE-EE. UU. y en las cláusulas contractuales tipo de la Comisión Europea (módulo 2) que incorpora su acuerdo de tratamiento de datos (https://resend.com/legal/dpa); también puedes pedirnos información en el correo de contacto. Brevo, el servicio previsto hasta el 20 de noviembre de 2026, es una empresa francesa y, según su documentación, aloja los datos en la Unión Europea.

Puedes escribir a sonoglitch@mainshai.com para acceder a tus datos, rectificarlos, solicitar su supresión o la limitación del tratamiento, u oponerte al tratamiento basado en nuestro interés legítimo. También puedes reclamar ante la Agencia Española de Protección de Datos.

Si abres una incidencia en GitHub, lo que escribas es público y se aplica la política de privacidad de GitHub.

## Menores

La app no recoge datos personales de nadie, incluidos los menores.

## Cambios y contacto

Los cambios en esta política aparecerán en este archivo y en las notas de cada versión. Si tienes dudas, escribe a [sonoglitch@mainshai.com](mailto:sonoglitch@mainshai.com) o [abre una incidencia en GitHub](https://github.com/dferrandizmont/sonoglitch/issues).
