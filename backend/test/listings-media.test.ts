import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { buildApp } from '../src/app.js';
import { signMediaToken } from '../src/modules/media/signing.js';
import { InMemoryMediaStorage } from '../src/modules/media/transports/file.js';
import type { OwnListingDto } from '../src/modules/listings/types.js';
import { buildTestApp, controllableClock, databaseUrl, freshIp } from './helpers/app.js';
import {
  BASE,
  GPS_MARKER,
  createDraft,
  ensureCategoriesSeeded,
  jpeg,
  patchDraft,
  png,
  uploadImage,
  uploadPathOf,
  webp,
} from './helpers/listings.js';
import { registerUser } from './helpers/users.js';

interface Envelope<T> {
  data: T;
}
interface ErrorEnvelope {
  error: { code: string; message: string };
}

const SECRET = Buffer.alloc(32, 3);

/**
 * §Phase 8: "media upload via presigned URL — **server-side content-type and
 * size validation, EXIF stripping on every image**".
 *
 * These go through the three real steps a client performs, because the whole
 * point of the presigned shape is that the client never holds an object key —
 * a test that called the service directly would exercise a flow nobody uses.
 *
 * The storage is `InMemoryMediaStorage` so the suite never writes to disk,
 * and so a test can read back exactly what was stored.
 */
