# ER Diagram — NOU Admissions & Learner Engagement

GitHub renders the Mermaid block below as a diagram directly in the browser,
so no image file is required. A PNG export is also kept in
`../docs/screenshots/` for the LMS document.

## Entity-relationship model

```mermaid
erDiagram
    FACULTY    ||--o{ PROGRAMME : "offers"
    PROGRAMME  ||--o{ COHORT    : "runs intakes of"
    PROGRAMME  ||--o{ COURSE    : "is made up of"

    APPLICANT  ||--o{ APPLICATION : "submits"
    COHORT     ||--o{ APPLICATION : "receives"
    CHANNEL    ||--o{ APPLICATION : "originates"
    STAFF      ||--o{ APPLICATION : "is assigned as officer"

    APPLICATION ||--o{ APPLICATION_DOCUMENT : "is supported by"
    APPLICATION ||--o{ PAYMENT              : "attracts"
    APPLICATION ||--|| ENROLMENT            : "converts to"
    STAFF       ||--o{ APPLICATION_DOCUMENT : "verifies"

    STAFF     ||--o{ ENROLMENT           : "advises"
    ENROLMENT ||--o{ COURSE_REGISTRATION : "registers"
    COURSE    ||--o{ COURSE_REGISTRATION : "is taken in"
    ENROLMENT ||--o{ ADVISOR_INTERACTION : "generates"
    STAFF     ||--o{ ADVISOR_INTERACTION : "conducts"

    FACULTY {
        smallint faculty_id PK
        varchar  faculty_name UK
    }

    PROGRAMME {
        smallint programme_id PK
        varchar  programme_code UK
        varchar  programme_name
        smallint faculty_id FK
        varchar  degree_level
        smallint duration_semesters
        numeric  tuition_per_semester
    }

    COHORT {
        smallint cohort_id PK
        smallint programme_id FK
        varchar  intake_code
        date     opens_on
        date     closes_on
        date     starts_on
        integer  seat_capacity
        integer  seats_taken
    }

    CHANNEL {
        smallint channel_id PK
        varchar  channel_name UK
        boolean  is_paid_media
    }

    STAFF {
        integer staff_id PK
        varchar staff_no UK
        varchar full_name
        varchar work_email UK
        varchar staff_role
        varchar team
        date    hired_on
        boolean is_active
    }

    APPLICANT {
        bigint      applicant_id PK
        varchar     person_ref UK
        varchar     first_name
        varchar     last_name
        varchar     email UK
        varchar     phone
        date        date_of_birth
        char        gender
        varchar     state_of_origin
        timestamptz created_at
    }

    APPLICATION {
        bigint      application_id PK
        bigint      applicant_id FK
        smallint    cohort_id FK
        smallint    channel_id FK
        integer     officer_id FK
        varchar     status
        timestamptz submitted_at
        timestamptz decided_at
    }

    APPLICATION_DOCUMENT {
        bigint      document_id PK
        bigint      application_id FK
        varchar     doc_type
        varchar     storage_path
        timestamptz uploaded_at
        varchar     verification_status
        integer     verified_by FK
        timestamptz verified_at
    }

    PAYMENT {
        bigint      payment_id PK
        bigint      application_id FK
        varchar     payment_ref UK
        varchar     purpose
        numeric     amount
        char        currency
        varchar     status
        varchar     gateway
        timestamptz initiated_at
        timestamptz settled_at
    }

    ENROLMENT {
        bigint      enrolment_id PK
        bigint      application_id FK
        varchar     learner_no UK
        integer     advisor_id FK
        date        enrolled_on
        varchar     status
        timestamptz last_active_at
    }

    COURSE {
        integer  course_id PK
        varchar  course_code UK
        varchar  course_title
        smallint credit_units
        smallint programme_id FK
        smallint semester_no
    }

    COURSE_REGISTRATION {
        bigint      registration_id PK
        bigint      enrolment_id FK
        integer     course_id FK
        varchar     academic_session
        timestamptz registered_at
        numeric     score
        char        grade
    }

    ADVISOR_INTERACTION {
        bigint      interaction_id PK
        bigint      enrolment_id FK
        integer     advisor_id FK
        varchar     contact_mode
        timestamptz occurred_at
        integer     duration_seconds
        varchar     outcome
        text        notes
    }
```

## Cardinality notes

| Relationship | Cardinality | How it is enforced |
|---|---|---|
| Applicant → Application | 1:M | FK `application.applicant_id`, plus `UNIQUE (applicant_id, cohort_id)` so one applicant cannot apply twice to the same intake |
| Cohort → Application | 1:M | FK `application.cohort_id` |
| Application → Enrolment | 1:1 | FK plus `UNIQUE` on `enrolment.application_id` |
| Enrolment ↔ Course | M:N | Resolved by the `course_registration` associative entity |
| Staff → Application | 1:M (optional) | `officer_id` is nullable: an application can sit unassigned in the queue |
| Staff → Enrolment | 1:M (optional) | `advisor_id` is nullable: a learner may be unassigned between advisor reshuffles |

## Why `programme_id` is not on `application`

An application belongs to a cohort, and a cohort belongs to exactly one
programme. Storing `programme_id` on `application` as well would create a
transitive dependency (`application_id → cohort_id → programme_id`) and open
the door to a row where the stored programme disagrees with the cohort's
programme. The programme is reached by joining through `cohort`. This is
discussed further in `normalisation.md`.
