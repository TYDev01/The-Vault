# Improvements

- Add events for vault creation, deposits, withdrawals, and penalties so indexers can track user activity.
- Add a configurable max lock period and optional preset helpers (7/30/90/180 days) to standardize UX.
- Add a per-vault status (active/closed) and a close-vault function to prevent reuse after full withdrawal.
- Add an owner-only rescue function for accidental token transfers (non-sBTC) with strict pause gating.
- Add checks to prevent overflow/underflow on penalty and received amount calculations.
- Add read-only helpers for user vault summaries and total vault count by owner.
- Add a view for penalty preview and blocks remaining to unlock in a single call.
- Add a configurable minimum deposit amount to reduce dust vaults.
- Add a pause-safe emergency path for users to withdraw when contract is paused (governance-defined).
- Add test coverage for pause behavior, invalid lock periods, and penalty edge cases.
