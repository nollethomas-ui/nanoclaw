/**
 * New file: src/voice-response.ts
 * Handles TTS synthesis and sending audio responses back to the user.
 * Supports Google Cloud TTS (default) and ElevenLabs (configurable via TTS_PROVIDER env var).
 * Parses <voice> tags for smart voice summaries (short TTS + full text).
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

const VOICE_TAG_REGEX = /<voice>([\s\S]*?)<\/voice>/;

/**
 * Synthesize text to OGG/Opus audio.
 * Uses ElevenLabs if TTS_PROVIDER=elevenlabs, otherwise Google Cloud TTS.
 * Falls back to Google if ElevenLabs fails.
 */
export async function synthesizeSpeech(text: string): Promise<Buffer> {
  const env = readEnvFile([
    'TTS_PROVIDER',
    'GOOGLE_TTS_VOICE',
    'GOOGLE_TTS_SPEAKING_RATE',
    'ELEVENLABS_API_KEY',
    'ELEVENLABS_VOICE_ID',
  ]);

  // Truncate long texts (API limits)
  if (text.length > 5000) {
    text = text.slice(0, 4990) + '...';
  }

  if (env.TTS_PROVIDER === 'elevenlabs' && env.ELEVENLABS_API_KEY) {
    try {
      return await synthesizeElevenLabs(
        text,
        env.ELEVENLABS_API_KEY,
        env.ELEVENLABS_VOICE_ID || '',
      );
    } catch (err) {
      logger.warn({ err }, 'ElevenLabs TTS failed, falling back to Google TTS');
      return synthesizeGoogle(text, env);
    }
  }

  return synthesizeGoogle(text, env);
}

async function synthesizeElevenLabs(
  text: string,
  apiKey: string,
  voiceId: string,
): Promise<Buffer> {
  const startTime = Date.now();

  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
      method: 'POST',
      headers: {
        'xi-api-key': apiKey,
        'Content-Type': 'application/json',
        Accept: 'audio/ogg',
      },
      body: JSON.stringify({
        text,
        model_id: 'eleven_multilingual_v2',
        output_format: 'ogg_opus',
        voice_settings: {
          stability: 0.5,
          similarity_boost: 0.75,
          use_speaker_boost: true,
        },
      }),
    },
  );

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`ElevenLabs TTS failed (${response.status}): ${errorBody}`);
  }

  const audioBuffer = Buffer.from(await response.arrayBuffer());
  const durationMs = Date.now() - startTime;

  logger.info(
    { outputSize: audioBuffer.length, processingMs: durationMs },
    'ElevenLabs TTS synthesis complete',
  );

  return audioBuffer;
}

async function synthesizeGoogle(
  text: string,
  env: Record<string, string>,
): Promise<Buffer> {
  const voice = env.GOOGLE_TTS_VOICE || 'de-DE-Standard-B';
  const speakingRate = parseFloat(env.GOOGLE_TTS_SPEAKING_RATE || '1.0');

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
 * For voice-originated messages: parse <voice> tags for smart response.
 * - Text message: full response without <voice> tags
 * - Voice note: only the <voice> summary (or full text as fallback)
 */
export async function synthesizeAndSend(
  channel: Channel,
  jid: string,
  text: string,
  isVoiceMessage: boolean,
): Promise<void> {
  // Parse <voice> tag if present
  const voiceMatch = text.match(VOICE_TAG_REGEX);
  const voiceSummary = voiceMatch ? voiceMatch[1].trim() : null;

  // Text message: full response without <voice> tags
  const textForChat = text.replace(VOICE_TAG_REGEX, '').trim();

  if (textForChat) {
    await channel.sendMessage(jid, textForChat);
  }

  // Voice note: only summary (or full text as fallback)
  if (isVoiceMessage && channel.sendAudio) {
    try {
      const ttsText = voiceSummary || textForChat;
      const audioBuffer = await synthesizeSpeech(ttsText);
      await channel.sendAudio(jid, audioBuffer, true);
      logger.info(
        { textLength: ttsText.length, usedVoiceTag: !!voiceSummary },
        'Sent TTS voice response',
      );
    } catch (err) {
      logger.error({ err }, 'TTS failed, text-only response sent');
    }
  }
}
