const net = require('net');
const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const EMULATOR_TCP_PORT = 8765;
const PLAYER2_WS_PORT = 8766;
const SCREEN_HTTP_PORT = 8767;
const SCREEN_FILE_PATH = path.join(__dirname, 'public', 'screen.png');

let emulatorSocket = null;
let emulatorBuffer = '';
const player2Sockets = new Set();
let lastPlayerInfoLine = null;

const tcpServer = net.createServer((socket) => {
  console.log('[relay] emulator connected');
  emulatorSocket = socket;
  emulatorBuffer = '';

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

const wss = new WebSocketServer({ port: PLAYER2_WS_PORT });

wss.on('connection', (ws) => {
  console.log('[relay] player 2 connected');
  player2Sockets.add(ws);
  if (lastPlayerInfoLine) {
    ws.send(lastPlayerInfoLine);
  }

  ws.on('message', (data) => {
    const line = data.toString('utf8');
    console.log('[relay] from player 2:', line);
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

console.log(`[relay] listening for player 2 on ws://127.0.0.1:${PLAYER2_WS_PORT}`);

const screenServer = http.createServer((req, res) => {
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
  res.writeHead(404);
  res.end();
});

screenServer.listen(SCREEN_HTTP_PORT, () => {
  console.log(`[relay] serving screen preview on http://127.0.0.1:${SCREEN_HTTP_PORT}/screen.png`);
});
