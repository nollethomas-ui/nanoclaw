/**
 * Replacement for NanoClaw's src/transcription.ts
 * Swaps OpenAI Whisper for Groq Whisper (free tier: 28,800 sec/day)
 *
 * Apply: Copy this file to nanoclaw/src/transcription.ts (replacing the original)
 */

import Groq from 'groq-sdk';
import { readEnvFile } from './env.js';
import pino from 'pino';

const logger = pino({ name: 'transcription' });

let groqClient: Groq | null = null;

function getGroqClient(): Groq {
  if (!groqClient) {
    const env = readEnvFile(['GROQ_API_KEY']);
    const apiKey = env.GROQ_API_KEY;
    if (!apiKey) {
      throw new Error('GROQ_API_KEY not found in .env file');
    }
    groqClient = new Groq({ apiKey });
  }
  return groqClient;
}

export async function transcribeAudio(audioBuffer: Buffer, mimeType = 'audio/ogg'): Promise<string> {
  const client = getGroqClient();
  const extension = mimeType.includes('ogg') ? 'ogg' : mimeType.includes('mp4') ? 'mp4' : 'ogg';
  const file = new File([audioBuffer], `voice.${extension}`, { type: mimeType });

  logger.info({ size: audioBuffer.length, mimeType }, 'Transcribing via Groq Whisper');

  const response = await client.audio.transcriptions.create({
    file,
    model: 'whisper-large-v3',
    language: 'de',
    response_format: 'text',
  });

  // Groq SDK types say Transcription object, but response_format: 'text' returns a string at runtime
  const raw = response as unknown;
  const text = (typeof raw === 'string' ? raw : (raw as { text: string }).text).trim();

  // H3: Log only length, not content
  logger.info({ length: text.length }, 'Transcription complete');
  return text;
}
