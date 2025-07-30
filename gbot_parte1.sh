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

cat > /root/gbot/bot/index.js << 'EOF'
const { Client, LocalAuth, MessageMedia } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const dbPath = path.join(__dirname, '../panel/db/gbot.db');

// Abrir BD SQLite para citas, respuestas, chats
const db = new sqlite3.Database(dbPath, (err) => {
  if(err) console.error("Error BD:", err);
  else console.log('Base de datos conectada');
});

// Crear tablas si no existen
db.serialize(() => {
  db.run(`CREATE TABLE IF NOT EXISTS respuestas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pregunta TEXT UNIQUE,
    respuesta TEXT
  )`);
  db.run(`CREATE TABLE IF NOT EXISTS citas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cliente TEXT,
    servicio TEXT,
    fecha TEXT,
    hora TEXT
  )`);
  db.run(`CREATE TABLE IF NOT EXISTS chats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cliente TEXT,
    mensaje TEXT,
    respuesta TEXT,
    fecha TEXT
  )`);
});

const client = new Client({
  authStrategy: new LocalAuth({ clientId: "gbot" }),
  puppeteer: { headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'] }
});

client.on('qr', qr => {
  qrcode.generate(qr, { small: true });
  console.log('Escanea el QR en WhatsApp para conectar el bot.');
});

client.on('ready', () => {
  console.log('✅ GBOT WhatsApp listo y conectado!');
});

function sendMessage(from, message) {
  client.sendMessage(from, message);
}

// Manejo mensajes entrantes
client.on('message', async msg => {
  const from = msg.from;
  const text = msg.body.toLowerCase();

  // Guardar chat en BD
  const now = new Date().toISOString();
  db.run(`INSERT INTO chats (cliente, mensaje, fecha) VALUES (?, ?, ?)`, [from, text, now]);

  // Respuestas automáticas dinámicas
  db.get(`SELECT respuesta FROM respuestas WHERE pregunta = ?`, [text], (err, row) => {
    if (row) {
      client.sendMessage(from, row.respuesta);
      // Actualizar chat con respuesta
      db.run(`UPDATE chats SET respuesta = ? WHERE cliente = ? AND mensaje = ?`, [row.respuesta, from, text]);
    } else {
      // Respuesta predeterminada si no hay coincidencia
      client.sendMessage(from, "Lo siento, no entendí tu mensaje. Puedes escribir 'ayuda' para opciones.");
    }
  });

  // Comandos especiales
  if(text.startsWith('agendar cita')) {
    // Ejemplo básico para agendar (deberás implementar formulario desde panel)
    client.sendMessage(from, "Para agendar una cita, por favor usa el panel web.");
  }
  
  if(text === 'ayuda') {
    client.sendMessage(from, "Comandos:\n- 'agendar cita'\n- 'preguntas frecuentes'\n- etc.");
  }
});

client.initialize();
EOF

echo "🤖 Bot avanzado creado."

cat > /root/gbot/panel/server.js << 'EOF'
const express = require('express');
const session = require('express-session');
const path = require('path');
const sqlite3 = require('sqlite3').verbose();
const bodyParser = require('body-parser');
const app = express();

const dbPath = path.join(__dirname, 'db/gbot.db');
const db = new sqlite3.Database(dbPath, (err) => {
  if(err) console.error('Error BD:', err);
  else console.log('Base de datos conectada');
});

app.use(express.static(path.join(__dirname, 'public')));
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(bodyParser.urlencoded({ extended: true }));

app.use(session({
  secret: 'super-secreto-gbot-2025',
  resave: false,
  saveUninitialized: false,
  cookie: { maxAge: 30*60*1000 } // 30 min
}));

// Middleware autenticación
function authMiddleware(req, res, next) {
  if (req.session && req.session.user) next();
  else res.redirect('/login');
}

// Variables para usuarios (multiusuario simple)
const usuarios = {
  admin: { password: 'Jeraldo2903@', role: 'admin' },
  operador: { password: 'operador123', role: 'operador' }
};

// Login
app.get('/login', (req, res) => {
  res.render('login', { error: null });
});
app.post('/login', (req, res) => {
  const { username, password } = req.body;
  if (usuarios[username] && usuarios[username].password === password) {
    req.session.user = username;
    req.session.role = usuarios[username].role;
    res.redirect('/');
  } else {
    res.render('login', { error: 'Usuario o contraseña incorrectos' });
  }
});
app.get('/logout', (req, res) => {
  req.session.destroy(() => {
    res.redirect('/login');
  });
});

// Panel principal
app.get('/', authMiddleware, (req, res) => {
  db.all(`SELECT * FROM citas ORDER BY fecha, hora`, [], (err, citas) => {
    if(err) citas = [];
    res.render('index', {
      user: req.session.user,
      role: req.session.role,
      citas
    });
  });
});

// Gestión preguntas y respuestas
app.get('/respuestas', authMiddleware, (req, res) => {
  db.all(`SELECT * FROM respuestas ORDER BY pregunta`, [], (err, respuestas) => {
    if(err) respuestas = [];
    res.render('respuestas', { respuestas, user: req.session.user });
  });
});

app.post('/respuestas/add', authMiddleware, (req, res) => {
  const { pregunta, respuesta } = req.body;
  db.run(`INSERT OR IGNORE INTO respuestas (pregunta, respuesta) VALUES (?, ?)`, [pregunta.toLowerCase(), respuesta], (err) => {
    if(err) console.error(err);
    res.redirect('/respuestas');
  });
});

app.post('/respuestas/delete/:id', authMiddleware, (req, res) => {
  const id = req.params.id;
  db.run(`DELETE FROM respuestas WHERE id = ?`, id, (err) => {
    if(err) console.error(err);
    res.redirect('/respuestas');
  });
});

// Agendamiento
app.get('/citas', authMiddleware, (req, res) => {
  db.all(`SELECT * FROM citas ORDER BY fecha, hora`, [], (err, citas) => {
    if(err) citas = [];
    res.render('citas', { citas, user: req.session.user });
  });
});

app.post('/citas/add', authMiddleware, (req, res) => {
  const { cliente, servicio, fecha, hora } = req.body;
  // Validar conflictos de citas
  db.get(`SELECT * FROM citas WHERE fecha = ? AND hora = ?`, [fecha, hora], (err, row) => {
    if(row) {
      res.send('Error: Ya existe una cita en ese horario.');
    } else {
      db.run(`INSERT INTO citas (cliente, servicio, fecha, hora) VALUES (?, ?, ?, ?)`, [cliente, servicio, fecha, hora], (err) => {
        if(err) console.error(err);
        res.redirect('/citas');
      });
    }
  });
});

// Historial de chats (básico)
app.get('/historial', authMiddleware, (req, res) => {
  db.all(`SELECT * FROM chats ORDER BY fecha DESC LIMIT 100`, [], (err, chats) => {
    if(err) chats = [];
    res.render('historial', { chats, user: req.session.user });
  });
});

// Notificaciones y alertas (básico, se pueden ampliar)
app.get('/alertas', authMiddleware, (req, res) => {
  // Placeholder para alertas
  res.render('alertas', { user: req.session.user, alerts: [] });
});

// Iniciar servidor
const PORT = 3000;
app.listen(PORT, () => {
  console.log(`✅ Panel corriendo en http://localhost:${PORT}`);
});
EOF

echo "🖥️ Backend del panel web avanzado creado."

cat > /root/gbot/panel/server.js << 'EOF'
const express = require('express');
const session = require('express-session');
const path = require('path');
const sqlite3 = require('sqlite3').verbose();
const bodyParser = require('body-parser');
const app = express();

const dbPath = path.join(__dirname, 'db/gbot.db');
const db = new sqlite3.Database(dbPath, (err) => {
  if(err) console.error('Error BD:', err);
  else console.log('Base de datos conectada');
});

app.use(express.static(path.join(__dirname, 'public')));
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(bodyParser.urlencoded({ extended: true }));

app.use(session({
  secret: 'super-secreto-gbot-2025',
  resave: false,
  saveUninitialized: false,
  cookie: { maxAge: 30*60*1000 } // 30 min
}));

// Middleware autenticación
function authMiddleware(req, res, next) {
  if (req.session && req.session.user) next();
  else res.redirect('/login');
}

// Variables para usuarios (multiusuario simple)
const usuarios = {
  admin: { password: 'Jeraldo2903@', role: 'admin' },
  operador: { password: 'operador123', role: 'operador' }
};

// Login
app.get('/login', (req, res) => {
  res.render('login', { error: null });
});
app.post('/login', (req, res) => {
  const { username, password } = req.body;
  if (usuarios[username] && usuarios[username].password === password) {
    req.session.user = username;
    req.session.role = usuarios[username].role;
    res.redirect('/');
  } else {
    res.render('login', { error: 'Usuario o contraseña incorrectos' });
  }
});
app.get('/logout', (req, res) => {
  req.session.destroy(() => {
    res.redirect('/login');
  });
});

// Panel principal
app.get('/', authMiddleware, (req, res) => {
  db.all(`SELECT * FROM citas ORDER BY fecha, hora`, [], (err, citas) => {
    if(err) citas = [];
    res.render('index', {
      user: req.session.user,
      role: req.session.role,
      citas
    });
  });
});

// Gestión preguntas y respuestas
app.get('/respuestas', authMiddleware, (req, res) => {
  db.all(`SELECT * FROM respuestas ORDER BY pregunta`, [], (err, respuestas) => {
    if(err) respuestas = [];
    res.render('respuestas', { respuestas, user: req.session.user });
  });
});

app.post('/respuestas/add', authMiddleware, (req, res) => {
  const { pregunta, respuesta } = req.body;
  db.run(`INSERT OR IGNORE INTO respuestas (pregunta, respuesta) VALUES (?, ?)`, [pregunta.toLowerCase(), respuesta], (err) => {
    if(err) console.error(err);
    res.redirect('/respuestas');
  });
});

app.post('/respuestas/delete/:id', authMiddleware, (req, res) => {
  const id = req.params.id;
  db.run(`DELETE FROM respuestas WHERE id = ?`, id, (err) => {
    if(err) console.error(err);
    res.redirect('/respuestas');
  });
});

// Agendamiento
app.get('/citas', authMiddleware, (req, res) => {
  db.all(`SELECT * FROM citas ORDER BY fecha, hora`, [], (err, citas) => {
    if(err) citas = [];
    res.render('citas', { citas, user: req.session.user });
  });
});

app.post('/citas/add', authMiddleware, (req, res) => {
  const { cliente, servicio, fecha, hora } = req.body;
  // Validar conflictos de citas
  db.get(`SELECT * FROM citas WHERE fecha = ? AND hora = ?`, [fecha, hora], (err, row) => {
    if(row) {
      res.send('Error: Ya existe una cita en ese horario.');
    } else {
      db.run(`INSERT INTO citas (cliente, servicio, fecha, hora) VALUES (?, ?, ?, ?)`, [cliente, servicio, fecha, hora], (err) => {
        if(err) console.error(err);
        res.redirect('/citas');
      });
    }
  });
});

// Historial de chats (básico)
app.get('/historial', authMiddleware, (req, res) => {
  db.all(`SELECT * FROM chats ORDER BY fecha DESC LIMIT 100`, [], (err, chats) => {
    if(err) chats = [];
    res.render('historial', { chats, user: req.session.user });
  });
});

// Notificaciones y alertas (básico, se pueden ampliar)
app.get('/alertas', authMiddleware, (req, res) => {
  // Placeholder para alertas
  res.render('alertas', { user: req.session.user, alerts: [] });
});

// Iniciar servidor
const PORT = 3000;
app.listen(PORT, () => {
  console.log(`✅ Panel corriendo en http://localhost:${PORT}`);
});
EOF

echo "🖥️ Backend del panel web avanzado creado."

mkdir -p /root/gbot/panel/views

cat > /root/gbot/panel/views/login.ejs << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8" />
<title>Login GBOT</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet" />
</head>
<body class="bg-light">
<div class="container mt-5" style="max-width: 400px;">
  <h2 class="mb-4 text-center">Iniciar sesión</h2>
  <% if (error) { %>
    <div class="alert alert-danger"><%= error %></div>
  <% } %>
  <form method="POST" action="/login">
    <div class="mb-3">
      <label for="username" class="form-label">Usuario</label>
      <input type="text" class="form-control" id="username" name="username" required autofocus />
    </div>
    <div class="mb-3">
      <label for="password" class="form-label">Contraseña</label>
      <input type="password" class="form-control" id="password" name="password" required />
    </div>
    <button type="submit" class="btn btn-primary w-100">Entrar</button>
  </form>
</div>
</body>
</html>
EOF

cat > /root/gbot/panel/views/index.ejs << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8" />
<title>Panel GBOT</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet" />
</head>
<body>
<nav class="navbar navbar-expand navbar-dark bg-primary px-3">
  <a class="navbar-brand" href="/">GBOT Panel</a>
  <div class="collapse navbar-collapse">
    <ul class="navbar-nav ms-auto">
      <li class="nav-item"><a class="nav-link" href="/respuestas">Respuestas</a></li>
      <li class="nav-item"><a class="nav-link" href="/citas">Citas</a></li>
      <li class="nav-item"><a class="nav-link" href="/historial">Historial</a></li>
      <li class="nav-item"><a class="nav-link" href="/alertas">Alertas</a></li>
      <li class="nav-item"><a class="nav-link" href="/logout">Cerrar sesión</a></li>
    </ul>
  </div>
</nav>
<div class="container text-center mt-5">
  <h1 class="mb-4">🎛️ Panel de Administración de GBOT</h1>
  <p>Bienvenido, <%= user %> 👋</p>
  <hr>
  <h3>📅 Citas agendadas:</h3>
  <% if(citas.length === 0) { %>
    <p>No hay citas programadas aún.</p>
  <% } else { %>
    <ul class="list-group text-dark mt-3">
      <% citas.forEach(cita => { %>
        <li class="list-group-item">
          <strong><%= cita.cliente %></strong> - <%= cita.servicio %> - <%= cita.fecha %> a las <%= cita.hora %>
        </li>
      <% }); %>
    </ul>
  <% } %>
</div>
</body>
</html>
EOF

cat > /root/gbot/panel/views/respuestas.ejs << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8" />
<title>Respuestas GBOT</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet" />
</head>
<body>
<nav class="navbar navbar-expand navbar-dark bg-primary px-3">
  <a class="navbar-brand" href="/">GBOT Panel</a>
  <div class="collapse navbar-collapse">
    <ul class="navbar-nav ms-auto">
      <li class="nav-item"><a class="nav-link" href="/">Inicio</a></li>
      <li class="nav-item"><a class="nav-link" href="/logout">Cerrar sesión</a></li>
    </ul>
  </div>
</nav>
<div class="container mt-5">
  <h1>📋 Respuestas automáticas</h1>
  <form method="POST" action="/respuestas/add" class="mb-4">
    <div class="mb-3">
      <label for="pregunta" class="form-label">Pregunta (en minúsculas)</label>
      <input type="text" class="form-control" id="pregunta" name="pregunta" required />
    </div>
    <div class="mb-3">
      <label for="respuesta" class="form-label">Respuesta</label>
      <textarea class="form-control" id="respuesta" name="respuesta" rows="3" required></textarea>
    </div>
    <button type="submit" class="btn btn-success">Agregar respuesta</button>
  </form>
  <h3>Respuestas existentes:</h3>
  <% if(respuestas.length === 0) { %>
    <p>No hay respuestas definidas.</p>
  <% } else { %>
    <ul class="list-group">
      <% respuestas.forEach(r => { %>
        <li class="list-group-item d-flex justify-content-between align-items-center">
          <strong><%= r.pregunta %></strong> → <%= r.respuesta %>
          <form method="POST" action="/respuestas/delete/<%= r.id %>" onsubmit="return confirm('¿Eliminar esta respuesta?');">
            <button type="submit" class="btn btn-danger btn-sm">Eliminar</button>
          </form>
        </li>
      <% }); %>
    </ul>
  <% } %>
</div>
</body>
</html>
EOF

cat > /root/gbot/panel/views/citas.ejs << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8" />
<title>Citas GBOT</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet" />
</head>
<body>
<nav class="navbar navbar-expand navbar-dark bg-primary px-3">
  <a class="navbar-brand" href="/">GBOT Panel</a>
  <div class="collapse navbar-collapse">
    <ul class="navbar-nav ms-auto">
      <li class="nav-item"><a class="nav-link" href="/">Inicio</a></li>
      <li class="nav-item"><a class="nav-link" href="/logout">Cerrar sesión</a></li>
    </ul>
  </div>
</nav>
<div class="container mt-5">
  <h1>📅 Agendamiento de Citas</h1>
  <form method="POST" action="/citas/add" class="mb-4">
    <div class="mb-3">
      <label for="cliente" class="form-label">Nombre del cliente</label>
      <input type="text" class="form-control" id="cliente" name="cliente" required />
    </div>
    <div class="mb-3">
      <label for="servicio" class="form-label">Servicio</label>
      <input type="text" class="form-control" id="servicio" name="servicio" required />
    </div>
    <div class="mb-3">
      <label for="fecha" class="form-label">Fecha</label>
      <input type="date" class="form-control" id="fecha" name="fecha" required />
    </div>
    <div class="mb-3">
      <label for="hora" class="form-label">Hora</label>
      <input type="time" class="form-control" id="hora" name="hora" required />
    </div>
    <button type="submit" class="btn btn-primary">Agregar cita</button>
  </form>

  <h3>Citas existentes:</h3>
  <% if(citas.length === 0) { %>
    <p>No hay citas programadas.</p>
  <% } else { %>
    <ul class="list-group">
      <% citas.forEach(cita => { %>
        <li class="list-group-item d-flex justify-content-between align-items-center">
          <div>
            <strong><%= cita.cliente %></strong> - <%= cita.servicio %> - <%= cita.fecha %> a las <%= cita.hora %>
          </div>
          <form method="POST" action="/citas/delete/<%= cita.id %>" onsubmit="return confirm('¿Eliminar esta cita?');">
            <button type="submit" class="btn btn-danger btn-sm">Eliminar</button>
          </form>
        </li>
      <% }); %>
    </ul>
  <% } %>
</div>
</body>
</html>
EOF

cat > /root/gbot/panel/views/historial.ejs << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8" />
<title>Historial de Chats</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet" />
</head>
<body>
<nav class="navbar navbar-expand navbar-dark bg-primary px-3">
  <a class="navbar-brand" href="/">GBOT Panel</a>
  <div class="collapse navbar-collapse">
    <ul class="navbar-nav ms-auto">
      <li class="nav-item"><a class="nav-link" href="/">Inicio</a></li>
      <li class="nav-item"><a class="nav-link" href="/logout">Cerrar sesión</a></li>
    </ul>
  </div>
</nav>
<div class="container mt-5">
  <h1>🗂️ Historial de Chats</h1>
  <% if(chats.length === 0) { %>
    <p>No hay chats guardados.</p>
  <% } else { %>
    <ul class="list-group">
      <% chats.forEach(chat => { %>
        <li class="list-group-item">
          <strong><%= chat.cliente %></strong> (<%= chat.fecha %>)<br/>
          <pre><%= chat.mensaje %></pre>
        </li>
      <% }); %>
    </ul>
  <% } %>
</div>
</body>
</html>
EOF

cat > /root/gbot/panel/views/alertas.ejs << 'EOF'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8" />
<title>Alertas y Notificaciones</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet" />
</head>
<body>
<nav class="navbar navbar-expand navbar-dark bg-primary px-3">
  <a class="navbar-brand" href="/">GBOT Panel</a>
  <div class="collapse navbar-collapse">
    <ul class="navbar-nav ms-auto">
      <li class="nav-item"><a class="nav-link" href="/">Inicio</a></li>
      <li class="nav-item"><a class="nav-link" href="/logout">Cerrar sesión</a></li>
    </ul>
  </div>
</nav>
<div class="container mt-5">
  <h1>🔔 Alertas y Notificaciones</h1>
  <p>No hay alertas por ahora.</p>
</div>
</body>
</html>
EOF

echo "📄 Vistas EJS avanzadas creadas."

#!/bin/bash

# Variables (serán solicitadas si están vacías)
if [ -z "$USUARIO_PANEL" ]; then
  read -p "Usuario para panel web: " USUARIO_PANEL
fi
if [ -z "$PASSWORD_PANEL" ]; then
  read -s -p "Contraseña para panel web: " PASSWORD_PANEL
  echo
fi
if [ -z "$DOMINIO_PANEL" ]; then
  read -p "Dominio para panel web (ejemplo: control.gerarvpn.uk): " DOMINIO_PANEL
fi
if [ -z "$EMAIL_CERTBOT" ]; then
  read -p "Email para Certbot (SSL): " EMAIL_CERTBOT
fi

echo "🚀 Iniciando instalación completa de GBOT..."

# Actualizar e instalar dependencias básicas
apt update && apt upgrade -y
apt install -y curl git build-essential nginx certbot python3-certbot-nginx sqlite3

# Instalar Node.js (versión 18.x)
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# Instalar pm2 globalmente
npm install -g pm2

# Crear estructura
mkdir -p /root/gbot/bot
mkdir -p /root/gbot/panel/views

echo "📂 Estructura creada"

# Crear base de datos SQLite (panel/db.sqlite)
mkdir -p /root/gbot/panel/db
cat > /root/gbot/panel/db/init.sql << 'EOF'
CREATE TABLE IF NOT EXISTS usuarios (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE,
  password TEXT,
  rol TEXT DEFAULT 'operador'
);
CREATE TABLE IF NOT EXISTS respuestas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pregunta TEXT UNIQUE,
  respuesta TEXT
);
CREATE TABLE IF NOT EXISTS citas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cliente TEXT,
  servicio TEXT,
  fecha TEXT,
  hora TEXT
);
CREATE TABLE IF NOT EXISTS chats (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cliente TEXT,
  mensaje TEXT,
  fecha TEXT
);
CREATE TABLE IF NOT EXISTS alertas (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  mensaje TEXT,
  fecha TEXT
);
EOF

