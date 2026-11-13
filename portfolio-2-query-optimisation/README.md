# Portfolio 2 — Query Processing and Optimisation

Same case study as Portfolio 1: Northgate Open University (NOU), the
simulated open-university admissions and learner-engagement system.

## Files

| File | Contents |
|---|---|
| `q1.sql` – `q5.sql` | Five queries: two reporting aggregates, two operational lookups, one point query |
| `indexes.sql` | The indexes added after reading the baseline plans, each with its justification, plus the indexes deliberately *not* created |
| `explain-before.txt` | `EXPLAIN (ANALYZE, BUFFERS)` output for all five queries with no indexes beyond PK/unique |
| `explain-after.txt` | The same five plans after `indexes.sql` |
| `performance-analysis.md` | Measured before/after comparison and the reasoning behind each result |
| `explain_all.sql` | Runs all five queries under `EXPLAIN (ANALYZE, BUFFERS)` in one pass, for capturing before/after plans |

## How to reproduce

```
psql -p 5433 -U postgres -d nou -f explain_all.sql > nul
psql -p 5433 -U postgres -d nou -f explain_all.sql > explain-before.txt
psql -p 5433 -U postgres -d nou -f indexes.sql
psql -p 5433 -U postgres -d nou -f explain_all.sql > nul
psql -p 5433 -U postgres -d nou -f explain_all.sql > explain-after.txt
```

## Headline results

| Query | Before | After | Change |
|---|---|---|---|
| Q1 officer conversion (reporting) | 60.5 ms | 26.3 ms | 2.3× faster |
| Q2 officer review queue | 41.9 ms | 0.28 ms | 152× faster |
| Q3 accepted without payment | 85.4 ms | 43.2 ms | 2.0× faster |
| Q4 advisor contact history | 56.0 ms | 10.4 ms | 5.4× faster |
| Q5 learner lookup | 0.28 ms | 0.14 ms | already optimal |

## Implementation notes

Running `explain_all.sql > nul` before capturing `explain-before.txt` and `explain-after.txt` primed `shared_buffers` so both runs reflected warm-cache execution rather than cold-disk reads.

Index gains varied by workload: Q2 dropped from 41.9 ms to 0.28 ms (152× faster) because a composite index on (officer_id, cohort_id, status) let the planner find 8 rows directly instead of scanning all 150,000 — PostgreSQL does not index foreign key columns automatically, so officer_id had no index at all before this. I skipped extra indexes on Q5 (`0.28 ms` → `0.14 ms`) because it already used a primary-key lookup and additional indexes would only add write overhead.
