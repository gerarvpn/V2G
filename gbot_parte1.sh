#!/bin/bash

echo "🚀 Iniciando instalación de GBOT Mejorado..."

# Solicitar datos personalizados
read -p "👤 Usuario para el panel: " USUARIO_PANEL
read -s -p "🔑 Contraseña para el panel: " PASSWORD_PANEL
echo ""
read -p "🌐 Dominio con el que se usará (sin https://): " DOMINIO_PANEL
read -p "📧 Correo para certbot SSL: " EMAIL_CERTBOT

# Actualizar sistema e instalar herramientas básicas
apt update && apt upgrade -y
apt install -y curl git build-essential nginx certbot python3-certbot-nginx sqlite3

# Instalar Node.js 18 LTS y PM2
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs
npm install -g pm2

# Crear estructura de proyecto
mkdir -p /root/gbot/{bot,panel/{views,public,db,logs}}