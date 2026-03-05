import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { writeFile, readFile, unlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import pino from 'pino';

const execFileAsync = promisify(execFile);
const logger = pino({ name: 'audio-converter' });

export class AudioConverter {
  /**
   * Convert MP3 buffer to OGG/Opus (needed when ElevenLabs output → WhatsApp/Telegram).
   * Requires ffmpeg installed on the system.
   */
  static async mp3ToOggOpus(mp3Buffer: Buffer): Promise<Buffer> {
    const id = randomUUID().slice(0, 8);
    const inputPath = join(tmpdir(), `nanoclaw-${id}.mp3`);
    const outputPath = join(tmpdir(), `nanoclaw-${id}.ogg`);

    try {
      await writeFile(inputPath, mp3Buffer);

      await execFileAsync('ffmpeg', [
        '-i', inputPath,
        '-c:a', 'libopus',
        '-b:a', '64k',
        '-ar', '48000',
        '-ac', '1',
        '-application', 'voip',
        '-y',
        outputPath,
      ]);

      const oggBuffer = await readFile(outputPath);
      logger.info(
        { inputSize: mp3Buffer.length, outputSize: oggBuffer.length },
        'Converted MP3 → OGG/Opus'
      );
      return oggBuffer;
    } finally {
      await unlink(inputPath).catch(() => {});
      await unlink(outputPath).catch(() => {});
    }
  }

  /**
   * Check if ffmpeg is available on the system.
   */
  static async isFFmpegAvailable(): Promise<boolean> {
    try {
      await execFileAsync('ffmpeg', ['-version']);
      return true;
    } catch {
      return false;
    }
  }
}
