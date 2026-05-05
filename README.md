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
npm install --platform=linux --arch=x64 sharp@0.33
```
```
npm install @aws-sdk/client-s3
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

Enviar imagen a la api
---
```
curl -X POST api-url \
  -H "Content-Type: image/png" \
  --data-binary "@C:ruta/foto"
```
"api-url" la dan despues del "terraform apply" de antes

Destruir los recursos
---
```
terraform destroy
```