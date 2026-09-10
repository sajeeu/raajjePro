/**
 * The PDF §1b step 6 requires: "on confirmation, a downloadable **PDF
 * invoice** is generated."
 *
 * ## Why this writes the file rather than importing a library
 *
 * The document is a single page of left-aligned text in one font. Writing it
 * out is ~80 lines of a format whose text-only subset has been stable since
 * 1993, against a dependency that brings a font subsetter, a stream layer and
 * a vector graphics API to draw fourteen lines of Helvetica — and every
 * dependency in this repository is pinned, audited in CI and eventually
 * somebody's upgrade. That trade goes the other way the moment an invoice
 * needs a logo, a table or a second page, and the boundary for that is
 * `renderInvoicePdf` returning bytes: swapping the renderer changes this file
 * and nothing else.
 *
 * ## What it does not do
 *
 * **Non-Latin text is not representable.** The base-14 fonts a PDF reader is
 * required to have carry WinAnsi, so a Thaana business name would render as
 * mojibake; unrepresentable characters become `?` rather than silently
 * producing a corrupt file. Dhivehi/Thaana localisation is explicitly out of
 * v1 scope (root CLAUDE.md), and the phase that puts it back in scope is the
 * one that embeds a font here.
 */

/** A4 at 72dpi, which is what a PDF point is. */
const PAGE_WIDTH = 595;
const PAGE_HEIGHT = 842;
const MARGIN = 56;

export interface InvoiceDocument {
  invoiceNumber: string;
  issuedAt: Date;
  /** Who the invoice is addressed to — the provider's own business or account name. */
  billedTo: string;
  /** What was bought, in words. One line. */
  description: string;
  periodStart: Date;
  periodEnd: Date;
  amountLaari: number;
  /** The code the provider put on their bank transfer (§1b step 2). */
  referenceCode: string;
}

/**
 * §1d: legal and registration text is "always inserted as clearly-marked,
 * structurally-correct placeholder pending real legal review, never
 * fabricated". A company registration number and a tax line are exactly that,
 * so the invoice carries the marker the Flutter legal screens carry rather
 * than an invented number.
 */
const ISSUER_DETAILS_PLACEHOLDER = '[ placeholder — registration details pending legal review ]';

export function renderInvoicePdf(invoice: InvoiceDocument): Buffer {
  const lines: TextLine[] = [
    { text: 'RaajjePro', size: 20, bold: true, gap: 6 },
    { text: ISSUER_DETAILS_PLACEHOLDER, size: 8, gap: 34 },

    { text: 'Invoice', size: 14, bold: true, gap: 18 },
    { text: `Invoice number   ${invoice.invoiceNumber}`, size: 11, gap: 4 },
    { text: `Issued           ${formatDate(invoice.issuedAt)}`, size: 11, gap: 4 },
    { text: `Reference        ${invoice.referenceCode}`, size: 11, gap: 22 },

    { text: 'Billed to', size: 11, bold: true, gap: 4 },
    { text: invoice.billedTo, size: 11, gap: 22 },

    { text: 'Description', size: 11, bold: true, gap: 4 },
    { text: invoice.description, size: 11, gap: 4 },
    {
      text: `Period           ${formatDate(invoice.periodStart)} to ${formatDate(invoice.periodEnd)}`,
      size: 11,
      gap: 22,
    },

    { text: `Total   ${formatMvr(invoice.amountLaari)}`, size: 14, bold: true, gap: 22 },

    // What actually happened, in the words §1b's mechanism supports: a manual
    // bank transfer, confirmed by a person. Nothing here may read as an
    // automated verification (§1b: "the admin confirming *is* the
    // verification").
    { text: 'Paid by bank transfer and confirmed by RaajjePro.', size: 10, gap: 4 },
    { text: 'This invoice covers a RaajjePro provider subscription only.', size: 10, gap: 0 },
  ];

  return assemble(contentStream(lines));
}

