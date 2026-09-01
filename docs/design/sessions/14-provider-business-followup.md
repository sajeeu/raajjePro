Two corrections. Session 13 came back correct on the first round — every rule the brief led with held, and Billing states the badge-isn't-Premium point twice without being asked. **Change only these two things.**

## 1. `Verification` — the "Good to know" list never renders

The template has:

```
<sc-for list="{{ facts }}" as="f" hint-placeholder-count="4">
```

but `renderVals` never returns `facts`. The `FACTS` array is defined on the class and never bound, so the section renders empty at runtime — the placeholder count makes it look populated in the editor, which is why it wasn't visible.

Add `facts:this.FACTS,` to the returned object. Four load-bearing facts are currently invisible:

- a tier is not needed to be listed or booked
- emergency work needs a tier — Gold on Electrical and Plumbing, Silver on AC Repair and Moving
- an admin confirms the phone number by calling it, and that is the only check the number ever gets
- tiers never expire, and the badge never lapses with a subscription

While you're in that file: `componentWillUnmount` is declared twice on the class. The second silently overrides the first, so behaviour is correct by luck. Keep the one that clears both `_tt` and `_up`, and delete the other.

## 2. `StatusPill` is being passed labels instead of status keys

Two places pass human text where the component expects one of its twelve booking-status keys:

- `Pay by Bank Transfer` — `status="Pending admin confirmation"`
- `Verification` — `status="Review pending"`

`StatusPill` falls back to rendering the raw string in grey, so both *look* right — but the label is then supplied by the screen, which is the drift the component exists to prevent. Neither of these is a booking status: one is a payment-submission state, the other a verification state.

**Style both inline instead**, the way `My Services` already does for Published / Draft / Hidden — a pill with its own background, foreground and dot, matching the surrounding card. Keep the wording exactly as it reads now.

`Pay by Bank Transfer` also passes the real key `pending_offline` on the same prop in its offline branch. Once the pill is inline, that branch needs its own inline treatment too — the offline wording (`Saved on this phone — sends on reconnect`, or keep what StatusPill was rendering) is your call, as long as it doesn't route through StatusPill.

---

## Leave alone

Everything else. Specifically worth *not* touching:

- `My Performance` — the metric grid with no editorial labels, `over your 15% threshold` as the only qualifier, the alert naming the date the oldest cancellation leaves the window, the four-step consequence ladder, the appeal sheet, and the below-floor state that says customers see exactly this
- `Billing` — the badge card, the "on neither list" line under the plan table, `YOUR RATE` with the per-provider note, "30 days from your billing anchor — not calendar months", the pause terms, and the lapse list with its protected listing and override
- `Pay by Bank Transfer` — "pending grants nothing yet", the verbatim rejection reason, resubmit-with-no-cooldown, and the Provider Agreement marked `[placeholder — draft terms, not final policy]`
- `Verification` — the tier ladder rendering `VerificationBadge` twice per rung under "What customers see, word for word", the automatic-Silver note, and the 90-day document deletion line
- `Analytics` — the dimmed example data with its "not your numbers" chip, and `No data yet` where a zero would mislead
- `Invoices` — the line-item/total split that leaves room for a GST row later
