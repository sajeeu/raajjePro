# Session 4 corrections — booking entry

The hard part came out right. The payment step is honest without being frightening,
and it gets there through clarity rather than borrowed security iconography — no
shield, no lock, no green tick. The paper-plane icon on the sent state instead of a
checkmark is exactly the right instinct. Keep all of that.

Five changes. Four are copy, one is state scoping. Nothing structural.

---

## Payment Step

### 1. Two claims the platform can't stand behind — material

**a. "most providers confirm within a few hours"**

There is no data for this. At launch there are no providers and no confirmation
history, and this sentence sets an expectation that the product will visibly fail to
meet in its first weeks. It is the same class of claim as the trust lines removed
from Home in session 1.

Replace with something true regardless of volume:

> That's your word, not a check — RaajjePro hasn't verified anything. {first} confirms
> receipt in this booking, and you'll be notified when they do.

**b. "disputes are recorded against the provider's account"** — appears twice

This tells a customer that reporting will mark the provider, before anyone has looked
at it. §1f is emphatic that RaajjePro publishes numbers and never generates
accusations; promising a mark in advance is an editorial judgement rendered as a
feature, and it is also a promise about an outcome we don't control.

Say what actually happens — the report is recorded and reviewed:

> If something goes wrong, report it from this booking and RaajjePro will look into it.
> The booking record — what was agreed, when, and both sides' messages — is the evidence.

Apply the same fix to the second instance in the sent state.

### 2. An invented deadline

**"No confirmation from {first} by tomorrow? Report it from this booking"**

"By tomorrow" is a number nobody set. The plan's only specified threshold here is that
an unresolved payment claim escalates to admin review at **day 7**. Either use that, or
drop the timeframe:

> Hasn't {first} confirmed yet? You can report it from this booking at any time.

### 3. "I haven't actually paid yet — undo"

Retracting a payment claim isn't in the specification. It may well be the right
behaviour — a mis-tap on this screen is easy and the consequence is a provider
believing money is on the way — but it needs deciding rather than appearing in a
prototype first.

**Leave the control in place** and mark it as an open question in your notes. I will
raise it against the plan. Do not build any further behaviour on top of it.

---

## Quote Received

### 4. "The 4 hours window" reads wrong

String concatenation is producing *"The 4 hours window to accept ran out"*. On the
long-window categories it becomes *"The 72 hours window"*.

Carry a separate adjectival form on the category object — `approveAdj: '4-hour'`
alongside `approveCopy: '4 hours'` — and use the adjective before "window" and the
plain form after "You then get …". Same for `quoteCopy` on Request a Time if it ever
lands before a noun.

---

## Pick a Time

### 5. The taken slot isn't scoped to a day

`slots.filter(t => t!=='14:00')` removes 14:00 from **every** date, and the banner
keeps claiming "14:00 is no longer available" after the customer has navigated to
tomorrow — where nobody took anything.

Scope it: hold the taken slot as a `{day, time}` pair, filter only that day, and show
the banner only while that day is selected.

---

## My error, not yours — the email-unverified state

I asked for that state on all four screens. It only belongs on **Pick a Time** and
**Request a Time**, where the booking is being created and the verified-email rule
actually bites.

On **Quote Received** and **Payment Step** the booking already exists, which means the
customer was verified when they created it. The only way back to unverified is
changing your email address afterwards, and the plan doesn't specify what happens then.

Remove the `email_unverified` scenario from those two screens. Keep it on the two
entry screens exactly as built.

---

## Leave alone

- The whole honesty treatment on Payment Step: "This payment never touches RaajjePro",
  "RaajjePro can't see it, hold it or refund it", the footnote under the CTA, and
  "Keep your bank's transfer receipt — it's your proof, not RaajjePro's."
- The paper-plane icon and "You've told {first} it's sent". Not a checkmark, not "Paid".
- The four amount kinds and their coupling to the booking that produced them,
  including the comment saying so. The emergency variant correctly separates the
  MVR 200 dispatch fee from Ibrahim's callout fee.
- The bank-name mismatch note on the business account.
- "Nearly right? Say so in chat" as a full card above Accept, with "declining just
  ends it". This is the best decision in the session.
- "What accepting means" and the locked-agreement copy in both the card and the
  accepted state.
- Lead time, quote window and approval window all read from a category object with a
  comment saying they are category rules.
- "Sending this asks Mariyam for the time — it isn't booked until she accepts",
  and "No chat yet — it opens the moment Mariyam accepts."
- The `lead_today_empty` state, which explains the cutoff and offers tomorrow.
- The demo clocks. Pick a Time's 10:30 and Request a Time's 12:30 reply deadline are
  consistent with each other and with the 2-hour Plumbing window. That consistency is
  worth preserving as more screens land.
