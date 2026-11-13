# Portfolio 5 — Distributed and Cloud Databases

Same case study: Northgate Open University (NOU).

This portfolio covers the two distributed concepts the system actually
touches — **horizontal partitioning** and **replication** — and argues the
consistency trade-offs against NOU's real operations rather than in the
abstract. Both are demonstrated on running systems, not described.

| Concept | Demonstrated on | Evidence |
|---|---|---|
| Horizontal partitioning / sharding | PostgreSQL 18.6, local | `01_partitioning_postgres.sql`, partition pruning in EXPLAIN |
| Replication, write concern, read preference | MongoDB Atlas M0, three-node replica set, Paris | `02_replication_mongodb.js`, `db.hello()` output |
| Managed-cloud trade-offs | Atlas M0 | restricted `rs.status()` |

---

## 1. Partitioning — sharding without the network

A shard and a partition are the same idea applied at different scales:
split one logical table into several physical stores by a key, so a query
bounded on that key reads only the stores it needs. Sharding puts those
stores on separate machines; partitioning keeps them on one. The planner
behaviour that makes either worthwhile — **pruning** — is identical, and
can be demonstrated on a laptop.

`application` is range-partitioned by `submitted_at`, one partition per
intake year.

### Row distribution

| Partition | Rows | Size |
|---|---|---|
| `application_2024` | 25,000 | 2,032 kB |
| `application_2025` | 75,000 | 6,088 kB |
| `application_2026` | 50,002 | 4,064 kB |
| `application_2027` | 0 | 0 bytes |

The empty 2027 partition is deliberate. Partitions must exist before the
data arrives, so a real deployment creates them ahead of time or automates
it. A row with no matching partition is rejected outright — a failure mode
that does not exist in an unpartitioned table.

### Measured results

| Query | Time | What was scanned |
|---|---|---|
| Partitioned, bounded to 2026 | **6.6 ms** | `application_2026` only |
| Partitioned, no date predicate | 34.2 ms | all four partitions (Parallel Append) |
| Unpartitioned, bounded to 2026 | 13.7 ms | the whole 150,000-row table |

Two conclusions, and the second matters more.

**Pruning works and is worth roughly 2×** — 6.6 ms against 13.7 ms for the
same answer. The plan shows `Seq Scan on application_2026` with no mention
of the other three partitions. They were eliminated at planning time, never
read.

**Partitioning without a partition-key predicate is actively worse.** The
unbounded query took 34.2 ms against 13.7 ms unpartitioned — more than twice
as slow, because `Parallel Append` must scan every partition and combine the
results. Partitioning does not make a table faster. It makes *queries that
filter on the partition key* faster, and makes everything else slower.

That is the central design lesson: the partition key must match the access
pattern. `submitted_at` is right for NOU because admissions reporting is
almost always scoped to an intake year. Partitioning by `state_of_origin`
would have produced the same storage layout and no benefit at all, because
no query filters on it.

### The constraint that caught me out

```sql
PRIMARY KEY (application_id, submitted_at)
```

The partition key must be part of every unique constraint. PostgreSQL
enforces uniqueness per partition, not globally, so it cannot guarantee
`application_id` alone is unique across all four. The surrogate key from
Portfolio 1 had to widen. In a distributed system this is the same reason
sharded databases push you toward composite or naturally-sharded keys.

---

## 2. Replication — the Atlas replica set

The M0 free tier is a **three-node replica set**: one primary accepting
writes, two secondaries replicating from it. `db.hello()` returns three
entries in `hosts`, and the Compass shell prompt names the set and the role
of the node serving the connection:

```
Atlas atlas-k0jbmx-shard-0 [primary] nou>
```

### Write concern — the durability dial

| Setting | Acknowledged by | Cost | Appropriate for |
|---|---|---|---|
| `w: 1` | primary only | fastest | advisor contact logs |
| `w: "majority"` | 2 of 3 nodes | slower | acceptance payments, seat allocation |

This is a per-operation choice, which is the point. A lost click-tracking
event costs nothing. A lost acceptance payment is the lost-update problem
from Portfolio 3 reappearing at the replication layer rather than the
transaction layer.

