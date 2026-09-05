#!/usr/bin/env python3
"""Run Round 38 §6's acceptance journeys against the prototype link graph.

Usage:  python3 docs/design/checks/journeys.py [mockups/design-composer]

Extracts every navigation in every .dc.html — markup href, window.location, and
the href: values inside ROWS/TILES/route-map objects — then traces each journey
hop by hop. A hop that needs one intermediate screen is reported as a detour
rather than a break; only a hop with no path at all is a failure.

Exit code 1 if any journey has a broken hop, a broken link target or an orphan.
"""
import io, re, sys, glob, os, urllib.parse
from collections import deque

ROOT = sys.argv[1] if len(sys.argv) > 1 else "mockups/design-composer"

PATTERNS = [
    re.compile(r'href="(?:\./)?([^"?#]+\.dc\.html)'),
    re.compile(r"""window\.location(?:\.href)?\s*=\s*['"](?:\./)?([^'"?#]+\.dc\.html)"""),
    re.compile(r"""href\s*:\s*['"](?:\./)?([^'"?#]+\.dc\.html)"""),
    re.compile(r"""['"](?:\./)?([A-Za-z][A-Za-z0-9%_ &-]*\.dc\.html)"""),
]

# Components and entry points are not expected to have inbound links.
NO_INBOUND_OK = {
    "BottomNav", "Chip", "EmptyState", "ServiceCard", "SkeletonCard",
    "StatusPill", "VerificationBadge", "Components", "Start", "App States",
}

# Round 38 §6, with journey 1's affordance renamed per Round 44 and the
# intermediate screens the flows actually pass through.
JOURNEYS = {
    # Intermediates are named explicitly rather than left to the 2-hop search:
    # a journey that only works through some unrelated screen is not a journey,
    # and spelling the route out is what makes a regression visible.
    "1 Customer · slot": [
        "Start", "Home", "Discovery", "Service Preview", "Pick a Time",
        "My Bookings", "Booking Detail", "Booking Thread", "Booking Detail",
        "Payment Step", "Booking Detail", "My Bookings", "Did This Happen",
        "Rate This Job"],
    "2 Customer · request": [
        "Home", "Service Preview", "Request a Time", "My Bookings",
        "Booking Detail", "Quote Received", "Payment Step", "Booking Detail"],
    "3 Customer · emergency": [
        "Home", "Emergency Flow", "Booking Detail", "Dispatch Fee",
        "Booking Detail", "Reveal Contact"],
    "4 Provider": [
        "Start", "My Calendar", "Booking Request", "Propose Time and Price",
        "Booking Thread", "Mark Complete", "Payment Received"],
    "5 Provider · business": [
        "My Services", "Create Service", "My Services", "Verification",
        "Billing", "Pay by Bank Transfer", "Invoices"],
    "6 Both · Profile fan-out": [
        "Profile", "Account Settings", "Profile", "Help Support", "Profile",
        "Saved Preferences", "Profile", "Legal"],
}


def build():
    files = sorted(os.path.basename(p) for p in glob.glob(os.path.join(ROOT, "*.dc.html")))
    if not files:
        sys.exit("no .dc.html files under " + ROOT)
    names, graph, broken = set(files), {}, []
    for f in files:
        s = io.open(os.path.join(ROOT, f), encoding="utf-8").read()
        outs = set()
        for p in PATTERNS:
            for m in p.finditer(s):
                t = urllib.parse.unquote(m.group(1))
                outs.add(t)
                if t not in names:
                    broken.append((f, t))
        graph[f] = outs
    return files, graph, sorted(set(broken))


def path(graph, a, b, limit=2):
    """Shortest hop count from a to b, up to `limit` hops. None if unreachable."""
    if a == b:
        return 0
    seen, q = {a}, deque([(a, 0)])
    while q:
        cur, d = q.popleft()
        if d >= limit:
            continue
        for nxt in graph.get(cur, ()):
            if nxt == b:
                return d + 1
            if nxt not in seen:
                seen.add(nxt)
                q.append((nxt, d + 1))
    return None


def main():
    files, graph, broken = build()
    fails = 0

    print("%d screens" % len(files))
    print("broken link targets: %d" % len(broken))
    for f, t in broken:
        print("  BROKEN  %s -> %s" % (f, t))
    fails += len(broken)

    inbound = {f: 0 for f in files}
    for f, outs in graph.items():
        for t in outs:
            if t != f:
                inbound[t] = inbound.get(t, 0) + 1
    orphans = [f for f in files if inbound.get(f, 0) == 0 and f[:-8] not in NO_INBOUND_OK]
    print("orphan screens: %d%s" % (len(orphans), "  " + ", ".join(orphans) if orphans else ""))
    fails += len(orphans)

    for name, hops in JOURNEYS.items():
        print("\n" + name)
        for a, b in zip(hops, hops[1:]):
            d = path(graph, a + ".dc.html", b + ".dc.html")
            if d == 1:
                mark = "ok"
            elif d:
                mark = "detour (%d hops)" % d
            else:
                mark, fails = "*** NO PATH ***", fails + 1
            print("   %-24s -> %-24s %s" % (a, b, mark))

    print("\n%s" % ("FAIL: %d problem(s)" % fails if fails else "all six journeys run with no dead end"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
