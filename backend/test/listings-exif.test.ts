import { describe, expect, it } from 'vitest';

import {
  MalformedImageError,
  sniffImageType,
  stripImageMetadata,
} from '../src/modules/media/exif.js';
import { GPS_MARKER, jpeg, png, webp } from './helpers/listings.js';

/**
 * §Phase 8: "EXIF stripping on every image".
 *
 * The assertion throughout is **the location bytes are not in the output**.
 * That is deliberately blunter than checking a parsed tag: what a provider
 * risks is their customer's address being served with the photo, and the
 * only thing that makes that safe is the bytes being gone. A test that
 * inspected a decoded Exif structure could pass while the original segment
 * sat untouched further down the file.
 *
 * No database, so these run everywhere.
 */
describe('image metadata stripping', () => {
  describe('the type is read from the bytes, not from what the client said', () => {
    it('identifies the three accepted types and nothing else', () => {
      expect(sniffImageType(jpeg())).toBe('image/jpeg');
      expect(sniffImageType(png())).toBe('image/png');
      expect(sniffImageType(webp())).toBe('image/webp');

      expect(sniffImageType(Buffer.from('%PDF-1.7\n%âãÏÓ', 'latin1'))).toBeNull();
      expect(sniffImageType(Buffer.from('GIF89a', 'latin1'))).toBeNull();
      expect(sniffImageType(Buffer.from([0xff, 0xd8]))).toBeNull(); // truncated JPEG
      expect(sniffImageType(Buffer.alloc(0))).toBeNull();
    });

    it('does not mistake a RIFF container that is not WEBP', () => {
      const wav = Buffer.alloc(16);
      wav.write('RIFF', 0, 'latin1');
      wav.write('WAVE', 8, 'latin1');
      expect(sniffImageType(wav)).toBeNull();
    });
  });

  describe('JPEG', () => {
    it('drops Exif, XMP and the comment, and keeps the image', () => {
      const original = jpeg({ withExif: true });
      expect(original.includes(GPS_MARKER)).toBe(true);

      const stripped = stripImageMetadata(original, 'image/jpeg');

      expect(stripped.includes(GPS_MARKER)).toBe(false);
      expect(stripped.length).toBeLessThan(original.length);
      // Still a JPEG: SOI, EOI, and the scan's own bytes survive untouched.
      expect(sniffImageType(stripped)).toBe('image/jpeg');
      expect(stripped.subarray(-2)).toEqual(Buffer.from([0xff, 0xd9]));
      expect(stripped.includes(Buffer.from([0x00, 0x01, 0x02, 0x03]))).toBe(true);
    });

    it('keeps JFIF and the frame headers — colour and geometry are not metadata', () => {
      const stripped = stripImageMetadata(jpeg({ withExif: true }), 'image/jpeg');
      expect(stripped.includes(Buffer.from('JFIF\0', 'latin1'))).toBe(true);
      // SOF0 and SOS still present: dropping either would leave a file no
      // decoder can open, which is a different failure from a stripped one.
      expect(hasMarker(stripped, 0xc0)).toBe(true);
      expect(hasMarker(stripped, 0xda)).toBe(true);
      expect(hasMarker(stripped, 0xe1)).toBe(false);
      expect(hasMarker(stripped, 0xfe)).toBe(false);
    });

    it('is a no-op on a file that carries no metadata', () => {
      const clean = jpeg({ withExif: false });
      expect(stripImageMetadata(clean, 'image/jpeg')).toEqual(clean);
    });

    it('refuses a truncated file rather than passing it through', () => {
      // An image whose container cannot be walked is one whose metadata
      // cannot be shown to be gone. Storing it would make the guarantee false
      // without saying so, so the strip throws and the upload is refused.
      const truncated = jpeg({ withExif: true }).subarray(0, 12);
      expect(() => stripImageMetadata(truncated, 'image/jpeg')).toThrow(MalformedImageError);
      expect(() => stripImageMetadata(Buffer.from('not a jpeg'), 'image/jpeg')).toThrow(
        MalformedImageError,
      );
    });
  });

  describe('PNG', () => {
    it('drops eXIf and tEXt and keeps the pixels', () => {
      const original = png({ withExif: true });
      expect(original.includes(GPS_MARKER)).toBe(true);

      const stripped = stripImageMetadata(original, 'image/png');

      expect(stripped.includes(GPS_MARKER)).toBe(false);
      expect(sniffImageType(stripped)).toBe('image/png');
      expect(stripped.includes(Buffer.from('IHDR', 'latin1'))).toBe(true);
      expect(stripped.includes(Buffer.from('IDAT', 'latin1'))).toBe(true);
      expect(stripped.includes(Buffer.from('IEND', 'latin1'))).toBe(true);
      expect(stripped.includes(Buffer.from('eXIf', 'latin1'))).toBe(false);
      expect(stripped.includes(Buffer.from('tEXt', 'latin1'))).toBe(false);
    });

    it('refuses a PNG with no IEND', () => {
      const complete = png({ withExif: true });
      expect(() => stripImageMetadata(complete.subarray(0, 40), 'image/png')).toThrow(
        MalformedImageError,
      );
    });
  });

  describe('WEBP', () => {
    it('drops the EXIF and XMP chunks and clears the flags that declared them', () => {
      const original = webp({ withExif: true });
      expect(original.includes(GPS_MARKER)).toBe(true);

      const stripped = stripImageMetadata(original, 'image/webp');

      expect(stripped.includes(GPS_MARKER)).toBe(false);
      expect(sniffImageType(stripped)).toBe('image/webp');
      expect(stripped.includes(Buffer.from('EXIF', 'latin1'))).toBe(false);
      expect(stripped.includes(Buffer.from('XMP ', 'latin1'))).toBe(false);
      // The image chunk survives.
      expect(stripped.includes(Buffer.from('VP8 ', 'latin1'))).toBe(true);

      // The VP8X flags no longer advertise chunks that are gone. A decoder
      // that trusts the flag and cannot find the chunk may treat the whole
      // file as corrupt, so dropping without clearing produces an image some
      // readers refuse — a subtler failure than not stripping at all.
      const vp8xAt = stripped.indexOf(Buffer.from('VP8X', 'latin1'));
      expect(vp8xAt).toBeGreaterThan(0);
      expect(stripped.readUInt8(vp8xAt + 8) & 0x0c).toBe(0);
    });

    it('rewrites the RIFF size to match what is left', () => {
      const stripped = stripImageMetadata(webp({ withExif: true }), 'image/webp');
      // A stale size is the other way a stripped WEBP becomes unreadable:
      // the header would claim bytes that are no longer there.
      expect(stripped.readUInt32LE(4)).toBe(stripped.length - 8);
    });
  });
});

/** Whether a JPEG carries a segment with this marker, walking the same way the stripper does. */
function hasMarker(bytes: Buffer, marker: number): boolean {
  let i = 2;
  while (i + 4 <= bytes.length) {
    if (bytes[i] !== 0xff) return false;
    const found = bytes[i + 1];
    if (found === marker) return true;
    if (found === 0xda || found === 0xd9) return false;
    i += 2 + bytes.readUInt16BE(i + 2);
  }
  return false;
}
