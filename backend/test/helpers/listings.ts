import { randomUUID } from 'node:crypto';
import { deflateSync } from 'node:zlib';

import type { FastifyInstance } from 'fastify';

import type { PrismaClient } from '../../src/generated/prisma/client.js';
import { seedCategories } from '../../src/modules/categories/seed.js';
import type { OwnListingDto } from '../../src/modules/listings/types.js';
import { freshIp } from './app.js';
import { ensureIslandsSeeded, islandByName } from './islands.js';

interface Envelope<T> {
  data: T;
}

/** The category catalogue, seeded once per process — the same shape `ensureIslandsSeeded` takes. */
let categoriesSeeded: Promise<unknown> | null = null;
export function ensureCategoriesSeeded(prisma: PrismaClient): Promise<unknown> {
  categoriesSeeded ??= seedCategories(prisma);
  return categoriesSeeded;
}

/** A seeded category by name. Tests name it because §1c's rules differ per category. */
export async function categoryByName(prisma: PrismaClient, name: string) {
  const row = await prisma.category.findUnique({ where: { seedKey: name } });
  if (row === null) throw new Error(`${name} is not seeded`);
  return row;
}

export const BASE = '/v1/providers/me/listings';

/**
 * The path-plus-query half of an absolute upload URL, which is what
 * `app.inject` takes. The token is in the query string, exactly as a real
 * presigned URL's signature is.
 */
export function uploadPathOf(url: string): string {
  const parsed = new URL(url);
  return `${parsed.pathname}${parsed.search}`;
}

export async function createDraft(
  app: FastifyInstance,
  headers: Record<string, string>,
  body: Record<string, unknown> = {},
): Promise<OwnListingDto> {
  const res = await app.inject({
    method: 'POST',
    url: BASE,
    headers: { ...headers, 'idempotency-key': randomUUID() },
    remoteAddress: freshIp(),
    payload: body,
  });
  if (res.statusCode !== 201) throw new Error(`createDraft: ${String(res.statusCode)} ${res.body}`);
  return res.json<Envelope<OwnListingDto>>().data;
}

export function patchDraft(
  app: FastifyInstance,
  headers: Record<string, string>,
  id: string,
  body: Record<string, unknown>,
) {
  return app.inject({
    method: 'PATCH',
    url: `${BASE}/${id}`,
    headers,
    remoteAddress: freshIp(),
    payload: body,
  });
}

export function publish(app: FastifyInstance, headers: Record<string, string>, id: string) {
  return app.inject({
    method: 'POST',
    url: `${BASE}/${id}/publish`,
    headers: { ...headers, 'idempotency-key': randomUUID() },
    remoteAddress: freshIp(),
  });
}

/**
 * The whole three-step upload, as a client performs it: ask for a target, PUT
 * the bytes to the URL the server handed back, then finalise.
 *
 * It goes through the real HTTP routes rather than calling the service,
 * because the point of the presigned shape is that the client never touches
 * an object key — a helper that shortcut that would test a flow nobody uses.
 */
export async function uploadImage(
  app: FastifyInstance,
  headers: Record<string, string>,
  listingId: string,
  bytes: Buffer = jpeg({ withExif: true }),
  contentType = 'image/jpeg',
): Promise<{ id: string; url: string | null }> {
  const created = await app.inject({
    method: 'POST',
    url: `${BASE}/${listingId}/media`,
    headers: { ...headers, 'idempotency-key': randomUUID() },
    remoteAddress: freshIp(),
    payload: { contentType },
  });
  if (created.statusCode !== 201) {
    throw new Error(`media create: ${String(created.statusCode)} ${created.body}`);
  }
  const body =
    created.json<
      Envelope<{ media: { id: string }; upload: { url: string; headers: Record<string, string> } }>
    >().data;

  const put = await app.inject({
    method: 'PUT',
    url: uploadPathOf(body.upload.url),
    headers: body.upload.headers,
    remoteAddress: freshIp(),
    payload: bytes,
  });
  if (put.statusCode !== 204) throw new Error(`media put: ${String(put.statusCode)} ${put.body}`);

  const done = await app.inject({
    method: 'POST',
    url: `${BASE}/${listingId}/media/${body.media.id}/complete`,
    headers,
    remoteAddress: freshIp(),
  });
  if (done.statusCode !== 200) {
    throw new Error(`media complete: ${String(done.statusCode)} ${done.body}`);
  }
  return done.json<Envelope<{ id: string; url: string | null }>>().data;
}

