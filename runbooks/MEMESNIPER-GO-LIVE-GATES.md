# MemeSniper go-live gates

**DRAFT, 2026-11-14. Not approved. Live trading is not authorized.**

MemeSniper does not trade real money until every gate below is passed, in order, and you
have signed each one. The goal in `goal.md` is repeatable profitable results after costs.
As of this date that is unproven, main is paper, and no live mode, real orders, transfers
or signing are authorized.

This page is the owner's checklist. Lines marked **[Codex]** need Codex to supply the exact
technical test or evidence, because it owns the MemeSniper tree. Lines marked **[you set]**
are numbers only you can choose. Nothing here overrides `CLAUDE.md`, `AGENTS.md` or
`goal.md` in `D:\memesniper`; where they are stricter, they win.

## Where things stand

| Area | State on 2026-11-14 |
|---|---|
| Strategy evidence | No profitable strategy established. Paper ledger negative |
| Live executor | Built, ships disabled. Guardian and executor are not installed as services on G7 |
| Node 24 | Tier 2 qualified and selected. Guardian and executor never qualified |
| Live keypair | On G7, backed up off-site, restore tested, hash verified. Wallet unfunded |
| Provider limits | Fee, dust, quota and continuity limits unresolved |

## Gate 1: Evidence

The strategy must earn its way to live on paper first.

- [ ] A written, dated plan for a future-data paper study, fixed before it starts: rules,
      costs, sample size, pass mark. **[Codex]** drafts, you approve
- [ ] The study runs to its original cutoff with no extension, backfill, reset of losses or
      re-run to get a better answer
- [ ] Result is profitable after all costs (fees, slippage, failed transactions, rent) on
      data the rules never saw, by the pass mark set in advance: **[you set]** ______
- [ ] The result repeats on a second, later, independent sample
- [ ] An independent review of the evidence (`review-prompt.md`) finds no leak of future
      data and no cherry-picking

Stop here if any box fails. Changing the rules means starting Gate 1 again.

## Gate 2: Software

- [ ] MemeSniper-CI green on the exact commit to be released, with the production SDK
- [ ] **[Codex]** The gaps recorded in `goal.md` are closed and tested: router validation,
      account and rent support, shared risk and ownership, startup reconciliation, and
      exits that work independently of entries
- [ ] Guardian and executor units installed, reviewed, and qualified on G7 under their
      real service identities with the same hash-pinned procedure used for Tier 2
- [ ] A signed transaction is built and simulated, and never broadcast, end to end on G7
      (dry run). **[Codex]** defines what a passing dry run records
- [ ] Restart test: stop the service mid-position in the dry run; on start it reconciles
      with the chain and does not double-buy or abandon an exit

## Gate 3: Keys and money

- [ ] Keypair restore re-tested from the off-site encrypted copy; hash matches
      `338c18fa...9520`
- [ ] The signer is the only process that can read the keypair; the unit's
      `InaccessiblePaths` and file modes are checked on G7
- [ ] The wallet is funded with the trial amount only: **[you set]** ______ SOL. Nothing
      else of value is ever held in it
- [ ] A dedicated RPC plan with headroom. No key rotation or other workaround for quotas
- [ ] You know how to move the funds out by hand without the bot, and have done it once
      with a trivial amount

## Gate 4: Hard limits and the kill switch

Limits live in configuration the bot cannot change, and are enforced by the guardian, not
only by the strategy.

| Limit | Value |
|---|---|
| Largest single buy | **[you set]** ______ SOL |
| Most open positions at once | **[you set]** ______ |
| Most capital at risk at once | **[you set]** ______ SOL |
| Daily loss that halts trading until you restart it | **[you set]** ______ SOL |
| Total loss that ends the trial | **[you set]** ______ SOL |
| Most transactions per hour | **[you set]** ______ |

- [ ] **[Codex]** Each limit has a test that proves the guardian refuses the order past it
- [ ] Kill switch: one command or file stops new entries at once and lets exits finish.
      Tested in the dry run, and written at the top of `runbooks/memesniper.md`
- [ ] Hard stop: one command stops everything, exits included. Tested, and you have
      decided in advance when you would use it
- [ ] Limits and loss history survive a restart. Nothing resets them except you, in writing

## Gate 5: Operations

- [ ] Alerts reach your phone for: any order, any failed transaction, any limit hit, the
      service stopping, RPC errors, and the wallet balance leaving its expected range
- [ ] A daily written summary: trades, fees, profit and loss, and current exposure
- [ ] `runbooks/memesniper.md` updated with start, stop, kill switch, rollback and
      "position stuck" steps, and you have walked through each one
- [ ] Rollback of the release tested on G7
- [ ] The nightly backup includes the new state, and no backup or restore is ever used to
      rewind a ledger or loss counter
- [ ] Tax records: every trade is exported in a form the firm's accountant can use

## Gate 6: Staged rollout

Each stage needs your written go-ahead, a start and end date fixed in advance, and a short
written review before the next one. Any hard limit hit, unexplained loss, reconciliation
mismatch or missed alert sends it back a stage.

| Stage | What runs | Size | Length | Pass to continue |
|---|---|---|---|---|
| A. Paper | Current system | None | Until Gate 1 passes | Gate 1 |
| B. Dry run | Live path, sign and simulate, never broadcast | None | **[you set]** ___ days | Simulated fills match paper; no errors |
| C. Smallest live | Real orders | Smallest size the venue allows | **[you set]** ___ days | Fills, fees and exits match the dry run; ledger reconciles to the chain every day |
| D. Small live | Real orders | **[you set]** ______ | **[you set]** ___ days | Profitable after costs, in line with paper |
| E. Step up | Real orders | One step at a time, each **[you set]** | Each step as long as D | Same test at each step |

## Stop conditions at any stage

Stop and return to paper if any of these happens:

- A loss limit is hit
- The ledger and the chain disagree and it cannot be explained the same day
- An order is placed that the rules or limits should have refused
- Live results fall outside the range the paper study predicted
- The provider, fees or market structure change in a way the study did not cover
- You are tempted to raise a limit to recover a loss

## Sign-off

| Gate | Passed on | Evidence (file or build) | Signed |
|---|---|---|---|
| 1. Evidence | | | |
| 2. Software | | | |
| 3. Keys and money | | | |
| 4. Limits and kill switch | | | |
| 5. Operations | | | |
| 6. Stage B | | | |
| 6. Stage C | | | |
| 6. Stage D | | | |
