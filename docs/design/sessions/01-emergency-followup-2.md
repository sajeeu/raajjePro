The provider screen is right in structure — keep it. Six states, the bid-not-a-race panel, the fee entry, the 5-minute countdown, the offline retry that keeps the fee on the phone, and withholding the exact address until the customer picks: all correct, do not rework them.

Four corrections, all in the copy and data rather than the design.

## 1 — The customer's name is wrong

The customer is **`Aishath`**, not `Aminath`. Change `custFirst` and every place it renders. The cast is fixed and no name outside it may appear.

## 2 — "Declining never counts against you" is false, and it is the most damaging line on the screen

It appears twice — in the decline confirmation sheet and on the declined screen. **Both must go.**

The truth is the opposite. A provider's acceptance rate is `accepted ÷ (accepted + declined)`, counting **explicit responses only**. An explicit decline lowers it. Letting the request time out does not — timeouts feed a separate, more forgiving response rate.

So the screen currently tells a provider the one thing that will make them choose the action that hurts them. Replace it with something honest and still kind:

> Declining is counted in your acceptance rate — letting it lapse is not. Either way, no one is told you passed.

Say it in the confirmation sheet, where the decision is actually made. On the declined screen afterwards, do not repeat it — the choice is already taken and repeating it is just a reprimand.

## 3 — Remove "Withdraw offer" entirely

The whole withdraw path goes: the button on the offer-sent screen, its confirmation sheet, and the toast. There is no way for a provider to take an offer back once it is in. The offer stands until the customer picks, or until it lapses.

Replace the button with nothing. The offer-sent screen keeps its countdown and its "You'll be told the moment Aishath decides" line, and the provider simply waits.

## 4 — Nothing on this screen is ever charged to the provider

The expired copy reads "Your offer was never charged anything", which implies a provider charge exists somewhere. It does not — a provider is never charged for offering, attending, or being passed over. Drop that clause and let the rest of the sentence stand.

## Everything else stays

Do not touch the customer artboard, the layout, the states, the animations, or the fee-entry behaviour. These are four copy and data edits.
