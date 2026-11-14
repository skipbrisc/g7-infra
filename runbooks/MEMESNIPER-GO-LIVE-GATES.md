# MemeSniper go-live gates

**DRAFT 2, 2026-11-14. Not approved. Live trading is not authorized.**
Revised the same day from Codex's review of draft 1 (it read both files, changed nothing).

The goal in `goal.md` is repeatable profitable results after costs. As of this date that is
unproven, main is paper, and no live mode, real orders, transfers or signing are authorized.

This page is the owner's checklist. Nothing here overrides `CLAUDE.md`, `AGENTS.md` or
`goal.md` in `D:\memesniper`; where they are stricter, they win. Lines marked **[you set]**
are numbers only you can choose.

## How the gates fit together

- **Gates 1 to 5** are passed with no real order ever placed.
- **Two preparation approvals** sit inside them, because they touch real money without
  trading: funding the wallet, and one manual transfer test (Gate 3). Each needs its own
  written approval before it is done.
- **Gate 6** is the activation authorization: one signed document for one trial.
- **Gate 7** is the live trial itself, in stages. Each stage needs approval before it starts.

Passing a gate approves the next step. It never proves profit by itself.

## Where things stand

| Area | State on 2026-11-14 |
|---|---|
| Strategy evidence | No profitable strategy established. Paper ledger negative |
| Live executor | Built, ships disabled. Guardian and executor are not installed as services on G7 |
| Transaction compatibility | Tier 2 report of 2026-11-11: 100 signals, 100 refusals, 0 unsigned acceptances. Not yet shown that a supported transaction is accepted |
| Runtime | Tier 2 qualified on Node 24 and selected (1,385 native tests). That is software and runtime qualification only. Guardian and executor never qualified |
| Built-in ceilings (disabled build, not approved live settings) | One position; 60 entries per rolling day; 30 round trips per 48 hours; fixed 10% settled-loss halt. See `live_executor/config.py` |
| Live keypair | On G7, backed up off-site, restore tested, hash verified |
| Wallet balance | Not verified today. The November 9 handoff says funded; notes record an owner-reported 0.3834 SOL. Needs a dated observation |
| Simulator | Submits the unsigned plan with `sigVerify=false`. The signed dry run in Gate 2 is not built yet |
| Alerts from the executor | A Windows-notice path. Phone delivery not demonstrated |
| Provider limits | Fee, dust, quota and continuity limits unresolved |

## Gate 1: Evidence

- [ ] A written plan for a future-data paper study, hashed and approved by you **before the
      first observation**. It contains:
  - exact strategy, source and configuration versions; the supported universe; execution assumptions
  - UTC start and cutoff, sample requirement, capital and resource budgets
  - treatment of fees, spread, slippage, latency, failed transactions, rent and unsold inventory
  - your numerical pass criteria **[you set]**, missing-data rules, and the later replication sample
  - a reproducible calculation that uses every admitted opportunity, failure and loss
  - statistical acceptance fixed in advance: coverage, treatment of unresolved positions,
    uncertainty, how much of the result may come from a few winners, and sensitivity to
    worse costs and latency. Positive total paper profit alone does not pass
- [ ] Your approval names that exact plan hash
- [ ] The study runs to its original cutoff: no extension, backfill, reset of losses or re-run
- [ ] The result meets the pass criteria on data the rules never saw
- [ ] It repeats on the second, later sample named in the plan
- [ ] An independent review (`review-prompt.md`) finds no leak of future data and no cherry-picking

Stop here if any box fails. Changing the rules means starting Gate 1 again.

## Gate 2: Software

- [ ] The exact release tree passes its full offline suite: zero failures, errors, skips and
      import errors
- [ ] Each gap below is closed, with the named tests passing on that tree

