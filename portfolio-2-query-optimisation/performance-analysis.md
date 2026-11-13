# Portfolio 2 — Query Performance Analysis

All measurements were taken on PostgreSQL 18.6 running locally, against the
dataset built in Portfolio 1 (150,000 applications, 214,656 advisor
interactions, 183,024 payments). Each measurement file was run twice and the
second run recorded, so the figures compare warm cache against warm cache
rather than measuring disk warm-up.

Plans were captured with `EXPLAIN (ANALYZE, BUFFERS)` using
`explain_all.sql`. Full output is in `explain-before.txt` and
`explain-after.txt`.

---

## Summary

| Query | What it does | Before | After | Change |
|---|---|---|---|---|
| Q1 | Officer conversion rate, 2026 intakes (reporting) | 60.5 ms | 26.3 ms | 2.3× faster |
| Q2 | One officer's open review queue (operational) | 41.9 ms | 0.28 ms | **152× faster** |
| Q3 | Accepted applicants with no successful acceptance fee | 85.4 ms | 43.2 ms | 2.0× faster |
| Q4 | One advisor's 90-day contact history (operational) | 56.0 ms | 10.4 ms | 5.4× faster |
| Q5 | Single learner lookup by `person_ref` | 0.28 ms | 0.14 ms | already optimal |

The size of each gain tracks how selective the query is. The two operational
lookups, which return a handful of rows from large tables, improved by
orders of magnitude. The two reporting aggregates, which touch a third of
the table or more, improved by around a factor of two and for a different
reason — explained under Q1.

---

## Q2 — the clearest win (152×)

**Before.** No index existed on `application.officer_id`. PostgreSQL does
not create indexes on foreign key columns automatically; only the referenced
side of the relationship gets one. Finding 8 rows therefore meant scanning
all 150,000.

**Index added.**

```sql
CREATE INDEX idx_application_officer_cohort_status
    ON application (officer_id, cohort_id, status);
```

Column order was chosen deliberately. `officer_id` is the most selective of
the three — 40 distinct values across 150,000 rows — so it leads. `status`
comes last because the query filters it with `IN`, which a B-tree handles as
several range probes rather than one.

**After.** 41.9 ms to 0.28 ms. The query stopped reading the table and
started reading only the index entries that could match.

This is the result that justifies the whole exercise: the work the database
avoids is proportional to how much of the table the query does not need.

---

## Q4 — advisor history (5.4×)

**Index added.**

```sql
CREATE INDEX idx_interaction_advisor_time
    ON advisor_interaction (advisor_id, occurred_at);
```

Equality column first, range column second. Within a single `advisor_id`,
the index is already ordered by `occurred_at`, so one index serves both the
`WHERE` filter and the `ORDER BY i.occurred_at DESC`. Reversing the two
columns would have forced a separate sort step after the scan.

56.0 ms to 10.4 ms. The residual cost is the join back to `enrolment` for
`learner_no`, which requires a heap fetch per matched row.

At 6.6 MB this is also the largest index created. `advisor_interaction` is
append-heavy, so that index is maintained on every insert — a real cost
bought in exchange for the read performance.

---

## Q1 — a covering index, and a planner choice I did not predict

Q1 aggregates across both 2026 intakes, roughly a third of the table. I
expected the planner to ignore any index here and stay with a sequential
scan, because once a query touches more than about 5–10% of a table, random
heap fetches cost more than reading pages in order.

That is not what happened. Execution dropped from 60.5 ms to 26.3 ms, and
the plan shows why:

```
Index Only Scan using idx_application_officer_cohort_status on application a
  Index Cond: (cohort_id = c.cohort_id)
  Heap Fetches: 21
  Buffers: shared hit=3670
```

Three things in that fragment are worth drawing out.

**It is an Index *Only* Scan.** The query needs just `officer_id`,
`cohort_id` and `status` from `application`, and all three are columns of
this index. PostgreSQL answered from the index and touched the heap only 21
times across 50,000 matched rows. The conventional objection to indexing a
low-selectivity query — that every index hit costs a random heap fetch —
does not apply when the index already contains every column the query asks
for. An index used this way is called a **covering index**.

