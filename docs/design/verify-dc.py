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
    # Round 44 renamed the slot-mode card affordance. "Book instantly" named an immediacy the
    # state machine does not produce: a slot booking enters `requested` and waits for the
    # provider on the same 24-hour clock as a request. Cleared by Round 44 - LOCKED.
    ("pre-Round-44 slot affordance", r"Book instantly|confirmed straight away|books? instantly",
     "Round 44: the slot label is 'Pick a time'. A slot booking still needs the provider to accept."),
    # Round 27 amended the never-torn-down rule: the booking thread stays open for the life of
    # the booking and 7 days after completion - the callback window - then locks read-only.
    # Copy promising an unlimited thread is pre-Round-27, and it misleads at the worst moment,
    # since it appears where a customer is being told what recourse they still have.
    ("pre-Round-27 claim that the chat never ends",
     r"chat never (expires|ends|closes)|never torn down|thread never (expires|ends|closes)|stays open after completion",
     "Round 27: the thread locks read-only 7 days after completion. Say the window, not 'never'."),
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
    # Invariant 15: "Never print an island total in UI copy." The register is revised, so any
    # printed count is wrong the moment it changes; and the picker is a search rather than a
    # browsable list, so its size was never the reader's problem. Cleared by Round 41 - LOCKED.
    ("island total printed in UI copy", r"\d+\s+inhabited islands",
     "Invariant 15 forbids an island total in UI copy - say 'every inhabited island'."),
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

# A persona name spelled almost right reads as a second person. "Aishath Naeem" for
# "Aishath Naeema" is one character, and it appeared on exactly one screen out of six.
# Catch a seed name that has lost its last character and is not part of a longer word.
def near_miss_persona(path, s):
    """A seed persona name rendered one character short."""
    seed = pathlib.Path(path).parent / "session.js"
    if not seed.exists():
        return []
    try:
        txt = seed.read_text(encoding="utf-8")
    except OSError:
        return []
    names = set(re.findall(r"(?:provider|name):\s*'([A-Z][a-z]+ [A-Z][a-z]+)'", txt))
    out = []
    for n in names:
        if len(n) < 9:
            continue
        truncated = n[:-1]
        if re.search(re.escape(truncated) + r"(?![A-Za-z])", s):
            out.append("%s (should be %s)" % (truncated, n))
    return sorted(set(out))

def badge_on_a_customer(path, s):
    """A VerificationBadge mounted on a screen whose subject is the customer."""
    stem = pathlib.Path(path).name.replace(".dc.html", "")
    if stem not in CUSTOMER_SUBJECT_SCREENS:
        return []
    n = len(re.findall(r'dc-import\s+name="VerificationBadge"', s))
    return ["%d badge(s) on %s" % (n, stem)] if n else []

# A handler bound to a control but defined as an empty arrow does nothing when tapped.
# `noop` is the agreed name for a deliberate placeholder, so anything else with an empty
# body is a dead end - and these cluster on secondary actions nobody walks in a demo:
# Service Preview's two report controls, Provider Profile's Message and Report.
def dead_handlers(s):
    """Named renderVals handlers with an empty body. `noop` is exempt by convention."""
    out = []
    for m in re.finditer(r"(\w+)\s*:\s*\(\s*\w*\s*\)\s*=>\s*\{\s*\}", s):
        name = m.group(1)
        if name == "noop":
            continue
        if re.search(r'\{\{\s*' + re.escape(name) + r'\s*\}\}', s):
            out.append(name)
    return sorted(set(out))

# `noop` is exempt above as the name for a deliberate placeholder - but that exemption can
# be used to hide a real dead end. A <button> with a visible label wired to noop is a control
# a person will tap expecting something: Quote Received had three of them, all saying
# "Message Ibrahim". An EmptyState's on-action is a different case and stays exempt.
# Round 43 wired up every `<button onClick="{{ noop }}">`, and the two rules above only ever
# looked at buttons. A component's own action - EmptyState's `on-action` - is the same dead end
# in a shape neither rule could see, which is how eighteen of them survived the round that was
# meant to remove them. Warn-only while that backlog stands.
# A retry that writes `scnOverride` into state but never reads it back is dead in a way neither
# dead-control rule can see: the handler has a body, and the control is not `noop`. Round 45 shipped
# this shape across nineteen screens, which turned a real warning into a clean pass while the button
# went on doing nothing. If a file writes the flag, something in it has to read the flag.
WRITES_OVERRIDE = re.compile(r"setState\(\s*\{\s*scnOverride\s*:")
READS_OVERRIDE = re.compile(r"(?:this\.state|\bs|\bS)\.scnOverride")


