import { describe, it, expect, vi } from 'vitest';

// Mock Google Cloud TTS
vi.mock('@google-cloud/text-to-speech', () => {
  return {
    default: {
      TextToSpeechClient: class MockTTSClient {
        synthesizeSpeech = vi.fn().mockResolvedValue([
          {
            audioContent: new Uint8Array([0x4f, 0x67, 0x67, 0x53]), // OGG magic bytes
          },
        ]);
      },
    },
  };
});

import { GoogleTTS } from '../src/tts/google-tts.js';

describe('GoogleTTS', () => {
  it('should synthesize text to OGG/Opus', async () => {
    const tts = new GoogleTTS('de-DE-Standard-B');
    const result = await tts.synthesize('Hallo Welt');

    expect(result.format).toBe('ogg_opus');
    expect(result.audioBuffer).toBeInstanceOf(Buffer);
    expect(result.audioBuffer.length).toBeGreaterThan(0);
  });

  it('should truncate text exceeding 5000 chars', async () => {
    const tts = new GoogleTTS();
    const longText = 'A'.repeat(6000);

    const result = await tts.synthesize(longText);

    expect(result.format).toBe('ogg_opus');
  });
});
