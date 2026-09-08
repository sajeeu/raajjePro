"""Render a markdown document in this repository to a PDF.

    python3 scripts/md2pdf.py <input.md> <output.pdf> ["running footer"]

Handles what the documents here actually use: headings, paragraphs, bullet
and numbered lists, blockquotes (rendered as a callout), pipe tables, fenced
code blocks, horizontal rules, and inline bold / italic / code.

Does NOT handle: nested lists, images, links (the text survives, the URL is
dropped), footnotes, or HTML. It uses the built-in Type 1 fonts, which carry
no emoji — any character outside WinAnsi is stripped rather than rendered as
a black box, so check the output if a document is heavy with symbols.

The point of keeping the generator rather than a generated PDF: a committed
PDF is a copy that drifts from its source, and this repository has been
bitten by that five times. Regenerate instead."""
import re
import sys

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (HRFlowable, KeepTogether, ListFlowable,
                                ListItem, PageBreak, Paragraph,
                                SimpleDocTemplate, Spacer, Table, TableStyle)

SRC, OUT = sys.argv[1], sys.argv[2]
# Optional third argument: the running footer. Defaults to the document's own
# H1. Pass it when a document needs something said on every page rather than
# once at the top - the counsel briefing needs its "not legal advice"
# disclaimer to travel with every printed page.
FOOT_ARG = sys.argv[3] if len(sys.argv) > 3 else None

INK = colors.HexColor("#12213A")
MUTE = colors.HexColor("#5B6B84")
RULE = colors.HexColor("#D8DFE9")
BANNER = colors.HexColor("#F2F5F9")
CODEBG = colors.HexColor("#F7F8FA")
OPEN, CLOSE = "\x01", "\x02"


def safe(t):
    """Drop anything the built-in Type 1 fonts cannot draw.

    WinAnsi covers Latin-1 plus the common typographic marks. Everything
    beyond it — emoji, arrows, mathematical symbols — renders as a solid
    black box, which is worse than its absence.
    """
    return "".join(c for c in t if ord(c) < 0x180 or c in "\u2013\u2014\u2018\u2019\u201c\u201d\u2022\u2026\u20ac\u2122")


def inline(t):
    """Markdown emphasis to ReportLab markup, with < > neutralised first."""
    t = safe(t)
    t = t.replace("&", "&amp;").replace("<", "").replace(">", "")
    t = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", t)
    t = re.sub(r"\*\*(.+?)\*\*", OPEN + "b" + CLOSE + r"\1" + OPEN + "/b" + CLOSE, t)
    t = re.sub(r"`(.+?)`",
               OPEN + 'font face="Courier" size="9"' + CLOSE + r"\1" + OPEN + "/font" + CLOSE, t)
    t = re.sub(r"(?<![\w*])\*([^*]+?)\*(?![\w*])",
               OPEN + "i" + CLOSE + r"\1" + OPEN + "/i" + CLOSE, t)
    return t.replace(OPEN, "<").replace(CLOSE, ">")


S = {
    "h1": ParagraphStyle("h1", fontName="Helvetica-Bold", fontSize=19, leading=23,
                         textColor=INK, spaceAfter=10),
    "h2": ParagraphStyle("h2", fontName="Helvetica-Bold", fontSize=12.5, leading=15.5,
                         textColor=INK, spaceBefore=17, spaceAfter=5),
    "h3": ParagraphStyle("h3", fontName="Helvetica-Bold", fontSize=10.3, leading=13,
                         textColor=INK, spaceBefore=11, spaceAfter=3),
    "body": ParagraphStyle("body", fontName="Helvetica", fontSize=9.6, leading=14,
                           textColor=INK, alignment=TA_LEFT, spaceAfter=7),
    "quote": ParagraphStyle("quote", fontName="Helvetica", fontSize=9.3, leading=13.6,
                            textColor=INK, leftIndent=8, rightIndent=8,
                            spaceBefore=3, spaceAfter=3),
    "li": ParagraphStyle("li", fontName="Helvetica", fontSize=9.6, leading=13.6,
                         textColor=INK, spaceAfter=3.5),
    "th": ParagraphStyle("th", fontName="Helvetica-Bold", fontSize=8.6, leading=11.5,
                         textColor=INK),
    "td": ParagraphStyle("td", fontName="Helvetica", fontSize=8.6, leading=11.5,
                         textColor=INK),
    "code": ParagraphStyle("code", fontName="Courier", fontSize=8.4, leading=11.5,
                           textColor=INK),
}

lines = open(SRC, encoding="utf-8").read().split("\n")
story, i = [], 0


def flush_para(buf):
    if buf:
        story.append(Paragraph(inline(" ".join(buf)), S["body"]))
    return []


