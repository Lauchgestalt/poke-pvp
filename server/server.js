const net = require('net');
const http = require('http');
const fs = require('fs');
const path = require('path');
const sirv = require('sirv');
const { WebSocketServer } = require('ws');

const EMULATOR_TCP_PORT = 8765;
const WEB_PORT = 8766;
const SCREEN_FILE_PATH = path.join(__dirname, 'public', 'screen.png');
const INTERFACE_BUILD_PATH = path.join(__dirname, '..', 'interface', 'build');

let emulatorSocket = null;
let emulatorBuffer = '';
const player2Sockets = new Set();
let lastPlayerInfoLine = null;
let lastPlayerNameLine = null;
let lastStreamEnabledLine = null;

const tcpServer = net.createServer((socket) => {
  console.log('[relay] emulator connected');
  emulatorSocket = socket;
  emulatorBuffer = '';

  if (lastPlayerNameLine) {
    socket.write(lastPlayerNameLine + '\n');
  }
  if (lastStreamEnabledLine) {
    socket.write(lastStreamEnabledLine + '\n');
  }

  socket.on('data', (chunk) => {
    emulatorBuffer += chunk.toString('utf8');
    let nl;
    while ((nl = emulatorBuffer.indexOf('\n')) !== -1) {
      const line = emulatorBuffer.slice(0, nl);
      emulatorBuffer = emulatorBuffer.slice(nl + 1);
      if (line.trim().length === 0) continue;
      console.log('[relay] from emulator:', line);
      if (line.includes('"type":"player_info"')) {
        lastPlayerInfoLine = line;
      }
      for (const ws of player2Sockets) {
        ws.send(line);
      }
    }
  });

  socket.on('close', () => {
    console.log('[relay] emulator disconnected');
    if (emulatorSocket === socket) emulatorSocket = null;
  });

  socket.on('error', (err) => {
    console.log('[relay] emulator socket error:', err.message);
  });
});

tcpServer.listen(EMULATOR_TCP_PORT, () => {
  console.log(`[relay] listening for emulator on tcp://127.0.0.1:${EMULATOR_TCP_PORT}`);
});

const serveInterface = sirv(INTERFACE_BUILD_PATH, { single: true });

const httpServer = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url.split('?')[0] === '/screen.png') {
    fs.readFile(SCREEN_FILE_PATH, (err, data) => {
      if (err) {
        res.writeHead(404);
        res.end();
        return;
      }
      res.writeHead(200, { 'Content-Type': 'image/png', 'Cache-Control': 'no-store' });
      res.end(data);
    });
    return;
  }
  serveInterface(req, res);
});

const wss = new WebSocketServer({ server: httpServer, path: '/ws' });

wss.on('connection', (ws) => {
  console.log('[relay] player 2 connected');
  player2Sockets.add(ws);
  if (lastPlayerInfoLine) {
    ws.send(lastPlayerInfoLine);
  }

  ws.on('message', (data) => {
    const line = data.toString('utf8');
    console.log('[relay] from player 2:', line);
    if (line.includes('"type":"set_player2_name"')) {
      lastPlayerNameLine = line;
    }
    if (line.includes('"type":"set_stream_enabled"')) {
      lastStreamEnabledLine = line;
    }
    if (emulatorSocket) {
      emulatorSocket.write(line + '\n');
    } else {
      console.log('[relay] no emulator connected, dropping message');
    }
  });

  ws.on('close', () => {
    console.log('[relay] player 2 disconnected');
    player2Sockets.delete(ws);
  });

  ws.on('error', (err) => {
    console.log('[relay] player 2 socket error:', err.message);
  });
});

httpServer.listen(WEB_PORT, () => {
  console.log(`[relay] serving the interface + websocket + screenshot on http://127.0.0.1:${WEB_PORT}`);
});