/**
 * A listing with all six required fields filled, ready to publish.
 *
 * `Cleaning` by default because it is emergency-incapable and
 * callback-ineligible, so a test that does not care about either gets a
 * listing neither rule touches.
 */
export async function completeDraft(
  app: FastifyInstance,
  headers: Record<string, string>,
  options: { categoryName?: string; islandNames?: [string, string][] } = {},
): Promise<OwnListingDto> {
  const prisma = app.deps.prisma;
  await ensureCategoriesSeeded(prisma);
  await ensureIslandsSeeded(prisma);
  const category = await categoryByName(prisma, options.categoryName ?? 'Cleaning');
  const islands = await Promise.all(
    (options.islandNames ?? [['K', "Male'"]]).map(([atoll, name]) =>
      islandByName(prisma, atoll, name),
    ),
  );

  const draft = await createDraft(app, headers, { categoryId: category.id });
  const cover = await uploadImage(app, headers, draft.id);
  const patched = await patchDraft(app, headers, draft.id, {
    name: 'Wiring & Fault Repair',
    shortDescription: 'Fault finding, rewiring and new installations.',
    serviceAreaIslandIds: islands.map((i) => i.id),
    pricingModel: 'fixed',
    priceLaari: 45_000,
    priceUnit: 'visit',
    coverMediaId: cover.id,
  });
  if (patched.statusCode !== 200) {
    throw new Error(`completeDraft patch: ${String(patched.statusCode)} ${patched.body}`);
  }
  return patched.json<Envelope<OwnListingDto>>().data;
}

// ---------------------------------------------------------------------------
// Synthetic images
// ---------------------------------------------------------------------------

/**
 * The GPS coordinates the test images carry, as a recognisable byte string.
 *
 * A real Exif GPS block is a TIFF IFD; what the stripper actually does is
 * drop the whole APP1 segment without parsing it, so what a test needs to
 * prove is that **the bytes are gone from the output**, not that a particular
 * IFD tag was understood. A marker string is a sharper assertion than a
 * synthesised IFD would be: if it survives anywhere in the stripped file, the
 * strip did not happen.
 */
export const GPS_MARKER = Buffer.from('GPSLatitude=4.1755N,GPSLongitude=73.5093E', 'latin1');

/** A minimal but structurally valid JPEG, optionally carrying an Exif APP1 and a comment. */
export function jpeg(options: { withExif?: boolean } = {}): Buffer {
  const parts: Buffer[] = [Buffer.from([0xff, 0xd8])]; // SOI

  // APP0 / JFIF — kept by the stripper (density affects rendering).
  parts.push(segment(0xe0, Buffer.concat([Buffer.from('JFIF\0', 'latin1'), Buffer.alloc(9)])));

  if (options.withExif !== false) {
    // APP1 / Exif, carrying the marker. Dropped.
    parts.push(segment(0xe1, Buffer.concat([Buffer.from('Exif\0\0', 'latin1'), GPS_MARKER])));
    // APP1 / XMP, which is where a phone writes location a second time. Dropped.
    parts.push(
      segment(
        0xe1,
        Buffer.concat([Buffer.from('http://ns.adobe.com/xap/1.0/\0', 'latin1'), GPS_MARKER]),
      ),
    );
    // COM — a free-text comment. Dropped.
    parts.push(segment(0xfe, Buffer.from('taken at home', 'latin1')));
  }

  // A quantisation table and a frame header, so the file is a plausible JPEG
  // rather than a header and a scan.
  parts.push(segment(0xdb, Buffer.concat([Buffer.from([0x00]), Buffer.alloc(64, 0x10)])));
  parts.push(segment(0xc0, Buffer.from([0x08, 0, 8, 0, 8, 1, 1, 0x11, 0])));
  parts.push(segment(0xda, Buffer.from([0x01, 0x01, 0x00, 0x00, 0x3f, 0x00])));
  parts.push(Buffer.from([0x00, 0x01, 0x02, 0x03])); // entropy-coded data
  parts.push(Buffer.from([0xff, 0xd9])); // EOI
  return Buffer.concat(parts);
}

