/**
 * Typed configuration, validated once at startup (plan §Phase 2: "typed
 * config module, fail-fast on missing vars").
 *
 * Configuration comes from process environment variables and nowhere else —
 * see .env.example, which is the contract for what a deployment must provide.
 * Every failure is collected and reported together so a deployment with three
 * missing variables learns about all three on the first boot, not the third.
 */
import { z } from 'zod';

const bool = z.enum(['true', 'false']).transform((v) => v === 'true');
const int = (fallback: number) => z.coerce.number().int().positive().default(fallback);

const base32Key = z.string().transform((v, ctx) => {
  const bytes = Buffer.from(v, 'base64');
  if (bytes.length !== 32) {
    ctx.addIssue({ code: 'custom', message: 'must be 32 bytes, base64-encoded' });
    return z.NEVER;
  }
  return bytes;
});

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: int(3000),
  HOST: z.string().min(1).default('0.0.0.0'),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
  TRUST_PROXY: bool.default(false),
  DATABASE_URL: z.string().min(1),

  ADMIN_ORIGIN: z.string().min(1).default('http://localhost:5173'),
  ADMIN_SESSION_IDLE_MINUTES: int(15),
  ADMIN_SESSION_ABSOLUTE_HOURS: int(12),
  ADMIN_REAUTH_MINUTES: int(5),
  ADMIN_TOTP_ENCRYPTION_KEY: base32Key,

  RATE_LIMIT_ANON_PER_MINUTE: int(60),
  RATE_LIMIT_AUTH_PER_MINUTE: int(300),

  AUTH_JWT_SECRET: base32Key,
  AUTH_ACCESS_TOKEN_MINUTES: int(15),
  AUTH_REFRESH_TOKEN_DAYS: int(30),
  AUTH_OTP_EXPIRY_MINUTES: int(10),
  AUTH_PASSWORD_RESET_EXPIRY_MINUTES: int(30),

  EMAIL_TRANSPORT: z.enum(['file', 'ses']).default('file'),
  EMAIL_FROM_ADDRESS: z.string().min(3),
  AWS_REGION: z.string().min(1).optional(),
  SES_CONFIGURATION_SET_OTP: z.string().min(1).optional(),
  SES_CONFIGURATION_SET_NOTIFICATION: z.string().min(1).optional(),
  SES_CONFIGURATION_SET_MARKETING: z.string().min(1).optional(),
  SES_EVENTS_TOPIC_ARN: z.string().min(1).optional(),

  // Phase 3c. `file` writes every push as JSON into backend/.push/, the same
  // posture EMAIL_TRANSPORT=file takes. `fcm_apns` is the shape the real
  // vendors will plug into and is refused below until they exist.
  PUSH_TRANSPORT: z.enum(['file', 'fcm_apns']).default('file'),

  // Phase 8. `file` keeps listing images in backend/.media/ and signs its own
  // upload and read URLs, the same posture the two transports above take —
  // the object store is procured at deployment (§0.0 item 17). `s3` is the
  // shape the real store will plug into and is refused below until it exists.
  MEDIA_STORAGE: z.enum(['file', 's3']).default('file'),
  /**
   * The absolute base a signed media URL is built on. Absolute because a real
   * store's URLs are absolute and point somewhere else entirely — a client
   * must never have to know which transport it is talking to, or resolve one
   * kind of URL differently from the other.
   */
  MEDIA_BASE_URL: z.string().min(1).default('http://localhost:3000'),
  MEDIA_SIGNING_KEY: base32Key,
});

export type EmailChannel = 'otp' | 'notification' | 'marketing';

export interface FilePushConfig {
  transport: 'file';
  /** Directory the file transport writes into. Gitignored, like .mail/. */
  directory: string;
}

export type PushConfig = FilePushConfig;

export interface FileMediaConfig {
  transport: 'file';
  /** Directory the file transport writes objects into. Gitignored, like .mail/ and .push/. */
  directory: string;
  baseUrl: string;
  /** Signs the stand-in presigned URLs. 32 bytes; must differ from the other two keys. */
  signingKey: Buffer;
}

export type MediaConfig = FileMediaConfig;

export interface SesEmailConfig {
  transport: 'ses';
  fromAddress: string;
  region: string;
  configurationSets: Record<EmailChannel, string>;
  eventsTopicArn: string;
}

export interface FileEmailConfig {
  transport: 'file';
  fromAddress: string;
  /** Directory the file transport writes into. Gitignored. */
  directory: string;
  /** Set from the optional SES_EVENTS_TOPIC_ARN so the webhook route is exercisable with the file transport too. */
  eventsTopicArn: string | null;
}