| Gap | Tests and evidence required |
|---|---|
| Transaction validation | `SignerPolicyTests` in `tests/test_live_executor.py`: substituted programs, external SOL transfers, foreign ATAs, authority changes, zero minimum output, excessive fees and altered metadata all refuse; a supported direct PumpSwap transaction passes |
| Accounts, fees and rent | All `SimulationPolicyTests` in `tests/test_live_simulation_policy.py`; in `tests/test_solana_settlement.py`, `SettlementTests.test_new_ata_rent_and_ephemeral_wsol_are_not_double_counted` and `test_failed_transaction_only_charges_fee_and_has_no_fill`. Real provider responses must also show supported account creation, standalone selling and account closure without weakening the policy |
| Risk, reservations and ownership | `SignerFixTests.test_policy_reservation_and_client_mapping_are_one_sql_transaction`, its rollback-on-mapping-failure test, second-position refusal and foreign-inventory refusal. Concurrent requests admit only one reservation |
| Startup and recovery | `JournalTests.test_restart_pending_entry_retains_reservation_and_requires_reconciliation`; settlement tests for duplicate receipts, unknown signatures, definitive expiry and orphaned confirmed fills; `BalanceExitTests.test_pending_resends_identical_bytes_once_per_second_and_survives_timeout`. Restart keeps the original intent, reservation, signature and loss history |
| Independent exits | `ControllerTests.test_kill_disabled_entry_mode_and_absent_arm_do_not_block_owned_exit`, `test_expired_arm_and_loss_halt_do_not_block_owned_exit`, missing-owned-token refusal, and inventory kept after three failed sales |

Fixture results alone cannot pass the provider and account parts.

- [ ] **Compatibility evidence:** a policy-accepted buy, and a standalone sell and account
      close, for each supported account state. A simulated buy leaves no inventory to sell,
      so the plan states how the sell is exercised
- [ ] Guardian and executor units installed, reviewed, and each qualified separately on G7
      under its real identity and sandbox, with the hash-pinned procedure used for Tier 2
- [ ] **Signed dry run** (needs building). A passing record binds:
  - release, SDK and Node hashes; service identity; wallet public address; network genesis;
    policy hash; your approved dry-run mode
  - a durable client and intent ID created before signing
  - a valid signature over the exact independently validated message. Hashes and
    verification results are kept openly; signed bytes stay in protected storage
  - simulation of those signed bytes with `sigVerify=true`, `replaceRecentBlockhash=false`,
    a valid blockhash and the required context slot
  - `err=null`, and acceptable instruction trace, token and SOL changes, minimum output,
    fees, rent and compute use
  - broadcast mechanically impossible in this mode, retries and recovery paths included,
    with zero submission attempts recorded
- [ ] **Dry-run artifacts are safe:** signed dry-run transactions can never be submitted
      later, and a mode change cannot replay dry-run intents into live operation
- [ ] **Restart test on a labelled test fixture.** A dry run cannot create a real chain
      position, so this uses a persistent, clearly marked test bank. Recovery of a real
      chain position is tested in a separately approved live stage
- [ ] **Fault tests under load:** RPC outage and 429, stale or regressing observations,
      clock skew, signer loss, disk full or database failure, missed notifications, and
      ambiguous signing or submission. Each has a stated, bounded entry halt and recovery
- [ ] **Runtime integrity:** Node is a versioned MemeSniper-only path or is hash-checked at
      start. Rollback is tested across the "Debian updated node or python" case and keeps
      both ledgers, pending signatures and ownership

## Gate 3: Keys and money

- [ ] Keypair restore re-tested from the off-site encrypted copy with the safe procedure in
      `runbooks/memesniper.md`: hash `338c18fa...9520` and the public address both match
- [ ] Key file is owned by `memesniper-signer`, mode 0600, as the signer requires. Only that
      identity and root can read it; root's access is accepted and written down
- [ ] A dated balance observation of the wallet, from a public source, on the day of approval
- [ ] **Preparation approval A (written): funding.** The wallet holds the trial amount only:
      **[you set]** ______ SOL. Unsolicited tokens may arrive; the bot ignores inventory it
      never traded, and so do you
- [ ] **Preparation approval B (written): one manual transfer.** You move a trivial amount
      out by hand, without the bot, to prove you can
- [ ] A dedicated RPC plan with headroom. No key rotation or other workaround for quotas

## Gate 4: Hard limits and the kill switch

Limits live in configuration the bot cannot change and are enforced at the guardian. Each
test uses an otherwise valid request, checks the exact refusal reason, and proves the
refused request never reaches signing or submission. Refusals are rechecked after limiter
waits and retries (pattern: `GatewayTests.test_kill_is_rechecked_before_every_provider_retry`).

