#!/bin/bash

echo "🚀 Iniciando instalación de GBOT con Panel Web Avanzado..."

# --- [1] Pedir configuración personalizada ---
read -p "👤 Usuario para el panel: " USUARIO_PANEL
read -s -p "🔑 Contraseña para el panel: " PASSWORD_PANEL
echo ""
read -p "🌐 Dominio del panel (ej. control.midominio.com): " DOMINIO_PANEL

# Guardar variables en archivo temporal
mkdir -p /root/gbot/.config
cat > /root/gbot/.config/vars.conf <<EOF
USUARIO_PANEL="${USUARIO_PANEL}"
PASSWORD_PANEL="${PASSWORD_PANEL}"
DOMINIO_PANEL="${DOMINIO_PANEL}"
EOF

# --- [2] Actualizar sistema e instalar dependencias ---
apt update && apt upgrade -y
apt install -y curl git nginx certbot python3-certbot-nginx build-essential

# Node.js y npm (v18 recomendada)
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs
npm install -g pm2

# --- [3] Clonar archivos necesarios del repositorio ---
mkdir -p /root/gbot/bot /root/gbot/panel/{views,public/css,controllers,db}

echo "📥 Descargando archivos..."

# Bot
curl -sLo /root/gbot/bot/index.js https://raw.githubusercontent.com/gerarvpn/V2G/main/bot/index.js

# Panel backend
curl -sLo /root/gbot/panel/server.js https://raw.githubusercontent.com/gerarvpn/V2G/main/panel/server.js
curl -sLo /root/gbot/panel/controllers/respuestas.js https://raw.githubusercontent.com/gerarvpn/V2G/main/panel/controllers/respuestas.js
curl -sLo /root/gbot/panel/db/db.json https://raw.githubusercontent.com/gerarvpn/V2G/main/panel/db/db.json

# Vistas
curl -sLo /root/gbot/panel/views/login.ejs https://raw.githubusercontent.com/gerarvpn/V2G/main/panel/views/login.ejs
curl -sLo /root/gbot/panel/views/index.ejs https://raw.githubusercontent.com/gerarvpn/V2G/main/panel/views/index.ejs
curl -sLo /root/gbot/panel/views/respuestas.ejs https://raw.githubusercontent.com/gerarvpn/V2G/main/panel/views/respuestas.ejs

# Estilos
curl -sLo /root/gbot/panel/public/css/styles.css https://raw.githubusercontent.com/gerarvpn/V2G/main/panel/public/css/styles.css

# --- [4] Instalar dependencias del proyecto ---
cd /root/gbot/bot
npm init -y
npm install whatsapp-web.js qrcode-terminal

cd /root/gbot/panel
npm init -y
npm install express express-session ejs body-parser cors fs

# --- [5] Iniciar con PM2 ---
pm2 start /root/gbot/bot/index.js --name gbot-bot
pm2 start /root/gbot/panel/server.js --name gbot-panel
pm2 save
pm2 startup systemd -u root --hp /root

# --- [6] Configurar NGINX ---
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

    location /public/ {
        alias /root/gbot/panel/public/;
    }
}
EOF

ln -s /etc/nginx/sites-available/gbot /etc/nginx/sites-enabled/gbot
nginx -t && systemctl reload nginx

# --- [7] Certificado SSL con Let's Encrypt ---
certbot --nginx -d ${DOMINIO_PANEL} --non-interactive --agree-tos -m admin@${DOMINIO_PANEL} --redirect

echo "✅ Instalación completa. Accede a: https://${DOMINIO_PANEL}"
echo "🧠 Usuario: $USUARIO_PANEL"