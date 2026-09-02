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
    ("pre-Round-25 category", r"(?<![A-Za-z])Gardening(?![A-Za-z])|'Computer'|>Computer<|&quot;Computer&quot;",
     "Round 25: Pest Control replaced Gardening, and Computer is now Appliance Repair."),
    ("pre-Round-26 category", r"'Events'|>Events<|&quot;Events&quot;",
     "Round 26: Home Repairs replaced Events."),
    ("pre-Round-27 chat claim", r"never torn down|stays open after completion",
     "Round 27: the booking thread locks read-only 7 days after completion."),
    ("callback on an ineligible category", r"cat:\s*'(Cleaning|Beauty|Fitness|Photography|Moving|Boat Charter)'[^}]*\b(cb|callback):\s*true|\b(cb|callback):\s*true[^}]*cat:\s*'(Cleaning|Beauty|Fitness|Photography|Moving|Boat Charter)'",
     "Round 28: callback is Plumbing, Electrical, AC Repair, Appliance Repair, Pest Control and Home Repairs only."),
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
    ("Round-23 emergency marker on a card", r"Emergency available|emergency filter",
     "Dispatch broadcasts to every eligible provider, so a card can never advertise it. "
     "Removed from ServiceCard in Round 23 and from Home's own card markup in Round 33."),
]

# (label, pattern, why) — a hit is a warning worth a human look.
SUSPECT = [
    ("possible phone number rendered", r">\s*[79]\d{6}\s*<",
     "No screen shows a phone number except the emergency reveal."),
    ("guarantee language on a provider claim", r"[Gg]uaranteed\s+(warranty|insurance)",
     "A provider warranty is attributed, never guaranteed."),
    # Invariant 15: "Never print an island total in UI copy." The register is revised and any
    # printed count is wrong the moment it changes; the picker is a search, so the size is
    # never the user's problem. Warn-only until Round 41 clears the five screens carrying it.
    ("island total printed in UI copy", r"all\s+\d+\s+inhabited islands|\d+\s+inhabited islands",
     "Invariant 15 forbids an island total in UI copy - say 'Sample list' with no number."),
]

# §1c booking modes. `slot` (shown as "instant") is these three categories and no others;
# every other category quotes, so it is `request`. A Plumbing card reading "Book instantly"
# promises a published-time booking the category does not have.
SLOT_CATEGORIES = {"Cleaning", "Beauty", "Fitness"}
REQUEST_CATEGORIES = {
    "Plumbing", "Electrical", "AC Repair", "Photography", "Pest Control",
    "Appliance Repair", "Moving", "Home Repairs", "Boat Charter",
}

# Round 23: there is no emergency search filter. Dispatch broadcasts to every eligible
# provider, so filtering a browse list by "Emergency" offers a cut that does not exist -
# and emergency is reached from its own distinct entry on Home and Explore instead.
# A chip named "Emergency" sitting in a filter row is that forbidden filter, which the
# text rule above misses because the word appears alone rather than as "emergency filter".
FILTER_LIST = re.compile(r"(?:QUICK|CHIPS?|FILTERS?|TOGGLES?)\w*\s*=\s*\[(.*?)\]", re.S | re.I)

def emergency_filter_chips(s):
    """A browse/filter chip list offering Emergency as one of its options."""
    out = []
    for m in FILTER_LIST.finditer(s):
        body = m.group(1)
        for c in re.finditer(r"['\"]([^'\"]{2,40})['\"]", body):
            if re.fullmatch(r"\s*emergency\s*", c.group(1), re.I):
                out.append(c.group(1))
    return out

# Verification is a PROVIDER attribute. `verificationTier` lives on the provider profile and
# means "ID and trade checked by RaajjePro" - a customer has no tier, so a badge beside a
# customer's name asserts a trust signal the system never produces. VerificationBadge cannot
# defend itself here: it renders whatever tier it is handed. So the check is by screen - these
# are the provider-side screens where the person shown is the CUSTOMER.
CUSTOMER_SUBJECT_SCREENS = {
    "Booking Request", "Payment Received", "Mark Complete",
    "Provider Emergency", "Propose Time and Price",
}

