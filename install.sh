#!/bin/bash

clear
echo "🚀 Instalador de GBOT con panel web avanzado"

# Pedir datos personalizados
read -p "👤 Usuario para el panel: " USUARIO_PANEL
read -s -p "🔒 Contraseña para el panel: " PASSWORD_PANEL
echo
read -p "🌐 Dominio del panel (ej: panel.midominio.com): " DOMINIO_PANEL

# Guardar configuración
cat > /root/gbot/configuracion.env <<EOF
USUARIO_PANEL=${USUARIO_PANEL}
PASSWORD_PANEL=${PASSWORD_PANEL}
DOMINIO_PANEL=${DOMINIO_PANEL}
EOF

# Actualizar sistema e instalar dependencias
apt update && apt upgrade -y
apt install -y curl git nginx nodejs npm build-essential certbot python3-certbot-nginx

# Instalar pm2
npm install -g pm2

# Crear carpetas necesarias
mkdir -p /root/gbot/bot
mkdir -p /root/gbot/panel/views

# Descargar todos los archivos necesarios desde GitHub
ARCHIVOS=(
  "bot/index.js"
  "panel/server.js"
  "panel/api.js"
  "panel/database.json"
  "panel/views/login.ejs"
  "panel/views/index.ejs"
  "panel/views/respuestas.ejs"
)

for FILE in "${ARCHIVOS[@]}"; do
  curl -Lo /root/gbot/$FILE https://raw.githubusercontent.com/gerarvpn/V2G/main/$FILE
done

# Instalar dependencias del bot
cd /root/gbot/bot
npm init -y
npm install whatsapp-web.js qrcode-terminal

# Instalar dependencias del panel
cd /root/gbot/panel
npm init -y
npm install express express-session ejs body-parser fs path

# Configurar PM2
pm2 start /root/gbot/bot/index.js --name gbot-bot
pm2 start /root/gbot/panel/server.js --name gbot-panel
pm2 save
pm2 startup systemd -u root --hp /root

# Configurar NGINX
cat > /etc/nginx/sites-available/gbot <<EOF
server {
    listen 80;
    server_name ${DOMINIO_PANEL};

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

ln -sf /etc/nginx/sites-available/gbot /etc/nginx/sites-enabled/gbot
nginx -t && systemctl reload nginx

# Instalar SSL
certbot --nginx -d ${DOMINIO_PANEL} --non-interactive --agree-tos -m contacto@${DOMINIO_PANEL} --redirect

echo "✅ Instalación completa. Accede al panel en: https://${DOMINIO_PANEL}"