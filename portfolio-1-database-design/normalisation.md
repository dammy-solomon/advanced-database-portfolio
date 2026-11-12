# Normalisation — NOU Admissions & Learner Engagement

The schema in `01_schema.sql` is in **third normal form**, with one documented
exception described at the end. This file shows how it got there, starting
from the kind of flat sheet that admissions teams genuinely keep before a
database exists.

---

## Starting point — the unnormalised intake sheet (UNF)

A single spreadsheet, one row per application:

| AppRef | ApplicantName | ApplicantEmail | Phone | ProgCode | ProgName | Faculty | TuitionPerSem | IntakeCode | IntakeStart | OfficerName | OfficerEmail | Channel | Status | DocsUploaded | DocsVerifiedBy | PaymentRefs | AmountsPaid |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A-1001 | Chidi Okafor | chidi@… | +2348… | BSC-CS | B.Sc. Computer Science | Computing and Applied Sciences | 450000 | SEP-2026 | 2026-09-07 | Aisha Bello | aisha@… | Website | offer_issued | WAEC, Transcript, ID Card | Tunde Lawal, Tunde Lawal, Ngozi Eze | PSK-AF-001, PSK-ACC-001 | 10000, 112500 |
| A-1002 | Fatima Umar | fatima@… | +2348… | BSC-CS | B.Sc. Computer Science | Computing and Applied Sciences | 450000 | SEP-2026 | 2026-09-07 | Aisha Bello | aisha@… | Walk-in | rejected | WAEC, ID Card | Tunde Lawal, Tunde Lawal | PSK-AF-002 | 10000 |

Three problems are visible immediately:

- **`DocsUploaded`, `DocsVerifiedBy`, `PaymentRefs` and `AmountsPaid` hold
  repeating groups** in a single cell, with position-based correspondence
  between two separate lists.
- **Programme and faculty details repeat** on every row for the same
  programme. Changing the tuition fee means editing thousands of rows.
- **Officer details repeat** on every application that officer touches.

### Anomalies this causes

| Anomaly | Example |
|---|---|
| Update | Correcting a misspelt programme name requires updating every application row for that programme. Miss one and the sheet now reports two programmes. |
| Insertion | A newly approved programme with no applicants yet cannot be recorded at all — there is no row to put it on. |
| Deletion | Deleting the last application for a programme destroys the tuition fee and faculty mapping along with it. |

---

## First normal form — remove repeating groups

**Rule:** every attribute holds a single atomic value; no repeating groups.

`DocsUploaded` / `DocsVerifiedBy` and `PaymentRefs` / `AmountsPaid` are
extracted into their own rows. Taking documents first, the sheet becomes one
row per *(application, document type)* pair:

**APPLICATION_DOC_1NF** — key: (AppRef, DocType)

| AppRef | DocType | DocVerifiedBy | ApplicantName | ApplicantEmail | ProgCode | ProgName | Faculty | TuitionPerSem | IntakeCode | OfficerName | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| A-1001 | WAEC | Tunde Lawal | Chidi Okafor | chidi@… | BSC-CS | B.Sc. Computer Science | Computing… | 450000 | SEP-2026 | Aisha Bello | offer_issued |
| A-1001 | Transcript | Tunde Lawal | Chidi Okafor | chidi@… | BSC-CS | B.Sc. Computer Science | Computing… | 450000 | SEP-2026 | Aisha Bello | offer_issued |
| A-1001 | ID Card | Ngozi Eze | Chidi Okafor | chidi@… | BSC-CS | B.Sc. Computer Science | Computing… | 450000 | SEP-2026 | Aisha Bello | offer_issued |

Atomic now, but far worse for redundancy: the applicant's name repeats once
per uploaded document. That is exactly what 2NF addresses.

Payments are split out the same way, keyed on (AppRef, PaymentRef).

---

## Second normal form — remove partial dependencies

**Rule:** in 1NF, and every non-key attribute depends on the *whole*
composite key, not part of it.

Functional dependencies in `APPLICATION_DOC_1NF`:

```
(AppRef, DocType)  →  DocVerifiedBy, StoragePath, UploadedAt, VerificationStatus
 AppRef            →  ApplicantName, ApplicantEmail, Phone, ProgCode, ProgName,
                      Faculty, TuitionPerSem, IntakeCode, OfficerName, Status
```

