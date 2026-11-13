# Portfolio 3 — Transactions and Concurrency

Same case study: Northgate Open University (NOU).

## The scenario

Offer acceptance is the natural transaction boundary in this system. When
an applicant accepts, four things must happen together: the application
status changes, a seat is allocated on the cohort, an enrolment row is
created, and the acceptance fee is recorded. Any partial outcome is a real
operational problem — a learner holding a seat with no payment on record,
or a paid learner with no enrolment.

The contended resource is `cohort.seats_taken`, the denormalised counter
introduced in Portfolio 1. All demonstrations use cohort 999, a sandbox
cohort created with exactly one free seat so two concurrent acceptances
genuinely compete.

## Files

| File | Demonstrates |
|---|---|
| `00_setup_scenario.sql` | Creates the scarce cohort and two applicants holding offers. Re-runnable. |
| `01_commit_and_rollback.sql` | Atomicity: a four-statement COMMIT, then a failure that rolls all of it back |
| `02_lost_update.sql` | The concurrency anomaly — a lost update at READ COMMITTED |
| `03_fix_select_for_update.sql` | Fix one: pessimistic row locking |
| `04_serializable.sql` | Fix two: optimistic concurrency control, SQLSTATE 40001 |
| `05_check_constraint_backstop.sql` | The storage-level invariant that cannot be bypassed |
| `transcript.txt` | Captured output of all four concurrency runs |

## Running the two-session demonstrations

Parts 2, 3 and 4 need two concurrent sessions.

1. Open **two Query Tool tabs** in pgAdmin, both on the `nou` database. Each tab is a separate connection, which is what makes them independent sessions.
2. **Turn off autocommit in both** — Query Tool toolbar, the `...` menu, untick *Auto commit*. This is essential. With autocommit on, every statement commits immediately and no transaction stays open, so no race can occur.
3. Run `00_setup_scenario.sql` once.
4. Work through the numbered steps in each file, alternating tabs as marked. Run one block at a time: select the block and press F5.

In Part 3, Session B's `SELECT ... FOR UPDATE` will appear to hang. That is
the demonstration working — B is waiting on A's lock. Screenshot it.

## Results

| Demonstration | Outcome |
|---|---|
| Commit | 4 statements, all effects present: seats 48→49, 1 accepted, 1 enrolment, 1 payment |
| Rollback | 3 statements succeeded, 4th violated UNIQUE on `payment_ref`; all four undone, seats unchanged at 49 |
| Lost update (READ COMMITTED) | 2 enrolments created, counter advanced by 1. No error raised. |
| `SELECT … FOR UPDATE` | B blocked, then read the fresh value, found 0 seats, rolled back. Counter matches enrolments. |
| SERIALIZABLE | B aborted with SQLSTATE 40001, `could not serialize access due to concurrent update` |
| CHECK constraint | Direct unguarded UPDATE rejected with SQLSTATE 23514 |

## Choosing between the two fixes

Both prevent the lost update. They fail differently, and that is the basis
for choosing.

`SELECT … FOR UPDATE` serialises contenders at read time. The second
session waits rather than failing, so no retry logic is needed — but a
waiting session holds a connection, and lock ordering mistakes across
different code paths can deadlock.

`SERIALIZABLE` takes no locks and lets both sessions proceed, then aborts
one at commit. Throughput is better when conflicts are rare, but the
application **must** handle SQLSTATE 40001 and retry. Code that treats
40001 as a fatal error will show users spurious failures under load.

For seat allocation specifically, `FOR UPDATE` is the better fit: the
contention is on one known row, conflicts are frequent near capacity, and
blocking briefly is preferable to telling an applicant to try again.

The CHECK constraint is not an alternative to either. It is the backstop
for code that uses neither.

## Implementation notes

<!-- WRITE THIS YOURSELF. Useful ground to cover:
     - What you expected Session B to do in Part 2, and what it actually did.
     - Why the lost update is more dangerous than an error would be.
     - Which fix you would deploy and why.
     - What you had to change in pgAdmin to make the demos work (autocommit)
       and what happened when you first forgot. -->

_To be completed._
