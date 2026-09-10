import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { ACCEPTED_IMAGE_TYPES } from './exif.js';
import { MAX_IMAGE_BYTES } from './service.js';
import { READ_PATH, UPLOAD_PATH } from './transports/file.js';

/**
 * The two routes the **local** media transport needs (§Phase 8).
 *
 * They exist because there is no object store yet to be presigned against
 * (§0.0 item 17 defers vendor procurement to deployment), so this process
 * plays the store: a signed token stands in for a presigned URL, this PUT
 * stands in for the store accepting the bytes, and this GET stands in for the
 * store serving them.
 *
 * **Registered only on the local transport.** With a real store the client
 * uploads to the store and reads from it, and these two URLs must not exist
 * at all — a live endpoint that accepts bytes against a token is not
 * something to leave switched on because it happens to be harmless.
 *
 * Neither route carries an auth guard, and that is correct rather than an
 * omission: **the token is the authorization**, exactly as it is for an S3
 * presigned URL, which travels with no AWS credential either. The token names
 * one object key, one content type and one size ceiling, and it expires.
 */
export function registerMediaRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  const secret = app.config.media.signingKey;

  // Raw image bodies. Fastify has no parser for these types, and without one
  // every upload would 415 before reaching the handler.
  for (const type of ACCEPTED_IMAGE_TYPES) {
    app.addContentTypeParser(type, { parseAs: 'buffer' }, (_request, body, done) => {
      done(null, body);
    });
  }

  const tokenQuery = z.object({ token: z.string().min(1).max(4096) });

  // Who may call: the holder of a `put` token, for the one object it names,
  // until it expires. See the note above on why that is the whole check.
  //
  // The size ceiling is enforced twice — by Fastify before the body is
  // buffered, and again in the service against the token's own `max`. The
  // first stops a 500 MB body being read into memory at all; the second is
  // the rule.
  r.put(
    UPLOAD_PATH,
    {
      schema: { querystring: tokenQuery },
      bodyLimit: MAX_IMAGE_BYTES,
      config: {
        // Declared per endpoint, as backend/CLAUDE.md requires. A gallery
        // upload is several files in a row, and a retry on a dropped
        // connection is normal on the connections this plan is built for.
        rateLimit: { max: 60, timeWindow: '1 minute', keyGenerator: (req) => `ip:${req.ip}` },
      },
    },
    async (request, reply) => {
      const body = request.body;
      if (!Buffer.isBuffer(body)) {
        return reply.code(415).send();
      }
      const contentType = (request.headers['content-type'] ?? '').split(';')[0]?.trim() ?? '';
      await app.media.receiveUpload(request.query.token, secret, body, contentType);
      // 204: the store has the bytes and has nothing to say about them yet.
      // What they are is decided at finalise, by the module that owns the row.
      return reply.code(204).send();
    },
  );

  // Who may call: the holder of a `get` token, until it expires.
  //
  // No caching header beyond the expiry the token already carries. A listing
  // image is public only while its listing is, and a `Cache-Control: public`
  // on a shared cache would keep serving one that moderation had hidden.
  r.get(
    READ_PATH,
    {
      schema: { querystring: tokenQuery },
      config: {
        rateLimit: { max: 300, timeWindow: '1 minute', keyGenerator: (req) => `ip:${req.ip}` },
      },
    },
    async (request, reply) => {
      const object = await app.media.serve(request.query.token, secret);
      return reply
        .header('content-type', object.contentType)
        .header('cache-control', 'private, no-store')
        .send(object.bytes);
    },
  );
}
