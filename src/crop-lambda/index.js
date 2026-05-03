const { S3Client, GetObjectCommand, PutObjectCommand } = require('@aws-sdk/client-s3');
const sharp = require('sharp');

const s3Client = new S3Client({});

exports.handler = async (event) => {
  // ReportBatchItemFailures: Arreglo para avisarle a SQS si alguna imagen falló
  const batchItemFailures = [];

  for (const record of event.Records) {
    try {
      // 1. Leer el mensaje de SQS (que a su vez contiene el aviso de S3)
      const sqsBody = JSON.parse(record.body);
      
      // Si es un evento de prueba automático de S3, lo saltamos
      if (!sqsBody.Records || sqsBody.Records.length === 0) continue;

      for (const s3Record of sqsBody.Records) {
        const bucketName = s3Record.s3.bucket.name;
        // Decodificar el nombre por si tiene espacios (S3 los cambia por '+')
        const originalKey = decodeURIComponent(s3Record.s3.object.key.replace(/\+/g, " "));

        // 2. Descargar la imagen original desde uploads/
        const getResponse = await s3Client.send(new GetObjectCommand({
          Bucket: bucketName,
          Key: originalKey
        }));
        
        // Convertir el stream de AWS a un Buffer que Sharp pueda leer
        const streamToBuffer = (stream) => new Promise((resolve, reject) => {
          const chunks = [];
          stream.on("data", (chunk) => chunks.push(chunk));
          stream.on("error", reject);
          stream.on("end", () => resolve(Buffer.concat(chunks)));
        });
        const imageBuffer = await streamToBuffer(getResponse.Body);

        // 3. El Recorte (Magia de Sharp basada en tu diagrama)
        // Creamos una máscara circular vectorial (SVG)
        const circleSvg = Buffer.from('<svg width="40" height="40"><circle cx="20" cy="20" r="20" fill="white"/></svg>');
        
        const processedBuffer = await sharp(imageBuffer)
          .resize(40, 40, { fit: 'cover' })
          .composite([{ input: circleSvg, blend: 'dest-in' }]) // Aplica la máscara
          .png() // Fuerza salida PNG con fondo transparente
          .toBuffer();

        // 4. Guardar la imagen procesada
        // Extraemos el nombre original. Ej: uploads/foto.jpg -> foto
        const fileName = originalKey.split('/').pop().split('.')[0]; 
        const newKey = `${process.env.PROCESSED_PREFIX}${fileName}_circular.png`;

        await s3Client.send(new PutObjectCommand({
          Bucket: process.env.S3_BUCKET,
          Key: newKey,
          Body: processedBuffer,
          ContentType: 'image/png'
        }));
        
        console.log(`Imagen procesada y guardada con éxito: ${newKey}`);
      }
    } catch (error) {
      console.error(`Error procesando mensaje SQS ${record.messageId}:`, error);
      // Si falla, lo metemos a la lista de errores. Si falla 3 veces, se va a la DLQ.
      batchItemFailures.push({ itemIdentifier: record.messageId });
    }
  }

  // Se devuelve a AWS para que borre los mensajes exitosos y reintente los fallidos
  return { batchItemFailures };
};