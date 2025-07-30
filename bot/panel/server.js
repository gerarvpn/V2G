const express = require('express');
const session = require('express-session');
const path = require('path');
const fs = require('fs');
const bodyParser = require('body-parser');

const app = express();

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

app.use(express.static(path.join(__dirname, 'public')));
app.use(bodyParser.urlencoded({ extended: true }));
app.use(bodyParser.json());

app.use(session({
  secret: 'un-secreto-muy-seguro-gbot',
  resave: false,
  saveUninitialized: false,
  cookie: { maxAge: 60 * 60 * 1000 } // 1 hora
}));

// Middleware de autenticación
function authMiddleware(req, res, next) {
  if (req.session && req.session.user) {
    next();
  } else {
    res.redirect('/login');
  }
}

// Configura aquí tus usuarios y contraseñas (ideal: usar base de datos)
const USUARIO_PANEL = "gerargzm";  // Cambiar en el script de instalación
const PASSWORD_PANEL = "Jeraldo2903@"; // Cambiar en el script de instalación

// Login
app.get('/login', (req, res) => {
  res.render('login', { error: null });
});

app.post('/login', (req, res) => {
  const { username, password } = req.body;
  if (username === USUARIO_PANEL && password === PASSWORD_PANEL) {
    req.session.user = username;
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

// Página principal - Panel
app.get('/', authMiddleware, (req, res) => {
  res.render('index', { user: req.session.user });
});

// Página para gestionar preguntas y respuestas
app.get('/respuestas', authMiddleware, (req, res) => {
  let data = [];
  try {
    const contenido = fs.readFileSync(path.join(__dirname, 'db', 'db.json'), 'utf-8');
    data = JSON.parse(contenido);
  } catch (err) {
    data = [];
  }
  res.render('respuestas', { user: req.session.user, respuestas: data });
});

// Agregar o actualizar preguntas y respuestas (POST)
app.post('/respuestas', authMiddleware, (req, res) => {
  const { pregunta, respuesta, tipo, mediaUrl } = req.body;
  const dbPath = path.join(__dirname, 'db', 'db.json');
  let data = [];
  try {
    const contenido = fs.readFileSync(dbPath, 'utf-8');
    data = JSON.parse(contenido);
  } catch (err) {
    data = [];
  }

  // Si la pregunta ya existe, actualizarla; si no, agregar
  const index = data.findIndex(r => r.pregunta.toLowerCase() === pregunta.toLowerCase());
  if (index >= 0) {
    data[index] = { pregunta, respuesta, tipo, mediaUrl };
  } else {
    data.push({ pregunta, respuesta, tipo, mediaUrl });
  }

  fs.writeFileSync(dbPath, JSON.stringify(data, null, 2), 'utf-8');
  res.redirect('/respuestas');
});

// API para historial básico (futuro)
app.get('/historial', authMiddleware, (req, res) => {
  try {
    const log = fs.readFileSync(path.join(__dirname, 'db', 'chat_history.log'), 'utf-8');
    res.send(`<pre>${log}</pre>`);
  } catch {
    res.send('No hay historial disponible.');
  }
});

// Página no encontrada
app.use((req, res) => {
  res.status(404).send('Página no encontrada');
});

// Crear carpeta db si no existe
const dbDir = path.join(__dirname, 'db');
if (!fs.existsSync(dbDir)) {
  fs.mkdirSync(dbDir);
}

// Iniciar servidor
const PORT = 3000;
app.listen(PORT, () => {
  console.log(`✅ Panel corriendo en http://localhost:${PORT}`);
});