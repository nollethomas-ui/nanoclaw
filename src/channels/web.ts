/**
 * src/channels/web.ts
 * WebSocket-based web channel for the Nano voice UI.
 * Serves static files (HAL 9000 UI) and accepts WebSocket connections.
 * JID format: web:<sessionId>
 */

import { createServer, type Server } from 'http';
import fs from 'fs';
import path from 'path';
import { WebSocketServer, WebSocket } from 'ws';

import { ASSISTANT_NAME } from '../config.js';
import { logger } from '../logger.js';
import type {
  Channel,
  OnChatMetadata,
  OnInboundMessage,
  RegisteredGroup,
} from '../types.js';

export interface WebChannelOpts {
  onMessage: OnInboundMessage;
  onChatMetadata: OnChatMetadata;
  registeredGroups: () => Record<string, RegisteredGroup>;
}

// MIME types for static file serving
const MIME_TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.svg': 'image/svg+xml',
  '.json': 'application/json',
  '.woff2': 'font/woff2',
};

export class WebChannel implements Channel {
  name = 'web';

  private server: Server | null = null;
  private wss: WebSocketServer | null = null;
  private connections = new Map<string, WebSocket>();
  private opts: WebChannelOpts;
  private port: number;
  private assetsDir: string;

  constructor(port: number, opts: WebChannelOpts) {
    this.port = port;
    this.opts = opts;
    this.assetsDir = path.join(process.cwd(), 'assets', 'web-ui');
  }

  async connect(): Promise<void> {
    // Serve static files via HTTP
    this.server = createServer((req, res) => {
      // Strip query parameters (cache busters like ?v=3)
      const urlPath = (req.url || '/').split('?')[0];

      let filePath: string;
      if (urlPath === '/' || urlPath === '/index.html') {
        filePath = path.join(this.assetsDir, 'index.html');
      } else if (urlPath.startsWith('/static/')) {
        filePath = path.join(this.assetsDir, urlPath.replace('/static/', ''));
      } else {
        filePath = path.join(this.assetsDir, urlPath);
      }

      // Prevent directory traversal
      if (!filePath.startsWith(this.assetsDir)) {
        res.writeHead(403);
        res.end('Forbidden');
        return;
      }

      const ext = path.extname(filePath).toLowerCase();
      const contentType = MIME_TYPES[ext] || 'application/octet-stream';

      fs.readFile(filePath, (err, data) => {
        if (err) {
          if (err.code === 'ENOENT') {
            res.writeHead(404);
            res.end('Not Found');
          } else {
            res.writeHead(500);
            res.end('Internal Server Error');
          }
          return;
        }
        res.writeHead(200, { 'Content-Type': contentType });
        res.end(data);
      });
    });

    // WebSocket server on the same HTTP server
    this.wss = new WebSocketServer({ server: this.server });

    this.wss.on('connection', (ws, req) => {
      // Extract session ID from query parameter: /ws?session=<uuid>
      const url = new URL(req.url || '/', `http://${req.headers.host}`);
      const sessionId = url.searchParams.get('session') || crypto.randomUUID();
      const jid = `web:${sessionId}`;

      this.connections.set(jid, ws);

      logger.info({ jid }, 'Web client connected');

      // Store metadata — web sessions are always solo chats
      this.opts.onChatMetadata(jid, new Date().toISOString(), 'Web UI', 'web', false);

      // Auto-register as solo chat if not already registered
      const group = this.opts.registeredGroups()[jid];
      if (!group) {
        logger.info({ jid }, 'Web session not registered — messages will be stored but require registration');
      }

      // Send session info to client
      ws.send(JSON.stringify({ type: 'connected', sessionId, assistant: ASSISTANT_NAME }));

      ws.on('message', (raw) => {
        try {
          const data = JSON.parse(raw.toString());

          if (data.type === 'message' && data.text) {
            const timestamp = new Date().toISOString();
            const msgId = `web-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

            // Deliver message to NanoClaw pipeline
            this.opts.onMessage(jid, {
              id: msgId,
              chat_jid: jid,
              sender: sessionId,
              sender_name: 'Web User',
              content: data.text,
              timestamp,
              is_from_me: false,
            });

            logger.info({ jid, length: data.text.length }, 'Web message received');
          }
        } catch (err) {
          logger.warn({ err }, 'Invalid WebSocket message');
        }
      });

      ws.on('close', () => {
        this.connections.delete(jid);
        logger.info({ jid }, 'Web client disconnected');
      });

      ws.on('error', (err) => {
        logger.error({ jid, err }, 'WebSocket error');
        this.connections.delete(jid);
      });
    });

    return new Promise<void>((resolve) => {
      this.server!.listen(this.port, () => {
        logger.info({ port: this.port }, 'Web channel started');
        console.log(`\n  Web UI: http://localhost:${this.port}/`);
        console.log(`  WebSocket: ws://localhost:${this.port}/\n`);
        resolve();
      });
    });
  }

  async sendMessage(jid: string, text: string): Promise<void> {
    const ws = this.connections.get(jid);
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      logger.warn({ jid }, 'Cannot send: web client not connected');
      return;
    }

    ws.send(JSON.stringify({ type: 'text', text }));
    logger.info({ jid, length: text.length }, 'Web message sent');
  }

  isConnected(): boolean {
    return this.server?.listening ?? false;
  }

  ownsJid(jid: string): boolean {
    return jid.startsWith('web:');
  }

  async disconnect(): Promise<void> {
    // Close all WebSocket connections
    for (const [jid, ws] of this.connections) {
      ws.close(1001, 'Server shutting down');
      this.connections.delete(jid);
    }

    // Close WebSocket server
    if (this.wss) {
      this.wss.close();
      this.wss = null;
    }

    // Close HTTP server
    if (this.server) {
      await new Promise<void>((resolve) => {
        this.server!.close(() => resolve());
      });
      this.server = null;
    }

    logger.info('Web channel stopped');
  }

  async setTyping(jid: string, isTyping: boolean): Promise<void> {
    const ws = this.connections.get(jid);
    if (!ws || ws.readyState !== WebSocket.OPEN) return;

    ws.send(JSON.stringify({ type: 'typing', isTyping }));
  }

  async sendAudio(jid: string, audioBuffer: Buffer, _ptt = true): Promise<void> {
    const ws = this.connections.get(jid);
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      logger.warn({ jid }, 'Cannot send audio: web client not connected');
      return;
    }

    const base64 = audioBuffer.toString('base64');
    ws.send(JSON.stringify({ type: 'audio', audio_base64: base64 }));
    logger.info({ jid, size: audioBuffer.length }, 'Web audio sent');
  }
}
