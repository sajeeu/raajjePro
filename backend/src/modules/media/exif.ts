/**
 * Metadata stripping for uploaded images (§Phase 8: "EXIF stripping on every
 * image").
 *
 * ## Why this exists and what it removes
 *
 * A photo taken on a phone carries the GPS coordinates it was taken at, the
 * device, and the timestamp. A provider photographing their own work
 * photographs their customer's home, and a listing image is served to
 * everybody. Stripping is therefore not a nicety — it is the difference
 * between publishing a picture of a bathroom and publishing the address of
 * the bathroom.
 *
 * ## Why it is a container rewrite rather than a re-encode
 *
 * Decoding and re-encoding the pixels would also drop the metadata, and would
 * need a native image library. It would also recompress every image the
 * provider uploaded, which is a visible quality loss applied to the one thing
 * §Phase 8 says most affects bookings. Walking the container and dropping the
 * metadata segments removes exactly what must go and leaves the compressed
 * image data byte-identical.
 *
 * ## What is kept, deliberately
 *
 * Colour management, not metadata: JPEG's APP0 (JFIF), APP2 (ICC profile) and
 * APP14 (Adobe colour transform), and PNG's `gAMA` / `cHRM` / `iCCP` / `sRGB`.
 * Dropping those shifts the colours of the image rather than protecting
 * anybody. Everything that can carry a location, a device, a name or a
 * free-text comment goes.
 */

/** The three types §Phase 8's upload control offers ("JPG, PNG or WEBP"). */
export type ImageContentType = 'image/jpeg' | 'image/png' | 'image/webp';

export const ACCEPTED_IMAGE_TYPES: readonly ImageContentType[] = [
  'image/jpeg',
  'image/png',
  'image/webp',
];

/**
 * The type these bytes actually are, from their magic number — not from the
 * `Content-Type` the client claimed.
 *
 * A declared content type is a client assertion and this is the check that
 * makes the server-side half of §Phase 8's "server-side content-type and size
 * validation" mean anything: an upload declaring `image/png` and carrying a
 * PDF is caught here, whatever the header said.
 *
 * Returns null for anything not one of the three accepted types, including a
 * truncated file too short to identify.
 */
export function sniffImageType(bytes: Buffer): ImageContentType | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 && bytes.subarray(0, 8).equals(PNG_SIGNATURE)) {
    return 'image/png';
  }
  if (
    bytes.length >= 12 &&
    bytes.subarray(0, 4).toString('latin1') === 'RIFF' &&
    bytes.subarray(8, 12).toString('latin1') === 'WEBP'
  ) {
    return 'image/webp';
  }
  return null;
}

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/**
 * Returns [bytes] with every metadata segment removed.
 *
 * Throws `MalformedImageError` on a container it cannot walk. That is the
 * right answer rather than passing the bytes through: an image whose
 * structure is not understood is an image whose metadata cannot be shown to
 * have been removed, and storing it would make this function's guarantee
 * false without saying so.
 */
export function stripImageMetadata(bytes: Buffer, type: ImageContentType): Buffer {
  switch (type) {
    case 'image/jpeg':
      return stripJpeg(bytes);
    case 'image/png':
      return stripPng(bytes);
    case 'image/webp':
      return stripWebp(bytes);
  }
}

export class MalformedImageError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'MalformedImageError';
  }
}

// ---------------------------------------------------------------------------
// JPEG
// ---------------------------------------------------------------------------

/**
 * The application segments that carry metadata rather than decoding
 * information.
 *
 * `APP1` is the one that matters most — it holds both Exif (with GPS) and
 * XMP, and a phone writes at least one of them on every photo. `APP13` is
 * Photoshop's IRB, which carries IPTC captions and credits. `COM` is a free
 * text comment.
 *
 * Every other `APPn` is dropped too, except the three colour-management ones
 * listed in `JPEG_KEEP`: an unknown application segment is by definition one
 * whose contents cannot be shown to be safe.
 */
const JPEG_KEEP = new Set([
  0xe0, // APP0  — JFIF density; dropping it can change how the image scales
  0xe2, // APP2  — ICC colour profile
  0xee, // APP14 — Adobe colour transform; without it YCCK/CMYK decodes wrong
]);

