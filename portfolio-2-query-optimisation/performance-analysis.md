# Portfolio 2 — Query Performance Analysis

All measurements come from PostgreSQL 16 running against the dataset built
in Portfolio 1 (150,000 applications, 214,656 advisor interactions, 183,024
payments). Each query was run twice and the second run recorded, so the
figures compare warm-cache against warm-cache rather than measuring disk
warm-up.

Plans were captured with `EXPLAIN (ANALYZE, BUFFERS)`. Full output is in
`explain-before.txt` and `explain-after.txt`.

---

## Summary

| Query | What it does | Before | After | Change |
|---|---|---|---|---|
| Q1 | Officer conversion rate, 2026 intakes (reporting) | 38.3 ms | 40.0 ms | no improvement |
| Q2 | One officer's open review queue (operational) | 25.9 ms | 0.15 ms | **169× faster** |
| Q3 | Accepted applicants with no successful acceptance fee | 63.1 ms | 38.6 ms | 1.6× faster |
| Q4 | One advisor's 90-day contact history (operational) | 29.7 ms | 8.6 ms | 3.5× faster |
| Q5 | Single learner lookup by `person_ref` | 0.14 ms | 0.14 ms | already optimal |

The pattern is the point: **indexes paid off on the selective operational
queries and did nothing for the wide reporting aggregate.** That is the
expected result, not a disappointment, and the reasoning is below.

---

## Q2 — the clearest win (169×)

**Before.** No index existed on `application.officer_id`. PostgreSQL does not
create indexes on foreign key columns automatically — only the referenced
side gets one — so finding 8 rows meant reading the whole table:

```
Parallel Seq Scan on application a  (rows=5 width=34)
  (actual time=0.335..22.246 rows=4 loops=2)
Buffers: shared hit=1900
```

1,900 buffer pages, roughly 15 MB of reads, to return 8 rows.

**Index added.**

```sql
CREATE INDEX idx_application_officer_cohort_status
    ON application (officer_id, cohort_id, status);
```

Column order matters. `officer_id` is the most selective of the three (40
distinct values over 150,000 rows), so it leads. `status` comes last because
the query uses `IN`, which a B-tree handles as several range probes rather
than a single one.

**After.**

```
Bitmap Index Scan on idx_application_officer_cohort_status
  (rows=8) (actual time=0.013..0.013 rows=8 loops=1)
Buffers: shared hit=44
```

1,900 buffers down to 44 — a 43× reduction in pages read, and a 169×
reduction in time. The extra gain beyond the buffer ratio comes from no
longer spinning up parallel workers for a query that returns 8 rows.

---

## Q4 — advisor history (3.5×)

**Before.** 3,265 buffers, sequential scan over all 214,656 interactions to
find 1,236.

**Index added.**

```sql
CREATE INDEX idx_interaction_advisor_time
    ON advisor_interaction (advisor_id, occurred_at);
```

Equality column first, range column second. This ordering lets one index
serve both the `WHERE` filter and the `ORDER BY i.occurred_at DESC`, because
within a single `advisor_id` the index is already sorted by time. Reversing
the columns would have forced a separate sort step.

**After.** 618 buffers, 8.6 ms. The remaining cost is the join back to
`enrolment` for `learner_no`, which is a heap fetch per matched row.

This is also the largest index at 6.6 MB, and worth noting as a cost:
`advisor_interaction` is append-heavy, so every insert now maintains this
index too.

---

## Q3 — anti-join (1.6×)

This one improved less than expected, and the reason is instructive.

```sql
CREATE INDEX idx_payment_acceptance_success
    ON payment (application_id)
    WHERE purpose = 'acceptance_fee' AND status = 'success';
```

A **partial index**: both predicates sit in the `WHERE` clause rather than
the key, so the index contains only the ~30,000 rows that can ever satisfy
the anti-join, at 680 kB instead of several megabytes.

Buffers fell from 6,902 to 3,180, but time only from 63 ms to 39 ms. The
reason is visible in the plan — the bottleneck moved:

```
Seq Scan on applicant ap  (rows=120000) (actual time=0.002..10.370 rows=120000)
Buffers: shared hit=2104
```

The query joins every accepted application to `applicant` to return the
email address, and 33,024 of 120,000 applicants is a large enough fraction
that a sequential scan on `applicant` genuinely is the cheaper plan. The
index fixed the payment lookup; the applicant join is now the floor. Pushing
further would mean a covering index on `applicant (applicant_id) INCLUDE
(person_ref, email)`, which is a lot of storage for 24 ms.

---

## Q1 — the index that did not help

Q1 aggregates across both 2026 intakes, which is roughly a third of the
table. `idx_application_cohort` was created and the planner **declined to use
it**, staying with the parallel sequential scan. Time went from 38.3 ms to
40.0 ms — marginally worse, within noise.

This is correct planner behaviour. Once a query touches more than roughly
5–10% of a table, an index scan costs more than a sequential scan, because
every index hit requires a random heap fetch while a sequential scan reads
pages in order. The index is still justified because it serves selective
single-cohort lookups elsewhere, but it does nothing for this query and the
analysis should say so rather than claim a win.

The honest conclusion: **indexing is a tool for selectivity, not a general
speed-up.** An index on `submitted_at` was also tested for the monthly
reporting query and rejected for exactly the same reason.

---

## Q5 — already optimal, no index added

Q5 runs in 0.14 ms untouched, using four index scans:

```
Index Scan using applicant_person_ref_key on applicant
Index Scan using uq_application_per_cohort on application
Index Scan using cohort_pkey on cohort
Index Scan using enrolment_application_id_key on enrolment
```

Note the second one. There is no index on `application.applicant_id`, yet
the lookup is an index scan — because `uq_application_per_cohort` is defined
as `(applicant_id, cohort_id)` and **a B-tree index can serve any query that
filters on a prefix of its key columns**. The same applies to
`course_registration`, where `uq_registration (enrolment_id, course_id,
academic_session)` serves `enrolment_id` lookups.

Adding separate indexes on those columns would consume storage and slow
every write while serving no query the existing indexes do not already
cover. They are listed as deliberately omitted at the end of `indexes.sql`.

---

## Index cost summary

| Index | Size | Justified by |
|---|---|---|
| `idx_interaction_advisor_time` | 6,640 kB | Q4, 3.5× |
| `idx_application_officer_cohort_status` | 1,744 kB | Q2, 169× |
| `idx_application_cohort` | 1,064 kB | selective cohort lookups, not Q1 |
| `idx_application_accepted` | 1,032 kB | Q3 outer side |
| `idx_payment_acceptance_success` | 680 kB | Q3 anti-join probe |

Total: about 11 MB of index against roughly 95 MB of table data. Every index
is maintained on every write to its table, which is the trade-off being
bought.

---

## Reflection

<!-- WRITE THIS YOURSELF. Worth covering in your own words:
     - Which result surprised you (Q1 getting slower is a good one).
     - Why you kept idx_application_cohort even though Q1 didn't use it.
     - The leading-column rule and how it changed what you planned to build.
     - Whether you'd accept 11 MB of index for these gains in a real system. -->

_To be completed._
