#!/usr/bin/env python3
"""Validate a Design Composer .dc.html against structure and the plan's locked rules.

    python3 docs/design/verify-dc.py mockups/design-composer/*.dc.html

Exit 0 if every file passes. Exit 1 on any FAIL. WARNs never fail the run.
"""
import sys, re, json, html, pathlib

# (label, pattern, why[, exclude_near]) — a hit is a failure unless exclude_near
# matches the surrounding text. Email verification is real and allowed to say so;
# provider-tier and phone 'Verified' are not.
FORBIDDEN = [
    ("payment claimed as verified", r"Payment verified|Payment Verified|Paid\s*✓|payment_verified",
     "RaajjePro cannot see a bank transfer. Use 'Provider confirmed receipt'."),
    ("bare Verified badge", r">\s*Verified\s*<|Verified [Pp]rovider(?!s\b)",
     "Verification is three tiers, each with its own copy.",
     r"mail|Mail|@"),
    ("phone shown as verified", r"(?is)phone.{0,400}?(>\s*Verified\s*<|verified\s+number)",
     "Uniqueness is not ownership. A phone number is never rendered as verified."),
    ("Tuition category", r"Tuition",
     "There are twelve categories and Tuition is not one. Boat Charter replaced it."),
    ("encryption claim", r"[Ee]ncrypt",
     "Chat is admin-readable in a dispute. Say 'your contact details are never shared'."),
    ("editorial provider label", r"Prone to|Unreliable|Top rated|Best value|Most reliable|Recommended provider",
     "Conduct is numbers only. Labels were considered and rejected as automated accusations."),
    ("wrong currency", r"(?<![A-Za-z])(Rf|MRF|USD)\s*[0-9]|\$[0-9]",
     "Money is written MVR, code first."),
    ("Moving on a 120-minute response window", r"win:\s*120",
     "Round 22: all four emergency categories respond in 30 minutes. 120 described arrival."),
    ("contact-info endpoint", r"contact-info",
     "GET /v1/bookings/:id/contact-info was deleted and must not reappear."),
]

# (label, pattern, why) — a hit is a warning worth a human look.
SUSPECT = [
    ("possible phone number rendered", r">\s*[79]\d{6}\s*<",
     "No screen shows a phone number except the emergency reveal."),
    ("guarantee language on a provider claim", r"[Gg]uaranteed\s+(warranty|insurance)",
     "A provider warranty is attributed, never guaranteed."),
]

def check(path):
    p = pathlib.Path(path)
    s = p.read_text(encoding="utf-8")
    fails, warns = [], []

    # --- structure ---
    if '<script src="./support.js"></script>' not in s:
        fails.append(("support.js line missing or altered",
                      "The editor swaps this for its runtime; it must stay verbatim."))
    if "<x-dc>" not in s or "</x-dc>" not in s:
        fails.append(("no <x-dc> wrapper", "Not a valid Design Component."))

    m = re.search(r'data-props="([^"]*)"', s)
    if not m:
        warns.append(("no data-props", "Fine for a static artboard; check it was intended."))
    else:
        try:
            json.loads(html.unescape(m.group(1)))
        except Exception as e:
            fails.append(("data-props does not parse", str(e)))

    for tag in ("sc-if", "sc-for"):
        o = len(re.findall(r"<%s[ >]" % tag, s))
        c = len(re.findall(r"</%s>" % tag, s))
        if o != c:
            fails.append(("%s unbalanced" % tag, "%d open, %d close" % (o, c)))

    # --- plan invariants ---
    for entry in FORBIDDEN:
        label, pat, why = entry[0], entry[1], entry[2]
        near = entry[3] if len(entry) > 3 else None
        hits = []
        for m in re.finditer(pat, s):
            if near:
                a, b = max(0, m.start() - 200), min(len(s), m.end() + 200)
                if re.search(near, s[a:b]):
                    continue  # legitimate in this context
            hits.append(m.group(0))
        if hits:
            fails.append((label + " (%d)" % len(hits), why))
    for label, pat, why in SUSPECT:
        if re.search(pat, s):
            warns.append((label, why))

    return fails, warns

def main(paths):
    if not paths:
        print(__doc__); return 1
    bad = 0
    for path in paths:
        fails, warns = check(path)
        name = pathlib.Path(path).name
        if fails:
            bad += 1
            print("FAIL  %s" % name)
            for label, why in fails:
                print("        %-44s %s" % (label, why))
        else:
            print("ok    %s" % name)
        for label, why in warns:
            print("  warn  %-44s %s" % (label, why))
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
