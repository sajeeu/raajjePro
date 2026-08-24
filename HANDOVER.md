# Picking this up on another machine

Everything needed to continue is in this repository. Nothing lives only in a chat session.

## Set up

```bash
git clone git@github.com:sajeeu/raajjePro.git
cd raajjePro
code .
```

VS Code will offer the recommended extensions from `.vscode/extensions.json` — the important one is **Claude Code**. Accept them.

Then open Claude Code in the workspace. It reads `CLAUDE.md` at the root automatically, which carries every architectural invariant, so it starts with the same constraints it has here. **You do not need to re-explain the project.**

Nothing else installs. There is no application code yet — this repository is the specification and the design system.

## What this repository is, right now

**No code has been written.** This is the specification, thirteen design prototypes' worth of work planned, and five of them built. The build starts at `/phase-0` when the specification stops moving.

| | |
|---|---|
| `01_Development_Plan_v5.md` | **The single source of truth**, revision 5.9. Every product decision. Read §0.0 first — it is a precedence rule |
| `CLAUDE.md` | Architectural invariants Claude must never violate. Loaded automatically |
| `docs/design/` | The design system: style guide, page briefs, session prompts, the plan for the rebuild |
| `mockups/design-composer/` | Working prototypes — the current design reference |
| `mockups/*.jpg` | The seventeen originally-delivered screens. Provenance only; a prototype beats an image |
| `.claude/commands/` | 38 phase commands — `/phase-0`, `/phase-17-1`, … |
| `.claude/skills/` | 13 skills that trigger on relevant work |
| `archive/` | Superseded. **Never read as current** |

## Continuing the design work

The app is being rebuilt screen by screen in Claude Design. **13 sessions, 1 done, 16 of 71 screens built.**

Read `docs/design/redesign-plan.md` — it has the full sequence, what each session covers, and which mockups to attach.

**The Claude Design project is "Mobile app design project", id `065ca2ad-ff8f-4eac-a8f8-e860a77561ff`.** Its `CLAUDE.md` should carry `docs/design/style-guide.md`; set that once per machine if the project is recreated.

### The loop, per session

1. Paste the session brief from `docs/design/sessions/` into a new chat in that project
2. Attach whatever the brief's *Attach* line names
3. Let it build; ask explicitly for any state it skipped
4. Tell Claude Code **"import and analyse"** — it pulls the file through the connector and audits it against the plan
5. Claude Code writes a correction prompt; paste it back
6. **Export** the corrected artboards into `mockups/design-composer/`
7. `python3 docs/design/verify-dc.py mockups/design-composer/*.dc.html`
8. Commit

Step 4 is the one that earns its keep. Across five prototypes it has caught a missing screen, a false claim about how declining affects a provider's record, invented functionality with no endpoint behind it, an implied charge that does not exist, two claims the product cannot keep printed on Home, and bank details missing from provider onboarding entirely. None of those were visible in the design. All were visible against the plan.

### Components are files, not sections

`<dc-import>` mounts a **sibling `.dc.html`**. Seven components exist as their own files — `ServiceCard`, `VerificationBadge`, `Chip`, `StatusPill`, `BottomNav`, `SkeletonCard`, `EmptyState` — and `Components.dc.html` is the gallery that mounts them. **Import them; never copy their markup.** A second copy is how twelve sessions drift into twelve products.

Two mappings live inside components deliberately: the tier copy in `VerificationBadge`, the twelve status labels in `StatusPill`. They must never be duplicated into a screen.

## End of day

```bash
scripts/eod-push.sh
```

Verifies every prototype, checks `origin` really is raajjePro, commits and pushes. Refuses to commit if a prototype fails its check. `--dry-run` to see what would happen. A clean tree is a normal outcome, not an error.

### The 16:30 backstop

A crontab entry runs it at **16:30 Maldives time** daily. Set it up once per machine:

```bash
( crontab -l 2>/dev/null | grep -v eod-push.sh
  echo "30 16 * * * /usr/bin/env bash $(pwd)/scripts/eod-push.sh >> $(pwd)/.eod-push.log 2>&1" ) | crontab -
```

Two things it depends on, worth checking on a new machine:

- **cron has no ssh-agent.** If your GitHub key has a passphrase the push will fail silently into the log. Test with
  `env -i HOME=$HOME PATH=/usr/bin:/bin ssh -o BatchMode=yes -T git@github.com` — it should greet you by name.
- **The machine has to be awake at 16:30.** A laptop asleep at that minute simply misses it; there is no catch-up.

Read `.eod-push.log` if a day looks missing. It is gitignored.

It is a safety net for a forgotten push, not a substitute for committing as you go — a day's work in one commit is a day's work you cannot bisect.

## What is outstanding, and who owns it

**Yours — none of this can be done from a keyboard here:**

- **AWS/SES account and domain verification**, then production access. Phase 3 cannot be tested from a sandboxed account, and it gates booking, enquiry and messaging
- **The real Maldivian island list.** Three design sessions render an island picker against six placeholders
- **Legal counsel on liability** (§1i) — whether a platform that verifies identity, gates emergency work by tier and dispatches providers is still "just a marketplace" under Maldivian law
- **App Store submission outcome.** Phase 10a ships in-app bank-transfer billing as a deliberate test of guideline 3.1.1; rejection is likely and the fallback is mapped
- **Admin load costing** at 200 providers

**Mine, on request:** the twelve remaining design sessions, and Phase 0 onward when you say go.

## One rule that overrides everything

Where anything disagrees with `01_Development_Plan_v5.md`, **the plan wins and the disagreement gets flagged, not silently resolved.** Five times a decision was reversed in the plan and survived in a copy of it. Every single time the plan was right and the copy was wrong.
