#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "A atualizar pacotes e a instalar dependências..."
dnf update -y
dnf install -y docker amazon-efs-utils jq 
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
  -o /usr/libexec/docker/cli-plugins/docker-compose
chmod +x /usr/libexec/docker/cli-plugins/docker-compose

echo "A iniciar e a habilitar o serviço Docker..."
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user


SECRET_NAME="creds/wordpress/rds"
AWS_REGION="us-east-2" # SUBSTITUA PELA SUA REGIÃO
EFS_ID="" # SUBSTITUA PELO SEU ID DO EFS
echo "A criar ponto de montagem para o EFS..."
mkdir -p /mnt/efs/wordpress
EFS_DNS_NAME="$EFS_ID.efs.$AWS_REGION.amazonaws.com"

echo "$EFS_DNS_NAME:/ /mnt/efs/wordpress nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0" >> /etc/fstab

echo "A montar todos os sistemas de ficheiros..."
mount -a
while ! grep -qs '/mnt/efs/wordpress' /proc/mounts; do
  echo "A aguardar pela montagem do EFS em /mnt/efs/wordpress..."
  sleep 5
done
echo "A criar diretório para o projeto WordPress..."
mkdir -p /home/ec2-user/wordpress-docker



echo "A ir buscar as credenciais do RDS ao Secrets Manager..."
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id $SECRET_NAME --region $AWS_REGION --query SecretString --output text)

DB_HOST=$(echo $SECRET_JSON | jq -r .host)
DB_USER=$(echo $SECRET_JSON | jq -r .username)
DB_PASSWORD=$(echo $SECRET_JSON | jq -r .password)
DB_NAME="wordpressdb" # Pode definir o nome da BD aqui

echo "Credenciais obtidas. A criar o ficheiro compose.yml..."

cat <<EOF > /home/ec2-user/wordpress-docker/compose.yml

services:
  wordpress:
    image: wordpress:latest
    restart: always
    ports:
      - "80:80"
    environment:
      WORDPRESS_DB_HOST: ${DB_HOST}:3306
      WORDPRESS_DB_USER: ${DB_USER}
      WORDPRESS_DB_PASSWORD: '${DB_PASSWORD}'
      WORDPRESS_DB_NAME: ${DB_NAME}
    volumes:
      - /mnt/efs/wordpress:/var/www/html/wp-content/uploads
EOF

echo "Ficheiro compose.yml criado."

echo "A ajustar permissões para o EFS e para o Docker..."
chown 33:33 /mnt/efs/wordpress
chown -R ec2-user:ec2-user /home/ec2-user/wordpress-docker

echo "A iniciar o container do WordPress..."
su - ec2-user -c "cd /home/ec2-user/wordpress-docker && docker compose up -d"

echo "Script de User Data concluído."