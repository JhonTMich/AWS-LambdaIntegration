const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const busboy = require('busboy');
const { v4: uuidv4 } = require('uuid');

const s3Client = new S3Client({});

exports.handler = async (event) => {
  return new Promise((resolve) => {
    try {
      const contentType = event.headers['content-type'] || event.headers['Content-Type'];
      if (!contentType) {
        return resolve({ statusCode: 400, body: 'Falta el header Content-Type' });
      }

      const bb = busboy({ headers: { 'content-type': contentType } });
      const uploadPromises = [];
      let fileProcessed = false;

      bb.on('file', (name, file, info) => {
        fileProcessed = true;
        const { filename, mimeType } = info;

        const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
        if (!allowedTypes.includes(mimeType)) {
          file.resume(); 
          return resolve({ statusCode: 400, body: 'Formato no permitido. Use jpg, png, gif o webp.' });
        }

        const fileId = uuidv4();
        const extension = filename.split('.').pop();
        const key = `${process.env.UPLOAD_PREFIX}${fileId}.${extension}`; 

        const chunks = [];
        file.on('data', (data) => chunks.push(data));
        file.on('end', () => {
          const buffer = Buffer.concat(chunks);

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