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

Parts 2, 3 and 4 need two concurrent sessions. These were run in two separate
Command Prompt windows, each with its own psql session:

    psql.exe -p 5433 -U postgres -d nou

psql holds a transaction open until an explicit COMMIT or ROLLBACK, so no
autocommit setting needs changing. Every statement must end in a semicolon —
without one, psql waits for more input and the prompt changes from `nou=#`
to `nou-#`.

Run `00_setup_scenario.sql` once, then work through the numbered steps in each
file, alternating between windows as marked.

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

When Session B stopped responding in Part 3, my first assumption was that something had gone wrong with the server. It had not. B was waiting on the lock Session A held on the cohort row, and would have waited indefinitely until A committed. I had not expected a correctly working database to simply stop and wait — I expected it to either succeed or return an error.

The lost update in Part 2 was the opposite problem, and the more worrying one. Two learners were enrolled while the seat counter advanced by one, and neither session reported anything wrong. An error would have been better, because I would have detected the anomaly immediately instead of discovering it only by counting rows afterwards. Silent incorrect data is harder to find than a failure.

My first attempt at the SERIALIZABLE demonstration produced SQLSTATE 23514, the capacity check constraint, rather than the 40001 serialization failure I was expecting. The cause was timing: Session B read the counter after Session A had already committed, so B saw 50 where A had seen 49. With no overlap between the two transactions there was no conflict for PostgreSQL to detect, and B simply tried to exceed capacity. Repeating it with both reads taken before either commit produced 40001 as expected. The lesson is that serialization failures depend on transactions genuinely overlapping, not merely on both using SERIALIZABLE.
