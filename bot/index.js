const { Client, LocalAuth, MessageMedia } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const fs = require('fs');
const axios = require('axios');

const client = new Client({
    authStrategy: new LocalAuth({ clientId: "gbot" }),
});

client.on('qr', qr => {
    qrcode.generate(qr, { small: true });
    console.log('✅ Escanea el código QR con WhatsApp');
});

client.on('ready', () => {
    console.log('🤖 GBOT está listo y conectado');
});

client.on('message', async message => {
    const respuestas = JSON.parse(fs.readFileSync('/root/gbot/panel/db/db.json'));

    const textoRecibido = message.body.toLowerCase();

    // Verificar coincidencias exactas
    const respuesta = respuestas.find(r => r.pregunta.toLowerCase() === textoRecibido);

    if (respuesta) {
        if (respuesta.tipo === "texto") {
            message.reply(respuesta.respuesta);
        } else if (respuesta.tipo === "imagen" && respuesta.mediaUrl) {
            const media = await MessageMedia.fromUrl(respuesta.mediaUrl);
            client.sendMessage(message.from, media, { caption: respuesta.respuesta });
        }
    }

    // Ejemplo de agendamiento básico (puedes expandirlo)
    if (textoRecibido.includes("cita")) {
        message.reply("🗓️ Para agendar una cita, por favor proporciona la fecha y hora.");
    }

    // Guardar historial (opcional futuro)
    const log = `[${new Date().toISOString()}] ${message.from}: ${message.body}\n`;
    fs.appendFileSync('/root/gbot/panel/db/chat_history.log', log);
});

client.on('auth_failure', msg => {
    console.error('❌ Error de autenticación', msg);
});

client.initialize();