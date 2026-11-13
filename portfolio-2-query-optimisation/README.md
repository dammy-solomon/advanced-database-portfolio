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

psql -p 5433 -U postgres -d nou -f explain_all.sql > nul
psql -p 5433 -U postgres -d nou -f explain_all.sql > explain-before.txt
psql -p 5433 -U postgres -d nou -f indexes.sql
psql -p 5433 -U postgres -d nou -f explain_all.sql > nul
psql -p 5433 -U postgres -d nou -f explain_all.sql > explain-after.txt

## Headline results

| Query | Before | After | Change |
|---|---|---|---|
| Q1 officer conversion (reporting) | 60.5 ms | 26.3 ms | 2.3× faster |
| Q2 officer review queue | 41.9 ms | 0.28 ms | 152× faster |
| Q3 accepted without payment | 85.4 ms | 43.2 ms | 2.0× faster |
| Q4 advisor contact history | 56.0 ms | 10.4 ms | 5.4× faster |
| Q5 learner lookup | 0.28 ms | 0.14 ms | already optimal |

## Implementation notes

**Why every run starts with a warm-up pass.** In the reproduction commands, running `explain_all.sql > nul` before capturing `explain-before.txt` and `explain-after.txt` was deliberate. Comparing a cold buffer cache against a warm cache would have overstated the impact of my indexes, so priming `shared_buffers` first ensured both runs reflected warm-cache execution plans.

**Why index gains varied sharply across queries.** Operational lookups like Q2 (`41.9 ms` → `0.28 ms`, 152× faster) saw dramatic improvements because a targeted composite/partial index isolated the small subset of open applications waiting for officer review without touching historical rows. By contrast, reporting queries like Q1 (`60.5 ms` → `26.3 ms`) and Q3 (`85.4 ms` → `43.2 ms`) still had to aggregate or anti-join large slices of the dataset, so indexing cut execution time roughly in half rather than by orders of magnitude.

**Deciding what not to index.** Looking at `EXPLAIN (ANALYZE, BUFFERS)` stopped me from adding speculative indexes on low-selectivity columns or duplicating existing unique constraints. Q5 (`0.28 ms` → `0.14 ms`) was already an index-only/primary-key lookup, so adding extra indexes there would only have slowed down writes in Portfolio 3 for zero read benefit.
