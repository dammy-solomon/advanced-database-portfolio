# Portfolio 4 — NoSQL and Advanced Data Models

Same case study: Northgate Open University (NOU). This portfolio takes one
part of the relational schema — learner engagement — and re-models it as a
MongoDB document collection, then argues where each model is the better
choice.

**Platform:** MongoDB 8.0 on Atlas M0 (free tier, three-node replica set),
region Paris (eu-west-3). Administered through MongoDB Compass.

---

## 1. What was re-modelled, and why that part

The relational schema answers "show me this learner and everything we know
about them" by joining nine tables: `enrolment`, `application`, `applicant`,
`cohort`, `programme`, `faculty`, `channel`, `staff` and
`advisor_interaction`.

That query is run constantly — every time a success advisor opens a learner
in the portal. It is also almost never run for a *set* of learners; advisors
work one learner at a time. A query that is frequent, always single-subject,
and expensive in joins is the textbook case for a document model.

The `advisor_interaction` table is also a poor relational fit in a second
way. Interactions vary by contact mode: a call has a duration, an email does
not, a WhatsApp message may carry a template id, a video session may carry a
recording link. In the relational schema these all share one table with
columns that are null for most rows. In a document model each interaction
carries only the fields it actually has.

---

## 2. The document model

One document per **learner**, with that learner's interactions embedded as
an array:

```json
{
  "_id": "NOU/2026/0000001",
  "person_ref": "NOU-P-00000001",
  "name": { "first": "Blessing", "last": "Salami" },
  "email": "blessing.salami1@mailbox.example.net",
  "state_of_origin": "Osun",
  "programme": {
    "code": "BSC-ACC",
    "name": "B.Sc. Accounting",
    "faculty": "Management and Social Sciences",
    "level": "Undergraduate"
  },
  "cohort": { "intake_code": "SEP-2026", "starts_on": "2026-09-07" },
  "acquisition_channel": "Walk-in",
  "enrolment": {
    "enrolled_on": "2026-09-07",
    "status": "active",
    "advisor": "Ngozi Salami",
    "advisor_no": "NOU-S-0049"
  },
  "interactions": [
    {
      "occurred_at": "2026-09-21T21:41:42",
      "year_month": "2026-09",
      "mode": "email",
      "outcome": "resolved",
      "duration_seconds": 916,
      "notes": "Discussed course registration"
    }
  ],
  "interaction_count": 2,
  "reached_count": 1
}
```

**`_id` is the learner number**, not a generated ObjectId. The learner
number is already unique, already meaningful to staff, and already the thing
people search by. Using it as the primary key means the most common lookup
needs no secondary index at all.

**Reference data is denormalised into the document.** Programme name,
faculty and advisor name are copied in rather than referenced. In the
relational model that would be a 3NF violation. Here it is the point: the
document is a read-optimised projection, and reads vastly outnumber the
occasional programme rename.

**`interaction_count` and `reached_count` are derived values** stored
alongside the array they summarise. This is the same trade-off as
`cohort.seats_taken` in Portfolio 1 — redundancy bought in exchange for not
recomputing on every read — and it carries the same risk of drift.

### Why embed rather than reference

MongoDB's 16 MB document limit makes embedding unsafe for unbounded arrays.
Here the array is bounded in practice: the busiest learner in this dataset
has 12 interactions, and a learner on a four-year programme contacted
fortnightly would accumulate roughly 100. At around 200 bytes each that is
20 kB — three orders of magnitude inside the limit.

If interactions were *unbounded* — a chat message log, say — embedding would
be wrong, and the correct pattern would be a separate collection referencing
the learner, or the bucket pattern grouping interactions by month.

---

## 3. Files

| File | Contents |
|---|---|
| `01_export_from_postgres.sql` | Exports the embedded document model from PostgreSQL as JSON Lines |
| `02_mongodb_queries.js` | Five aggregation pipelines, index definitions, and before/after explain plans |
| `learner_engagement.json` | The exported dataset — 33,024 documents, 52 MB *(not committed; regenerate with the script)* |

