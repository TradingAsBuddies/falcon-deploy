# ADR 0005: Rename POLYGON_API_KEY to MASSIVE_API_KEY

## Status

Accepted — with one open sub-decision (see *Open Questions*).

## Date

2026-09-01

## Context

Polygon.io rebranded to **Massive**. Every credential we hold from that vendor is
still named after the old company, and the estate has drifted badly enough that the
rename is no longer cosmetic.

### What is actually on disk

Measured on `daslaptop` 2026-09-01 by comparing SHA-256 digests, never values:

| Variable | File | Length | SHA-256 (first 16) |
|---|---|---|---|
| `POLYGON_API_KEY` | `~/.claude/.env` | 32 | `b3d325adb23aa61f` |
| `POLYGON_API_KEY` | `~/.config/falcon/falcon.env` | 32 | `b3d325adb23aa61f` |
| `MASSIVE_API_KEY` | `~/.config/falcon/falcon.env` | 32 | `b3d325adb23aa61f` |
| `MASSIVE_SECRET_KEY` | `~/.config/falcon/falcon.env` | 32 | `b3d325adb23aa61f` |
| `MASSIVE_S3_SECRET_KEY` | `~/.claude/.env` | 32 | `b3d325adb23aa61f` |

**One secret is stored under five names across two files.** Three of those names
already say "Massive" — the rename is not being proposed, it is being *finished*.

Two credentials in the same family are genuinely distinct and must not be folded in:

| Variable | Length | SHA-256 (first 16) | What it is |
|---|---|---|---|
| `MASSIVE_S3_ACCESS_KEY` / `MASSIVE_ACCESS_KEY` | 36 | `f197c839c7b21be3` | flat-file access key ID |
| `MASSIVE_S3_ENDPOINT` / `MASSIVE_ENDPOINT` | 25 | `84324eac77374108` | S3 endpoint |
| `MASSIVE_BUCKET` | 9 | `bcf2a9aeb1df414c` | bucket name |

The REST API key and the flat-file S3 *secret* currently hold the same string. That
is a property of how the vendor issues credentials today, **not a guarantee**, and
the distinction is load-bearing — see *Open Questions*.

### Why this matters beyond tidiness

1. **Rotation is unsafe.** Replacing the key means editing five entries in two files.
   Miss one and a data path fails silently — the REST client keeps working while the
   flat-file sync 403s, or vice versa. That is precisely the failure shape that left
   `minute_bars` and `daily_bars` empty after the 2026-08-31 Hyper-V cutover.
2. **Two config files disagree.** `~/.claude/.env` (LifeOS tooling, 38 vars) and
   `~/.config/falcon/falcon.env` (container units, 17 vars) use *different names for
   the same secrets* — `MASSIVE_S3_ACCESS_KEY` vs `MASSIVE_ACCESS_KEY`,
   `FINVIZ_API_KEY` vs `FINVIZ_AUTH_KEY`, `ANTHROPIC_API_KEY` vs `CLAUDE_API_KEY`.
   A reader cannot tell from a variable name which file supplies it.
3. **The decision is already half-made.** `tradekit`'s
   `packaging/tradekit.conf.example` documents `MASSIVE_API_KEY` as canonical with
   `POLYGON_API_KEY` annotated "alias for MASSIVE_API_KEY". Ratifying that convention
   costs nothing; leaving two conventions in the estate costs a rotation outage.

### Blast radius

**57 code and configuration files**, plus 3 environment files, across eight
distinct projects:

`falcon-core` · `falcon-platform` · `falcon-trader` · `falcon-screener` ·
`falcon-stats` · `davdunc-plugins` · `tradekit` · `~/.claude/Tools` ·
`~/falcon/dashboard`

Several are checked out twice (`~/Projects/*` and `~/src/TradingAsBuddies/*`), and
`tradekit` and `davdunc-plugins` are **public**. Verified 2026-09-01: the real key
appears in no tracked file — every `.example` carries a placeholder.

## Decision

**`MASSIVE_API_KEY` is the canonical name for the Massive REST API credential.
`POLYGON_API_KEY` is deprecated.**

Three rules follow:

1. **New code reads `MASSIVE_API_KEY` only.** No new reference to `POLYGON_API_KEY`
   is accepted in review.
2. **Existing code reads `MASSIVE_API_KEY` and falls back to `POLYGON_API_KEY`**
   during migration, emitting a deprecation warning when it takes the fallback. The
   canonical helper:

   ```python
   def massive_api_key() -> str:
       """The Massive (formerly Polygon.io) REST credential.

       POLYGON_API_KEY is the pre-rebrand name. It is still honored so a node that
       has not been migrated keeps working, but it warns: a silent fallback would
       let the old name survive indefinitely, which is how we ended up with one
       secret under five names in the first place.
       """
       key = os.environ.get("MASSIVE_API_KEY")
       if key:
           return key
       key = os.environ.get("POLYGON_API_KEY")
       if key:
           warnings.warn(
               "POLYGON_API_KEY is deprecated; rename it to MASSIVE_API_KEY "
               "(ADR 0005). This fallback will be removed after 2026-12-01.",
               DeprecationWarning, stacklevel=2,
           )
           return key
       raise RuntimeError("MASSIVE_API_KEY is not set")
   ```