**It matched on the index's second column.** The index is
`(officer_id, cohort_id, status)` and the condition is on `cohort_id`. This
is not a prefix match, so the index cannot be used for an efficient range
seek. PostgreSQL instead scanned index entries and filtered, which is
cheaper than scanning the table only because the index is far narrower than
the table row.

**It did not use `idx_application_cohort`.** That index was created
specifically for this query, and the planner preferred the wider composite
one — precisely because the composite covers all three needed columns while
the single-column index covers one and would still require heap access.

The lesson is that an index is not chosen because of the query it was
created for. The planner compares costs across every available index, and a
wider index can beat a narrower one when it removes heap access entirely.

`idx_application_cohort` is retained because it serves selective
single-cohort lookups elsewhere in the system, but on the evidence here it
earns nothing for Q1, and a stricter review would question whether it is
worth its 1 MB and its write cost.

---

## Q3 — anti-join (2.0×)

```sql
CREATE INDEX idx_payment_acceptance_success
    ON payment (application_id)
    WHERE purpose = 'acceptance_fee' AND status = 'success';
```

A **partial index**: both predicates sit in the `WHERE` clause rather than
the key, so the index contains only the roughly 30,000 payment rows that can
ever satisfy the anti-join, at 680 kB instead of several megabytes.

85.4 ms to 43.2 ms — real, but smaller than Q2's gain, because the
bottleneck moved rather than disappearing. The query joins every accepted
application to `applicant` to return the email address, and 33,024 of
120,000 applicants is a large enough fraction that a sequential scan on
`applicant` genuinely is the cheaper plan for that step. The index fixed the
payment probe; the applicant join is now the floor.

Pushing further would mean a covering index on
`applicant (applicant_id) INCLUDE (person_ref, email)` — a lot of storage to
buy the remaining 43 ms on a report that runs occasionally.

---

## Q5 — already optimal, no index added

Q5 runs in well under half a millisecond untouched, using four index scans:

```
Index Scan using applicant_person_ref_key on applicant
Index Scan using uq_application_per_cohort on application
Index Scan using cohort_pkey on cohort
Index Scan using enrolment_application_id_key on enrolment
```

The before and after figures (0.281 ms and 0.141 ms) differ by less than a
sixth of a millisecond, which is measurement noise rather than an
improvement. No index was added for this query and none is needed.

Note the second line. There is no index on `application.applicant_id`, yet
the lookup is an index scan — because `uq_application_per_cohort` is defined
as `(applicant_id, cohort_id)`, and **a B-tree index can serve any query
that filters on a prefix of its key columns**. The same applies to
`course_registration`, where `uq_registration (enrolment_id, course_id,
academic_session)` serves `enrolment_id` lookups.

Separate indexes on those columns would consume storage and slow every write
while serving no query the existing constraints do not already cover. They
are listed as deliberately omitted at the end of `indexes.sql`.

---

## Index cost summary

| Index | Size | Justified by |
|---|---|---|
| `idx_interaction_advisor_time` | 6,640 kB | Q4, 5.4× |
| `idx_application_officer_cohort_status` | 1,744 kB | Q2 (152×) and, as a covering index, Q1 |
| `idx_application_cohort` | 1,064 kB | selective single-cohort lookups; not used by Q1 |
| `idx_application_accepted` | 1,032 kB | Q3 outer side |
| `idx_payment_acceptance_success` | 680 kB | Q3 anti-join probe |

About 11 MB of index against roughly 95 MB of table data. Every one of these
is maintained on every write to its table. That is the trade-off being
bought, and it is the reason for not creating indexes speculatively.

---

## Reflection

<!-- WRITE THIS YOURSELF.
     (This is an HTML comment. It does not appear when GitHub renders the
     page - click "Raw" or the edit pencil to read it.)

     Worth covering in your own words:
     - Q1 was the surprise. Say what you expected and what the plan
       actually showed, and what "Heap Fetches: 21" told you.
     - Whether you would keep idx_application_cohort now that you know
       Q1 does not use it.
     - The leading-column rule, and how Q5 changed what you thought you
       needed to build.
     - Whether 11 MB of index is a price you would pay in a real system. -->

_To be completed._
