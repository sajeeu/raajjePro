import { randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

import { signMediaToken } from '../signing.js';
import type { IssueUploadInput, IssuedUpload, MediaStorage } from '../types.js';

/**
 * The two paths the local transport serves, shared with `routes.ts` so the
 * URL is written once.
 *
 * **The token travels in the query string, as a real presigned URL's
 * signature does** (`?X-Amz-Signature=…`). Not decoration: a signed token is
 * far longer than Fastify's 100-character path-parameter limit, and the
 * logger already drops query strings (`core/logging.ts` logs `path` only,
 * "a query string may carry an email or a reference code") — which is
 * exactly the handling a credential in a URL needs.
 */
export const UPLOAD_PATH = '/v1/media/uploads';
export const READ_PATH = '/v1/media';

/**
 * Development/test transport: objects are files in a gitignored directory,
 * the same posture `EMAIL_TRANSPORT=file` and `PUSH_TRANSPORT=file` take
 * (§0.0 item 17 — the vendor is procured at deployment).
 *
 * "Presigned" here means a token this process signs, addressed at routes this
 * process serves (`modules/media/routes.ts`). The client's experience is the
 * same as with a real store — request a target, PUT to an opaque expiring
 * URL, then ask the server to finalise — which is the property that makes the
 * eventual S3 transport a swap rather than a rewrite.
 */
export class FileMediaStorage implements MediaStorage {
  /**
   * @param directory  Where objects live. Resolved by the caller.
   * @param baseUrl    What a client can reach this API on. The signed URLs are
   *                   absolute because a real store's would be, so the client
   *                   never has to know which of the two it is talking to.
   * @param secret     Signs the tokens. The API's own key; see `config.media`.
   */
  constructor(
    private readonly directory: string,
    private readonly baseUrl: string,
    private readonly secret: Buffer,
  ) {}

  issueUploadTarget(input: IssueUploadInput): IssuedUpload {
    // Server-chosen, unguessable, and namespaced by purpose. A client-supplied
    // key here is how one provider overwrites another provider's cover image.
    const objectKey = `${input.purpose}/${randomUUID()}`;
    const token = signMediaToken(this.secret, {
      op: 'put',
      key: objectKey,
      exp: input.expiresAt.getTime(),
      ct: input.contentType,
      max: input.maxBytes,
    });
    return {
      objectKey,
      target: {
        url: `${this.baseUrl}${UPLOAD_PATH}?token=${token}`,
        method: 'PUT',
        headers: { 'content-type': input.contentType },
        expiresAt: input.expiresAt,
        maxBytes: input.maxBytes,
      },
    };
  }

  async get(objectKey: string): Promise<Buffer | null> {
    try {
      return await readFile(this.pathFor(objectKey));
    } catch (error) {
      if (isNotFound(error)) return null;
      throw error;
    }
  }

  async put(objectKey: string, bytes: Buffer): Promise<void> {
    const path = this.pathFor(objectKey);
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, bytes);
  }

  readUrl(objectKey: string, expiresAt: Date): string {
    const token = signMediaToken(this.secret, {
      op: 'get',
      key: objectKey,
      exp: expiresAt.getTime(),
    });
    return `${this.baseUrl}${READ_PATH}?token=${token}`;
  }

  /**
   * Keys are server-generated (`purpose/uuid`), so this cannot be reached
   * with `../` today. It is checked anyway: the day something derives a key
   * from a filename, path traversal out of the media directory is the bug
   * that gets written, and a check costs nothing.
   */
  private pathFor(objectKey: string): string {
    const path = resolve(this.directory, objectKey);
    if (path !== this.directory && !path.startsWith(this.directory + '/')) {
      throw new Error(`object key escapes the media directory: ${objectKey}`);
    }
    return path;
  }
}

function isNotFound(error: unknown): boolean {
  return (error as NodeJS.ErrnoException | null)?.code === 'ENOENT';
}

/** Same shape as the email and push factories: one branch today, additive later. */
export function createMediaStorage(config: {
  directory: string;
  baseUrl: string;
  signingKey: Buffer;
}): MediaStorage {
  return new FileMediaStorage(
    resolve(process.cwd(), config.directory),
    config.baseUrl,
    config.signingKey,
  );
}

/** The in-memory variant tests use, so a suite never touches the filesystem. */
export class InMemoryMediaStorage implements MediaStorage {
  private readonly objects = new Map<string, Buffer>();

  constructor(
    private readonly baseUrl: string,
    private readonly secret: Buffer,
  ) {}

  issueUploadTarget(input: IssueUploadInput): IssuedUpload {
    const objectKey = `${input.purpose}/${randomUUID()}`;
    const token = signMediaToken(this.secret, {
      op: 'put',
      key: objectKey,
      exp: input.expiresAt.getTime(),
      ct: input.contentType,
      max: input.maxBytes,
    });
    return {
      objectKey,
      target: {
        url: `${this.baseUrl}${UPLOAD_PATH}?token=${token}`,
        method: 'PUT',
        headers: { 'content-type': input.contentType },
        expiresAt: input.expiresAt,
        maxBytes: input.maxBytes,
      },
    };
  }

  get(objectKey: string): Promise<Buffer | null> {
    return Promise.resolve(this.objects.get(objectKey) ?? null);
  }

  put(objectKey: string, bytes: Buffer): Promise<void> {
    this.objects.set(objectKey, bytes);
    return Promise.resolve();
  }

  readUrl(objectKey: string, expiresAt: Date): string {
    const token = signMediaToken(this.secret, {
      op: 'get',
      key: objectKey,
      exp: expiresAt.getTime(),
    });
    return `${this.baseUrl}${READ_PATH}?token=${token}`;
  }
}
