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
| Q1 officer conversion (reporting) | 60.5 ms | 26.3 ms | 2.3× faster |
| Q2 officer review queue | 41.9 ms | 0.28 ms | 152× faster |
| Q3 accepted without payment | 85.4 ms | 43.2 ms | 2.0× faster |
| Q4 advisor contact history | 56.0 ms | 10.4 ms | 5.4× faster |
| Q5 learner lookup | 0.28 ms | 0.14 ms | already optimal |
| `explain_all.sql` | Runs all five queries under `EXPLAIN (ANALYZE, BUFFERS)` in one pass, for capturing before/after plans |
