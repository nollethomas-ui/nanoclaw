import pino from 'pino';
import type { TTSProvider, TTSResult } from '../types.js';

const logger = pino({ name: 'elevenlabs-tts' });

const ELEVENLABS_API_BASE = 'https://api.elevenlabs.io/v1';

export class ElevenLabsTTS implements TTSProvider {
  private apiKey: string;
  private voiceId: string;
  private modelId: string;

  constructor(apiKey: string, voiceId: string, modelId = 'eleven_multilingual_v2') {
    this.apiKey = apiKey;
    this.voiceId = voiceId;
    this.modelId = modelId;
  }

  async synthesize(text: string): Promise<TTSResult> {
    const startTime = Date.now();

    logger.info(
      { length: text.length, voiceId: this.voiceId },
      'Synthesizing speech via ElevenLabs'
    );

    const response = await fetch(
      `${ELEVENLABS_API_BASE}/text-to-speech/${this.voiceId}`,
      {
        method: 'POST',
        headers: {
          'xi-api-key': this.apiKey,
          'Content-Type': 'application/json',
          Accept: 'audio/mpeg',
        },
        body: JSON.stringify({
          text,
          model_id: this.modelId,
          voice_settings: {
            stability: 0.5,
            similarity_boost: 0.75,
            style: 0.0,
            use_speaker_boost: true,
          },
        }),
      }
    );

    if (!response.ok) {
      const errorBody = await response.text();
      throw new Error(`ElevenLabs TTS failed (${response.status}): ${errorBody}`);
    }

    const arrayBuffer = await response.arrayBuffer();
    const audioBuffer = Buffer.from(arrayBuffer);
    const durationMs = Date.now() - startTime;

    logger.info(
      { outputSize: audioBuffer.length, processingMs: durationMs },
      'ElevenLabs TTS synthesis complete'
    );

    return {
      audioBuffer,
      format: 'mp3',
    };
  }
}