# On a customer-subject screen the only two people on show are the signed-in provider
# and the customer. So any OTHER provider persona appearing there is standing in the
# customer's slot - which is how Mariyam Shifa, the cleaner, ended up being billed as
# the customer on three separate screens. Names come from the seed rather than a list
# here, so this tracks session.js instead of drifting from it.
SESSION_PROVIDER = "Ibrahim Rasheed"  # the seed's signed-in provider; legitimately on show

def _seed_providers(path):
    seed = pathlib.Path(path).parent / "session.js"
    if not seed.exists():
        return set()
    try:
        txt = seed.read_text(encoding="utf-8")
    except OSError:
        return set()
    names = set(re.findall(r"provider:\s*'([^']+)'", txt))
    return {n for n in names if n != SESSION_PROVIDER}

def provider_as_customer(path, s):
    """A provider persona other than the signed-in one, on a screen whose subject is the customer."""
    stem = pathlib.Path(path).name.replace(".dc.html", "")
    if stem not in CUSTOMER_SUBJECT_SCREENS:
        return []
    # Full name only. Matching on the first name collides with the customer persona -
    # "Aishath Leela" is a Beauty provider and "Aishath" is the customer, so a first-name
    # match flags every screen she legitimately appears on.
    return sorted(n for n in _seed_providers(path) if n in s)

def badge_on_a_customer(path, s):
    """A VerificationBadge mounted on a screen whose subject is the customer."""
    stem = pathlib.Path(path).name.replace(".dc.html", "")
    if stem not in CUSTOMER_SUBJECT_SCREENS:
        return []
    n = len(re.findall(r'dc-import\s+name="VerificationBadge"', s))
    return ["%d badge(s) on %s" % (n, stem)] if n else []

def mode_mismatches(s):
    """Object literals carrying both a category and a booking mode that contradict §1c."""
    out = []
    for m in re.finditer(r"\{[^{}]*\}", s):
        o = m.group(0)
        c = re.search(r"cat(?:egory)?:\s*'([^']+)'", o)
        d = re.search(r"mode:\s*'(instant|slot|request)'", o)
        if not (c and d):
            continue
        cat, mode = c.group(1), d.group(1)
        norm = "slot" if mode in ("instant", "slot") else "request"
        if cat in SLOT_CATEGORIES and norm != "slot":
            out.append("%s is slot-mode, found %s" % (cat, mode))
        elif cat in REQUEST_CATEGORIES and norm != "request":
            out.append("%s quotes, so it is request-mode, found %s" % (cat, mode))
    return out


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

    for who in provider_as_customer(path, s):
        warns.append(("provider persona shown as the customer (%s)" % who,
                      "This screen's subject is the customer, so a provider persona here is in the "
                      "wrong role. Check it against session.js rather than renaming ad hoc."))

    for detail in badge_on_a_customer(path, s):
        warns.append(("verification badge shown for a customer (%s)" % detail,
                      "verificationTier is a provider attribute - a customer has no tier, so the "
                      "badge claims a check that never happened. Warn-only until Round 41 removes it."))

    for chip in emergency_filter_chips(s):
        warns.append(("emergency offered as a browse filter (%s)" % chip,
                      "Round 23 removed the emergency search filter - dispatch never targets a "
                      "provider, so the filter advertised a cut that does not exist. Emergency has "
                      "its own entry on Home and Explore. Warn-only until Round 41 removes the chip."))

    for detail in mode_mismatches(s):
        fails.append(("booking mode contradicts the category", detail + " — §1c. "
                      "Only Cleaning, Beauty and Fitness publish bookable slots; "
                      "every other category quotes first, so it is request-mode."))

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
