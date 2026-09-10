import { describe, expect, it } from 'vitest';

import { formatMvr, renderInvoicePdf } from '../src/modules/subscriptions/invoice-pdf.js';

/**
 * §1b step 6: "on confirmation, a downloadable **PDF invoice** is generated."
 *
 * What a test can prove about a PDF without a human looking at it: that the
 * bytes are a structurally valid file a reader will accept — the header, the
 * single page object, a cross-reference table whose offsets are the real byte
 * positions, and the trailer — and that the numbers on it are right. The
 * structural half is asserted here **and independently by poppler**
 * (`pdftotext`), which is what turned up that an em dash was rendering as a
 * question mark; see `docs/decisions/22-phase-8a-subscription-and-trial.md`.
 */

const INVOICE = {
  invoiceNumber: 'RP-000042',
  issuedAt: new Date('2026-09-10T19:30:00.000Z'),
  billedTo: 'Coral Reef Plumbing (Pvt) Ltd',
  description: 'Provider subscription — 30 days',
  periodStart: new Date('2026-09-10T19:30:00.000Z'),
  periodEnd: new Date('2026-10-10T19:30:00.000Z'),
  amountLaari: 7_500,
  referenceCode: 'RP-K7M2-9QXW',
};

/** The xref table's offsets, read back out of the file the way a reader reads them. */
function crossReferenceOffsets(pdf: string): number[] {
  const start = Number(/startxref\s+(\d+)/.exec(pdf)?.[1] ?? -1);
  const table = pdf.slice(start);
  return [...table.matchAll(/^(\d{10}) 00000 n $/gm)].map((m) => Number(m[1]));
}

describe('§1b step 6 — the PDF invoice', () => {
  it('is a structurally valid single-page PDF whose xref offsets point at the objects', () => {
    const bytes = renderInvoicePdf(INVOICE);
    const pdf = bytes.toString('latin1');

    expect(pdf.startsWith('%PDF-1.4')).toBe(true);
    expect(pdf.trimEnd().endsWith('%%EOF')).toBe(true);
    expect(pdf).toContain('/Type /Page');
    expect(pdf).toContain('/Count 1');

    // The offsets are the assertion that matters: a PDF whose xref is off by
    // a byte is technically parseable by one reader and rejected by another,
    // which is exactly the failure a "does it contain the text?" test misses.
    const offsets = crossReferenceOffsets(pdf);
    expect(offsets).toHaveLength(6);
    offsets.forEach((offset, index) => {
      expect(pdf.slice(offset)).toMatch(new RegExp(`^${String(index + 1)} 0 obj`));
    });

    // The content stream's declared length must match its real byte length,
    // or a reader stops mid-page.
    const declared = Number(/\/Length (\d+) >>\s*\nstream\n/.exec(pdf)?.[1] ?? -1);
    const stream = /stream\n([\s\S]*?)\nendstream/.exec(pdf)?.[1] ?? '';
    expect(Buffer.byteLength(stream, 'latin1')).toBe(declared);
  });

  it('carries the numbers and the reference code, and reads MVR from integer laari', () => {
    const pdf = renderInvoicePdf(INVOICE).toString('latin1');
    expect(pdf).toContain('RP-000042');
    expect(pdf).toContain('RP-K7M2-9QXW');
    // Invariant 7: laari in, a rendered rufiyaa string out, no float anywhere.
    expect(pdf).toContain('MVR 75.00');
    expect(formatMvr(15_000)).toBe('MVR 150.00');
    expect(formatMvr(7_500)).toBe('MVR 75.00');
    expect(formatMvr(150_005)).toBe('MVR 1500.05');
  });

  it('presents dates in Maldives time, not the server timezone', () => {
    // §Phase 9a's convention: stored UTC, presented UTC+5. 19:30 UTC on the
    // 10th is half past midnight on the 11th in Malé, and a document that
    // said the 10th would disagree with the app beside it.
    const pdf = renderInvoicePdf(INVOICE).toString('latin1');
    expect(pdf).toContain('11 Sep 2026');
    expect(pdf).toContain('11 Oct 2026');
  });

  it('escapes a business name that would otherwise break the file', () => {
    // `(`, `)` and `\` are literal-string syntax in PDF. An unescaped
    // parenthesis in a provider's own business name would truncate the
    // document at that character — and "(Pvt) Ltd" is the commonest company
    // suffix in the Maldives, so this is the normal case, not an edge one.
    const pdf = renderInvoicePdf({
      ...INVOICE,
      billedTo: String.raw`Fehi (Pvt) Ltd \ Malé`,
    }).toString('latin1');
    expect(pdf).toContain(String.raw`(Fehi \(Pvt\) Ltd \\ Malé)`);

    const offsets = crossReferenceOffsets(pdf);
    offsets.forEach((offset, index) => {
      expect(pdf.slice(offset)).toMatch(new RegExp(`^${String(index + 1)} 0 obj`));
    });
  });

  it('renders an em dash rather than a question mark, and substitutes what it cannot draw', () => {
    // The base-14 fonts carry WinAnsi, so the punctuation this codebase's copy
    // is full of is mapped to its single-byte position. Thaana is genuinely
    // not representable without an embedded font — Dhivehi localisation is
    // out of v1 scope — so it degrades to `?` rather than producing a
    // corrupt file.
    const pdf = renderInvoicePdf({ ...INVOICE, billedTo: 'ފެހި ފިހާރަ' }).toString('latin1');
    expect(pdf).toContain(String.fromCharCode(0x97)); // the em dash in the description
    expect(pdf).toMatch(/\(\?+ \?+\)/);
  });

  it('carries a marked placeholder where the registration details belong, never an invented number', () => {
    // §1d: legal and registration text is "always inserted as clearly-marked,
    // structurally-correct placeholder pending real legal review, never
    // fabricated" — the same convention `LegalPlaceholderScreen` uses.
    const pdf = renderInvoicePdf(INVOICE).toString('latin1');
    expect(pdf).toContain('placeholder');
    expect(pdf).toContain('pending legal review');
  });

  it('says what actually happened, and never that a payment was verified', () => {
    // §1b: the admin confirming *is* the verification, and no copy anywhere
    // may imply a platform-level certainty (root CLAUDE.md 1c).
    const pdf = renderInvoicePdf(INVOICE).toString('latin1');
    expect(pdf).toContain('Paid by bank transfer and confirmed by RaajjePro.');
    expect(pdf.toLowerCase()).not.toContain('verified');
  });
});
