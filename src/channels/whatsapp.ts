import fs from 'fs';
import path from 'path';

import makeWASocket, {
  Browsers,
  DisconnectReason,
  WASocket,
  downloadMediaMessage,
  fetchLatestWaWebVersion,
  makeCacheableSignalKeyStore,
  useMultiFileAuthState,
} from '@whiskeysockets/baileys';

import { transcribeAudio } from '../transcription.js';

import {
  ASSISTANT_HAS_OWN_NUMBER,
  ASSISTANT_NAME,
  STORE_DIR,
} from '../config.js';
import { getLastGroupSync, setLastGroupSync, updateChatName } from '../db.js';
import { readEnvFile } from '../env.js';
import { logger } from '../logger.js';
import {
  Channel,
  OnInboundMessage,
  OnChatMetadata,
  RegisteredGroup,
} from '../types.js';

const GROUP_SYNC_INTERVAL_MS = 24 * 60 * 60 * 1000; // 24 hours

// --- Pairing code for headless authentication ---
// Set WHATSAPP_PHONE in .env (e.g. "4917XXXXXXXX") to enable pairing code mode.
// On QR event, the service requests a numeric pairing code instead of exiting.
const WHATSAPP_PHONE = (() => {
  const env = readEnvFile(['WHATSAPP_PHONE']);
  return env.WHATSAPP_PHONE || '';
})();

// --- K1: Sender allowlist ---
// Comma-separated phone numbers (without @s.whatsapp.net), e.g. "4917XXXXXXXX,4915XXXXXXXX"
const ALLOWED_SENDERS = (() => {
  const env = readEnvFile(['ALLOWED_SENDERS']);
  const raw = env.ALLOWED_SENDERS || '';
  if (!raw) return null; // null = no restriction (allowlist disabled)
  const set = new Set(raw.split(',').map(s => s.trim()).filter(Boolean));
  if (set.size > 0) logger.info({ count: set.size }, 'Sender allowlist active');
  return set;
})();

function isSenderAllowed(senderJid: string): boolean {
  if (!ALLOWED_SENDERS) return true; // no allowlist = allow all
  const phone = senderJid.split('@')[0].split(':')[0];
  return ALLOWED_SENDERS.has(phone);
}

// --- H6: Rate limiting per sender ---
const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute
const RATE_LIMIT_MAX = (() => {
  const env = readEnvFile(['RATE_LIMIT_MAX_PER_MIN']);
  return parseInt(env.RATE_LIMIT_MAX_PER_MIN || '10', 10);
})();

const senderTimestamps = new Map<string, number[]>();

function isRateLimited(senderJid: string): boolean {
  const now = Date.now();
  const phone = senderJid.split('@')[0].split(':')[0];
  const timestamps = senderTimestamps.get(phone) || [];
  // Remove entries outside the window
  const recent = timestamps.filter(t => now - t < RATE_LIMIT_WINDOW_MS);
  if (recent.length >= RATE_LIMIT_MAX) {
    logger.warn({ sender: maskJid(phone) }, 'Rate limited');
    return true;
  }
  recent.push(now);
  senderTimestamps.set(phone, recent);
  return false;
}

// --- H3: Mask JIDs in logs ---
function maskJid(jidOrPhone: string): string {
  const phone = jidOrPhone.split('@')[0].split(':')[0];
  if (phone.length <= 4) return '****';
  return phone.slice(0, 3) + '***' + phone.slice(-2);
}

// --- H2: Audio validation constants ---
const MAX_AUDIO_SIZE = 10 * 1024 * 1024; // 10 MB
const ALLOWED_AUDIO_MIMETYPES = ['audio/ogg', 'audio/mpeg', 'audio/mp4', 'audio/wav', 'audio/x-opus+ogg'];

// --- H1: Voice input sanitization ---
const MAX_TRANSCRIPT_LENGTH = 2000;

function sanitizeTranscript(raw: string): string {
  // Truncate to limit
  let text = raw.slice(0, MAX_TRANSCRIPT_LENGTH);
  // Strip control characters (keep basic whitespace)
  text = text.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');
  return text.trim();
}

export interface WhatsAppChannelOpts {
  onMessage: OnInboundMessage;
  onChatMetadata: OnChatMetadata;
  registeredGroups: () => Record<string, RegisteredGroup>;
}

export class WhatsAppChannel implements Channel {
  name = 'whatsapp';

  private sock!: WASocket;
  private connected = false;
  private lidToPhoneMap: Record<string, string> = {};
  private outgoingQueue: Array<{ jid: string; text: string }> = [];
  private flushing = false;
  private groupSyncTimerStarted = false;

  private opts: WhatsAppChannelOpts;

