import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';

import { ok } from '../../core/envelope.js';
import { requireAuth, userOf } from '../auth/guards.js';
import {
  ackBody,
  dispatchParams,
  installationParams,
  permissionBody,
  registerDeviceBody,
} from './schema.js';

/**
 * Device registration and delivery acknowledgement (§Phase 3c).
 *
 * Every route here is `requireAuth` and scoped to the caller's own account —
 * registration needs an authenticated user, which is why this phase sits
 * after Phase 3. `requireEmailVerified` is deliberately NOT used: an
 * unverified user still needs to register a device, and email verification
 * gates booking, enquiry and messaging (§1c), not notification plumbing.
 *
 * Guards go on `preValidation`, not `preHandler`, for the reason spelled out
 * in `auth/guards.ts`: an unauthenticated call must see 401 before its body
 * is validated.
 */
export function registerPushRoutes(app: FastifyInstance): void {
  const r = app.withTypeProvider<ZodTypeProvider>();
  const prefix = '/v1/push';
  const perPrincipal = (max: number, timeWindow: string) => ({ rateLimit: { max, timeWindow } });

  // Who may call: the signed-in user, registering their own device. Called on
  // sign-in and again on every vendor token refresh, so the tier is generous
  // enough for a device that rotates often and tight enough to bound abuse.
  r.post(
    `${prefix}/devices`,
    {
      schema: { body: registerDeviceBody },
      preValidation: requireAuth,
      config: perPrincipal(30, '1 hour'),
    },
    async (request, reply) => {
      const device = await app.pushRegistration.register({
        userId: userOf(request).id,
        installationId: request.body.installationId,
        platform: request.body.platform,
        token: request.body.token,
        deviceName: request.body.deviceName,
        permission: request.body.permission,
      });
      return reply.send(ok(device));
    },
  );

  // Who may call: the signed-in user, for their own devices. A read is
  // authorized too — the list says where this account receives notifications.
  r.get(`${prefix}/devices`, { preValidation: requireAuth }, async (request, reply) => {
    return reply.send(ok(await app.pushRegistration.listDevices(userOf(request).id)));
  });

  // Who may call: the signed-in user, for their own device. Soft-revokes; the
  // row stays as history (invariant 8).
  r.delete(
    `${prefix}/devices/:installationId`,
    { schema: { params: installationParams }, preValidation: requireAuth },
    async (request, reply) => {
      await app.pushRegistration.unregister(userOf(request).id, request.params.installationId);
      return reply.send(ok({ revoked: true }));
    },
  );

  // Who may call: the signed-in user, reporting what the OS told their app.
  // This is not a preference switch — see `PushRegistrationService.setPermission`.
  r.post(
    `${prefix}/permission`,
    {
      schema: { body: permissionBody },
      preValidation: requireAuth,
      config: perPrincipal(60, '1 hour'),
    },
    async (request, reply) => {
      const permission = await app.pushRegistration.setPermission(
        userOf(request).id,
        request.body.permission,
      );
      return reply.send(ok({ permission }));
    },
  );

  // Who may call: the signed-in user, for a dispatch addressed to them. The
  // ownership check is inside the service and a miss is a 404 — otherwise one
  // account could confirm another's notification and suppress their fallback.
  // High tier: a multi-device user acks once per device per notification.
  r.post(
    `${prefix}/dispatches/:dispatchId/ack`,
    {
      schema: { params: dispatchParams, body: ackBody },
      preValidation: requireAuth,
      config: perPrincipal(300, '1 hour'),
    },
    async (request, reply) => {
      const result = await app.pushRegistration.acknowledge(
        userOf(request).id,
        request.params.dispatchId,
        request.body.installationId,
      );
      return reply.send(ok(result));
    },
  );
}
