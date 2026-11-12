-- =====================================================================
-- Northgate Open University (NOU)
-- Admissions & Learner Engagement Database
-- Portfolio 1 : Database Design and Modelling
-- Target DBMS : PostgreSQL 16
--
-- Run with:  psql -d nou -f 01_schema.sql
-- =====================================================================

DROP SCHEMA IF EXISTS nou CASCADE;
CREATE SCHEMA nou;
SET search_path TO nou, public;


-- ---------------------------------------------------------------------
-- 1. Reference / lookup entities
-- ---------------------------------------------------------------------

CREATE TABLE channel (
    channel_id    SMALLINT     PRIMARY KEY,
    channel_name  VARCHAR(40)  NOT NULL UNIQUE,
    is_paid_media BOOLEAN      NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE channel IS
    'How the applicant first reached the university (walk-in, website, agent, ...).';


CREATE TABLE faculty (
    faculty_id   SMALLINT    PRIMARY KEY,
    faculty_name VARCHAR(80) NOT NULL UNIQUE
);


CREATE TABLE programme (
    programme_id         SMALLINT      PRIMARY KEY,
    programme_code       VARCHAR(12)   NOT NULL UNIQUE,
    programme_name       VARCHAR(120)  NOT NULL,
    faculty_id           SMALLINT      NOT NULL REFERENCES faculty(faculty_id),
    degree_level         VARCHAR(20)   NOT NULL,
    duration_semesters   SMALLINT      NOT NULL,
    tuition_per_semester NUMERIC(10,2) NOT NULL,

    CONSTRAINT ck_programme_level
        CHECK (degree_level IN ('Undergraduate','Postgraduate')),
    CONSTRAINT ck_programme_duration
        CHECK (duration_semesters BETWEEN 2 AND 12),
    CONSTRAINT ck_programme_tuition
        CHECK (tuition_per_semester > 0)
);


CREATE TABLE cohort (
    cohort_id     SMALLINT    PRIMARY KEY,
    programme_id  SMALLINT    NOT NULL REFERENCES programme(programme_id),
    intake_code   VARCHAR(16) NOT NULL,
    opens_on      DATE        NOT NULL,
    closes_on     DATE        NOT NULL,
    starts_on     DATE        NOT NULL,
    seat_capacity INTEGER     NOT NULL,
    seats_taken   INTEGER     NOT NULL DEFAULT 0,

    CONSTRAINT uq_cohort_intake   UNIQUE (programme_id, intake_code),
    CONSTRAINT ck_cohort_window   CHECK (closes_on > opens_on AND starts_on >= closes_on),
    CONSTRAINT ck_cohort_capacity CHECK (seat_capacity > 0),
    CONSTRAINT ck_cohort_seats    CHECK (seats_taken >= 0 AND seats_taken <= seat_capacity)
);

COMMENT ON COLUMN cohort.seats_taken IS
    'Denormalised running count. Deliberate: it is the contended resource used to '
    'demonstrate lost updates and locking in Portfolio 3.';


CREATE TABLE staff (
    staff_id   INTEGER      PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    staff_no   VARCHAR(12)  NOT NULL UNIQUE,
    full_name  VARCHAR(120) NOT NULL,
    work_email VARCHAR(160) NOT NULL UNIQUE,
    staff_role VARCHAR(24)  NOT NULL,
    team       VARCHAR(40),
    hired_on   DATE         NOT NULL,
    is_active  BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT ck_staff_role
        CHECK (staff_role IN ('admissions_officer','success_advisor','registry'))
);


-- ---------------------------------------------------------------------
-- 2. Admissions entities
-- ---------------------------------------------------------------------

CREATE TABLE applicant (
    applicant_id    BIGINT       PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    person_ref      VARCHAR(16)  NOT NULL UNIQUE,
    first_name      VARCHAR(60)  NOT NULL,
    last_name       VARCHAR(60)  NOT NULL,
    email           VARCHAR(160) NOT NULL UNIQUE,
    phone           VARCHAR(20),
    date_of_birth   DATE,
    gender          CHAR(1),
    state_of_origin VARCHAR(40),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT ck_applicant_gender CHECK (gender IN ('M','F','U')),
    CONSTRAINT ck_applicant_dob
        CHECK (date_of_birth IS NULL
               OR date_of_birth < CURRENT_DATE - INTERVAL '15 years')
);

COMMENT ON COLUMN applicant.person_ref IS
    'Stable external identifier. Used for de-duplication instead of email, '
    'because applicants frequently change the email address they apply with.';


CREATE TABLE application (
    application_id BIGINT      PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    applicant_id   BIGINT      NOT NULL REFERENCES applicant(applicant_id) ON DELETE CASCADE,
    cohort_id      SMALLINT    NOT NULL REFERENCES cohort(cohort_id),
    channel_id     SMALLINT    NOT NULL REFERENCES channel(channel_id),
    officer_id     INTEGER              REFERENCES staff(staff_id),
    status         VARCHAR(16) NOT NULL DEFAULT 'submitted',
    submitted_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    decided_at     TIMESTAMPTZ,

    CONSTRAINT uq_application_per_cohort UNIQUE (applicant_id, cohort_id),
    CONSTRAINT ck_application_status
        CHECK (status IN ('submitted','under_review','offer_issued',
                          'accepted','rejected','withdrawn')),
    -- An application that has reached a terminal state must carry a decision
    -- timestamp; one still in progress must not.
    CONSTRAINT ck_application_decision
        CHECK ( (status IN ('submitted','under_review') AND decided_at IS NULL)
             OR (status NOT IN ('submitted','under_review') AND decided_at IS NOT NULL) ),
    CONSTRAINT ck_application_chronology
        CHECK (decided_at IS NULL OR decided_at >= submitted_at)
);

COMMENT ON TABLE application IS
    'Note: programme_id is deliberately NOT stored here. It is functionally '
    'dependent on cohort_id, so storing it would be a 3NF (transitive '
    'dependency) violation. See normalisation.md.';


CREATE TABLE application_document (
    document_id         BIGINT       PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    application_id      BIGINT       NOT NULL REFERENCES application(application_id) ON DELETE CASCADE,
    doc_type            VARCHAR(24)  NOT NULL,
    storage_path        VARCHAR(255) NOT NULL,
    uploaded_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    verification_status VARCHAR(12)  NOT NULL DEFAULT 'pending',
    verified_by         INTEGER               REFERENCES staff(staff_id),
    verified_at         TIMESTAMPTZ,

    CONSTRAINT uq_document_per_application UNIQUE (application_id, doc_type),
    CONSTRAINT ck_document_type
        CHECK (doc_type IN ('waec','degree_certificate','transcript',
                            'id_card','passport_photo')),
    CONSTRAINT ck_document_verification
        CHECK (verification_status IN ('pending','verified','rejected')),
    CONSTRAINT ck_document_verifier
        CHECK ( (verification_status = 'pending'
                 AND verified_by IS NULL AND verified_at IS NULL)
             OR (verification_status <> 'pending'
                 AND verified_by IS NOT NULL AND verified_at IS NOT NULL) )
);


CREATE TABLE payment (
    payment_id     BIGINT        PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    application_id BIGINT        NOT NULL REFERENCES application(application_id) ON DELETE CASCADE,
    payment_ref    VARCHAR(32)   NOT NULL UNIQUE,
    purpose        VARCHAR(16)   NOT NULL,
    amount         NUMERIC(10,2) NOT NULL,
    currency       CHAR(3)       NOT NULL DEFAULT 'NGN',
    status         VARCHAR(12)   NOT NULL,
    gateway        VARCHAR(20)   NOT NULL,
    initiated_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    settled_at     TIMESTAMPTZ,

    CONSTRAINT ck_payment_purpose
        CHECK (purpose IN ('application_fee','acceptance_fee','tuition')),
    CONSTRAINT ck_payment_status
        CHECK (status IN ('pending','success','failed','reversed')),
    CONSTRAINT ck_payment_amount  CHECK (amount > 0),
    CONSTRAINT ck_payment_settled
        CHECK ( (status = 'pending' AND settled_at IS NULL)
             OR (status <> 'pending' AND settled_at IS NOT NULL) )
);


-- ---------------------------------------------------------------------
-- 3. Learner / engagement entities
-- ---------------------------------------------------------------------

CREATE TABLE enrolment (
    enrolment_id   BIGINT      PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    application_id BIGINT      NOT NULL UNIQUE REFERENCES application(application_id),
    learner_no     VARCHAR(16) NOT NULL UNIQUE,
    advisor_id     INTEGER              REFERENCES staff(staff_id),
    enrolled_on    DATE        NOT NULL,
    status         VARCHAR(12) NOT NULL DEFAULT 'active',
    last_active_at TIMESTAMPTZ,

    CONSTRAINT ck_enrolment_status
        CHECK (status IN ('active','deferred','withdrawn','graduated'))
);

COMMENT ON TABLE enrolment IS
    'One row per accepted application. The UNIQUE constraint on application_id '
    'enforces the 1:1 relationship at the database level rather than in code.';


CREATE TABLE course (
    course_id    INTEGER      PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    course_code  VARCHAR(12)  NOT NULL UNIQUE,
    course_title VARCHAR(140) NOT NULL,
    credit_units SMALLINT     NOT NULL,
    programme_id SMALLINT     NOT NULL REFERENCES programme(programme_id),
    semester_no  SMALLINT     NOT NULL,

    CONSTRAINT ck_course_units    CHECK (credit_units BETWEEN 1 AND 6),
    CONSTRAINT ck_course_semester CHECK (semester_no BETWEEN 1 AND 12)
);


CREATE TABLE course_registration (
    registration_id  BIGINT       PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    enrolment_id     BIGINT       NOT NULL REFERENCES enrolment(enrolment_id) ON DELETE CASCADE,
    course_id        INTEGER      NOT NULL REFERENCES course(course_id),
    academic_session VARCHAR(9)   NOT NULL,
    registered_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    score            NUMERIC(5,2),
    grade            CHAR(1),

    CONSTRAINT uq_registration
        UNIQUE (enrolment_id, course_id, academic_session),
    CONSTRAINT ck_registration_score CHECK (score IS NULL OR score BETWEEN 0 AND 100),
    CONSTRAINT ck_registration_grade CHECK (grade IS NULL OR grade IN ('A','B','C','D','E','F'))
);

COMMENT ON TABLE course_registration IS
    'Associative entity resolving the many-to-many relationship between '
    'enrolment and course.';


CREATE TABLE advisor_interaction (
    interaction_id   BIGINT      PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    enrolment_id     BIGINT      NOT NULL REFERENCES enrolment(enrolment_id) ON DELETE CASCADE,
    advisor_id       INTEGER     NOT NULL REFERENCES staff(staff_id),
    contact_mode     VARCHAR(12) NOT NULL,
    occurred_at      TIMESTAMPTZ NOT NULL,
    duration_seconds INTEGER,
    outcome          VARCHAR(20) NOT NULL,
    notes            TEXT,

    CONSTRAINT ck_interaction_mode
        CHECK (contact_mode IN ('call','whatsapp','email','video','sms')),
    CONSTRAINT ck_interaction_outcome
        CHECK (outcome IN ('reached','no_answer','rescheduled','escalated','resolved')),
    CONSTRAINT ck_interaction_duration
        CHECK (duration_seconds IS NULL OR duration_seconds >= 0)
);

COMMENT ON TABLE advisor_interaction IS
    'Relational home for learner touchpoints. Portfolio 4 re-models this same '
    'entity as a MongoDB document collection and argues the trade-off.';