  constructor(opts: WhatsAppChannelOpts) {
    this.opts = opts;
  }

  async connect(): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      this.connectInternal(resolve).catch(reject);
    });
  }

  private async connectInternal(onFirstOpen?: () => void): Promise<void> {
    const authDir = path.join(STORE_DIR, 'auth');
    fs.mkdirSync(authDir, { recursive: true });

    const { state, saveCreds } = await useMultiFileAuthState(authDir);

    const { version } = await fetchLatestWaWebVersion({}).catch((err) => {
      logger.warn(
        { err },
        'Failed to fetch latest WA Web version, using default',
      );
      return { version: undefined };
    });
    this.sock = makeWASocket({
      version,
      auth: {
        creds: state.creds,
        keys: makeCacheableSignalKeyStore(state.keys, logger),
      },
      printQRInTerminal: false,
      logger,
      browser: Browsers.macOS('Chrome'),
    });

    this.sock.ev.on('connection.update', (update) => {
      const { connection, lastDisconnect, qr } = update;

      if (qr) {
        if (WHATSAPP_PHONE) {
          // Headless pairing code mode — request numeric code instead of QR scan
          logger.info('QR received but WHATSAPP_PHONE set — requesting pairing code...');
          this.sock.requestPairingCode(WHATSAPP_PHONE).then((code) => {
            logger.info({ code }, '========================================');
            logger.info({ code }, '  PAIRING CODE: ' + code);
            logger.info({ code }, '========================================');
            logger.info('  1. Open WhatsApp on your phone');
            logger.info('  2. Settings → Linked Devices → Link a Device');
            logger.info('  3. Tap "Link with phone number instead"');
            logger.info('  4. Enter the code above');
          }).catch((err) => {
            logger.error({ err }, 'Failed to request pairing code');
          });
        } else {
          const msg =
            'WhatsApp authentication required. Set WHATSAPP_PHONE in .env for headless pairing, or run /setup in Claude Code.';
          logger.error(msg);
          setTimeout(() => process.exit(1), 1000);
        }
      }

      if (connection === 'close') {
        this.connected = false;
        const reason = (
          lastDisconnect?.error as { output?: { statusCode?: number } }
        )?.output?.statusCode;
        const shouldReconnect = reason !== DisconnectReason.loggedOut;
        logger.info(
          {
            reason,
            shouldReconnect,
            queuedMessages: this.outgoingQueue.length,
          },
          'Connection closed',
        );

        if (shouldReconnect) {
          logger.info('Reconnecting...');
          this.connectInternal().catch((err) => {
            logger.error({ err }, 'Failed to reconnect, retrying in 5s');
            setTimeout(() => {
              this.connectInternal().catch((err2) => {
                logger.error({ err: err2 }, 'Reconnection retry failed');
              });
            }, 5000);
          });
        } else {
          logger.info('Logged out. Run /setup to re-authenticate.');
          process.exit(0);
        }
      } else if (connection === 'open') {
        this.connected = true;
        logger.info('Connected to WhatsApp');

        // Announce availability so WhatsApp relays subsequent presence updates (typing indicators)
        this.sock.sendPresenceUpdate('available').catch((err) => {
          logger.warn({ err }, 'Failed to send presence update');
        });

        // Build LID to phone mapping from auth state for self-chat translation
        if (this.sock.user) {
          const phoneUser = this.sock.user.id.split(':')[0];
          const lidUser = this.sock.user.lid?.split(':')[0];
          if (lidUser && phoneUser) {
            this.lidToPhoneMap[lidUser] = `${phoneUser}@s.whatsapp.net`;
            logger.debug('LID to phone mapping set');
          }
        }

        // Flush any messages queued while disconnected
        this.flushOutgoingQueue().catch((err) =>
          logger.error({ err }, 'Failed to flush outgoing queue'),
        );

        // Sync group metadata on startup (respects 24h cache)
        this.syncGroupMetadata().catch((err) =>
          logger.error({ err }, 'Initial group sync failed'),
        );
        // Set up daily sync timer (only once)
        if (!this.groupSyncTimerStarted) {
          this.groupSyncTimerStarted = true;
          setInterval(() => {
            this.syncGroupMetadata().catch((err) =>
              logger.error({ err }, 'Periodic group sync failed'),
            );
          }, GROUP_SYNC_INTERVAL_MS);
        }

        // Signal first connection to caller
        if (onFirstOpen) {
          onFirstOpen();
          onFirstOpen = undefined;
        }
      }
    });

    this.sock.ev.on('creds.update', saveCreds);

    this.sock.ev.on('messages.upsert', async ({ messages }) => {
      for (const msg of messages) {
        if (!msg.message) continue;
        const rawJid = msg.key.remoteJid;
        if (!rawJid || rawJid === 'status@broadcast') continue;

        // Translate LID JID to phone JID if applicable
        const chatJid = await this.translateJid(rawJid);

        const timestamp = new Date(
          Number(msg.messageTimestamp) * 1000,
        ).toISOString();

        // Always notify about chat metadata for group discovery
        const isGroup = chatJid.endsWith('@g.us');
        this.opts.onChatMetadata(
          chatJid,
          timestamp,
          undefined,
          'whatsapp',
          isGroup,
        );

        // Only deliver full message for registered groups
        const groups = this.opts.registeredGroups();
        if (groups[chatJid]) {
          // K1: Check sender allowlist (bypass for own messages in self-chat/DM)
          const sender = msg.key.participant || msg.key.remoteJid || '';
          const fromMe = msg.key.fromMe || false;
          if (!fromMe && !isSenderAllowed(sender)) {
            logger.info({ sender: maskJid(sender) }, 'Blocked: sender not on allowlist');
            continue;
          }

          // H6: Check rate limit
          if (isRateLimited(sender)) {
            continue;
          }

          const isVoiceMessage = !!msg.message?.audioMessage;
          let content =
            msg.message?.conversation ||
            msg.message?.extendedTextMessage?.text ||
            msg.message?.imageMessage?.caption ||
            msg.message?.videoMessage?.caption ||
            '';

          // Skip bot-sent voice notes to prevent TTS feedback loop.
          // Bot-sent audio comes from the PN-JID (@s.whatsapp.net),
          // while user voice notes come from the LID-JID (@lid).
          if (isVoiceMessage && fromMe && sender.endsWith('@s.whatsapp.net')) {
            logger.debug({ sender: maskJid(sender) }, 'Skipping bot-sent voice note');
            continue;
          }

          // Handle voice messages: download, transcribe, inject as [Voice: ...]
          if (isVoiceMessage && !content) {
            try {
              // H2: Validate audio before downloading
              const audioMsg = msg.message.audioMessage!;
              const fileSize = audioMsg.fileLength ? Number(audioMsg.fileLength) : 0;
              const mimetype = audioMsg.mimetype || 'audio/ogg';

              if (fileSize > MAX_AUDIO_SIZE) {
                logger.warn({ sender: maskJid(sender), size: fileSize }, 'Audio too large, skipping');
                continue;
              }

              if (!ALLOWED_AUDIO_MIMETYPES.some(m => mimetype.startsWith(m))) {
                logger.warn({ sender: maskJid(sender), mimetype }, 'Invalid audio MIME type, skipping');
                continue;
              }

              const audioBuffer = await downloadMediaMessage(
                msg,
                'buffer',
                {},
                { logger, reuploadRequest: this.sock!.updateMediaMessage },
              ) as Buffer;

              // H2: Double-check actual buffer size
              if (audioBuffer.length > MAX_AUDIO_SIZE) {
                logger.warn({ sender: maskJid(sender), size: audioBuffer.length }, 'Downloaded audio too large');
                continue;
              }

              const transcript = await transcribeAudio(audioBuffer, mimetype);
              // H1: Sanitize transcript to prevent prompt injection
              const sanitized = sanitizeTranscript(transcript);
              content = `[Voice: ${sanitized}]`;
              // H3: Log only length, not content or full JID
              logger.info({ sender: maskJid(sender), transcriptLen: sanitized.length }, 'Voice message transcribed');
            } catch (err) {
              // H3: Mask JID in error logs
              logger.error({ err, sender: maskJid(sender) }, 'Failed to transcribe voice message');
              continue;
            }
          }

          // Skip protocol messages with no text content (encryption keys, read receipts, etc.)
          if (!content) continue;

          const senderName = msg.pushName || sender.split('@')[0];
          // Detect bot messages: with own number, fromMe is reliable
          // since only the bot sends from that number.
          // With shared number, bot messages carry the assistant name prefix
          // (even in DMs/self-chat) so we check for that.
          const isBotMessage = ASSISTANT_HAS_OWN_NUMBER
            ? fromMe
            : content.startsWith(`${ASSISTANT_NAME}:`);

          this.opts.onMessage(chatJid, {
            id: msg.key.id || '',
            chat_jid: chatJid,
            sender,
            sender_name: senderName,
            content,
            timestamp,
            is_from_me: fromMe,
            is_bot_message: isBotMessage,
          });
        }
      }
    });
  }

  async sendMessage(jid: string, text: string): Promise<void> {
    // Prefix bot messages with assistant name so users know who's speaking.
    // On a shared number, prefix is also needed in DMs (including self-chat)
    // to distinguish bot output from user messages.
    // Skip only when the assistant has its own dedicated phone number.
    const prefixed = ASSISTANT_HAS_OWN_NUMBER
      ? text
      : `${ASSISTANT_NAME}: ${text}`;

    if (!this.connected) {
      this.outgoingQueue.push({ jid, text: prefixed });
      logger.info(
        { jid: maskJid(jid), length: prefixed.length, queueSize: this.outgoingQueue.length },
        'WA disconnected, message queued',
      );
      return;
    }
    try {
      await this.sock.sendMessage(jid, { text: prefixed });
      logger.info({ jid: maskJid(jid), length: prefixed.length }, 'Message sent');
    } catch (err) {
      // If send fails, queue it for retry on reconnect
      this.outgoingQueue.push({ jid, text: prefixed });
      logger.warn(
        { jid: maskJid(jid), err, queueSize: this.outgoingQueue.length },
        'Failed to send, message queued',
      );
    }
  }

  async sendAudio(jid: string, audioBuffer: Buffer, ptt = true): Promise<void> {
    if (!this.sock || !this.connected) {
      logger.warn({ jid: maskJid(jid) }, 'Cannot send audio: not connected');
      return;
    }

    await this.sock.sendMessage(jid, {
      audio: audioBuffer,
      mimetype: 'audio/ogg; codecs=opus',
      ptt, // push-to-talk = true → shows as voice note (not audio file)
    });

    logger.info({ jid: maskJid(jid), size: audioBuffer.length }, 'Sent voice note');
  }

  isConnected(): boolean {
    return this.connected;
  }

  ownsJid(jid: string): boolean {
    return jid.endsWith('@g.us') || jid.endsWith('@s.whatsapp.net');
  }

  async disconnect(): Promise<void> {
    this.connected = false;
    this.sock?.end(undefined);
  }

  async setTyping(jid: string, isTyping: boolean): Promise<void> {
    try {
      const status = isTyping ? 'composing' : 'paused';
      logger.debug({ jid, status }, 'Sending presence update');
      await this.sock.sendPresenceUpdate(status, jid);
    } catch (err) {
      logger.debug({ jid, err }, 'Failed to update typing status');
    }
  }

  /**
   * Sync group metadata from WhatsApp.
   * Fetches all participating groups and stores their names in the database.
   * Called on startup, daily, and on-demand via IPC.
   */
  async syncGroupMetadata(force = false): Promise<void> {
    if (!force) {
      const lastSync = getLastGroupSync();
      if (lastSync) {
        const lastSyncTime = new Date(lastSync).getTime();
        if (Date.now() - lastSyncTime < GROUP_SYNC_INTERVAL_MS) {
          logger.debug({ lastSync }, 'Skipping group sync - synced recently');
          return;
        }
      }
    }

    try {
      logger.info('Syncing group metadata from WhatsApp...');
      const groups = await this.sock.groupFetchAllParticipating();

      let count = 0;
      for (const [jid, metadata] of Object.entries(groups)) {
        if (metadata.subject) {
          updateChatName(jid, metadata.subject);
          count++;
        }
      }

      setLastGroupSync();
      logger.info({ count }, 'Group metadata synced');
    } catch (err) {
      logger.error({ err }, 'Failed to sync group metadata');
    }
  }

  private async translateJid(jid: string): Promise<string> {
    if (!jid.endsWith('@lid')) return jid;
    const lidUser = jid.split('@')[0].split(':')[0];

    // Check local cache first
    const cached = this.lidToPhoneMap[lidUser];
    if (cached) {
      logger.debug('Translated LID to phone JID (cached)');
      return cached;
    }

    // Query Baileys' signal repository for the mapping
    try {
      const pn = await this.sock.signalRepository?.lidMapping?.getPNForLID(jid);
      if (pn) {
        const phoneJid = `${pn.split('@')[0].split(':')[0]}@s.whatsapp.net`;
        this.lidToPhoneMap[lidUser] = phoneJid;
        logger.info('Translated LID to phone JID (signalRepository)');
        return phoneJid;
      }
    } catch (err) {
      logger.debug({ err, jid }, 'Failed to resolve LID via signalRepository');
    }

    return jid;
  }

  private async flushOutgoingQueue(): Promise<void> {
    if (this.flushing || this.outgoingQueue.length === 0) return;
    this.flushing = true;
    try {
      logger.info(
        { count: this.outgoingQueue.length },
        'Flushing outgoing message queue',
      );
      while (this.outgoingQueue.length > 0) {
        const item = this.outgoingQueue.shift()!;
        // Send directly — queued items are already prefixed by sendMessage
        await this.sock.sendMessage(item.jid, { text: item.text });
        logger.info(
          { jid: maskJid(item.jid), length: item.text.length },
          'Queued message sent',
        );
      }
    } finally {
      this.flushing = false;
    }
  }
}