### Read preference — which node answers

Reading from a secondary spreads load but returns data that may lag the
primary. For NOU the engagement dashboard can tolerate a few seconds of
staleness; a check on whether a learner has paid cannot. Same cluster, same
data, opposite correct settings.

### What the free tier withholds

`rs.status()` fails on M0 with a "not authorized" error. That is a finding,
not a defect. Managed tiers trade administrative control for zero
operational burden: on a self-managed replica set you would own `rs.conf()`,
stepdowns and election tuning; on M0 the provider owns them, and in exchange
you never patch, back up or fail over anything. For a university with no
dedicated DBA, that is a good trade. For an organisation that needs custom
election priorities across regions, it is not.

---

## 3. CAP applied to this system

Under a network partition a distributed system can hold consistency or
availability, not both. The useful version of this question is not which the
system chooses, but which it should choose **per operation**.

| Operation | Choose | Why |
|---|---|---|
| Offer acceptance and seat allocation | **Consistency** | Two learners taking the last seat is the exact failure Portfolio 3 exists to prevent. Refusing the write during a partition is better than over-allocating. |
| Acceptance fee payment | **Consistency** | A payment recorded on one node and lost on failover is a reconciliation problem with a real person's money attached. |
| Advisor contact logging | **Availability** | Losing the ability to log a call because a node is unreachable stops advisors working. A few seconds of inconsistency costs nothing. |
| Engagement dashboard reads | **Availability** | Stale by seconds is fine; unavailable is not. |

This maps directly onto the two databases. The transactional core stays in
PostgreSQL, where `SERIALIZABLE` and row locks give strict consistency. The
engagement read model sits in MongoDB with `w: 1` and
`secondaryPreferred`, where availability matters more than freshness.

**The honest cost:** running both means the engagement model must be kept in
sync with the relational source. That sync is a system — it needs
monitoring, reconciliation and a defined behaviour when it falls behind. The
polyglot architecture is the right answer here, but it is not a free one,
and a single PostgreSQL instance with a JSONB column would be a defensible
simpler choice for an institution of this size.

---

## 4. Cloud deployment comparison

| | Local PostgreSQL 18.6 | MongoDB Atlas M0 |
|---|---|---|
| Nodes | 1 | 3 (replica set) |
| Survives node loss | No | Yes, automatic failover |
| Backups | manual | provider-managed |
| Admin access | full superuser | restricted |
| Scaling | reinstall and migrate | change tier in the console |
| Cost | hardware already owned | free at this tier |
| Latency from Lagos | sub-millisecond | ~120 ms to Paris |

The latency row is the one most often ignored. Atlas is in Paris because the
free tier offers no African region. For the engagement dashboard, 120 ms is
invisible. For a chatty workload issuing hundreds of sequential round trips,
it would dominate everything else — which is an argument for the document
model independent of anything else, since one document fetch costs one round
trip where a nine-table join would cost nine.

---

## 5. Files

| File | Contents |
|---|---|
| `01_partitioning_postgres.sql` | Range-partitioned table, row distribution, pruned vs unpruned vs unpartitioned EXPLAIN |
| `02_replication_mongodb.js` | `db.hello()` topology, write concern, read concern, read preference, the restricted `rs.status()` |

### Running them

```
psql.exe -p 5433 -U postgres -d nou -f 01_partitioning_postgres.sql
```

Then paste `02_replication_mongodb.js` section by section into the Compass
MongoDB shell.

---

## 6. Implementation notes

<!-- WRITE THIS YOURSELF.
     (HTML comment - invisible in GitHub's rendered view. Click "Raw" or
     the edit pencil to read it.)

     Strong material here:
     - The unbounded partitioned query being SLOWER than unpartitioned.
       Did you expect that? What does it tell you about choosing a
       partition key?
     - Having to widen the primary key to include submitted_at.
     - rs.status() being refused, and what you think of that trade.
     - Whether you would actually run two databases for a real
       university, or keep it all in PostgreSQL. -->

_To be completed._
