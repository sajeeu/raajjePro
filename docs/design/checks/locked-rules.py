#!/usr/bin/env python3
"""Check the files that INSTRUCT against rules the plan has already reversed.

Usage:  python3 docs/design/checks/locked-rules.py

`verify-dc.py` guards the prototypes. Nothing guarded the documents that tell a
developer — or Claude — what to build. That gap was real: `frontend/CLAUDE.md`
told Phase 1 to label slot cards "Book instantly" six rounds after Round 44
renamed it, and to render an "Emergency available" marker long after Round 23
deleted it. Neither was ever seen, because the gate only reads .dc.html.

Scope is deliberately narrow. Only files that give instructions are checked —
not `archive/`, not the round prompts in `docs/design/sessions/`, not the
decision records in `docs/decisions/`, and not the READMEs that describe what
the old mockups got wrong. Those all discuss superseded rules by design, and a
checker that flags them is a checker nobody runs.

A line may NAME a superseded rule as superseded. It may not state one as
current. Exit 1 on any violation.
"""
import io
import re
import subprocess
import sys

INSTRUCTION_FILES = (
    "CLAUDE.md",
    "backend/CLAUDE.md",
    "frontend/CLAUDE.md",
    "HANDOVER.md",
    "docs/design/style-guide.md",
    "docs/design/designer-brief.md",
)
INSTRUCTION_GLOBS = (".claude/skills/",)

# A hit is excused when the line is describing the old rule rather than
# instructing it. Keep this list honest: every entry is a phrase that only
# appears when a line is disowning something.
EXCUSED = re.compile(
    r"Round \d+|was ['\"`]|used to (say|read)|replacing|superseded|obsolete|"
    r"no longer|has been removed|DOES NOT EXIST|does not exist|must not be|"
    r"There is no|there is no|NEVER|Never render|not ['\"`]|rather than|"
    r"instead of|is stale|deleted|retired|replaced by|appeared here|"
    r"delivered mockup|three tiers|becomes three",
    re.I,
)

RULES = [
    ("pre-Round-44 slot affordance", r"Book instantly",
     'Round 44: the slot label is "Pick a time". A slot booking still needs the provider to accept.'),
    ("pre-Round-23 emergency marker", r"Emergency available",
     "Round 23: no emergency marker on a card, no emergency search filter — dispatch never targets a provider."),
    ("SMS", r"\bSMS\b",
     "There is no SMS in this system. OTP goes to email; SES is the only transactional sender."),
    ("pre-Round-25 category", r"\bGardening\b",
     "Round 25: Pest Control replaced Gardening."),
    ("binary verified badge", r"Verified Provider",
     "Verification is three tiers. A bare 'Verified' reads as a track record, not an ID check."),
    ("pre-Round-15 flat quote window", r"24 hours to quote|72 hours to approve",
     "Round 15: quote windows are per-category — 120/240 or 1440/4320. Never hardcode."),
    ("pre-Round-22 Moving window", r"Moving[^.]{0,40}\b120\b|\b120\b[^.]{0,40}Moving",
     "Round 22: the emergency response window is 30 minutes for all four categories."),
]


def targets():
    tracked = set(subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout.split("\n"))
    for f in INSTRUCTION_FILES:
        if f in tracked:
            yield f
    for f in sorted(tracked):
        if f.startswith(INSTRUCTION_GLOBS) and f.endswith(".md"):
            yield f


def main():
    findings, checked = [], 0
    for path in targets():
        checked += 1
        for n, line in enumerate(io.open(path, encoding="utf-8").read().split("\n"), 1):
            if EXCUSED.search(line):
                continue
            for label, pattern, why in RULES:
                if re.search(pattern, line):
                    findings.append((path, n, label, why, line.strip()[:110]))

    if not findings:
        print("locked rules: clean across %d instruction files" % checked)
        return 0

    print("locked rules: %d violation(s) across %d instruction files\n" % (len(findings), checked))
    for path, n, label, why, text in findings:
        print("  %s:%d\n      %s\n      %s\n      %s\n" % (path, n, label, why, text))
    print("A line may NAME a superseded rule; it may not state one as current.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