---

## 4. How to reproduce

**Export from PostgreSQL.** Edit the output path near the top of
`01_export_from_postgres.sql` to match your machine, then from Command
Prompt (not from inside psql):

```
psql.exe -p 5433 -U postgres -d nou -f 01_export_from_postgres.sql
```

Produces `learner_engagement.json` — 33,024 lines, one JSON document per
line.

**Import into Atlas.** In Compass, open the `nou` database, create a
collection named `learner_engagement`, then **Add Data → Import JSON or CSV
file**. Select the file and choose **JSON** as the input type. Compass
detects JSON Lines automatically. The import takes a few minutes over a home
connection.

**Verify:** the collection should show 33,024 documents.

**Then work through `02_mongodb_queries.js`**, running the explain *before*
creating the indexes, then creating them, then running it again.

---

## 5. Where each model wins

| Operation | Relational | Document | Better |
|---|---|---|---|
| One learner's full profile | nine-table join | one `find()` by `_id` | Document |
| Advisor workload across all learners | one GROUP BY | `$unwind` then `$group` | Relational |
| "Which interactions were escalated?" | `WHERE outcome = 'escalated'` | returns whole learners, needs `$unwind` | Relational |
| Rename a programme | one UPDATE | update every affected document | Relational |
| Add a field only video calls have | ALTER TABLE, nullable column | just write it | Document |
| Enforce "every enrolment has a valid cohort" | foreign key | application code only | Relational |
| Seat allocation under concurrency | row locks, SERIALIZABLE | single-document atomicity only | Relational |

The last two rows matter most for this case study. The admissions side of
the system — offers, payments, seat allocation — depends on multi-row
constraints and transactional integrity, which is exactly what Portfolio 3
demonstrates and exactly what a document store does not give for free.

**The honest conclusion is that neither model replaces the other here.** The
transactional core belongs in PostgreSQL. The engagement view is a read
model that MongoDB serves better. A real deployment would keep both and
synchronise one from the other, which is the polyglot persistence pattern —
and it is a real operational cost, not a free win, because that sync is now
a system you have to build, monitor and reconcile.

---

## 6. Indexing notes

Three indexes are created in `02_mongodb_queries.js`. One is worth
particular attention:

```javascript
db.learner_engagement.createIndex({ "interactions.outcome": 1 })
```

This is a **multikey index** — it indexes a field inside an embedded array,
creating one index entry per array element. One index therefore holds
214,656 entries across 33,024 documents.

It has no relational equivalent, because in PostgreSQL the interactions are
a separate table and this would simply be an ordinary index on that table.
It also has a limitation worth stating: a query using it returns whole
learner documents containing at least one matching interaction, not the
matching interactions themselves. Extracting those still needs `$unwind` and
`$match`. Embedding makes the parent cheap to fetch and the children harder
to filter.

### Measured results

| | Documents examined | Execution time |
|---|---|---|
| Before indexing (COLLSCAN) | 33,024 | 28 ms |
| After indexing (IXSCAN on `idx_advisor_status`) | 1,051 | 10 ms |

The query returns 1,051 learner documents. Without an index MongoDB examined
all 33,024 documents to find them; with the index it examined exactly 1,051
and no more — a 31× reduction in documents touched.

---

## 7. Implementation notes

<!-- WRITE THIS YOURSELF.
     (HTML comment - invisible in GitHub's rendered view. Click "Raw" or
     the edit pencil to read it.)

     Worth covering:
     - Record your actual explain numbers: totalDocsExamined and
       executionTimeMillis, before and after the indexes.
     - Whether embedding still looks right to you after running Q3,
       where every aggregation starts with $unwind.
     - What you think of keeping two databases in sync in a real system.
     - Anything about the Atlas setup that surprised you. -->

_To be completed._
