/**
 * New file: src/voice-response.ts
 * Handles TTS synthesis and sending audio responses back to the user.
 *
 * Apply: Add this file to nanoclaw/src/voice-response.ts
 */

import textToSpeech from '@google-cloud/text-to-speech';
import pino from 'pino';
import { readEnvFile } from './env.js';
import type { Channel } from './types.js';

const logger = pino({ name: 'voice-response' });

let ttsClient: textToSpeech.TextToSpeechClient | null = null;

function getTTSClient(): textToSpeech.TextToSpeechClient {
  if (!ttsClient) {
    ttsClient = new textToSpeech.TextToSpeechClient();
  }
  return ttsClient;
}

/**
 * Synthesize text to OGG/Opus audio using Google Cloud TTS.
 */
export async function synthesizeSpeech(text: string): Promise<Buffer> {
  const env = readEnvFile();
  const voice = env.GOOGLE_TTS_VOICE || 'de-DE-Standard-B';
  const speakingRate = parseFloat(env.GOOGLE_TTS_SPEAKING_RATE || '1.0');

  // Truncate long texts (Google TTS limit: 5000 chars)
  if (text.length > 5000) {
    text = text.slice(0, 4990) + '...';
  }

  const client = getTTSClient();
  const [response] = await client.synthesizeSpeech({
    input: { text },
    voice: {
      languageCode: voice.split('-').slice(0, 2).join('-'),
      name: voice,
    },
    audioConfig: {
      audioEncoding: 'OGG_OPUS',
      speakingRate,
      sampleRateHertz: 24000,
    },
  });

  return Buffer.from(response.audioContent as Uint8Array);
}

/**
 * For voice-originated messages: synthesize the agent response and send as audio.
 * Falls back to text if TTS fails.
 */
export async function synthesizeAndSend(
  channel: Channel,
  jid: string,
  text: string,
  isVoiceMessage: boolean,
): Promise<void> {
  // Always send text response
  await channel.sendMessage(jid, text);

  // Additionally send voice note for voice-originated messages
  if (isVoiceMessage && channel.sendAudio) {
    try {
      const audioBuffer = await synthesizeSpeech(text);
      await channel.sendAudio(jid, audioBuffer, true);
      logger.info({ jid, textLength: text.length }, 'Sent TTS voice response');
    } catch (err) {
      logger.error({ err, jid }, 'TTS failed, text-only response sent');
    }
  }
}
