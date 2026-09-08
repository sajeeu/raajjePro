import { BusinessRuleError, NotFoundError } from '../../core/errors.js';

export const SOCIAL_PROVIDERS = ['apple', 'google', 'facebook', 'viber'] as const;
export type SocialProviderName = (typeof SOCIAL_PROVIDERS)[number];

export interface SocialIdentity {
  providerUserId: string;
  email?: string;
  fullName?: string;
}

/**
 * Provider-agnostic social sign-in (plan §Phase 3: "interface with stubs";
 * Apple added by §1 divergence 6 because App Review requires it wherever
 * another third-party sign-in exists). Real implementations are post-v1
 * (plan §6). The interface fixes the seam; the stubs fix the client contract.
 */
export interface SocialAuthProvider {
  readonly name: SocialProviderName;
  verify(idToken: string): Promise<SocialIdentity>;
}

class StubProvider implements SocialAuthProvider {
  constructor(readonly name: SocialProviderName) {}
  verify(): Promise<SocialIdentity> {
    return Promise.reject(
      new BusinessRuleError(
        'SOCIAL_AUTH_UNAVAILABLE',
        `Sign-in with ${this.name} isn't available yet — use your email and password`,
      ),
    );
  }
}

export class SocialAuthRegistry {
  private readonly providers: Map<SocialProviderName, SocialAuthProvider>;
  constructor(providers: SocialAuthProvider[]) {
    this.providers = new Map(providers.map((p) => [p.name, p]));
  }
  /**
   * Who may call: the social route, with whatever name the client sent — not
   * narrowed to `SocialProviderName`, since the whole point is to tell an
   * unregistered name apart from a known stub (plan §4: 404, not a Zod
   * rejection).
   */
  get(name: string): SocialAuthProvider {
    const provider = this.providers.get(name as SocialProviderName);
    if (provider === undefined) {
      throw new NotFoundError(`Sign-in with ${name} isn't supported`);
    }
    return provider;
  }
}

export function stubProviders(): SocialAuthProvider[] {
  return SOCIAL_PROVIDERS.map((name) => new StubProvider(name));
}