3. **The S3 credential names stay separate.** `MASSIVE_S3_ACCESS_KEY`,
   `MASSIVE_S3_SECRET_KEY` and `MASSIVE_S3_ENDPOINT` remain distinct variables even
   though the secret currently equals the API key. They describe a different
   protocol against a different endpoint, and the vendor may decouple them without
   notice.

### Migration

Alias first, cut later. A big-bang rename cannot work here: the same key is read by
systemd container units, by local CLI tools, and by two public repositories, and
those do not deploy together.

| Phase | Action | Done when |
|---|---|---|
| 1 | Add `MASSIVE_API_KEY` beside `POLYGON_API_KEY` in `~/.claude/.env` and every `.env.example`. Land the compat helper in `falcon-core` and `tradekit`. | Both names resolve on every node |
| 2 | Migrate the 57 call sites to the helper, repo by repo. Public repos (`tradekit`, `davdunc-plugins`) go last so their examples stay coherent through the change. | No direct `os.environ["POLYGON_API_KEY"]` remains |
| 3 | After **2026-12-01**: delete `POLYGON_API_KEY` from all env files and drop the fallback branch. | `grep -r POLYGON_API_KEY` returns only this ADR |

Also in phase 1, reconcile the duplicate names between the two env files
(`MASSIVE_ACCESS_KEY` → `MASSIVE_S3_ACCESS_KEY`, `MASSIVE_SECRET_KEY` →
`MASSIVE_S3_SECRET_KEY`, `CLAUDE_API_KEY` → `ANTHROPIC_API_KEY`, `FINVIZ_AUTH_KEY` →
`FINVIZ_API_KEY`) so one name means one thing estate-wide.

## Consequences

### Positive

- **Rotation becomes a one-line edit** instead of a five-entry scavenger hunt across
  two files, removing the silent-partial-failure mode.
- **The name matches the vendor**, so a new reader is not hunting for a Polygon
  account that no longer exists.
- **Ratifies existing practice** rather than inventing a third convention —
  `tradekit` already documents exactly this.
- **The deprecation warning is load-bearing**: it makes an unmigrated node say so
  instead of working quietly until the cut date.

### Negative

- **57 files to touch across 8 projects**, several checked out twice. This is real
  work with no user-visible benefit.
- **A window where both names are live**, which is temporarily *more* confusing than
  the status quo. Phase 3 is not optional; an alias left in place forever is the
  problem, not the fix.
- **Public repositories change**, so downstream users of `tradekit` and
  `davdunc-plugins` must update their own configuration. Their examples already name
  `MASSIVE_API_KEY`, which softens this.
- **Two checkouts can diverge** mid-migration. Migrate `~/src/TradingAsBuddies/*` (the
  remote-tracking clones) and push; treat `~/Projects/*` as downstream.

## Alternatives Considered

**Do nothing.** The estate works today. Rejected because it works only until the key
is rotated: five entries in two files, and a miss fails silently on one data path
while the other keeps serving. The 2026-08-31 cutover already demonstrated that shape.

**Big-bang rename, no alias.** Rename everywhere and cut `POLYGON_API_KEY` in one
change. Rejected because the 57 call sites do not deploy together — systemd container
units, local CLI tools and two public repositories are on independent release paths,
so any single moment leaves some consumer reading a name that no longer exists.

**Keep `POLYGON_API_KEY` as canonical and drop the Massive aliases.** Fewer edits,
and the vendor's REST endpoint still answers on the old paths. Rejected because three
of the five existing names already say Massive and `tradekit` has already published
`MASSIVE_API_KEY` as canonical; reversing that would break a public repo's documented
interface to preserve a dead company's name.

**Alias forever, never cut.** Ship the fallback and skip phase 3. Rejected because a
permanent alias *is* the defect this ADR exists to remove — it guarantees both names
stay in circulation and the next reader has to discover, again, that they are the
same secret.

## Open Questions

**Should `MASSIVE_S3_SECRET_KEY` be collapsed into `MASSIVE_API_KEY`?**

They hold the same 32-character string today, so collapsing them would take the
estate from five aliases to two variables instead of three.

This ADR says **no**, on the grounds that the merge is not reversible by inspection:
if Massive later issues a distinct S3 secret, code that reads `MASSIVE_API_KEY` for
the S3 path would keep sending the REST key and fail with an opaque 403 that looks
like an expired credential rather than a wrong one. The cost of keeping them separate
is one duplicated line in an env file; the cost of merging wrongly is a debugging
session during market hours.

Revisit if Massive documents that the two are the same credential by contract.

## References

- ADR 0002 — PostgreSQL as Primary Database (config precedent)
- `tradekit` `packaging/tradekit.conf.example` — existing `MASSIVE_API_KEY` convention
- Memory: `reference_massive_setup`, `feedback_separate_keys_per_machine`
- Audit performed 2026-09-01 on `daslaptop`; digests recorded above, values never printed
