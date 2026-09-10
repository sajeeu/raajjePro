import type {
  Invoice,
  PaymentSubmission,
  Prisma,
  PrismaClient,
  ProviderSubscription,
} from '../../generated/prisma/client.js';
import type { PaymentPurpose, PaymentSubmissionStatus } from '../../generated/prisma/enums.js';

/** A Prisma client or an open transaction — a confirmation writes four tables inside one. */
export type Db = PrismaClient | Prisma.TransactionClient;

/**
 * Reads and writes for §Phase 8a's three tables.
 *
 * Nothing here decides anything: the rules live in `pause.ts`, `trial.ts`,
 * `downgrade.ts` and the service, so they can be asserted without a database
 * (backend/CLAUDE.md — business logic in the service layer, never in a route
 * handler, and here never in a query either).
 */
export class SubscriptionRepository {
  constructor(private readonly prisma: PrismaClient) {}

  find(providerProfileId: string, db: Db = this.prisma): Promise<ProviderSubscription | null> {
    return db.providerSubscription.findUnique({ where: { providerProfileId } });
  }

  /**
   * The row, creating an empty free-tier one if there is none.
   *
   * Concurrency-safe for the same reason `getOrCreateProviderProfile` is: two
   * parallel calls both see no row and both insert, and the loser's `P2002`
   * against the `@unique` on `provider_profile_id` would otherwise surface as
   * a 500 — from a double tap on "Try Premium", on the flaky connections this
   * plan is built for. `upsert` with an empty update is one statement the
   * unique index arbitrates.
   */
  ensure(providerProfileId: string, db: Db = this.prisma): Promise<ProviderSubscription> {
    return db.providerSubscription.upsert({
      where: { providerProfileId },
      create: { providerProfileId },
      update: {},
    });
  }

  update(
    providerProfileId: string,
    data: Prisma.ProviderSubscriptionUpdateInput,
    db: Db = this.prisma,
  ): Promise<ProviderSubscription> {
    return db.providerSubscription.update({ where: { providerProfileId }, data });
  }

  /** Every subscription the lifecycle job might have work for. Sorted so a sweep is deterministic. */
  findLifecycleCandidates(db: Db = this.prisma): Promise<ProviderSubscription[]> {
    return db.providerSubscription.findMany({
      where: { status: { in: ['trialing', 'active', 'paused', 'expired', 'free'] } },
      orderBy: { createdAt: 'asc' },
    });
  }

  createSubmission(
    data: Prisma.PaymentSubmissionUncheckedCreateInput,
    db: Db = this.prisma,
  ): Promise<PaymentSubmission> {
    return db.paymentSubmission.create({ data });
  }

  findSubmission(id: string, db: Db = this.prisma): Promise<PaymentSubmission | null> {
    return db.paymentSubmission.findUnique({ where: { id } });
  }

  /** Ownership is in the WHERE, so somebody else's submission is *not found* rather than found and refused. */
  findOwnedSubmission(id: string, payerId: string): Promise<PaymentSubmission | null> {
    return this.prisma.paymentSubmission.findFirst({ where: { id, payerId } });
  }

  /** What §Phase 10a's Billing and Pay-by-Bank-Transfer screens render: the provider's most recent attempt. */
  findLatestSubmission(
    payerId: string,
    purpose: PaymentPurpose,
  ): Promise<PaymentSubmission | null> {
    return this.prisma.paymentSubmission.findFirst({
      where: { payerId, purpose },
      orderBy: { createdAt: 'desc' },
    });
  }

  updateSubmission(
    id: string,
    data: Prisma.PaymentSubmissionUpdateInput,
    db: Db = this.prisma,
  ): Promise<PaymentSubmission> {
    return db.paymentSubmission.update({ where: { id }, data });
  }

  /**
   * Moves a submission out of one status, and reports whether *this* caller
   * was the one that did it.
   *
   * One conditional statement rather than read-then-write, because two admins
   * confirming the same submission at the same moment is a real sequence —
   * the queue is shared and the 48-hour SLA has them working it in parallel.
   * A read-then-write there confirms twice, issues two invoices and extends
   * the period by sixty days.
   */
  async transitionSubmission(
    id: string,
    from: PaymentSubmissionStatus,
    data: Prisma.PaymentSubmissionUpdateInput,
    db: Db = this.prisma,
  ): Promise<boolean> {
    const { count } = await db.paymentSubmission.updateMany({
      where: { id, status: from },
      data,
    });
    return count === 1;
  }

