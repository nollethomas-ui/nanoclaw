import { describe, it, expect, vi, beforeAll, afterAll } from 'vitest';
import { ElevenLabsTTS } from '../src/tts/elevenlabs.js';

// Mock global fetch
const mockFetch = vi.fn();

describe('ElevenLabsTTS', () => {
  beforeAll(() => {
    vi.stubGlobal('fetch', mockFetch);
  });

  afterAll(() => {
    vi.unstubAllGlobals();
  });

  it('should synthesize text via ElevenLabs API', async () => {
    const fakeAudio = new ArrayBuffer(100);
    mockFetch.mockResolvedValueOnce({
      ok: true,
      arrayBuffer: () => Promise.resolve(fakeAudio),
    });

    const tts = new ElevenLabsTTS('test-key', 'voice-123');
    const result = await tts.synthesize('Hallo Welt');

    expect(result.format).toBe('mp3');
    expect(result.audioBuffer.length).toBe(100);
    expect(mockFetch).toHaveBeenCalledWith(
      'https://api.elevenlabs.io/v1/text-to-speech/voice-123',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({ 'xi-api-key': 'test-key' }),
      })
    );
  });

  it('should throw on API error', async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 401,
      text: () => Promise.resolve('Unauthorized'),
    });

    const tts = new ElevenLabsTTS('bad-key', 'voice-123');
    await expect(tts.synthesize('Test')).rejects.toThrow('ElevenLabs TTS failed (401)');
  });
});
