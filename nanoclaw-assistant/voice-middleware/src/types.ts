export interface TranscriptionResult {
  text: string;
  language: string;
  duration_seconds: number;
}

export interface TTSResult {
  audioBuffer: Buffer;
  format: 'ogg_opus' | 'mp3' | 'wav';
  durationMs?: number;
}

export interface STTProvider {
  transcribe(audioBuffer: Buffer, mimeType?: string): Promise<TranscriptionResult>;
}

export interface TTSProvider {
  synthesize(text: string): Promise<TTSResult>;
}

export interface VoiceConfig {
  stt: {
    provider: 'groq';
    model: string;
    language: string;
    apiKey: string;
  };
  tts: {
    provider: 'google' | 'elevenlabs';
    google?: {
      voice: string;
      speakingRate?: number;
    };
    elevenlabs?: {
      apiKey: string;
      voiceId: string;
      modelId?: string;
    };
  };
}
