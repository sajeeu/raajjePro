import { createSign, generateKeyPairSync, randomUUID } from 'node:crypto';
import { EventEmitter } from 'node:events';
import type { ClientRequest, IncomingMessage } from 'node:http';
import https from 'node:https';
import type { KeyObject } from 'node:crypto';

import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';

import { SnsValidatorAdapter } from '../src/modules/email/sns/validator.js';

// The exact key order and separator sns-validator signs over for a
// Notification/SubscriptionConfirmation message (its own
// `signableKeysForNotification` — see node_modules/sns-validator/index.js).
const SIGNABLE_KEYS = [
  'Message',
  'MessageId',
  'Subject',
  'SubscribeURL',
  'Timestamp',
  'TopicArn',
  'Type',
] as const;

interface SignableFields {
  Type: string;
  MessageId: string;
  TopicArn: string;
  Message: string;
  Timestamp: string;
  SignatureVersion: '1' | '2';
  SigningCertURL: string;
  Subject?: string;
  SubscribeURL?: string;
}

function canonicalString(fields: SignableFields): string {
  let out = '';
  for (const key of SIGNABLE_KEYS) {
    const value = fields[key];
    if (value !== undefined) {
      out += `${key}\n${value}\n`;
    }
  }
  return out;
}

function signFields(fields: SignableFields, privateKey: KeyObject): string {
  const algorithm = fields.SignatureVersion === '1' ? 'RSA-SHA1' : 'RSA-SHA256';
  return createSign(algorithm).update(canonicalString(fields)).sign(privateKey, 'base64');
}

function freshCertUrl(): string {
  // A distinct SigningCertURL per call — sns-validator caches fetched
  // certificates by URL at module level, so reusing one across tests would
  // let a later test skip the (stubbed) fetch entirely on a cache hit.
  return `https://sns.ap-south-1.amazonaws.com/SimpleNotificationService-${randomUUID()}.pem`;
}

describe('SnsValidatorAdapter', () => {
  const adapter = new SnsValidatorAdapter();
  let keyPair: { publicKey: KeyObject; privateKey: KeyObject };

  beforeAll(() => {
    keyPair = generateKeyPairSync('rsa', { modulusLength: 2048 });
  });

  function certificatePem(): string {
    // sns-validator's verifier.verify(certificate, signature, 'base64') calls
    // into crypto.createVerify(...).verify(), which accepts a PEM public key
    // exactly as it would an X.509 certificate — so the public key half of
    // the generated pair stands in for a real AWS-issued certificate here.
    return keyPair.publicKey.export({ type: 'spki', format: 'pem' });
  }

  // Stubs the certificate fetch: sns-validator does `require('https')` and
  // calls `https.get(certUrl, cb)` at call time, so spying on the same
  // node:https module object intercepts it — no real network call, no local
  // TLS server needed. (Tried this first per the brief; it works, so the
  // https.createServer fallback was not needed.)
  function stubCertificateFetch(): void {
    vi.spyOn(https, 'get').mockImplementation(((
      _url: string | URL,
      callback?: (res: IncomingMessage) => void,
    ): ClientRequest => {
      const res = Object.assign(new EventEmitter(), {
        statusCode: 200,
      }) as unknown as IncomingMessage;
      callback?.(res);
      res.emit('data', certificatePem());
      res.emit('end');
      return new EventEmitter() as unknown as ClientRequest;
    }) as typeof https.get);
  }

  afterEach(() => {
    vi.restoreAllMocks();
  });

  function buildNotification(version: '1' | '2'): SignableFields & { Signature: string } {
    const fields: SignableFields = {
      Type: 'Notification',
      MessageId: randomUUID(),
      TopicArn: 'arn:aws:sns:ap-south-1:123456789012:raajjepro-ses-events',
      Message: JSON.stringify({ eventType: 'Delivery', mail: { messageId: randomUUID() } }),
      Timestamp: new Date().toISOString(),
      SignatureVersion: version,
      SigningCertURL: freshCertUrl(),
    };
    return { ...fields, Signature: signFields(fields, keyPair.privateKey) };
  }

  it('rejects a body that is not JSON', async () => {
    await expect(adapter.validate('nope')).rejects.toThrow();
  });

  it('rejects a message missing required fields', async () => {
    await expect(adapter.validate(JSON.stringify({ Type: 'Notification' }))).rejects.toThrow();
  });

  it('rejects a signing certificate not hosted by AWS SNS before fetching anything', async () => {
    await expect(
      adapter.validate(
        JSON.stringify({
          Type: 'Notification',
          MessageId: 'm',
          TopicArn: 'arn:aws:sns:ap-south-1:1:t',
          Message: '{}',
          Timestamp: '2026-09-06T00:00:00.000Z',
          SignatureVersion: '1',
          Signature: 'AAAA',
          SigningCertURL: 'https://attacker.example/cert.pem',
        }),
      ),
    ).rejects.toThrow();
  });

  it('validates a correctly signed v1 message and resolves the parsed message', async () => {
    stubCertificateFetch();
    const notification = buildNotification('1');
    const result = await adapter.validate(JSON.stringify(notification));
    expect(result.Type).toBe('Notification');
    expect(result.MessageId).toBe(notification.MessageId);
    expect(result.Message).toBe(notification.Message);
  });

  it('validates a correctly signed v2 message', async () => {
    stubCertificateFetch();
    const notification = buildNotification('2');
    const result = await adapter.validate(JSON.stringify(notification));
    expect(result.Type).toBe('Notification');
    expect(result.MessageId).toBe(notification.MessageId);
  });

  it('rejects a v1 message with one flipped character in the signature', async () => {
    stubCertificateFetch();
    const notification = buildNotification('1');
    // Flip a character well inside the payload, not the trailing `=` padding
    // — Node's base64 decoder is lenient about a corrupted pad character and
    // can still decode to the original bytes, which would make this
    // assertion pass for the wrong reason.
    const chars = notification.Signature.split('');
    const flipIndex = 10;
    chars[flipIndex] = chars[flipIndex] === 'A' ? 'B' : 'A';
    const flipped = chars.join('');
    await expect(
      adapter.validate(JSON.stringify({ ...notification, Signature: flipped })),
    ).rejects.toThrow();
  });

  it('rejects a message whose Message field was tampered with after signing', async () => {
    stubCertificateFetch();
    const notification = buildNotification('2');
    const tampered = { ...notification, Message: JSON.stringify({ eventType: 'Bounce' }) };
    await expect(adapter.validate(JSON.stringify(tampered))).rejects.toThrow();
  });
});
