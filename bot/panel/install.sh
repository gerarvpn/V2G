#!/bin/bash

# Script maestro para instalar GBOT bot y panel

echo "🚀 Iniciando instalación completa de GBOT..."

# Ejecutar cada parte en orden

echo "📁 Ejecutando parte 1: Preparación del sistema..."
bash ./install_part1.sh || { echo "Error en parte 1"; exit 1; }

echo "🤖 Ejecutando parte 2: Instalando bot WhatsApp..."
# Asume que la parte 2 es solo el código del bot (index.js), 
# aquí instalamos dependencias necesarias para el bot
cd ./gbot/bot || { echo "No se encontró carpeta bot"; exit 1; }
npm install whatsapp-web.js qrcode-terminal || { echo "Error instalando dependencias bot"; exit 1; }
cd - > /dev/null

echo "🖥️ Ejecutando parte 3: Instalando backend del panel..."
cd ./gbot/panel || { echo "No se encontró carpeta panel"; exit 1; }
npm install express express-session ejs dotenv || { echo "Error instalando dependencias panel"; exit 1; }
cd - > /dev/null

echo "🔧 Configurando PM2 y arrancando procesos..."

pm2 start ./gbot/bot/index.js --name gbot-bot || { echo "Error iniciando bot con PM2"; exit 1; }
pm2 start ./gbot/panel/server.js --name gbot-panel || { echo "Error iniciando panel con PM2"; exit 1; }

pm2 save
pm2 startup systemd -u $(whoami) --hp $HOME

echo "🌐 Configurando NGINX..."

# Ajusta el dominio aquí o solicita por input para personalizar
DOMINIO="control.gerarvpn.uk"

cat > /etc/nginx/sites-available/gbot <<EOF
server {
    listen 80;
    server_name $DOMINIO;

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

echo "🔐 Instalando certificado SSL con certbot..."
certbot --nginx -d $DOMINIO --non-interactive --agree-tos -m tuemail@dominio.com --redirect

echo "✅ Instalación completa! Accede a https://$DOMINIO"