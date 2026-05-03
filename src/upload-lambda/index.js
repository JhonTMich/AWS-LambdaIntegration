const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const busboy = require('busboy');
const { v4: uuidv4 } = require('uuid');

// AWS SDK v3 no necesita que le pases credenciales si corre dentro de Lambda
const s3Client = new S3Client({});

exports.handler = async (event) => {
  return new Promise((resolve) => {
    try {
      // 1. Extraer los headers (API Gateway a veces los pone en minúsculas)
      const contentType = event.headers['content-type'] || event.headers['Content-Type'];
      if (!contentType) {
        return resolve({ statusCode: 400, body: 'Falta el header Content-Type' });
      }

      // 2. Configurar Busboy para analizar el archivo multipart/form-data
      const bb = busboy({ headers: { 'content-type': contentType } });
      const uploadPromises = [];
      let fileProcessed = false;

      bb.on('file', (name, file, info) => {
        fileProcessed = true;
        const { filename, mimeType } = info;
        
        // 3. Validar los formatos permitidos por el diagrama
        const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
        if (!allowedTypes.includes(mimeType)) {
          file.resume(); // Ignorar archivo
          return resolve({ statusCode: 400, body: 'Formato no permitido. Use jpg, png, gif o webp.' });
        }

        // 4. Crear un nombre único para evitar que las fotos se sobrescriban
        const fileId = uuidv4();
        const extension = filename.split('.').pop();
        const key = `${process.env.UPLOAD_PREFIX}${fileId}.${extension}`; // Ej: uploads/1234-abcd.jpg

        const chunks = [];
        file.on('data', (data) => chunks.push(data));
        file.on('end', () => {
          const buffer = Buffer.concat(chunks);
          
          // 5. Preparar el envío a S3
          const uploadParams = {
            Bucket: process.env.S3_BUCKET,
            Key: key,
            Body: buffer,
            ContentType: mimeType,
          };

          const command = new PutObjectCommand(uploadParams);
          uploadPromises.push(s3Client.send(command));
        });
      });

      bb.on('finish', async () => {
        if (!fileProcessed) {
          return resolve({ statusCode: 400, body: 'No se encontró ninguna imagen en la petición' });
        }
        try {
          // 6. Esperar a que se termine de guardar en S3 y responder con éxito
          await Promise.all(uploadPromises);
          resolve({
            statusCode: 200,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ message: 'Imagen subida exitosamente a la bóveda' })
          });
        } catch (err) {
          console.error("Error al subir a S3:", err);
          resolve({ statusCode: 500, body: 'Error interno guardando la imagen' });
        }
      });

      // 7. Entregarle los datos del evento a Busboy para que trabaje
      // API Gateway envía los archivos binarios codificados en base64
      const bodyBuffer = event.isBase64Encoded 
        ? Buffer.from(event.body, 'base64') 
        : Buffer.from(event.body);
        
      bb.end(bodyBuffer);

    } catch (error) {
      console.error("Error general:", error);
      resolve({ statusCode: 500, body: JSON.stringify({ error: error.message }) });
    }
  });
};