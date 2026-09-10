import { AppError, BusinessRuleError, NotFoundError } from '../../core/errors.js';
import type { Clock } from '../../core/clock.js';
import {
  ACCEPTED_IMAGE_TYPES,
  MalformedImageError,
  sniffImageType,
  stripImageMetadata,
  type ImageContentType,
} from './exif.js';
import { MediaTokenError, verifyMediaToken } from './signing.js';
import type { MediaStorage, UploadTarget } from './types.js';

/**
 * The media surface every module uploads through (§Phase 8).
 *
 * It knows nothing about listings. §Phase 10a's identity documents will use
 * the same three steps against a different `purpose` and a different storage
 * location — §1d requires those to live somewhere separate from payment
 * proofs and general media — and keeping the ownership rules out of here is
 * what makes that possible without a second implementation of any of this.
 */

/**
 * "JPG, PNG or WEBP · Max 10 MB · 1200×675 works best" — the wizard's own
 * media step (`mockups/design-composer/Create Service.dc.html`). The cap is
 * enforced at three points, on purpose: when the target is issued (so a
 * client is not invited to start an upload it cannot finish), by the store
 * when the bytes arrive, and again at finalise against what was actually
 * stored. The last of those is the one that counts — the first two are a
 * client contract and a transport's promise.
 */
export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;

/** Long enough to pick a photo and upload it on a weak atoll connection; short enough that a leaked URL is nearly always dead. */
const UPLOAD_TARGET_MINUTES = 30;

/**
 * How long a read URL lives. Short because the listing it belongs to can be
 * hidden, taken down by moderation or deleted, and a URL that outlives that
 * keeps serving an image the platform has decided to stop showing.
 */
const READ_URL_MINUTES = 60;

interface Deps {
  storage: MediaStorage;
  clock: Clock;
}

export interface FinalisedObject {
  contentType: ImageContentType;
  byteSize: number;
}

export class MediaService {
  private readonly storage: MediaStorage;
  private readonly clock: Clock;

  constructor(deps: Deps) {
    this.storage = deps.storage;
    this.clock = deps.clock;
  }

  /**
   * Who may call: a module that has already authorized its own caller. This
   * takes no viewer and is not a route — the ownership check belongs to
   * whoever owns the row the object will hang from, and putting it here would
   * mean two places knowing what a listing is.
   *
   * The declared content type is checked against the allowlist now so a
   * client learns immediately, and checked again against the real bytes at
   * `finalise`, which is the check that cannot be lied to.
   */
  issueUploadTarget(
    purpose: string,
    declaredContentType: string,
  ): { objectKey: string; target: UploadTarget } {
    assertAcceptedType(declaredContentType);
    return this.storage.issueUploadTarget({
      purpose,
      contentType: declaredContentType,
      expiresAt: new Date(this.clock().getTime() + UPLOAD_TARGET_MINUTES * 60_000),
      maxBytes: MAX_IMAGE_BYTES,
    });
  }

  /**
   * Reads the uploaded object back, checks what it really is, strips its
   * metadata and writes the stripped bytes over the original.
   *
   * **This is where §Phase 8's guarantee is kept**, and it is deliberately
   * after the upload rather than during it: with a real presigned PUT the
   * bytes go straight to the store and the server never sees them in flight.
   * Doing it here means the same code runs for both transports.
   *
   * The stripped bytes replace the original at the same key, so there is no
   * window in which the store holds a copy that still carries the GPS
   * coordinates — and no second key for a cleanup job to miss.
   */
  async finalise(objectKey: string, declaredContentType: string): Promise<FinalisedObject> {
    const raw = await this.storage.get(objectKey);
    if (raw === null) {
      throw new BusinessRuleError(
        'MEDIA_NOT_UPLOADED',
        'No file has been uploaded for this image yet',
      );
    }
    if (raw.length > MAX_IMAGE_BYTES) {
      throw new BusinessRuleError('MEDIA_TOO_LARGE', `Images must be ${megabytes()} or smaller`);
    }

    // The declared type is a client assertion; this is the fact.
    const actual = sniffImageType(raw);
    if (actual === null) {
      throw new BusinessRuleError(
        'MEDIA_CONTENT_NOT_AN_IMAGE',
        'That file is not a JPG, PNG or WEBP image',
      );
    }
    if (actual !== declaredContentType) {
      throw new BusinessRuleError(
        'MEDIA_CONTENT_MISMATCH',
        `The uploaded file is ${actual}, not the ${declaredContentType} it was declared as`,
      );
    }

    let stripped: Buffer;
    try {
      stripped = stripImageMetadata(raw, actual);
    } catch (error) {
      if (error instanceof MalformedImageError) {
        // Refused rather than stored as-is. An image whose container cannot
        // be walked is one whose metadata cannot be shown to be gone, and
        // storing it would quietly make this method's promise false.
        throw new BusinessRuleError(
          'MEDIA_UNREADABLE',
          'That image could not be read — try re-exporting or re-taking it',
        );
      }
      throw error;
    }

    await this.storage.put(objectKey, stripped, actual);
    return { contentType: actual, byteSize: stripped.length };
  }

