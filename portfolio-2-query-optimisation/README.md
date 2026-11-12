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

## How to reproduce

Load Portfolio 1 first, then:

```bash
# baseline
for q in q1 q2 q3 q4 q5; do
  echo "=== $q ==="
  psql -d nou -c "EXPLAIN (ANALYZE, BUFFERS) $(grep -v '^--' $q.sql)"
done

# add indexes
psql -d nou -f indexes.sql

# re-measure
for q in q1 q2 q3 q4 q5; do
  echo "=== $q ==="
  psql -d nou -c "EXPLAIN (ANALYZE, BUFFERS) $(grep -v '^--' $q.sql)"
done
```

Run each query twice and record the second result — the first run warms the
cache and will overstate the improvement.

## Headline results

| Query | Before | After | Change |
|---|---|---|---|
| Q1 officer conversion (reporting) | 38.3 ms | 40.0 ms | no improvement |
| Q2 officer review queue | 25.9 ms | 0.15 ms | 169× faster |
| Q3 accepted without payment | 63.1 ms | 38.6 ms | 1.6× faster |
| Q4 advisor contact history | 29.7 ms | 8.6 ms | 3.5× faster |
| Q5 learner lookup | 0.14 ms | 0.14 ms | already optimal |

Two of the five results are *not* improvements, and `performance-analysis.md`
explains why that is the correct outcome rather than a failure: indexes help
selective queries and do not help aggregates that touch a third of a table.