def write_only_override(s):
    if not WRITES_OVERRIDE.search(s):
        return []
    return [] if READS_OVERRIDE.search(s) else ["scnOverride"]


NOOP_ACTION = re.compile(r'action-label="([^"]+)"[^>]*on-action="\{\{\s*noop\s*\}\}"')


def noop_component_actions(s):
    return sorted(set(NOOP_ACTION.findall(s)))


NOOP_BUTTON = re.compile(r"<button[^>]*onClick=\"\{\{\s*noop\s*\}\}\"[^>]*>(.*?)</button>", re.S)

def noop_labelled_buttons(s):
    """Buttons carrying real label text but wired to the placeholder handler."""
    out = []
    for m in NOOP_BUTTON.finditer(s):
        text = re.sub(r"<[^>]+>", " ", m.group(1))
        text = re.sub(r"\{\{[^}]*\}\}", " ", text)
        text = " ".join(text.split())
        if len(text) >= 6 and re.search(r"[A-Za-z]{3}", text):
            out.append(text[:48])
    return sorted(set(out))

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
        # This check asks whether category and mode AGREE, so 'instant' still
        # normalises to slot here — it is a stale spelling of the right answer,
        # not a wrong category. stale_instant_mode owns the spelling, and stays
        # a warn only until the four live seeds are fixed; promote it then.
        norm = "slot" if mode in ("instant", "slot") else "request"
        if cat in SLOT_CATEGORIES and norm != "slot":
            out.append("%s is slot-mode, found %s" % (cat, mode))
        elif cat in REQUEST_CATEGORIES and norm != "request":
            out.append("%s quotes, so it is request-mode, found %s" % (cat, mode))
    return out


STALE_MODE = re.compile(r"mode:\s*'instant'")


def stale_instant_mode(s):
    """Seed data still on the pre-Round-45 prop value.

    ServiceCard and Service Preview resolve slot mode with `(p.mode ?? …) === 'slot'`
    since Round 45 §3c, and their prop enum is 'slot' | 'request'. A seed still
    carrying 'instant' falls through to the request branch, so a slot listing
    renders "Request a time" with a calendar icon — the exact affordance Round 44
    existed to get right. Home and Discovery pass the seed value straight into the
    card, so this is visible on the two most-seen screens.
    """
    return ["mode: 'instant'"] * len(STALE_MODE.findall(s))


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

    for who in near_miss_persona(path, s):
        fails.append(("persona name one character short (%s)" % who,
                      "A name spelled almost right reads as a different person. Match session.js."))

    for who in provider_as_customer(path, s):
        fails.append(("provider persona shown as the customer (%s)" % who,
                      "This screen's subject is the customer, so a provider persona here is in the "
                      "wrong role. Check it against session.js rather than renaming ad hoc."))

    for detail in badge_on_a_customer(path, s):
        fails.append(("verification badge shown for a customer (%s)" % detail,
                      "verificationTier is a provider attribute - a customer has no tier, so the "
                      "badge claims a check that never happened."))

    for chip in emergency_filter_chips(s):
        fails.append(("emergency offered as a browse filter (%s)" % chip,
                      "Round 23 removed the emergency search filter - dispatch never targets a "
                      "provider, so the filter advertised a cut that does not exist. Emergency has "
                      "its own entry on Home and Explore."))

    for name in dead_handlers(s):
        fails.append(("control wired to an empty handler (%s)" % name,
                      "Tapping it does nothing. Name a deliberate placeholder `noop`; otherwise "
                      "point it at the screen it belongs to."))

    for label in noop_labelled_buttons(s):
        fails.append(("labelled button wired to noop (%s)" % label,
                      "noop is for deliberate placeholders, not for a control with a real label. "
                      "Point it at the screen it names."))

    for _ in write_only_override(s):
        fails.append(("retry writes scnOverride but nothing reads it",
                      "The handler runs and the screen does not move - a dead control with a body. "
                      "Read it where the scenario is resolved: `const sc = s.scnOverride ?? props.scenario ?? ...`."))

    for label in noop_component_actions(s):
        warns.append(("component action wired to noop (%s)" % label,
                      "Same dead end as a noop button, passed to a component instead. The label "
                      "promises something; point it at the screen or state it belongs to."))

    n = len(stale_instant_mode(s))
    if n:
        warns.append(("seed still on the pre-Round-45 mode value (%d)" % n,
                      "ServiceCard's prop enum is 'slot' | 'request' and it tests === 'slot', "
                      "so 'instant' renders as request. Round 45 \u00a73c renamed the value; "
                      "these seeds were missed."))

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
