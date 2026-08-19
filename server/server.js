const net = require('net');
const http = require('http');
const crypto = require('crypto');
const path = require('path');
const sirv = require('sirv');
const { WebSocketServer } = require('ws');

const EMULATOR_TCP_PORT = 8765;
const WEB_PORT = 8766;
const EMULATOR_BIND_HOST = process.env.EMULATOR_BIND_HOST || '127.0.0.1';
// Player 2's browser generally needs to reach this from off-box (LAN IP, tunnel, or a standing
// public address)
const WEB_BIND_HOST = process.env.WEB_BIND_HOST || '0.0.0.0';
const INTERFACE_BUILD_PATH = path.join(__dirname, '..', 'interface', 'build');

const CONTROLLER_TOKEN = process.env.CONTROLLER_TOKEN || crypto.randomBytes(9).toString('base64url');
const MAX_MESSAGE_BYTES = 2048;
const MAX_NAME_LENGTH = 20;
const MAX_TOKEN_LENGTH = 256;
const MAX_EMULATOR_BUFFER_BYTES = 1024 * 1024; // defensive cap in case a line with no \n ever shows up
const MAX_FRAME_LINE_BYTES = 400 * 1024;
const MIN_STREAM_FPS = 5;
const MAX_STREAM_FPS = 24;

let emulatorSocket = null;
let emulatorBuffer = '';
const player2Sockets = new Set();
let controllerSocket = null;
let lastPlayerInfoLine = null;
let lastPlayerNameLine = null;
let lastStreamEnabledLine = null;
let lastStreamFpsLine = null;
let latestFrame = null; // most recent screenshot as a raw PNG Buffer

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
  if (lastStreamFpsLine) {
    socket.write(lastStreamFpsLine + '\n');
  }

  socket.on('data', (chunk) => {
    emulatorBuffer += chunk.toString('utf8');
    if (emulatorBuffer.length > MAX_EMULATOR_BUFFER_BYTES) {
      console.log('[relay] emulator sent an unreasonably large line, dropping connection');
      socket.destroy();
      return;
    }
    let nl;
    while ((nl = emulatorBuffer.indexOf('\n')) !== -1) {
      const line = emulatorBuffer.slice(0, nl);
      emulatorBuffer = emulatorBuffer.slice(nl + 1);
      if (line.trim().length === 0) continue;

      // Decode base64 blob and send to browser as a binary WS message
      if (line.includes('"type":"screen_frame"')) {
        if (line.length > MAX_FRAME_LINE_BYTES) {
          console.log('[relay] dropping oversized screen_frame from emulator');
          continue;
        }
        let frame;
        try {
          const parsed = JSON.parse(line);
          if (typeof parsed.data !== 'string') throw new Error('missing data field');
          frame = Buffer.from(parsed.data, 'base64');
        } catch (err) {
          console.log('[relay] dropping malformed screen_frame from emulator:', err.message);
          continue;
        }
        latestFrame = frame;
        for (const ws of player2Sockets) {
          ws.send(frame);
        }
        continue;
      }

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

tcpServer.listen(EMULATOR_TCP_PORT, EMULATOR_BIND_HOST, () => {
  console.log(`[relay] listening for emulator on tcp://${EMULATOR_BIND_HOST}:${EMULATOR_TCP_PORT}`);
});

const serveInterface = sirv(INTERFACE_BUILD_PATH, { single: true });

const httpServer = http.createServer((req, res) => {
  serveInterface(req, res);
});

const wss = new WebSocketServer({ server: httpServer, path: '/ws' });

function parseIncomingMessage(raw) {
  if (raw.length > MAX_MESSAGE_BYTES) {
    console.log('[relay] dropping oversized message from player 2');
    return null;
  }

  let msg;
  try {
    msg = JSON.parse(raw);
  } catch {
    console.log('[relay] dropping malformed JSON from player 2');
    return null;
  }
  if (typeof msg !== 'object' || msg === null) return null;

  switch (msg.type) {
    case 'authenticate': {
      if (typeof msg.token !== 'string' || msg.token.length === 0 || msg.token.length > MAX_TOKEN_LENGTH) {
        return null;
      }
      return msg;
    }
    case 'action_choice': {
      if (msg.action === 'move') {
        if (!Number.isInteger(msg.moveIndex) || msg.moveIndex < 0 || msg.moveIndex > 3) return null;
        return msg;
      }
      if (msg.action === 'switch') {
        if (!Number.isInteger(msg.partySlot) || msg.partySlot < 0 || msg.partySlot > 5) return null;
        return msg;
      }
      return null;
    }
    case 'set_player2_name': {
      if (typeof msg.name !== 'string' || msg.name.trim().length === 0 || msg.name.length > MAX_NAME_LENGTH) {
        return null;
      }
      return msg;
    }
    case 'set_stream_enabled': {
      if (typeof msg.enabled !== 'boolean') return null;
      return msg;
    }
    case 'set_stream_fps': {
      if (!Number.isInteger(msg.fps) || msg.fps < MIN_STREAM_FPS || msg.fps > MAX_STREAM_FPS) {
        return null;
      }
      return msg;
    }
    default:
      console.log('[relay] dropping unknown message type from player 2:', msg.type);
      return null;
  }
}

wss.on('connection', (ws) => {
  console.log('[relay] player 2 connected (spectating until authenticated)');
  player2Sockets.add(ws);
  if (lastPlayerInfoLine) {
    ws.send(lastPlayerInfoLine);
  }
  if (latestFrame) {
    ws.send(latestFrame);
  }

  ws.on('message', (data) => {
    const raw = data.toString('utf8');
    const msg = parseIncomingMessage(raw);
    if (!msg) return;

    if (msg.type === 'authenticate') {
      if (msg.token !== CONTROLLER_TOKEN) {
        ws.send(JSON.stringify({ type: 'auth_result', role: 'spectator', reason: 'invalid_token' }));
        return;
      }
      if (controllerSocket && controllerSocket !== ws) {
        ws.send(JSON.stringify({ type: 'auth_result', role: 'spectator', reason: 'controller_taken' }));
        return;
      }
      controllerSocket = ws;
      console.log('[relay] player 2 authenticated as controller');
      ws.send(JSON.stringify({ type: 'auth_result', role: 'controller' }));
      return;
    }

    if (ws !== controllerSocket) {
      console.log('[relay] dropping command from a non-controller (spectator)');
      return;
    }

    const line = JSON.stringify(msg);
    console.log('[relay] from player 2:', line);
    if (msg.type === 'set_player2_name') {
      lastPlayerNameLine = line;
    }
    if (msg.type === 'set_stream_enabled') {
      lastStreamEnabledLine = line;
    }
    if (msg.type === 'set_stream_fps') {
      lastStreamFpsLine = line;
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
    if (controllerSocket === ws) {
      controllerSocket = null;
      console.log('[relay] controller slot is free again');
    }
  });

  ws.on('error', (err) => {
    console.log('[relay] player 2 socket error:', err.message);
  });
});

httpServer.listen(WEB_PORT, WEB_BIND_HOST, () => {
  console.log(`[relay] serving the interface + websocket + screenshot on http://${WEB_BIND_HOST}:${WEB_PORT}`);
  console.log(`[relay] controller token: ${CONTROLLER_TOKEN} (share this with Player 2, not spectators)`);
});