function stripJpeg(bytes: Buffer): Buffer {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) {
    throw new MalformedImageError('not a JPEG: no SOI marker');
  }
  const out: Buffer[] = [bytes.subarray(0, 2)];
  let i = 2;

  while (i < bytes.length) {
    if (bytes[i] !== 0xff) {
      throw new MalformedImageError(`JPEG segment does not start with 0xFF at ${String(i)}`);
    }
    // Fill bytes: a run of 0xFF before a marker is legal padding.
    let markerAt = i;
    while (markerAt < bytes.length && bytes[markerAt] === 0xff) markerAt++;
    if (markerAt >= bytes.length) {
      throw new MalformedImageError('JPEG ends inside a marker');
    }
    const marker = bytes[markerAt];
    if (marker === undefined) throw new MalformedImageError('JPEG ends inside a marker');

    // Standalone markers carry no length: EOI, and the RSTn / TEM set.
    if (marker === 0xd9) {
      out.push(bytes.subarray(i));
      return Buffer.concat(out);
    }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      out.push(bytes.subarray(i, markerAt + 1));
      i = markerAt + 1;
      continue;
    }

    if (markerAt + 3 > bytes.length) {
      throw new MalformedImageError('JPEG ends inside a segment length');
    }
    const length = bytes.readUInt16BE(markerAt + 1);
    if (length < 2) {
      throw new MalformedImageError(`JPEG segment length ${String(length)} is impossible`);
    }
    const end = markerAt + 1 + length;
    if (end > bytes.length) {
      throw new MalformedImageError('JPEG segment runs past the end of the file');
    }

    // SOS: the entropy-coded scan follows and is not segment-structured.
    // Everything from here to the end is image data and is copied verbatim.
    if (marker === 0xda) {
      out.push(bytes.subarray(i));
      return Buffer.concat(out);
    }

    const isApp = marker >= 0xe0 && marker <= 0xef;
    const isComment = marker === 0xfe;
    const drop = (isApp && !JPEG_KEEP.has(marker)) || isComment;
    if (!drop) out.push(bytes.subarray(i, end));
    i = end;
  }

  // No SOS and no EOI. Every real JPEG has both; a file that runs out first
  // is truncated, and a truncated file is not one whose metadata we can claim
  // to have removed.
  throw new MalformedImageError('JPEG ended without a scan');
}

// ---------------------------------------------------------------------------
// PNG
// ---------------------------------------------------------------------------

/**
 * The PNG chunks that carry metadata. `eXIf` is a literal Exif block —
 * including GPS — and the three text chunks carry anything at all, which is
 * where phone software and editors write author, software and comment.
 * `tIME` is the last-modified timestamp.
 */
const PNG_DROP = new Set(['eXIf', 'tEXt', 'zTXt', 'iTXt', 'tIME']);

function stripPng(bytes: Buffer): Buffer {
  if (bytes.length < 8 || !bytes.subarray(0, 8).equals(PNG_SIGNATURE)) {
    throw new MalformedImageError('not a PNG: bad signature');
  }
  const out: Buffer[] = [bytes.subarray(0, 8)];
  let i = 8;
  let sawEnd = false;

  while (i + 8 <= bytes.length) {
    const length = bytes.readUInt32BE(i);
    const type = bytes.subarray(i + 4, i + 8).toString('latin1');
    const end = i + 12 + length; // length + type + data + CRC
    if (end > bytes.length) {
      throw new MalformedImageError('PNG chunk runs past the end of the file');
    }
    if (!PNG_DROP.has(type)) out.push(bytes.subarray(i, end));
    i = end;
    if (type === 'IEND') {
      sawEnd = true;
      break;
    }
  }
  if (!sawEnd) throw new MalformedImageError('PNG ended without IEND');
  return Buffer.concat(out);
}

// ---------------------------------------------------------------------------
// WEBP
// ---------------------------------------------------------------------------

/**
 * Bits in the `VP8X` flags byte. Clearing them is not cosmetic: a decoder
 * that reads the flag and then cannot find the chunk is entitled to treat the
 * file as corrupt, so dropping the chunks without clearing the flags produces
 * an image some readers refuse.
 */
const VP8X_EXIF_FLAG = 0x08;
const VP8X_XMP_FLAG = 0x04;

function stripWebp(bytes: Buffer): Buffer {
  if (bytes.length < 12) throw new MalformedImageError('not a WEBP: too short');
  if (bytes.subarray(0, 4).toString('latin1') !== 'RIFF') {
    throw new MalformedImageError('not a WEBP: no RIFF header');
  }
  if (bytes.subarray(8, 12).toString('latin1') !== 'WEBP') {
    throw new MalformedImageError('not a WEBP: RIFF form is not WEBP');
  }

  const chunks: Buffer[] = [];
  let i = 12;
  while (i + 8 <= bytes.length) {
    const fourcc = bytes.subarray(i, i + 4).toString('latin1');
    const size = bytes.readUInt32LE(i + 4);
    // RIFF pads every chunk to an even length; the pad byte is not counted.
    const padded = size + (size % 2);
    const end = i + 8 + padded;
    if (end > bytes.length) {
      throw new MalformedImageError('WEBP chunk runs past the end of the file');
    }
    if (fourcc !== 'EXIF' && fourcc !== 'XMP ') {
      const chunk = Buffer.from(bytes.subarray(i, end));
      // Byte 8 is the flags byte (4 fourcc + 4 size).
      const flags = fourcc === 'VP8X' && size >= 1 ? chunk[8] : undefined;
      if (flags !== undefined) {
        chunk[8] = flags & ~(VP8X_EXIF_FLAG | VP8X_XMP_FLAG);
      }
      chunks.push(chunk);
    }
    i = end;
  }
  if (chunks.length === 0) throw new MalformedImageError('WEBP carries no chunks');

  const body = Buffer.concat(chunks);
  const header = Buffer.alloc(12);
  header.write('RIFF', 0, 'latin1');
  // The RIFF size counts everything after this field — the 'WEBP' fourcc plus
  // the chunks. Leaving the original size behind after dropping a chunk is
  // what makes a stripped file unreadable.
  header.writeUInt32LE(4 + body.length, 4);
  header.write('WEBP', 8, 'latin1');
  return Buffer.concat([header, body]);
}
