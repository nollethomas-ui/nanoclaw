import Groq from 'groq-sdk';
import pino from 'pino';
import type { STTProvider, TranscriptionResult } from '../types.js';

const logger = pino({ name: 'groq-whisper-stt' });

export class GroqWhisperSTT implements STTProvider {
  private client: Groq;
  private model: string;
  private language: string;

  constructor(apiKey: string, model = 'whisper-large-v3', language = 'de') {
    this.client = new Groq({ apiKey });
    this.model = model;
    this.language = language;
  }

  async transcribe(audioBuffer: Buffer, mimeType = 'audio/ogg'): Promise<TranscriptionResult> {
    const startTime = Date.now();
    const extension = this.getExtension(mimeType);
    const file = new File([new Uint8Array(audioBuffer)], `audio.${extension}`, { type: mimeType });

    logger.info({ size: audioBuffer.length, mimeType }, 'Transcribing audio via Groq Whisper');

    const response = await this.client.audio.transcriptions.create({
      file,
      model: this.model,
      language: this.language,
      response_format: 'verbose_json',
    });

    const durationMs = Date.now() - startTime;
    const text = response.text.trim();
    const audioDuration = (response as unknown as Record<string, unknown>).duration as number ?? 0;

    logger.info(
      { text: text.slice(0, 80), audioDuration, processingMs: durationMs },
      'Transcription complete'
    );

    return {
      text,
      language: this.language,
      duration_seconds: audioDuration,
    };
  }

  private getExtension(mimeType: string): string {
    const map: Record<string, string> = {
      'audio/ogg': 'ogg',
      'audio/ogg; codecs=opus': 'ogg',
      'audio/mpeg': 'mp3',
      'audio/wav': 'wav',
      'audio/webm': 'webm',
      'audio/mp4': 'mp4',
    };
    return map[mimeType] ?? 'ogg';
  }
}
