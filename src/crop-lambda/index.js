const { S3Client, GetObjectCommand, PutObjectCommand } = require("@aws-sdk/client-s3");
const Jimp = require("jimp");

const s3 = new S3Client({});

exports.handler = async (event) => {
  for (const record of event.Records) {
    const body = JSON.parse(record.body);

    if (!body.Records || !body.Records[0].s3) continue;
    
    const s3Event = body.Records[0];
    const bucket = s3Event.s3.bucket.name;
    const key = decodeURIComponent(s3Event.s3.object.key.replace(/\+/g, ' '));

    try {
      console.log(`Iniciando recorte de la imagen: ${key}`);

      const getCmd = new GetObjectCommand({ Bucket: bucket, Key: key });
      const { Body } = await s3.send(getCmd);
      const buffer = await Body.transformToByteArray();

      const image = await Jimp.read(Buffer.from(buffer));
      image.resize(40, 40);
      image.circle(); // <-- Aquí está la magia para hacerla circular
      const resizedBuffer = await image.getBufferAsync(Jimp.MIME_PNG);

      const newKey = key.replace('uploads/', 'processed/');
      const putCmd = new PutObjectCommand({
        Bucket: bucket,
        Key: newKey,
        Body: resizedBuffer,
        ContentType: 'image/png'
      });
      await s3.send(putCmd);
      
      console.log(`¡Éxito! Imagen procesada y guardada en: ${newKey}`);
      
    } catch (error) {
      console.error(`Error procesando la imagen ${key}:`, error);
      throw error;
    }
  }
};