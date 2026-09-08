import { describe, expect, it } from 'vitest';

import { ConfigError, loadConfig } from '../src/config/env.js';

const minimal = {
  NODE_ENV: 'test',
  DATABASE_URL: 'postgresql://u:p@localhost:5435/db',
  ADMIN_TOTP_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString('base64'),
  EMAIL_FROM_ADDRESS: 'no-reply@example.test',
  AUTH_JWT_SECRET: Buffer.alloc(32, 9).toString('base64'),
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
    };
    expect(loadConfig(production).push.transport).toBe('file');
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