  /** The admin queue (§Phase 10a), oldest submission first — §1b's 48-hour SLA runs from `submittedAt`. */
  async pendingSubmissions(query: {
    purpose?: PaymentPurpose;
    status?: PaymentSubmissionStatus;
    limit: number;
    cursor?: { submittedAt: Date; id: string } | undefined;
  }) {
    const rows = await this.prisma.paymentSubmission.findMany({
      where: {
        ...(query.purpose === undefined ? {} : { purpose: query.purpose }),
        status: query.status ?? 'pending',
        // An intent nobody finished is not work for an admin (§1b step 3:
        // status `pending` means proof uploaded and submitted).
        submittedAt: { not: null },
        ...(query.cursor === undefined
          ? {}
          : {
              OR: [
                { submittedAt: { gt: query.cursor.submittedAt } },
                { submittedAt: query.cursor.submittedAt, id: { gt: query.cursor.id } },
              ],
            }),
      },
      include: {
        payer: {
          select: {
            id: true,
            fullName: true,
            email: true,
            providerProfile: {
              select: { id: true, businessName: true, subscriptionPriceLaari: true },
            },
          },
        },
      },
      orderBy: [{ submittedAt: 'asc' }, { id: 'asc' }],
      take: query.limit + 1,
    });
    return rows;
  }

  createInvoice(data: Prisma.InvoiceUncheckedCreateInput, db: Db = this.prisma): Promise<Invoice> {
    return db.invoice.create({ data });
  }

  findInvoiceBySubmission(paymentSubmissionId: string, db: Db = this.prisma) {
    return db.invoice.findUnique({ where: { paymentSubmissionId } });
  }

  voidInvoice(id: string, reason: string, now: Date, db: Db = this.prisma): Promise<Invoice> {
    return db.invoice.update({
      where: { id },
      data: { voidedAt: now, voidedReason: reason },
    });
  }

  /** Newest first — §Phase 10a's invoice list. Voided invoices stay in it (invariant 8). */
  invoicesFor(
    providerProfileId: string,
    limit: number,
    cursor?: { issuedAt: Date; id: string },
  ): Promise<Invoice[]> {
    return this.prisma.invoice.findMany({
      where: {
        providerProfileId,
        ...(cursor === undefined
          ? {}
          : {
              OR: [
                { issuedAt: { lt: cursor.issuedAt } },
                { issuedAt: cursor.issuedAt, id: { lt: cursor.id } },
              ],
            }),
      },
      orderBy: [{ issuedAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
  }

  /**
   * The next invoice number, from the sequence the migration creates.
   *
   * Deliberately **outside** the confirming transaction: a sequence is
   * non-transactional by design, so a rolled-back confirmation burns a number
   * and leaves a gap. A gap in an invoice series is a bookkeeping curiosity; a
   * duplicate number is a broken document, and a count-based number produces
   * duplicates the first time two admins work the queue at once.
   */
  async nextInvoiceNumber(): Promise<string> {
    const [row] = await this.prisma.$queryRaw<
      { nextval: bigint }[]
    >`SELECT nextval('invoice_number_seq') AS nextval`;
    return `RP-${String(row?.nextval ?? 0n).padStart(6, '0')}`;
  }

  /**
   * §Phase 8a's third trigger needs "7 days after a provider's first
   * published listing", which is `firstPublishedAt` — set once and never
   * cleared (§Phase 8), so a provider who unpublished and republished is not
   * prompted twice.
   */
  async firstPublishedAt(providerProfileId: string): Promise<Date | null> {
    const row = await this.prisma.listing.findFirst({
      where: { providerProfileId, firstPublishedAt: { not: null } },
      orderBy: { firstPublishedAt: 'asc' },
      select: { firstPublishedAt: true },
    });
    return row?.firstPublishedAt ?? null;
  }

  /** Providers with a published listing and no trial yet — the candidate set for the 7-day prompt. */
  candidatesForTrialPrompt(): Promise<
    { id: string; userId: string; firstPublishedAt: Date | null }[]
  > {
    return this.prisma.providerProfile
      .findMany({
        where: {
          listings: { some: { firstPublishedAt: { not: null } } },
          OR: [{ subscription: null }, { subscription: { trialStartedAt: null } }],
        },
        select: {
          id: true,
          userId: true,
          listings: {
            where: { firstPublishedAt: { not: null } },
            orderBy: { firstPublishedAt: 'asc' },
            take: 1,
            select: { firstPublishedAt: true },
          },
        },
      })
      .then((rows) =>
        rows.map((row) => ({
          id: row.id,
          userId: row.userId,
          firstPublishedAt: row.listings[0]?.firstPublishedAt ?? null,
        })),
      );
  }
}
