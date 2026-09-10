/**
 * The object-storage boundary (§Phase 8: "media upload via presigned URL").
 *
 * ## Why there is a boundary here at all
 *
 * The same posture Phase 2 took for email and Phase 3c took for push: the
 * vendor is procured at deployment (§0.0 item 17), so the *mechanism* is
 * built and tested now against a local transport and the real object store
 * plugs in behind this interface later. `docs/deferred-verification.md`
 * carries the row.
 *
 * ## Why an upload is three steps and not one
 *
 * A genuine presigned PUT means the client uploads **straight to the object
 * store** and the server never sees the bytes. That is the point of it — a
 * 10 MB photo does not pass through the API — and it is also why §Phase 8's
 * "server-side content-type and size validation, EXIF stripping on every
 * image" cannot happen during the upload. So:
 *
 *   1. `issueUploadTarget` — the server chooses the object key, records a
 *      pending row and hands back a URL the client may PUT to.
 *   2. The client PUTs the bytes to that URL, against the store.
 *   3. `finalise` — the server reads the object back, sniffs its real type,
 *      checks its real size, strips its metadata and rewrites it.
 *
 * Step 3 is what makes the guarantee true, and it is identical whether the
 * bytes went to a local directory or to S3. Swapping the transport is a
 * transport swap, not a redesign.
 *
 * ## The key is the server's to choose
 *
 * `issueUploadTarget` takes a *purpose*, never a key. A client-supplied key
 * on a presigned upload is the classic way one tenant overwrites another's
 * object, and here that would mean one provider replacing another provider's
 * cover image.
 */

/** What the client is told to do with the bytes. */
export interface UploadTarget {
  /** Where to send them. Opaque, expiring, and specific to this one object. */
  url: string;
  /** Always `PUT` today. Named rather than assumed, so an S3 POST policy can differ without a client change. */
  method: 'PUT';
  /** Headers the store requires on the upload — the declared content type, at minimum. */
  headers: Record<string, string>;
  /** After this the target is refused and a new one must be requested. */
  expiresAt: Date;
  /** The store refuses anything larger. The client should not start an upload it cannot finish. */
  maxBytes: number;
}

export interface IssueUploadInput {
  /** A short slug naming what the object is for — `listing-media`. Becomes the key's prefix. */
  purpose: string;
  /** What the client says it will upload. Checked against an allowlist here and against the bytes at finalise. */
  contentType: string;
  expiresAt: Date;
  maxBytes: number;
}

export interface IssuedUpload {
  /** The server-chosen key. Stored on the owning row; never returned to a client. */
  objectKey: string;
  target: UploadTarget;
}

/**
 * The store itself. Deliberately small: put bytes, get bytes, hand out URLs.
 * No listing, no copying, no lifecycle — anything more would be an interface
 * written for a vendor rather than for the two things this phase does.
 */
export interface MediaStorage {
  issueUploadTarget(input: IssueUploadInput): IssuedUpload;

  /** The stored bytes, or null if nothing was ever uploaded to that key. */
  get(objectKey: string): Promise<Buffer | null>;

  /** Writes (or overwrites) the object. `finalise` uses it to put the stripped bytes back. */
  put(objectKey: string, bytes: Buffer, contentType: string): Promise<void>;

  /**
   * A short-lived URL a client may read the object from.
   *
   * Short-lived for listing media too, not only for the identity documents
   * §1d requires it for. A listing image is public *while the listing is
   * published*, and a permanent URL outlives that — it would keep serving
   * after the provider hid the listing, after moderation hid it, and after
   * the account was deleted.
   */
  readUrl(objectKey: string, expiresAt: Date): string;
}