export interface Config {
  nodeEnv: 'development' | 'test' | 'production';
  port: number;
  host: string;
  logLevel: 'fatal' | 'error' | 'warn' | 'info' | 'debug' | 'trace' | 'silent';
  trustProxy: boolean;
  databaseUrl: string;
  admin: {
    origin: string;
    sessionIdleMinutes: number;
    sessionAbsoluteHours: number;
    reauthMinutes: number;
    totpEncryptionKey: Buffer;
    cookieSecure: boolean;
  };
  rateLimit: { anonPerMinute: number; authPerMinute: number };
  auth: {
    /** HS256 key for user access tokens. 32 bytes; must differ from the TOTP key. */
    jwtSecret: Buffer;
    accessTokenMinutes: number;
    refreshTokenDays: number;
    otpExpiryMinutes: number;
    /** Longer than an OTP's: the reset code is read from a mailbox the user may have to go and open (Forgot Password.dc.html says 30 minutes). */
    passwordResetExpiryMinutes: number;
  };
  email: SesEmailConfig | FileEmailConfig;
  push: PushConfig;
  media: MediaConfig;
}

export class ConfigError extends Error {
  constructor(public readonly issues: string[]) {
    super(`Invalid configuration (see .env.example):\n  ${issues.join('\n  ')}`);
    this.name = 'ConfigError';
  }
}

