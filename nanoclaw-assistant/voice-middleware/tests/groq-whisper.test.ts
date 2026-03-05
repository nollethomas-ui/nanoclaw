import { describe, it, expect, vi } from 'vitest';

// Mock Groq SDK
vi.mock('groq-sdk', () => {
  return {
    default: class MockGroq {
      audio = {
        transcriptions: {
          create: vi.fn().mockResolvedValue({
            text: 'Hallo, wie geht es dir?',
            duration: 3.5,
          }),
        },
      };
    },
  };
});

import { GroqWhisperSTT } from '../src/stt/groq-whisper.js';

describe('GroqWhisperSTT', () => {
  it('should transcribe audio buffer', async () => {
    const stt = new GroqWhisperSTT('test-api-key');
    const fakeAudio = Buffer.from('fake-audio-data');

    const result = await stt.transcribe(fakeAudio, 'audio/ogg');

    expect(result.text).toBe('Hallo, wie geht es dir?');
    expect(result.language).toBe('de');
    expect(result.duration_seconds).toBe(3.5);
  });

  it('should handle different mime types', async () => {
    const stt = new GroqWhisperSTT('test-api-key', 'whisper-large-v3', 'de');
    const fakeAudio = Buffer.from('fake-mp3-data');

    const result = await stt.transcribe(fakeAudio, 'audio/mpeg');

    expect(result.text).toBe('Hallo, wie geht es dir?');
  });
});
