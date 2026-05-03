La arquitectura debe poder desplegarse en 3 entornos: DEV, QA y PROD.

cd src/upload-lambda
npm install

cd src/crop-lambda
npm install --platform=linux --arch=x64 sharp@0.33
npm install @aws-sdk/client-s3