The second line is a **partial dependency**: those attributes rely on `AppRef`
alone, which is only half of the key. Decompose:

**APPLICATION_2NF** — key: AppRef
`AppRef, ApplicantName, ApplicantEmail, Phone, ProgCode, ProgName, Faculty, TuitionPerSem, IntakeCode, IntakeStart, OfficerName, OfficerEmail, Channel, Status`

**APPLICATION_DOCUMENT_2NF** — key: (AppRef, DocType)
`AppRef, DocType, StoragePath, UploadedAt, VerificationStatus, DocVerifiedBy`

The composite key survives in the schema as
`CONSTRAINT uq_document_per_application UNIQUE (application_id, doc_type)`,
which is what stops the same application carrying two WAEC results. The
surrogate `document_id` is the primary key; the composite is the real
business key.

---

## Third normal form — remove transitive dependencies

**Rule:** in 2NF, and no non-key attribute determines another non-key
attribute.

`APPLICATION_2NF` still contains several transitive chains:

```
AppRef → ProgCode    → ProgName, Faculty, TuitionPerSem, DurationSemesters
AppRef → OfficerID   → OfficerName, OfficerEmail, Team
AppRef → ApplicantID → ApplicantName, ApplicantEmail, Phone, DOB
AppRef → IntakeCode  → IntakeStart, OpensOn, ClosesOn, SeatCapacity
ProgCode → FacultyID → FacultyName
```

Each right-hand side depends on a non-key attribute, not on `AppRef`. Breaking
them out produces the final tables:

| Determinant extracted to | Resulting table |
|---|---|
| `FacultyID` | `faculty` |
| `ProgCode` | `programme` (keeps `faculty_id` as FK) |
| `IntakeCode` + programme | `cohort` |
| `OfficerID` | `staff` |
| `ApplicantID` | `applicant` |
| remainder | `application` |

`application` now holds only attributes that depend on the application itself:
its applicant, its cohort, its channel, its assigned officer, its status, and
its two timestamps.

### The programme_id decision

`programme_id` is **not** stored on `application`, even though analysts ask
for applications-by-programme constantly. `AppRef → CohortID → ProgrammeID`
is a transitive dependency, and duplicating it would allow a row whose stored
programme contradicts its cohort's programme. The programme is reached with a
single join through `cohort`, and `cohort_id` is indexed in Portfolio 2
precisely because that join is hot.

---

## BCNF check

Boyce-Codd normal form requires every determinant to be a candidate key. In
the final schema:

- `applicant`: determinants are `applicant_id`, `person_ref`, `email` — all
  candidate keys (the latter two are `UNIQUE`).
- `application`: determinants are `application_id` and
  `(applicant_id, cohort_id)` — both candidate keys.
- `enrolment`: determinants are `enrolment_id`, `application_id`,
  `learner_no` — all `UNIQUE`.
- `course_registration`: determinants are `registration_id` and
  `(enrolment_id, course_id, academic_session)` — both candidate keys.

No determinant is a non-key attribute, so the schema satisfies BCNF as well
as 3NF.

---

## One deliberate denormalisation: `cohort.seats_taken`

`seats_taken` is derivable by counting enrolments for a cohort, so strictly
it is redundant data. It is kept for two reasons:

1. **Operationally**, the admissions portal checks remaining seats on every
   offer acceptance. Running `COUNT(*)` over the enrolment table on each
   acceptance is wasteful when the answer is a single integer.
2. **For this portfolio**, it is the contended resource that Portfolio 3 uses
   to demonstrate a lost update, and then to fix with `SELECT … FOR UPDATE`
   and with `SERIALIZABLE` isolation.

The risk is drift between the counter and the underlying rows. Two controls
handle this:

- `CONSTRAINT ck_cohort_seats CHECK (seats_taken >= 0 AND seats_taken <= seat_capacity)`
  makes over-allocation impossible at the storage level, whatever the
  application code does.
- A reconciliation query (run at the end of `03_generate_synthetic_data.sql`,
  and again as a check in Portfolio 3) recomputes the counter from the
  `enrolment` rows.

This is the normal trade-off: normalisation protects correctness,
denormalisation buys read performance, and the cost is a consistency control
you now have to maintain deliberately.