function segment(marker: number, payload: Buffer): Buffer {
  const header = Buffer.alloc(4);
  header[0] = 0xff;
  header[1] = marker;
  header.writeUInt16BE(payload.length + 2, 2);
  return Buffer.concat([header, payload]);
}

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/** A one-pixel PNG, optionally carrying `eXIf` and `tEXt` chunks. */
export function png(options: { withExif?: boolean } = {}): Buffer {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(1, 0);
  ihdr.writeUInt32BE(1, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // truecolour
  const parts: Buffer[] = [PNG_SIGNATURE, pngChunk('IHDR', ihdr)];
  if (options.withExif !== false) {
    parts.push(pngChunk('eXIf', GPS_MARKER));
    parts.push(pngChunk('tEXt', Buffer.concat([Buffer.from('Comment\0', 'latin1'), GPS_MARKER])));
  }
  parts.push(pngChunk('IDAT', deflateSync(Buffer.from([0x00, 0xff, 0x00, 0x00]))));
  parts.push(pngChunk('IEND', Buffer.alloc(0)));
  return Buffer.concat(parts);
}

function pngChunk(type: string, data: Buffer): Buffer {
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  out.write(type, 4, 'latin1');
  data.copy(out, 8);
  // A real CRC32. The stripper does not check it, but a fixture that carries
  // a wrong one would be a fixture no decoder would accept, which is not the
  // thing under test.
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
}

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(bytes: Buffer): number {
  let c = 0xffffffff;
  for (const byte of bytes) {
    // The index is masked to 0–255 and the table has 256 entries, so this is
    // always defined; `?? 0` satisfies the compiler without a cast.
    c = (CRC_TABLE[(c ^ byte) & 0xff] ?? 0) ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

/** An extended WEBP (VP8X) that declares and carries EXIF and XMP chunks. */
export function webp(options: { withExif?: boolean } = {}): Buffer {
  const chunks: Buffer[] = [];
  const vp8x = Buffer.alloc(10);
  // Flags: EXIF (0x08) | XMP (0x04) — both set, so the stripper has to clear
  // them as well as drop the chunks. A decoder that trusts the flag and finds
  // no chunk is entitled to call the file corrupt.
  vp8x[0] = options.withExif === false ? 0x00 : 0x0c;
  chunks.push(riffChunk('VP8X', vp8x));
  chunks.push(riffChunk('VP8 ', Buffer.alloc(16, 0x11)));
  if (options.withExif !== false) {
    chunks.push(riffChunk('EXIF', GPS_MARKER));
    chunks.push(riffChunk('XMP ', GPS_MARKER));
  }
  const body = Buffer.concat(chunks);
  const header = Buffer.alloc(12);
  header.write('RIFF', 0, 'latin1');
  header.writeUInt32LE(4 + body.length, 4);
  header.write('WEBP', 8, 'latin1');
  return Buffer.concat([header, body]);
}

function riffChunk(fourcc: string, data: Buffer): Buffer {
  const padded = data.length + (data.length % 2);
  const out = Buffer.alloc(8 + padded);
  out.write(fourcc, 0, 'latin1');
  out.writeUInt32LE(data.length, 4);
  data.copy(out, 8);
  return out;
}