  /** A short-lived URL for a stored object. Re-issued on every read, never persisted. */
  readUrl(objectKey: string): string {
    return this.storage.readUrl(
      objectKey,
      new Date(this.clock().getTime() + READ_URL_MINUTES * 60_000),
    );
  }

  // -------------------------------------------------------------------------
  // The local transport's own two operations
  // -------------------------------------------------------------------------

  /**
   * Who may call: whoever holds the token. That is the whole point — a
   * presigned URL carries no session, and an S3 presigned PUT carries no AWS
   * credential either. The token names one object key, one content type and
   * one size ceiling, and expires.
   *
   * Only reachable on the local transport; with a real store the client PUTs
   * to the store and this route does not exist.
   */
  async receiveUpload(token: string, secret: Buffer, body: Buffer, contentType: string) {
    const claims = this.verify(token, secret);
    if (claims.op !== 'put') {
      throw new AppError(403, 'MEDIA_LINK_INVALID', 'This link cannot be used to upload');
    }
    if (claims.ct !== undefined && claims.ct !== contentType) {
      throw new BusinessRuleError(
        'MEDIA_CONTENT_MISMATCH',
        `This link accepts ${claims.ct}, not ${contentType}`,
      );
    }
    if (claims.max !== undefined && body.length > claims.max) {
      throw new BusinessRuleError('MEDIA_TOO_LARGE', `Images must be ${megabytes()} or smaller`);
    }
    await this.storage.put(claims.key, body, contentType);
  }

  /**
   * Who may call: whoever holds the token, for the one object it names, until
   * it expires.
   *
   * The content type is **sniffed from the stored bytes** rather than carried
   * in the token. Everything in the store has been through `finalise`, so the
   * bytes are known to be one of the three accepted types, and reading it off
   * the object rather than off the URL means a token cannot assert a type the
   * object does not have.
   */
  async serve(token: string, secret: Buffer): Promise<{ bytes: Buffer; contentType: string }> {
    const claims = this.verify(token, secret);
    if (claims.op !== 'get') {
      throw new AppError(403, 'MEDIA_LINK_INVALID', 'This link cannot be used to read');
    }
    const bytes = await this.storage.get(claims.key);
    if (bytes === null) throw new NotFoundError('No such image');
    return { bytes, contentType: sniffImageType(bytes) ?? 'application/octet-stream' };
  }

  private verify(token: string, secret: Buffer) {
    try {
      return verifyMediaToken(secret, token, this.clock());
    } catch (error) {
      if (error instanceof MediaTokenError) {
        // Expiry is told apart from a bad signature because a client can act
        // on it — ask for a fresh target — where a bad signature means
        // something is wrong that retrying will not fix.
        throw error.reason === 'expired'
          ? new AppError(410, 'MEDIA_LINK_EXPIRED', 'This link has expired — request a new one')
          : new AppError(403, 'MEDIA_LINK_INVALID', 'This link is not valid');
      }
      throw error;
    }
  }
}

function assertAcceptedType(contentType: string): asserts contentType is ImageContentType {
  if (!(ACCEPTED_IMAGE_TYPES as readonly string[]).includes(contentType)) {
    throw new BusinessRuleError(
      'MEDIA_TYPE_NOT_ACCEPTED',
      'Images must be JPG, PNG or WEBP',
      ACCEPTED_IMAGE_TYPES.map((t) => ({ path: 'contentType', message: t })),
    );
  }
}

function megabytes(): string {
  return `${String(MAX_IMAGE_BYTES / 1024 / 1024)} MB`;
}
