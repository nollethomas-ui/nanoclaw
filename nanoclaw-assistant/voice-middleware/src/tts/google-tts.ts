import { TextToSpeechClient } from '@google-cloud/text-to-speech';
import pino from 'pino';
import type { TTSProvider, TTSResult } from '../types.js';

const logger = pino({ name: 'google-tts' });

export class GoogleTTS implements TTSProvider {
  private client: TextToSpeechClient;
  private voice: string;
  private speakingRate: number;

  constructor(voice = 'de-DE-Standard-B', speakingRate = 1.0) {
    this.client = new TextToSpeechClient();
    this.voice = voice;
    this.speakingRate = speakingRate;
  }

  async synthesize(text: string): Promise<TTSResult> {
    const startTime = Date.now();

    // Google TTS has a 5000 character limit per request
    if (text.length > 5000) {
      logger.warn({ length: text.length }, 'Text exceeds 5000 chars, truncating');
      text = text.slice(0, 4990) + '...';
    }

    logger.info({ length: text.length, voice: this.voice }, 'Synthesizing speech via Google TTS');

    const [response] = await this.client.synthesizeSpeech({
      input: { text },
      voice: {
        languageCode: this.voice.split('-').slice(0, 2).join('-'), // e.g. "de-DE"
        name: this.voice,
      },
      audioConfig: {
        audioEncoding: 'OGG_OPUS' as const,
        speakingRate: this.speakingRate,
        sampleRateHertz: 24000,
      },
    });

    const audioBuffer = Buffer.from(response.audioContent as Uint8Array);
    const durationMs = Date.now() - startTime;

    logger.info(
      { outputSize: audioBuffer.length, processingMs: durationMs },
      'TTS synthesis complete'
    );

    return {
      audioBuffer,
      format: 'ogg_opus',
    };
  }
}