describe.skipIf(databaseUrl === undefined)('listing media', () => {
  let app: Awaited<ReturnType<typeof buildApp>>;
  let storage: InMemoryMediaStorage;
  let owner: Awaited<ReturnType<typeof registerUser>>;
  let listingId: string;

  beforeAll(async () => {
    storage = new InMemoryMediaStorage('http://api.test', SECRET);
    ({ app } = await buildTestApp({ deps: { mediaStorage: storage } }));
    await ensureCategoriesSeeded(app.deps.prisma);
    owner = await registerUser(app, { role: 'provider' });
    listingId = (await createDraft(app, owner.headers, {})).id;
  });

  afterAll(async () => {
    await app.close();
  });

  async function issueTarget(contentType = 'image/jpeg') {
    const res = await app.inject({
      method: 'POST',
      url: `${BASE}/${listingId}/media`,
      headers: { ...owner.headers, 'idempotency-key': randomUUID() },
      remoteAddress: freshIp(),
      payload: { contentType },
    });
    return res;
  }

  describe('the upload target', () => {
    it('hands back an expiring URL and a pending row, and never an object key', async () => {
      const res = await issueTarget();
      expect(res.statusCode).toBe(201);
      const body = res.json<
        Envelope<{
          media: { id: string; status: string; url: string | null };
          upload: { url: string; method: string; maxBytes: number; expiresAt: string };
        }>
      >().data;

      expect(body.media.status).toBe('pending');
      // Nothing to point at yet — a URL here would 404, and saying null is
      // what lets the wizard tell "uploading" from "uploaded".
      expect(body.media.url).toBeNull();
      expect(body.upload.method).toBe('PUT');
      expect(body.upload.maxBytes).toBe(10 * 1024 * 1024);
      expect(new Date(body.upload.expiresAt).getTime()).toBeGreaterThan(Date.now());

      // The object key is the server's and is never on the wire — a
      // client-supplied key is how one provider overwrites another's cover.
      const row = await app.deps.prisma.listingMedia.findUniqueOrThrow({
        where: { id: body.media.id },
      });
      expect(res.body).not.toContain(row.objectKey);
    });

    it('refuses a content type outside the three the wizard offers', async () => {
      for (const contentType of ['image/gif', 'application/pdf', 'image/svg+xml']) {
        const res = await issueTarget(contentType);
        expect(res.statusCode).toBe(422);
        expect(res.json<ErrorEnvelope>().error.code).toBe('MEDIA_TYPE_NOT_ACCEPTED');
      }
    });

    it('replays on a repeated idempotency key rather than orphaning a row', async () => {
      const key = randomUUID();
      const send = () =>
        app.inject({
          method: 'POST',
          url: `${BASE}/${listingId}/media`,
          headers: { ...owner.headers, 'idempotency-key': key },
          remoteAddress: freshIp(),
          payload: { contentType: 'image/jpeg' },
        });
      const first = await send();
      const second = await send();
      const idOf = (r: typeof first) => r.json<Envelope<{ media: { id: string } }>>().data.media.id;
      expect(idOf(second)).toBe(idOf(first));
    });
  });

  describe('the upload itself', () => {
    it('accepts the bytes against the token alone — no session, exactly like a presigned PUT', async () => {
      const created = await issueTarget();
      const { upload } = created.json<Envelope<{ upload: { url: string } }>>().data;

      const put = await app.inject({
        method: 'PUT',
        url: uploadPathOf(upload.url),
        // No Authorization header. The token IS the authorization, which is
        // the property that makes this swappable for a real presigned URL —
        // an S3 presigned PUT carries no AWS credential either.
        headers: { 'content-type': 'image/jpeg' },
        remoteAddress: freshIp(),
        payload: jpeg(),
      });
      expect(put.statusCode).toBe(204);
    });

    it('refuses a body larger than the token allows', async () => {
      const created = await issueTarget();
      const { upload } = created.json<Envelope<{ upload: { url: string } }>>().data;
      // Fastify's own bodyLimit stops the read before the handler sees it,
      // which is the point of enforcing the ceiling twice: this one stops a
      // huge body being buffered at all.
      const put = await app.inject({
        method: 'PUT',
        url: uploadPathOf(upload.url),
        headers: { 'content-type': 'image/jpeg' },
        remoteAddress: freshIp(),
        payload: Buffer.alloc(11 * 1024 * 1024),
      });
      expect(put.statusCode).toBeGreaterThanOrEqual(400);
    });

    it('refuses a content type the token did not name', async () => {
      const created = await issueTarget('image/png');
      const { upload } = created.json<Envelope<{ upload: { url: string } }>>().data;
      const put = await app.inject({
        method: 'PUT',
        url: uploadPathOf(upload.url),
        headers: { 'content-type': 'image/jpeg' },
        remoteAddress: freshIp(),
        payload: jpeg(),
      });
      expect(put.statusCode).toBe(422);
      expect(put.json<ErrorEnvelope>().error.code).toBe('MEDIA_CONTENT_MISMATCH');
    });

    it('refuses a forged token', async () => {
      // The token is the only authorization on this route, so a signature
      // that does not verify has to be the end of it.
      const forged = signMediaToken(Buffer.alloc(32, 9), {
        op: 'put',
        key: 'listing-media/somebody-elses-cover',
        exp: Date.now() + 60_000,
        ct: 'image/jpeg',
        max: 1024,
      });
      const put = await app.inject({
        method: 'PUT',
        url: `/v1/media/uploads?token=${forged}`,
        headers: { 'content-type': 'image/jpeg' },
        remoteAddress: freshIp(),
        payload: jpeg(),
      });
      expect(put.statusCode).toBe(403);
      expect(put.json<ErrorEnvelope>().error.code).toBe('MEDIA_LINK_INVALID');
    });

    it('refuses a read token used to upload, and an upload token used to read', async () => {
      const key = 'listing-media/crossed-purpose';
      const readToken = signMediaToken(SECRET, { op: 'get', key, exp: Date.now() + 60_000 });
      const putToken = signMediaToken(SECRET, { op: 'put', key, exp: Date.now() + 60_000 });

      const put = await app.inject({
        method: 'PUT',
        url: `/v1/media/uploads?token=${readToken}`,
        headers: { 'content-type': 'image/jpeg' },
        remoteAddress: freshIp(),
        payload: jpeg(),
      });
      expect(put.statusCode).toBe(403);

      const get = await app.inject({
        method: 'GET',
        url: `/v1/media?token=${putToken}`,
        remoteAddress: freshIp(),
      });
      expect(get.statusCode).toBe(403);
    });

    it('tells an expired link apart from an invalid one', async () => {
      // A client can act on expiry — ask for a fresh target — where a bad
      // signature means something retrying will not fix.
      const expired = signMediaToken(SECRET, {
        op: 'put',
        key: 'listing-media/stale',
        exp: Date.now() - 1,
        ct: 'image/jpeg',
        max: 1024,
      });
      const put = await app.inject({
        method: 'PUT',
        url: `/v1/media/uploads?token=${expired}`,
        headers: { 'content-type': 'image/jpeg' },
        remoteAddress: freshIp(),
        payload: jpeg(),
      });
      expect(put.statusCode).toBe(410);
      expect(put.json<ErrorEnvelope>().error.code).toBe('MEDIA_LINK_EXPIRED');
    });
  });

  describe('finalise — where the guarantee is kept', () => {
    it('strips the metadata from what is actually stored, not from a copy', async () => {
      // The end-to-end assertion §Phase 8's bullet is about: a photo goes in
      // carrying its GPS coordinates, and what the store holds afterwards
      // does not. Read straight out of the storage, so this cannot pass by
      // stripping only on the way out.
      const before = jpeg({ withExif: true });
      expect(before.includes(GPS_MARKER)).toBe(true);

      const media = await uploadImage(app, owner.headers, listingId, before);

      const row = await app.deps.prisma.listingMedia.findUniqueOrThrow({
        where: { id: media.id },
      });
      const stored = await storage.get(row.objectKey);
      expect(stored).not.toBeNull();
      expect(stored?.includes(GPS_MARKER)).toBe(false);
      // The stripped bytes REPLACED the original at the same key, so there is
      // no window in which the store holds a copy that still carries them,
      // and no second key for a cleanup job to miss.
      expect(row.byteSize).toBe(stored?.length);
      expect(row.byteSize).toBeLessThan(before.length);
      expect(row.status).toBe('stored');
      expect(row.storedAt).not.toBeNull();
    });

    it('does the same for PNG and WEBP', async () => {
      for (const [bytes, contentType] of [
        [png({ withExif: true }), 'image/png'],
        [webp({ withExif: true }), 'image/webp'],
      ] as const) {
        const media = await uploadImage(app, owner.headers, listingId, bytes, contentType);
        const row = await app.deps.prisma.listingMedia.findUniqueOrThrow({
          where: { id: media.id },
        });
        const stored = await storage.get(row.objectKey);
        expect(stored?.includes(GPS_MARKER)).toBe(false);
      }
    });

    it('catches a file that is not what it said it was', async () => {
      // The declared content type is a client assertion; the magic number is
      // the fact. An upload declaring image/jpeg and carrying a PDF is caught
      // here whatever the header said.
      const created = await issueTarget('image/jpeg');
      const body =
        created.json<Envelope<{ media: { id: string }; upload: { url: string } }>>().data;
      await app.inject({
        method: 'PUT',
        url: uploadPathOf(body.upload.url),
        headers: { 'content-type': 'image/jpeg' },
        remoteAddress: freshIp(),
        payload: Buffer.from('%PDF-1.7\n%âãÏÓ\ntrailer', 'latin1'),
      });

      const done = await app.inject({
        method: 'POST',
        url: `${BASE}/${listingId}/media/${body.media.id}/complete`,
        headers: owner.headers,
        remoteAddress: freshIp(),
      });
      expect(done.statusCode).toBe(422);
      expect(done.json<ErrorEnvelope>().error.code).toBe('MEDIA_CONTENT_NOT_AN_IMAGE');

      // The row stays `pending`, so the publish gate still treats it as a
      // missing cover rather than a present one.
      const row = await app.deps.prisma.listingMedia.findUniqueOrThrow({
        where: { id: body.media.id },
      });
      expect(row.status).toBe('pending');
    });

    it('refuses a JPEG whose container cannot be walked', async () => {
      const created = await issueTarget('image/jpeg');
      const body =
        created.json<Envelope<{ media: { id: string }; upload: { url: string } }>>().data;
      await app.inject({
        method: 'PUT',
        url: uploadPathOf(body.upload.url),
        headers: { 'content-type': 'image/jpeg' },
        remoteAddress: freshIp(),
        payload: jpeg({ withExif: true }).subarray(0, 20),
      });

      const done = await app.inject({
        method: 'POST',
        url: `${BASE}/${listingId}/media/${body.media.id}/complete`,
        headers: owner.headers,
        remoteAddress: freshIp(),
      });
      // Not stored as-is: an image whose structure is not understood is one
      // whose metadata cannot be shown to be gone.
      expect(done.statusCode).toBe(422);
      expect(done.json<ErrorEnvelope>().error.code).toBe('MEDIA_UNREADABLE');
    });

    it('refuses to finalise an upload that never happened', async () => {
      const created = await issueTarget();
      const mediaId = created.json<Envelope<{ media: { id: string } }>>().data.media.id;
      const done = await app.inject({
        method: 'POST',
        url: `${BASE}/${listingId}/media/${mediaId}/complete`,
        headers: owner.headers,
        remoteAddress: freshIp(),
      });
      expect(done.statusCode).toBe(422);
      expect(done.json<ErrorEnvelope>().error.code).toBe('MEDIA_NOT_UPLOADED');
    });
  });

  describe('reading it back', () => {
    it('serves the stored bytes with their real type, and stops when the link expires', async () => {
      const time = controllableClock();
      const scoped = new InMemoryMediaStorage('http://api.test', SECRET);
      const { app: timed } = await buildTestApp({
        clock: time.clock,
        deps: { mediaStorage: scoped },
      });
      try {
        await ensureCategoriesSeeded(timed.deps.prisma);
        const user = await registerUser(timed, { role: 'provider' });
        const draft = await createDraft(timed, user.headers, {});
        const media = await uploadImage(timed, user.headers, draft.id);
        expect(media.url).not.toBeNull();

        const url = new URL(media.url ?? '');
        const fetched = await timed.inject({
          method: 'GET',
          url: `${url.pathname}${url.search}`,
          remoteAddress: freshIp(),
        });
        expect(fetched.statusCode).toBe(200);
        expect(fetched.headers['content-type']).toBe('image/jpeg');
        expect(fetched.rawPayload.includes(GPS_MARKER)).toBe(false);
        // Never cached by a shared cache: the listing can be hidden, taken
        // down by moderation or deleted, and a cached copy would outlive that.
        expect(fetched.headers['cache-control']).toBe('private, no-store');

        // An hour later the same URL is dead. Tested by advancing the clock,
        // not by waiting.
        time.advance(61 * 60_000);
        const stale = await timed.inject({
          method: 'GET',
          url: `${url.pathname}${url.search}`,
          remoteAddress: freshIp(),
        });
        expect(stale.statusCode).toBe(410);
      } finally {
        await timed.close();
      }
    });
  });

  describe('cover and gallery', () => {
    it('keeps the cover out of the gallery and orders the rest as given', async () => {
      const user = await registerUser(app, { role: 'provider' });
      const draft = await createDraft(app, user.headers, {});
      const cover = await uploadImage(app, user.headers, draft.id);
      const a = await uploadImage(app, user.headers, draft.id);
      const b = await uploadImage(app, user.headers, draft.id);

      const res = await patchDraft(app, user.headers, draft.id, {
        coverMediaId: cover.id,
        galleryMediaIds: [b.id, a.id],
      });
      expect(res.statusCode).toBe(200);
      const body = res.json<Envelope<OwnListingDto>>().data;
      expect(body.coverMedia?.id).toBe(cover.id);
      // "Use the arrows to reorder — the first photo shows first."
      expect(body.gallery.map((m) => m.id)).toEqual([b.id, a.id]);
      // The cover is named separately and is never also a gallery slot.
      expect(body.gallery.map((m) => m.id)).not.toContain(cover.id);
    });

    it('removing the cover clears it and leaves the listing published', async () => {
      const user = await registerUser(app, { role: 'provider' });
      const draft = await createDraft(app, user.headers, {});
      const cover = await uploadImage(app, user.headers, draft.id);
      await patchDraft(app, user.headers, draft.id, { coverMediaId: cover.id });

      const res = await app.inject({
        method: 'DELETE',
        url: `${BASE}/${draft.id}/media/${cover.id}`,
        headers: user.headers,
        remoteAddress: freshIp(),
      });
      expect(res.statusCode).toBe(200);
      const body = res.json<Envelope<OwnListingDto>>().data;
      expect(body.coverMedia).toBeNull();
      // Incomplete again — which is a thing to fix, and the publish gate
      // will say so.
      expect(body.missingRequiredFields.map((f) => f.field)).toContain('coverMediaId');

      // Invariant 8: the row is stamped, not deleted, and the object stays.
      const row = await app.deps.prisma.listingMedia.findUniqueOrThrow({
        where: { id: cover.id },
      });
      expect(row.removedAt).not.toBeNull();
      expect(await storage.get(row.objectKey)).not.toBeNull();
    });

    /**
     * §Phase 8 (2026-09-10): a media row needs **reversible moderation
     * visibility** on top of invariant 8's soft delete, because `photo` is
     * one of §Phase 22's six `Report.targetType` values.
     *
     * Phase 22 owns the admin action; Phase 8 owns the columns and the
     * filter, which is the split §Phase 5 used for `suspendedAt`. So the
     * hide is written directly here — what is under test is that the rest of
     * the module honours it.
     */
    it('drops a moderated image from the gallery and refuses it as a cover, reversibly', async () => {
      const user = await registerUser(app, { role: 'provider' });
      const draft = await createDraft(app, user.headers, {});
      const keep = await uploadImage(app, user.headers, draft.id);
      const reported = await uploadImage(app, user.headers, draft.id);
      await patchDraft(app, user.headers, draft.id, {
        galleryMediaIds: [keep.id, reported.id],
      });

      await app.deps.prisma.listingMedia.update({
        where: { id: reported.id },
        data: { hiddenByAdminAt: new Date(), hiddenByAdminReason: 'reported: misleading' },
      });

      // Gone from the gallery — the listing stays up and the reported photo
      // does not render.
      const afterHide = await app.inject({
        method: 'GET',
        url: `${BASE}/${draft.id}`,
        headers: user.headers,
        remoteAddress: freshIp(),
      });
      const hidden = afterHide.json<Envelope<OwnListingDto>>().data;
      expect(hidden.gallery.map((m) => m.id)).toEqual([keep.id]);

      // And it cannot be promoted to the cover, which would put it back on
      // every card and in every search result — the most visible place it
      // could be.
      const promote = await patchDraft(app, user.headers, draft.id, {
        coverMediaId: reported.id,
      });
      expect(promote.statusCode).toBe(422);
      expect(promote.json<ErrorEnvelope>().error.code).toBe('MEDIA_HIDDEN_BY_ADMIN');

      // §1d: moderation is always reversible. Clearing the stamp puts it
      // back exactly where it was — and note it did NOT resurrect through
      // `removedAt`, which is why the two are separate columns.
      await app.deps.prisma.listingMedia.update({
        where: { id: reported.id },
        data: { hiddenByAdminAt: null, hiddenByAdminReason: null },
      });
      const afterRestore = await app.inject({
        method: 'GET',
        url: `${BASE}/${draft.id}`,
        headers: user.headers,
        remoteAddress: freshIp(),
      });
      expect(afterRestore.json<Envelope<OwnListingDto>>().data.gallery.map((m) => m.id)).toEqual([
        keep.id,
        reported.id,
      ]);
    });

    it('makes a listing incomplete again when its cover is moderated', async () => {
      // Rather than publishing with a blank thumbnail, which is the whole
      // reason §0.2 item 4 made the cover required.
      const user = await registerUser(app, { role: 'provider' });
      const draft = await createDraft(app, user.headers, {});
      const cover = await uploadImage(app, user.headers, draft.id);
      await patchDraft(app, user.headers, draft.id, { coverMediaId: cover.id });

      await app.deps.prisma.listingMedia.update({
        where: { id: cover.id },
        data: { hiddenByAdminAt: new Date(), hiddenByAdminReason: 'reported' },
      });

      const res = await app.inject({
        method: 'GET',
        url: `${BASE}/${draft.id}`,
        headers: user.headers,
        remoteAddress: freshIp(),
      });
      const body = res.json<Envelope<OwnListingDto>>().data;
      expect(body.missingRequiredFields.map((f) => f.field)).toContain('coverMediaId');
    });

    it("keeps a provider's own removal separate from moderation's", async () => {
      // §1b's reasoning, applied to a media row: under one field the two are
      // indistinguishable, and un-hiding a moderated image would resurrect
      // one the provider had deliberately taken down.
      const user = await registerUser(app, { role: 'provider' });
      const draft = await createDraft(app, user.headers, {});
      const image = await uploadImage(app, user.headers, draft.id);
      await patchDraft(app, user.headers, draft.id, { galleryMediaIds: [image.id] });

      await app.inject({
        method: 'DELETE',
        url: `${BASE}/${draft.id}/media/${image.id}`,
        headers: user.headers,
        remoteAddress: freshIp(),
      });
      // An admin later clears a hide that was never set. The provider's
      // removal is untouched.
      await app.deps.prisma.listingMedia.update({
        where: { id: image.id },
        data: { hiddenByAdminAt: null },
      });

      const row = await app.deps.prisma.listingMedia.findUniqueOrThrow({
        where: { id: image.id },
      });
      expect(row.removedAt).not.toBeNull();
      const res = await app.inject({
        method: 'GET',
        url: `${BASE}/${draft.id}`,
        headers: user.headers,
        remoteAddress: freshIp(),
      });
      expect(res.json<Envelope<OwnListingDto>>().data.gallery).toEqual([]);
    });

    it("refuses another listing's image as a cover", async () => {
      const user = await registerUser(app, { role: 'provider' });
      const mine = await createDraft(app, user.headers, {});
      const theirs = await createDraft(app, owner.headers, {});
      const theirImage = await uploadImage(app, owner.headers, theirs.id);

      const res = await patchDraft(app, user.headers, mine.id, { coverMediaId: theirImage.id });
      expect(res.statusCode).toBe(422);
      expect(res.json<ErrorEnvelope>().error.code).toBe('MEDIA_NOT_FOUND');
    });
  });
});
