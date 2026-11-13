# Portfolio 1 — Database Design and Modelling

## 1. Selected case study

**Organisation:** Northgate Open University (NOU) — a *simulated* open and
distance-learning university. The organisation is fictional and all data in
this repository is synthetic. No data from any real institution is used.

**Nature of the system.** NOU runs fully online degree programmes with three
intakes a year. Prospective students apply online or through a walk-in
centre, upload supporting documents, pay an application fee, and are assigned
to an admissions officer who reviews the file and issues or declines an
offer. Applicants who accept an offer and pay the acceptance fee become
enrolled learners, are allocated to a success advisor, register for courses,
and are contacted periodically by their advisor throughout the semester.

**Users of the database**

| User group | What they do with it |
|---|---|
| Admissions officers | Review applications, verify documents, issue offers |
| Registry | Confirm payments, enrol accepted applicants, issue learner numbers |
| Success advisors | Track assigned learners, log contact attempts and outcomes |
| Programme leads | Monitor seat capacity and registration by cohort |
| Data/reporting team | Conversion, retention and channel-performance analysis |

**Major data stored:** applicants, applications, supporting documents,
payments, programmes, faculties, cohorts and their seat capacity, staff,
enrolments, courses, course registrations and grades, advisor interactions.

**Key operations the database supports**

- Record an application and prevent the same applicant applying twice to one intake
- Track an application through its status lifecycle to a decision
- Verify supporting documents and record who verified them and when
- Accept an offer, allocate a seat, and record the acceptance payment as one atomic unit
- Enrol an accepted applicant and allocate a success advisor
- Register learners for courses and record scores
- Log and report on advisor contact attempts
- Report conversion by officer, channel and cohort

This same case study is used across all five portfolio activities.

---

## 2. Files in this folder

| File | What it contains |
|---|---|
| `01_schema.sql` | Full DDL: 13 tables, primary and foreign keys, unique and check constraints |
| `02_reference_data.sql` | Lookup data: 4 faculties, 14 programmes, 84 cohorts, 72 staff, 112 courses |
| `03_generate_synthetic_data.sql` | Synthetic transactional data (~1.28M rows) |
| `er-diagram.md` | ER diagram (Mermaid — renders directly on GitHub) and cardinality notes |
| `normalisation.md` | UNF → 1NF → 2NF → 3NF walkthrough, BCNF check, and the one deliberate denormalisation |

---

## 3. How to run

Requires PostgreSQL 14 or later.

```bash
createdb nou
psql -d nou -v ON_ERROR_STOP=1 -f 01_schema.sql
psql -d nou -v ON_ERROR_STOP=1 -f 02_reference_data.sql
psql -d nou -v ON_ERROR_STOP=1 -f 03_generate_synthetic_data.sql
```

Total runtime on a laptop: roughly 15–40 seconds. All objects are created in
the `nou` schema, so run `SET search_path TO nou, public;` before querying.

### Expected row counts after loading

| Table | Rows |
|---|---|
| applicant | 120,000 |
| application | 150,000 |
| application_document | 450,000 |
| payment | 183,024 |
| enrolment | 33,024 |
| course_registration | 132,096 |
| advisor_interaction | 214,656 |

### Expected application status distribution

| Status | Applications |
|---|---|
| offer_issued | 37,072 |
| rejected | 33,569 |
| accepted | 33,024 |
| withdrawn | 18,118 |
| submitted | 15,585 |
| under_review | 12,632 |

The dataset is reproducible: `rnd01()` is an `IMMUTABLE` hash of each row's
key rather than a call to `random()`, so re-running the scripts produces
identical data.

---

## 4. Design decisions worth noting

**Surrogate keys throughout, with business keys enforced separately.** Every
table uses a generated identity column as its primary key, and the real
business key is enforced with a `UNIQUE` constraint —
`UNIQUE (applicant_id, cohort_id)` on `application`,
`UNIQUE (application_id, doc_type)` on `application_document`,
`UNIQUE (enrolment_id, course_id, academic_session)` on `course_registration`.
This keeps foreign keys narrow without giving up the integrity rule.

**De-duplication on `person_ref`, not email.** Applicants frequently reapply
with a different email address, so `person_ref` is the stable identifier and
email is unique but not the matching key.

**Status and timestamp consistency enforced in the schema, not in code.**
`ck_application_decision` requires `decided_at` to be NULL while an
application is still open and non-NULL once it reaches a terminal state. The
same pattern applies to `payment.settled_at` and
`application_document.verified_by` / `verified_at`. These rules are true
regardless of which application writes to the database.

**`cohort.seats_taken` is deliberately denormalised.** See the final section
of `normalisation.md` for the reasoning and the two controls that stop it
drifting.

---

## 5. Implementation notes

## 5. Implementation notes

**Design choices I changed my mind about.** Early on, I considered using natural keys (such as `person_ref` or `programme_code`) as primary keys across the schema. Once I mapped out the 13 tables, carrying composite natural keys through `application`, `enrolment`, and `course_registration` made foreign keys bulky and awkward to join. Switching to generated surrogate keys everywhere while enforcing the real business keys via `UNIQUE` constraints (`(applicant_id, cohort_id)`, `(application_id, doc_type)`) gave me clean joins without weakening data integrity. I also moved applicant deduplication from `email` to `person_ref` after realising returning applicants often apply with a different email address.

**The `random()` generator bug.** In the first draft of `03_generate_synthetic_data.sql`, I used `CROSS JOIN LATERAL (SELECT random())` to assign each application a status. When I checked the distribution afterwards, all 120,000 rows had landed in a single status (`120000 / 0 / 0`). Because the lateral subquery did not reference any column from the outer row, PostgreSQL's planner hoisted it into an `InitPlan` and evaluated it once for the entire statement. Replacing `random()` with an `IMMUTABLE` hash-based function (`rnd01()`) keyed on each row's identifier fixed the distribution immediately and made the entire 1.28M-row dataset deterministic across rebuilds.

**Capping acceptances at 80% of seat capacity.** Rather than letting synthetic acceptances run unconstrained, I capped generated acceptances at 80% of `cohort.seat_capacity`. Without that ceiling, random variance pushed several cohorts past capacity and triggered `ck_cohort_capacity` (`seats_taken <= seat_capacity`), while leaving 20% headroom ensured realistic open cohorts remained available for query and transaction testing in Portfolios 2 and 3.

**What proved harder than expected.** Keeping lifecycle timestamps consistent across parent and child tables (`submitted_at` → `decided_at` → `settled_at` → `enrolled_on`) took several iterations. Enforcing timestamp rules with table-level `CHECK` constraints meant the synthetic data generator had to derive every downstream date from its predecessor rather than generating timestamps independently.
