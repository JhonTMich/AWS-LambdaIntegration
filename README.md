Instalar librerias node
---
```
cd src/upload-lambda
```
```
npm install
```
---
```
cd src/crop-lambda
```
```
npm install jimp@0.22.12 @aws-sdk/client-s3
```

Iniciar terraform 
---
```
terraform init
```

Crear entornos
---
```
terraform workspace new dev
terraform workspace new qa
terraform workspace new prod
```

Crear infraestructura
---
```
terraform workspace select dev
```
```
terraform plan
terraform apply
```
Al finalizar copiar la api_gateway_url

Enviar imagen a la api desde powershell
---
```
curl.exe -X POST "api-url" `
  -F "image=@C:\ruta\imagen"
```
"api-url" la dan despues del "terraform apply" de antes

Destruir los recursos
---
```
terraform destroy
```