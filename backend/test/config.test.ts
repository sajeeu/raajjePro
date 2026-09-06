import { describe, expect, it } from 'vitest';

import { ConfigError, loadConfig } from '../src/config/env.js';

const minimal = {
  NODE_ENV: 'test',
  DATABASE_URL: 'postgresql://u:p@localhost:5435/db',
  ADMIN_TOTP_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString('base64'),
  EMAIL_FROM_ADDRESS: 'no-reply@example.test',
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
    expect(config.admin.totpEncryptionKey).toEqual(Buffer.alloc(32, 7));
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
  });

  it('rejects an encryption key that is not 32 bytes', () => {
    expect(() =>
      loadConfig({ ...minimal, ADMIN_TOTP_ENCRYPTION_KEY: Buffer.alloc(16).toString('base64') }),
    ).toThrow(/ADMIN_TOTP_ENCRYPTION_KEY/);
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
});
