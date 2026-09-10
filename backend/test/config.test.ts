import { describe, expect, it } from 'vitest';

import { ConfigError, loadConfig } from '../src/config/env.js';

const minimal = {
  NODE_ENV: 'test',
  DATABASE_URL: 'postgresql://u:p@localhost:5435/db',
  ADMIN_TOTP_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString('base64'),
  EMAIL_FROM_ADDRESS: 'no-reply@example.test',
  AUTH_JWT_SECRET: Buffer.alloc(32, 9).toString('base64'),
  // Phase 8. Required like the other two keys, and distinct from both — the
  // media token is the ONLY authorization on the upload route.
  MEDIA_SIGNING_KEY: Buffer.alloc(32, 11).toString('base64'),
};

describe('loadConfig', () => {
  it('applies the documented defaults', () => {
    const config = loadConfig(minimal);
    expect(config.port).toBe(3000);
    expect(config.host).toBe('0.0.0.0');
    expect(config.logLevel).toBe('info');
    expect(config.trustProxy).toBe(false);
    expect(config.admin.sessionIdleMinutes).toBe(15);
    expect(config.admin.sessionAbsoluteHours).toBe(12);
    expect(config.admin.reauthMinutes).toBe(5);
    expect(config.admin.origin).toBe('http://localhost:5173');
    expect(config.rateLimit.anonPerMinute).toBe(60);
    expect(config.rateLimit.authPerMinute).toBe(300);
    expect(config.email.transport).toBe('file');
    expect(config.push.transport).toBe('file');
    expect(config.media.transport).toBe('file');
    expect(config.media.baseUrl).toBe('http://localhost:3000');
    expect(config.media.signingKey).toEqual(Buffer.alloc(32, 11));
    expect(config.admin.totpEncryptionKey).toEqual(Buffer.alloc(32, 7));
    expect(config.auth.accessTokenMinutes).toBe(15);
    expect(config.auth.refreshTokenDays).toBe(30);
    expect(config.auth.otpExpiryMinutes).toBe(10);
    expect(config.auth.jwtSecret).toEqual(Buffer.alloc(32, 9));
  });

  it('names every missing or malformed variable in one error', () => {
    let caught: unknown;
    try {
      loadConfig({ NODE_ENV: 'test', PORT: 'abc' });
    } catch (error) {
      caught = error;
    }
    expect(caught).toBeInstanceOf(ConfigError);
    const issues = (caught as ConfigError).issues.join('\n');
    expect(issues).toContain('DATABASE_URL');
    expect(issues).toContain('ADMIN_TOTP_ENCRYPTION_KEY');
    expect(issues).toContain('EMAIL_FROM_ADDRESS');
    expect(issues).toContain('PORT');
    expect(issues).toContain('AUTH_JWT_SECRET');
  });

  it('rejects an encryption key that is not 32 bytes', () => {
    expect(() =>
      loadConfig({ ...minimal, ADMIN_TOTP_ENCRYPTION_KEY: Buffer.alloc(16).toString('base64') }),
    ).toThrow(/ADMIN_TOTP_ENCRYPTION_KEY/);
  });

  it('requires AUTH_JWT_SECRET and rejects one that is not 32 bytes', () => {
    const withoutSecret = Object.fromEntries(
      Object.entries(minimal).filter(([k]) => k !== 'AUTH_JWT_SECRET'),
    );
    expect(() => loadConfig(withoutSecret)).toThrow(/AUTH_JWT_SECRET/);
    expect(() =>
      loadConfig({ ...minimal, AUTH_JWT_SECRET: Buffer.alloc(16).toString('base64') }),
    ).toThrow(/AUTH_JWT_SECRET/);
  });

  it('refuses a JWT secret equal to the TOTP encryption key', () => {
    const same = Buffer.alloc(32, 7).toString('base64');
    expect(() =>
      loadConfig({ ...minimal, ADMIN_TOTP_ENCRYPTION_KEY: same, AUTH_JWT_SECRET: same }),
    ).toThrow(/AUTH_JWT_SECRET: must differ/);
  });

  it('refuses the file transport and a plain-http admin origin in production', () => {
    const production = { ...minimal, NODE_ENV: 'production', EMAIL_TRANSPORT: 'file' };
    expect(() => loadConfig(production)).toThrow(/EMAIL_TRANSPORT/);
    expect(() =>
      loadConfig({
        ...production,
        EMAIL_TRANSPORT: 'ses',
        AWS_REGION: 'ap-south-1',
        SES_CONFIGURATION_SET_OTP: 'otp',
        SES_CONFIGURATION_SET_NOTIFICATION: 'n',
        SES_CONFIGURATION_SET_MARKETING: 'm',
        SES_EVENTS_TOPIC_ARN: 'arn:aws:sns:ap-south-1:1:t',
      }),
    ).toThrow(/ADMIN_ORIGIN/);
  });

  it('refuses PUSH_TRANSPORT=fcm_apns, because neither transport is built', () => {
    // No Firebase project and no Apple developer account exist and Phase 3c
    // procures neither (docs/decisions/15-phase-3c-push.md). Refusing the
    // value outright is honest; the alternative is a deployment that believes
    // pushes are going out when nothing is sending them.
    expect(() => loadConfig({ ...minimal, PUSH_TRANSPORT: 'fcm_apns' })).toThrow(
      /PUSH_TRANSPORT: "fcm_apns" is not available yet/,
    );
  });

  it('does NOT force a push transport in production, unlike email', () => {
    // Deliberate asymmetry. Requiring a transport that is not built would make
    // production unbootable rather than safe; the email fallback is what
    // carries a notification when push does not (§Phase 3c).
    const production = {
      ...minimal,
      NODE_ENV: 'production',
      ADMIN_ORIGIN: 'https://admin.raajjepro.mv',
      EMAIL_TRANSPORT: 'ses',
      AWS_REGION: 'ap-south-1',
      SES_CONFIGURATION_SET_OTP: 'otp',
      SES_CONFIGURATION_SET_NOTIFICATION: 'n',
      SES_CONFIGURATION_SET_MARKETING: 'm',
      SES_EVENTS_TOPIC_ARN: 'arn:aws:sns:ap-south-1:1:t',
      MEDIA_BASE_URL: 'https://api.raajjepro.mv',
    };
    // The media guard below makes production unbootable today on purpose, so
    // this asserts on the ISSUE LIST rather than on a successful load: what
    // it is checking is that no issue mentions the push transport.
    let issues: string[] = [];
    try {
      loadConfig(production);
    } catch (error) {
      issues = error instanceof ConfigError ? error.issues : [];
    }
    expect(issues.filter((i) => i.startsWith('PUSH_TRANSPORT'))).toEqual([]);
  });

  // 🔧 Phase 8 copies EMAIL_TRANSPORT's guard rather than half of it. The two
  // rules are deliberately unsatisfiable together until the object store
  // lands — `s3` is refused because it is not built, `file` is refused in
  // production because the images would vanish on the next deploy. Production
  // therefore cannot boot yet, and that is the honest signal.
  it('refuses a file media store in production, and s3 everywhere', () => {
    const production = {
      ...minimal,
      NODE_ENV: 'production',
      ADMIN_ORIGIN: 'https://admin.raajjepro.mv',
      EMAIL_TRANSPORT: 'ses',
      AWS_REGION: 'ap-south-1',
      SES_CONFIGURATION_SET_OTP: 'otp',
      SES_CONFIGURATION_SET_NOTIFICATION: 'n',
      SES_CONFIGURATION_SET_MARKETING: 'm',
      SES_EVENTS_TOPIC_ARN: 'arn:aws:sns:ap-south-1:1:t',
      MEDIA_BASE_URL: 'https://api.raajjepro.mv',
    };
    expect(() => loadConfig({ ...production, MEDIA_STORAGE: 'file' })).toThrow(
      /MEDIA_STORAGE: must be "s3" in production/,
    );
    // …and naming s3 does not get past it either, because s3 is not built.
    expect(() => loadConfig({ ...production, MEDIA_STORAGE: 's3' })).toThrow(
      /"s3" is not available yet/,
    );
    // Outside production the file transport is the normal, working default.
    expect(loadConfig(minimal).media.transport).toBe('file');
  });

  // Phase 8, and the same shape as the two production rules above it: a
  // signed media URL handed to a client over http:// is a token in the clear,
  // and that token is the only authorization the upload route has.
  it('requires an https media base URL in production', () => {
    const production = {
      ...minimal,
      NODE_ENV: 'production',
      ADMIN_ORIGIN: 'https://admin.raajjepro.mv',
      EMAIL_TRANSPORT: 'ses',
      AWS_REGION: 'ap-south-1',
      SES_CONFIGURATION_SET_OTP: 'otp',
      SES_CONFIGURATION_SET_NOTIFICATION: 'n',
      SES_CONFIGURATION_SET_MARKETING: 'm',
      SES_EVENTS_TOPIC_ARN: 'arn:aws:sns:ap-south-1:1:t',
    };
    expect(() => loadConfig(production)).toThrow(/MEDIA_BASE_URL/);
  });

  // The object store is procured at deployment (§0.0 item 17), exactly like
  // SES and the push vendors. Refused outright rather than silently falling
  // back, so a deployment cannot believe images are landing in a bucket.
  it('refuses MEDIA_STORAGE=s3 until the transport exists', () => {
    expect(() => loadConfig({ ...minimal, MEDIA_STORAGE: 's3' })).toThrow(/MEDIA_STORAGE/);
  });

  // The media token is the ONLY authorization on the upload route, so a key
  // shared with another purpose means a signature forged in one context is
  // valid here.
  it('refuses a media signing key reused from another purpose', () => {
    const shared = Buffer.alloc(32, 9).toString('base64');
    expect(() => loadConfig({ ...minimal, MEDIA_SIGNING_KEY: shared })).toThrow(
      /MEDIA_SIGNING_KEY: must differ from|AUTH_JWT_SECRET: must differ from MEDIA_SIGNING_KEY/,
    );
  });

  it('requires the SES variables only when the transport is ses', () => {
    expect(() => loadConfig({ ...minimal, EMAIL_TRANSPORT: 'ses' })).toThrow(/AWS_REGION/);
    const config = loadConfig({
      ...minimal,
      EMAIL_TRANSPORT: 'ses',
      AWS_REGION: 'ap-south-1',
      SES_CONFIGURATION_SET_OTP: 'otp',
      SES_CONFIGURATION_SET_NOTIFICATION: 'n',
      SES_CONFIGURATION_SET_MARKETING: 'm',
      SES_EVENTS_TOPIC_ARN: 'arn:aws:sns:ap-south-1:1:t',
    });
    expect(config.email.transport).toBe('ses');
    if (config.email.transport === 'ses') {
      expect(config.email.configurationSets.otp).toBe('otp');
    }
  });

  // Phase 8a, §1b step 2: a provider cannot pay a subscription without
  // somewhere to send the money. Unset in development is fine — the endpoint
  // returns `bankTransfer: null` rather than an example account, because a
  // provider who transfers to a made-up number has lost it — and required in
  // production, the posture EMAIL_TRANSPORT and MEDIA_STORAGE already take.
  it('leaves the billing bank details null when unset, and requires all three in production', () => {
    expect(loadConfig(minimal).billing.bankDetails).toBeNull();

    // All three or none: a half-configured account is the worst of the three
    // states, because the screen renders and the transfer goes nowhere.
    expect(
      loadConfig({ ...minimal, BILLING_BANK_NAME: 'Bank of Maldives' }).billing.bankDetails,
    ).toBeNull();

    const configured = loadConfig({
      ...minimal,
      BILLING_BANK_NAME: 'Bank of Maldives',
      BILLING_BANK_ACCOUNT_NAME: 'RaajjePro Pvt Ltd',
      BILLING_BANK_ACCOUNT_NUMBER: '7770000000000',
    });
    expect(configured.billing.bankDetails).toEqual({
      bankName: 'Bank of Maldives',
      accountName: 'RaajjePro Pvt Ltd',
      accountNumber: '7770000000000',
    });

    let caught: unknown;
    try {
      loadConfig({ ...minimal, NODE_ENV: 'production' });
    } catch (error) {
      caught = error;
    }
    const issues = (caught as ConfigError).issues.join('\n');
    for (const name of [
      'BILLING_BANK_NAME',
      'BILLING_BANK_ACCOUNT_NAME',
      'BILLING_BANK_ACCOUNT_NUMBER',
    ]) {
      expect(issues).toContain(`${name}: required in production`);
    }
  });

  it('reports a schema failure and a production business-rule violation together', () => {
    let caught: unknown;
    try {
      loadConfig({ NODE_ENV: 'production', EMAIL_TRANSPORT: 'file' });
    } catch (error) {
      caught = error;
    }
    expect(caught).toBeInstanceOf(ConfigError);
    const issues = (caught as ConfigError).issues.join('\n');
    expect(issues).toContain('DATABASE_URL');
    expect(issues).toContain('EMAIL_TRANSPORT');
  });
});