export function loadConfig(env: NodeJS.ProcessEnv): Config {
  // Empty strings are "unset": a CI runner that exports FOO= did not set FOO.
  const cleaned = Object.fromEntries(
    Object.entries(env).filter(([, v]) => v !== undefined && v !== ''),
  );
  const parsed = schema.safeParse(cleaned);
  const issues: string[] = [];
  if (!parsed.success) {
    for (const issue of parsed.error.issues) {
      issues.push(`${issue.path.join('.')}: ${issue.message}`);
    }
  }

  // Business-rule checks run against the raw env regardless of whether the
  // schema itself parsed, so a deployment with both a missing variable and a
  // production-only violation learns about both on the first boot, not the
  // second. They read `cleaned` directly (applying the same defaults the
  // schema would) rather than `parsed.data`, which does not exist on failure.
  const production = cleaned.NODE_ENV === 'production';
  const emailTransport = cleaned.EMAIL_TRANSPORT ?? 'file';
  const adminOrigin = cleaned.ADMIN_ORIGIN ?? 'http://localhost:5173';
  if (production && emailTransport !== 'ses') {
    issues.push('EMAIL_TRANSPORT: must be "ses" in production');
  }
  if (production && !adminOrigin.startsWith('https://')) {
    issues.push('ADMIN_ORIGIN: must be an https:// origin in production');
  }
  // There is deliberately NO "must be fcm_apns in production" rule to match
  // email's. The FCM and APNs transports are not built — no Firebase project
  // and no Apple developer account exist (docs/decisions/15-phase-3c-push.md)
  // — so requiring them in production would make production unbootable rather
  // than safe. What we can do honestly is refuse the value outright, so a
  // deployment that sets it learns immediately instead of believing pushes are
  // going out.
  if (cleaned.PUSH_TRANSPORT === 'fcm_apns') {
    issues.push(
      'PUSH_TRANSPORT: "fcm_apns" is not available yet — the FCM and APNs transports arrive with their vendor accounts (docs/deferred-verification.md L11, L12)',
    );
  }
  // 🔧 **EMAIL_TRANSPORT's whole posture, not half of it** (§Phase 8,
  // 2026-09-10). Two rules that look contradictory and are not:
  //
  //   - `s3` is refused, because the transport is not built and no bucket
  //     exists — a deployment that set it would believe images were going
  //     somewhere durable.
  //   - `file` is refused **in production**, because a local directory there
  //     is worse than no images at all: they vanish on the next deploy, and
  //     the provider who uploaded them is never told.
  //
  // Together they make production unbootable until the object store lands,
  // which is the honest signal and the point of copying the guard. This is
  // deliberately UNLIKE `PUSH_TRANSPORT`, which has no production rule
  // because the email fallback carries a notification when push cannot.
  // Nothing carries a listing's cover image if the store does not.
  const mediaStorage = cleaned.MEDIA_STORAGE ?? 'file';
  if (mediaStorage === 's3') {
    issues.push(
      'MEDIA_STORAGE: "s3" is not available yet — the object-store transport arrives with the bucket (docs/deferred-verification.md L13)',
    );
  }
  if (production && mediaStorage !== 's3') {
    issues.push('MEDIA_STORAGE: must be "s3" in production');
  }
  // Three distinct 32-byte keys. Reusing one across purposes means a
  // signature forged in one context is valid in another, and the media token
  // is the *only* authorization on the upload route.
  const keys: { name: string; value: unknown }[] = [
    { name: 'AUTH_JWT_SECRET', value: cleaned.AUTH_JWT_SECRET },
    { name: 'ADMIN_TOTP_ENCRYPTION_KEY', value: cleaned.ADMIN_TOTP_ENCRYPTION_KEY },
    { name: 'MEDIA_SIGNING_KEY', value: cleaned.MEDIA_SIGNING_KEY },
  ];
  for (const [index, a] of keys.entries()) {
    for (const b of keys.slice(index + 1)) {
      if (a.value !== undefined && a.value === b.value) {
        issues.push(`${a.name}: must differ from ${b.name}`);
      }
    }
  }
  if (production && !(cleaned.MEDIA_BASE_URL ?? '').startsWith('https://')) {
    issues.push('MEDIA_BASE_URL: must be an https:// URL in production');
  }

  if (emailTransport === 'ses') {
    const required: [string, string | undefined][] = [
      ['AWS_REGION', cleaned.AWS_REGION],
      ['SES_CONFIGURATION_SET_OTP', cleaned.SES_CONFIGURATION_SET_OTP],
      ['SES_CONFIGURATION_SET_NOTIFICATION', cleaned.SES_CONFIGURATION_SET_NOTIFICATION],
      ['SES_CONFIGURATION_SET_MARKETING', cleaned.SES_CONFIGURATION_SET_MARKETING],
      ['SES_EVENTS_TOPIC_ARN', cleaned.SES_EVENTS_TOPIC_ARN],
    ];
    for (const [name, value] of required) {
      if (value === undefined) issues.push(`${name}: required when EMAIL_TRANSPORT=ses`);
    }
  }

  if (issues.length > 0) throw new ConfigError(issues);
  if (!parsed.success) {
    // Unreachable: a schema failure always adds at least one issue above,
    // which throws before this line. Kept so the compiler can narrow
    // `parsed.data` below without an unsafe cast.
    throw new ConfigError(issues);
  }
  const v = parsed.data;

  let email: Config['email'];
  if (v.EMAIL_TRANSPORT === 'ses') {
    email = {
      transport: 'ses',
      fromAddress: v.EMAIL_FROM_ADDRESS,
      region: v.AWS_REGION ?? '',
      configurationSets: {
        otp: v.SES_CONFIGURATION_SET_OTP ?? '',
        notification: v.SES_CONFIGURATION_SET_NOTIFICATION ?? '',
        marketing: v.SES_CONFIGURATION_SET_MARKETING ?? '',
      },
      eventsTopicArn: v.SES_EVENTS_TOPIC_ARN ?? '',
    };
  } else {
    email = {
      transport: 'file',
      fromAddress: v.EMAIL_FROM_ADDRESS,
      directory: '.mail',
      eventsTopicArn: v.SES_EVENTS_TOPIC_ARN ?? null,
    };
  }

  return {
    nodeEnv: v.NODE_ENV,
    port: v.PORT,
    host: v.HOST,
    logLevel: v.LOG_LEVEL,
    trustProxy: v.TRUST_PROXY,
    databaseUrl: v.DATABASE_URL,
    admin: {
      origin: v.ADMIN_ORIGIN,
      sessionIdleMinutes: v.ADMIN_SESSION_IDLE_MINUTES,
      sessionAbsoluteHours: v.ADMIN_SESSION_ABSOLUTE_HOURS,
      reauthMinutes: v.ADMIN_REAUTH_MINUTES,
      totpEncryptionKey: v.ADMIN_TOTP_ENCRYPTION_KEY,
      cookieSecure: production,
    },
    rateLimit: {
      anonPerMinute: v.RATE_LIMIT_ANON_PER_MINUTE,
      authPerMinute: v.RATE_LIMIT_AUTH_PER_MINUTE,
    },
    auth: {
      jwtSecret: v.AUTH_JWT_SECRET,
      accessTokenMinutes: v.AUTH_ACCESS_TOKEN_MINUTES,
      refreshTokenDays: v.AUTH_REFRESH_TOKEN_DAYS,
      otpExpiryMinutes: v.AUTH_OTP_EXPIRY_MINUTES,
      passwordResetExpiryMinutes: v.AUTH_PASSWORD_RESET_EXPIRY_MINUTES,
    },
    email,
    push: { transport: 'file', directory: '.push' },
    media: {
      transport: 'file',
      directory: '.media',
      // Trailing slashes would double up in every signed URL.
      baseUrl: v.MEDIA_BASE_URL.replace(/\/+$/, ''),
      signingKey: v.MEDIA_SIGNING_KEY,
    },
  };
}