sqlite3 /root/gbot/panel/db/db.sqlite < /root/gbot/panel/db/init.sql

echo "🗄️ Base de datos SQLite creada con tablas necesarias"

# Guardar usuario admin inicial (contraseña en texto plano, recomendado cambiar a hash para producción)
sqlite3 /root/gbot/panel/db/db.sqlite "INSERT OR IGNORE INTO usuarios (username, password, rol) VALUES ('$USUARIO_PANEL', '$PASSWORD_PANEL', 'admin');"

echo "👤 Usuario admin '$USUARIO_PANEL' creado"

# Instalar dependencias bot
cd /root/gbot/bot
npm init -y
npm install whatsapp-web.js qrcode-terminal sqlite3 moment node-cron

# Instalar dependencias panel
cd /root/gbot/panel
npm init -y
npm install express express-session ejs sqlite3 bcrypt moment node-cron

echo "📦 Dependencias instaladas para bot y panel"

# Iniciar procesos con PM2
pm2 delete gbot-bot gbot-panel 2>/dev/null
pm2 start /root/gbot/bot/index.js --name gbot-bot
pm2 start /root/gbot/panel/server.js --name gbot-panel
pm2 save
pm2 startup systemd -u root --hp /root

echo "⚙️ PM2 configurado y procesos iniciados"

# Configurar NGINX para proxy y SSL
cat > /etc/nginx/sites-available/gbot << EOF
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

echo "🌐 NGINX configurado para el dominio ${DOMINIO_PANEL}"

# Obtener certificado SSL con Certbot (modo no interactivo)
certbot --nginx -d ${DOMINIO_PANEL} --non-interactive --agree-tos -m ${EMAIL_CERTBOT} --redirect

echo "🔐 Certificado SSL instalado y configurado"

echo "✅ Instalación completa! Accede a https://${DOMINIO_PANEL}"
echo "👤 Usuario admin: $USUARIO_PANEL"
echo "🔑 Recuerda cambiar la contraseña en el panel si es necesario."