buf = []
while i < len(lines):
    ln = lines[i]

    if ln.startswith("```"):
        buf = flush_para(buf)
        i += 1
        code = []
        while i < len(lines) and not lines[i].startswith("```"):
            code.append(safe(lines[i]))
            i += 1
        i += 1
        cell = Paragraph(
            "<br/>".join(x.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                         .replace(" ", "&nbsp;") or "&nbsp;" for x in code),
            S["code"])
        t = Table([[cell]], colWidths=[170 * mm - 6 * mm], hAlign="LEFT")
        t.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), CODEBG),
            ("BOX", (0, 0), (-1, -1), 0.4, RULE),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("RIGHTPADDING", (0, 0), (-1, -1), 8),
            ("TOPPADDING", (0, 0), (-1, -1), 6),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ]))
        story.append(t)
        story.append(Spacer(1, 8))
        continue

    if ln.startswith("|") and i + 1 < len(lines) and re.match(r"^\|[\s:|-]+\|?\s*$", lines[i + 1]):
        buf = flush_para(buf)
        rows = []
        header = [c.strip() for c in ln.strip().strip("|").split("|")]
        i += 2
        while i < len(lines) and lines[i].startswith("|"):
            rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
            i += 1
        ncol = max([len(header)] + [len(r) for r in rows])
        header += [""] * (ncol - len(header))
        data = [[Paragraph(inline(c), S["th"]) for c in header]]
        for r in rows:
            r += [""] * (ncol - len(r))
            data.append([Paragraph(inline(c), S["td"]) for c in r])
        avail = 170 * mm
        first = avail * (0.30 if ncol > 2 else 0.42)
        widths = [first] + [(avail - first) / (ncol - 1)] * (ncol - 1) if ncol > 1 else [avail]
        t = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
        t.setStyle(TableStyle([
            ("LINEBELOW", (0, 0), (-1, 0), 0.8, INK),
            ("LINEBELOW", (0, 1), (-1, -2), 0.25, RULE),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("TOPPADDING", (0, 0), (-1, -1), 3.5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
            ("LEFTPADDING", (0, 0), (-1, -1), 0),
            ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ]))
        story.append(t)
        story.append(Spacer(1, 9))
        continue

    if ln.startswith("> "):
        buf = flush_para(buf)
        q = []
        while i < len(lines) and (lines[i].startswith("> ") or lines[i].strip() == ">"):
            q.append(lines[i][2:].strip())
            i += 1
        cell = Paragraph(inline(" ".join(x for x in q if x)), S["quote"])
        t = Table([[cell]], colWidths=[170 * mm - 6 * mm], hAlign="LEFT")
        t.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), BANNER),
            ("LINEBEFORE", (0, 0), (0, -1), 2.2, INK),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("RIGHTPADDING", (0, 0), (-1, -1), 8),
            ("TOPPADDING", (0, 0), (-1, -1), 7),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
        ]))
        story.append(t)
        story.append(Spacer(1, 9))
        continue

    if ln.startswith("- "):
        buf = flush_para(buf)
        items = []
        while i < len(lines) and (lines[i].startswith("- ") or
                                  (lines[i].startswith("  ") and lines[i].strip() and items)):
            if lines[i].startswith("- "):
                items.append([lines[i][2:].strip()])
            else:
                items[-1].append(lines[i].strip())
            i += 1
        story.append(ListFlowable(
            [ListItem(Paragraph(inline(" ".join(x)), S["li"]), leftIndent=14) for x in items],
            bulletType="bullet", bulletChar="•", bulletFontSize=8,
            leftIndent=12, bulletOffsetY=-1, spaceAfter=7))
        continue

    m = re.match(r"^(\d+)\.\s+(.*)$", ln)
    if m:
        buf = flush_para(buf)
        items, start = [], int(m.group(1))
        while i < len(lines):
            mm_ = re.match(r"^(\d+)\.\s+(.*)$", lines[i])
            if mm_:
                items.append([mm_.group(2).strip()])
                i += 1
            elif lines[i].startswith("   ") and lines[i].strip() and items:
                items[-1].append(lines[i].strip())
                i += 1
            else:
                break
        story.append(ListFlowable(
            [ListItem(Paragraph(inline(" ".join(x)), S["li"]), leftIndent=18) for x in items],
            bulletType="1", start=start, bulletFontName="Helvetica-Bold",
            bulletFontSize=9.6, leftIndent=16, spaceAfter=7))
        continue

    if ln.startswith("### "):
        buf = flush_para(buf)
        story.append(Paragraph(inline(ln[4:]), S["h3"]))
    elif ln.startswith("## "):
        buf = flush_para(buf)
        story.append(Paragraph(inline(ln[3:]), S["h2"]))
    elif ln.startswith("# "):
        buf = flush_para(buf)
        story.append(Paragraph(inline(ln[2:]), S["h1"]))
    elif ln.strip() == "---":
        buf = flush_para(buf)
        story.append(Spacer(1, 4))
        story.append(HRFlowable(width="100%", thickness=0.6, color=RULE))
        story.append(Spacer(1, 6))
    elif ln.strip() == "":
        buf = flush_para(buf)
    else:
        buf.append(ln.strip())
    i += 1
flush_para(buf)


# The running footer names the document itself. It was hardcoded to the first
# document this rendered, which then footered an admin-load costing analysis
# as "briefing for counsel - not legal advice" - wrong, and the kind of wrong
# a reader would believe.
TITLE = next((safe(l[2:].strip()) for l in lines if l.startswith("# ")), "RaajjePro")
FOOT = FOOT_ARG or (f"RaajjePro - {TITLE}" if not TITLE.startswith("RaajjePro") else TITLE)


def footer(canv, doc):
    canv.saveState()
    canv.setFont("Helvetica", 7.3)
    canv.setFillColor(MUTE)
    canv.drawString(20 * mm, 12 * mm, FOOT[:110])
    canv.drawRightString(A4[0] - 20 * mm, 12 * mm, str(canv.getPageNumber()))
    canv.setStrokeColor(RULE)
    canv.setLineWidth(0.4)
    canv.line(20 * mm, 16 * mm, A4[0] - 20 * mm, 16 * mm)
    canv.restoreState()


doc = SimpleDocTemplate(OUT, pagesize=A4, leftMargin=20 * mm, rightMargin=20 * mm,
                        topMargin=18 * mm, bottomMargin=20 * mm,
                        title=TITLE, author="RaajjePro")
doc.build(story, onFirstPage=footer, onLaterPages=footer)
print("built")