| Limit | Value | Passing test | Support today |
|---|---|---|---|
| Largest single buy | **[you set]** ___ SOL | Accept at the boundary in lamports; refuse one lamport above. Total commitment includes costs and reservations | Partial: `test_swap_input_ceiling` |
| Open positions | **[you set]** ___ | Accept the first; refuse another, including concurrent requests and after restart | Yes, one position: `test_second_position_refusal` |
| Capital at risk | **[you set]** ___ SOL | Inventory, pending reservations, fees and rent counted together; refuse one lamport above | No. Today's rule is proportional, not an absolute cap |
| Daily loss | **[you set]** ___ SOL | Day boundary and loss formula defined; crossed by fills and by failed-transaction fees; entry refusal survives restart and re-arm | No. Not built |
| Total trial loss | **[you set]** ___ SOL | Threshold, persistent latch, owned exits continue | Partial: fixed 10% rule, `test_settled_loss_halt_persists_after_equity_recovery` |
| Transactions per hour | **[you set]** ___ | Defined as unique transactions or attempts; window edges and persistence tested; capacity reserved for exits | No. Not built. The daily-entry limit and the HTTP rate limiter are different controls |

- [ ] A loss halt is cleared only by you, in writing. A restart never clears it
- [ ] Kill switch: one action stops new entries at once and lets owned exits finish. Tested,
      and written at the top of `runbooks/memesniper.md`
- [ ] Hard stop: one action stops everything, exits included. Tested, and you have decided
      in advance when you would use it
- [ ] Limits and loss history survive restart and re-arm

## Gate 5: Operations

- [ ] Each required alert is proven to reach your phone, including while the PC is asleep:
      any order, any failed transaction, any limit hit, guardian or executor stopping, RPC
      errors, and the wallet balance leaving its expected range
- [ ] Guardian and executor health is monitored separately from the dashboard being up
- [ ] A daily written summary: trades, fees, profit and loss, current exposure
- [ ] `runbooks/memesniper.md` updated with start, stop, kill switch, rollback and
      "position stuck" steps, and you have walked through each
- [ ] The nightly backup includes the new state. No backup or restore is ever used to
      rewind a ledger or loss counter
- [ ] Every trade is exported in a form your accountant can use

## Gate 6: Activation authorization

One signed document, for one trial, bound to the reviewed policy and release hashes:

- [ ] Exact wallet, network, programs, pools and token universe
- [ ] Exit rule, allocation, and every effective limit from Gate 4
- [ ] Mode, start and end, and the date the approval expires

## Gate 7: Staged rollout

Each stage needs your written go-ahead before it starts, fixed start and end dates, and a
short written review before the next. Live fills are judged against tolerances set in
advance, not against an exact match with the dry run.

| Stage | What runs | Size | Length | Pass to continue |
|---|---|---|---|---|
| A. Paper | Current system | None | Until Gate 1 passes | Gate 1 |
| B. Dry run | Live path: sign and simulate, never broadcast | None | **[you set]** ___ days | Gate 2 dry-run records clean; zero submission attempts |
| C. Smallest live | Real orders | Smallest size the venue allows | **[you set]** ___ days | Fills, fees and exits inside tolerance; ledger reconciles to the chain daily; real-position restart recovery shown once |
| D. Small live | Real orders | **[you set]** ___ | **[you set]** ___ days | Profitable after costs, in line with paper |
| E. Step up | Real orders | One step at a time, each **[you set]** | Each as long as D | Same test at each step |

## Stop conditions at any stage

**Halt new entries immediately** when any of these happens. Do not wait to see whether it
resolves:

- The ledger and the chain disagree
- An order is placed that the rules or limits should have refused
- A loss limit is hit
- A required alert did not arrive
- Live results fall outside the range the paper study predicted
- The provider, fees or market structure change in a way the study did not cover
- You are tempted to raise a limit to recover a loss

Halting entries is not abandoning positions: reconciliation and exits of owned inventory
keep running. Returning to paper happens after owned inventory is exited and the ledger
reconciles.

## Sign-off

| Gate | Passed on | Evidence (file, hash or build) | Signed |
|---|---|---|---|
| 1. Evidence | | | |
| 2. Software | | | |
| 3. Keys and money (incl. approvals A and B) | | | |
| 4. Limits and kill switch | | | |
| 5. Operations | | | |
| 6. Activation authorization | | | |
| 7. Stage B | | | |
| 7. Stage C | | | |
| 7. Stage D | | | |
