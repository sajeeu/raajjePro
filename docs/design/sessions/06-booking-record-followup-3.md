# Session 5 corrections, round 3 — the demo proposes nothing

The round-2 fix is right: `sentField = field`, and the confirmation now names whatever the proposer actually changed. The fallback change it asked for — `s.propVal || defProp` instead of the hardcoded `'MVR 600'` — is also right in spirit. But it uncovered the case the hardcoded amount had been papering over.

One change.

---

## Propose Amendment

### The `sent` demo scenario renders an arrow into nothing

Pick `scenario: sent` from the state picker. Nobody has typed anything, so `s.propVal` is empty — and for a customer, `defProp` is empty too (it only carries `'MVR 600'` for a provider on Price). The record card comes out as:

> **Your proposal · on the record**
> Time: 14:00 →
> “—”

An empty proposed value on the very card whose caption says *on the record*. The interactive path is unaffected — `send()` stores `propVal` before the sent state renders — it is only the direct demo state that shows a half-line.

Give each field a demo proposal to fall back to, the same way each already carries its original:

```js
FIELDS = {
  price:{ label:'Price', orig:'MVR 450', ph:'MVR …', demo:'MVR 600' },
  date:{ label:'Date', orig:'Tue 25 Aug', ph:'e.g. Wed 26 Aug', demo:'Wed 26 Aug' },
  time:{ label:'Time', orig:'14:00', ph:'e.g. 16:00', demo:'16:00' },
  scope:{ label:'Scope', orig:'Deep clean — two bedrooms and kitchen', ph:'Describe the new scope', demo:'Deep clean — three bedrooms and kitchen' } };
```

and let `sentLine` reach for it last:

```js
sentLine: … + ' → ' + (s.propVal || defProp || this.FIELDS[sentField].demo),
```

While you're there, give the demo reason the same courtesy so the quote line doesn't read as a bare dash — `(s.reason || defReason || 'Afternoon slot works better for both of us')` in `sentReason`. The `'—'` fallback can go; with a per-field demo value it is no longer reachable.

The demo scenario will then read **"Time: 14:00 → 16:00"** under "the new time takes effect only if Mariyam accepts" — a sent state that finally demonstrates what it claims to record.

---

## Leave alone

Everything else — this is a demo-data fix, not a behaviour change. Specifically: `sentField = field` and the field-named confirmation copy, the `defProp` gating (`isProvider && !s.pFedited && field==='price'`), the `showAdherence` gate, the four chips and the `fieldTouched` default, the not-arrived copy, the arrival-estimate labels, reveal contact, and the dispatch-fee treatment. No other artboard is touched this round.