/** Integer laari to the string a provider reads (invariant 7 — never a float on the way here or out). */
export function formatMvr(amountLaari: number): string {
  const rufiyaa = Math.trunc(amountLaari / 100);
  const laari = Math.abs(amountLaari % 100);
  return `MVR ${String(rufiyaa)}.${String(laari).padStart(2, '0')}`;
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/**
 * Maldives time, which is the plan's presentation rule (§Phase 9a: "all times
 * stored UTC, presented in Maldives time (UTC+5)"). A single-timezone market
 * with no DST makes this a fixed offset, so the shift is arithmetic and the
 * getters stay UTC — using local getters would make the document depend on
 * the server's timezone.
 */
const MALDIVES_OFFSET_MINUTES = 5 * 60;

function formatDate(date: Date): string {
  const shifted = new Date(date.getTime() + MALDIVES_OFFSET_MINUTES * 60_000);
  return `${String(shifted.getUTCDate()).padStart(2, '0')} ${MONTHS[shifted.getUTCMonth()] ?? ''} ${String(
    shifted.getUTCFullYear(),
  )}`;
}

interface TextLine {
  text: string;
  size: number;
  bold?: boolean;
  /** Extra space below this line, on top of its own height. */
  gap: number;
}

function contentStream(lines: TextLine[]): string {
  let y = PAGE_HEIGHT - MARGIN;
  const ops: string[] = [];
  for (const line of lines) {
    y -= line.size;
    ops.push(
      'BT',
      `/${line.bold === true ? 'F2' : 'F1'} ${String(line.size)} Tf`,
      `1 0 0 1 ${String(MARGIN)} ${String(y)} Tm`,
      `(${escapeText(line.text)}) Tj`,
      'ET',
    );
    y -= line.gap;
  }
  return ops.join('\n');
}

/**
 * The punctuation this codebase's copy actually uses, at the single-byte
 * positions WinAnsiEncoding puts it. Without this an em dash — which every
 * line of copy in this repository is full of — silently becomes a question
 * mark, and "Provider subscription ? 30 days" is the kind of detail that
 * makes a real document look broken.
 */
const WINANSI_PUNCTUATION = new Map<string, string>([
  ['\u2014', String.fromCharCode(0x97)], // em dash
  ['\u2013', String.fromCharCode(0x96)], // en dash
  ['\u2018', String.fromCharCode(0x91)],
  ['\u2019', String.fromCharCode(0x92)],
  ['\u201c', String.fromCharCode(0x93)],
  ['\u201d', String.fromCharCode(0x94)],
  ['\u2026', String.fromCharCode(0x85)], // ellipsis
  ['\u00a0', ' '],
]);

/**
 * PDF literal strings escape the backslash and both parentheses; anything
 * outside WinAnsi's single-byte range becomes `?`, because the base-14 fonts
 * cannot draw it and a raw multi-byte sequence would corrupt the string.
 */
function escapeText(text: string): string {
  let out = '';
  for (const char of text) {
    const mapped = WINANSI_PUNCTUATION.get(char);
    if (mapped !== undefined) {
      out += mapped;
      continue;
    }
    const code = char.codePointAt(0) ?? 0;
    if (char === '\\' || char === '(' || char === ')') out += `\\${char}`;
    else if (code >= 32 && code <= 255) out += char;
    else out += '?';
  }
  return out;
}

/**
 * The file itself: seven objects, a cross-reference table and a trailer.
 *
 * The xref offsets have to be the real byte positions of each object, which
 * is why the objects are appended to a buffer that also records where each one
 * started — computing them from string lengths afterwards is how a PDF ends up
 * technically parseable by one reader and rejected by another.
 */
function assemble(content: string): Buffer {
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${String(PAGE_WIDTH)} ${String(PAGE_HEIGHT)}] ` +
      '/Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>',
    `<< /Length ${String(Buffer.byteLength(content, 'latin1'))} >>\nstream\n${content}\nendstream`,
  ];

  const parts: Buffer[] = [];
  const offsets: number[] = [];
  let length = 0;
  const push = (text: string) => {
    const buffer = Buffer.from(text, 'latin1');
    parts.push(buffer);
    length += buffer.length;
  };

  // The comment line of high bytes is conventional: it tells a transfer
  // program that reads the first bytes of a file that this one is binary.
  push('%PDF-1.4\n%âãÏÓ\n');
  objects.forEach((body, index) => {
    offsets.push(length);
    push(`${String(index + 1)} 0 obj\n${body}\nendobj\n`);
  });

  const xrefOffset = length;
  const xref = [
    'xref',
    `0 ${String(objects.length + 1)}`,
    '0000000000 65535 f ',
    ...offsets.map((offset) => `${String(offset).padStart(10, '0')} 00000 n `),
  ].join('\n');
  push(
    `${xref}\ntrailer\n<< /Size ${String(objects.length + 1)} /Root 1 0 R >>\nstartxref\n${String(
      xrefOffset,
    )}\n%%EOF\n`,
  );

  return Buffer.concat(parts);
}
