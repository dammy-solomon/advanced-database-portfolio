-- =====================================================================
-- Northgate Open University (NOU)
-- Portfolio 1 : synthetic transactional data
--
-- All data in this portfolio is generated. No personal data from any
-- live system is used anywhere.
--
-- NOTE ON THE GENERATOR
-- ---------------------
-- An earlier version of this script used
--     CROSS JOIN LATERAL (SELECT random() AS r1, random() AS r2) rnd
-- to obtain a stable random value per row. That is wrong. The subquery
-- has no correlation to the outer row, so the planner hoists it into an
-- InitPlan and evaluates random() exactly ONCE for the whole statement.
-- All 120,000 applications came out with an identical status: the
-- distribution was 120000 / 0 / 0 instead of the intended spread.
--
-- rnd01() below fixes it: a deterministic hash of the row's own key. It
-- is IMMUTABLE and keyed on the row, so it varies per row, and it also
-- makes the dataset reproducible without setseed().
--
-- Run after 02_reference_data.sql:
--     psql -d nou -f 03_generate_synthetic_data.sql
-- =====================================================================

SET search_path TO nou, public;


-- ---------------------------------------------------------------------
-- 0. Deterministic per-row pseudo-random helper, returns [0,1)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nou.rnd01(seed BIGINT, salt INTEGER DEFAULT 0)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT ((hashint8(seed * 1000003 + salt) & 2147483647) % 1000000)::numeric
           / 1000000.0;
$$;

COMMENT ON FUNCTION nou.rnd01 IS
    'Deterministic pseudo-random value in [0,1) derived from a row key. '
    'Used instead of random() so values vary per row and the dataset is '
    'reproducible across runs.';


-- ---------------------------------------------------------------------
-- 1. Applicants  (120,000)
-- ---------------------------------------------------------------------
INSERT INTO applicant
    (person_ref, first_name, last_name, email, phone,
     date_of_birth, gender, state_of_origin, created_at)
SELECT
    'NOU-P-' || lpad(g::text, 8, '0'),
    fn.v,
    ln.v,
    lower(fn.v) || '.' || lower(ln.v) || g || '@mailbox.example.net',
    '+2348' || lpad(((g * 7919) % 100000000)::text, 8, '0'),
    DATE '2007-06-30' - (rnd01(g, 1) * 9000)::int,
    (ARRAY['M','F','F','M','U'])[1 + floor(rnd01(g, 2) * 4.999)::int],
    st.v,
    TIMESTAMPTZ '2024-09-01 00:00:00+01' + (rnd01(g, 3) * 730) * INTERVAL '1 day'
FROM generate_series(1, 120000) AS g
CROSS JOIN LATERAL (
    SELECT (ARRAY['Chidi','Aisha','Tunde','Ngozi','Emeka','Fatima','Seyi','Blessing',
                  'Ibrahim','Chioma','Yusuf','Adaeze','Kelechi','Hauwa','Olumide',
                  'Zainab','Obinna','Temitope','Musa','Uchenna','Folake','Nasir',
                  'Amaka','Segun','Halima'])[1 + ((g * 7) % 25)] AS v) fn
CROSS JOIN LATERAL (
    SELECT (ARRAY['Okafor','Bello','Adeyemi','Nwosu','Lawal','Eze','Balogun','Umar',
                  'Ogunleye','Danjuma','Iweala','Salami','Chukwu','Abubakar',
                  'Oyelaran','Nnamdi','Aliyu','Obi','Shonibare','Garba'])
           [1 + ((g * 11) % 20)] AS v) ln
CROSS JOIN LATERAL (
    SELECT (ARRAY['Lagos','Oyo','Kano','Rivers','Enugu','Kaduna','Ogun','Delta',
                  'Anambra','Borno','Edo','Plateau','Abia','Osun','Benue','FCT'])
           [1 + ((g * 13) % 16)] AS v) st;


-- ---------------------------------------------------------------------
-- 2. Applications
--    Pass A : one application per applicant.
--    Pass B : the first 30,000 applicants re-apply to a different cohort.
--    'accepted' is NOT assigned here. Step 3 caps acceptances against
--    each cohort's seat_capacity.
-- ---------------------------------------------------------------------
INSERT INTO application
    (applicant_id, cohort_id, channel_id, officer_id, status, submitted_at, decided_at)
WITH officers AS (
    SELECT array_agg(staff_id ORDER BY staff_id) AS ids
    FROM staff
    WHERE staff_role = 'admissions_officer'
)
SELECT
    a.applicant_id,
    c.cohort_id,
    (ARRAY[1,1,1,2,2,3,3,4,5,6])[1 + floor(rnd01(a.applicant_id, 11) * 9.999)::int],
    o.ids[1 + floor(rnd01(a.applicant_id, 12) * array_length(o.ids, 1))::int],
    s.status,
    sub.submitted_at,
    CASE WHEN s.status IN ('submitted','under_review')
         THEN NULL
         ELSE sub.submitted_at + ((1 + rnd01(a.applicant_id, 14) * 30) * INTERVAL '1 day')
    END
FROM applicant a
CROSS JOIN officers o
CROSS JOIN LATERAL (
    SELECT * FROM cohort WHERE cohort_id = 1 + ((a.applicant_id * 29) % 84)
) c
CROSS JOIN LATERAL (
    SELECT (c.opens_on + (rnd01(a.applicant_id, 15) * (c.closes_on - c.opens_on))::int)::timestamptz
           + (rnd01(a.applicant_id, 16) * 10 + 8) * INTERVAL '1 hour' AS submitted_at
) sub
CROSS JOIN LATERAL (
    SELECT CASE
             WHEN rnd01(a.applicant_id, 13) < 0.10 THEN 'submitted'
             WHEN rnd01(a.applicant_id, 13) < 0.18 THEN 'under_review'
             WHEN rnd01(a.applicant_id, 13) < 0.30 THEN 'withdrawn'
             WHEN rnd01(a.applicant_id, 13) < 0.52 THEN 'rejected'
             ELSE 'offer_issued'
           END AS status
) s;


-- Pass B : repeat applicants, deterministically shifted to another cohort
-- so UNIQUE (applicant_id, cohort_id) cannot be violated.
INSERT INTO application
    (applicant_id, cohort_id, channel_id, officer_id, status, submitted_at, decided_at)
WITH officers AS (
    SELECT array_agg(staff_id ORDER BY staff_id) AS ids
    FROM staff
    WHERE staff_role = 'admissions_officer'
)
SELECT
    ap.applicant_id,
    c2.cohort_id,
    (ARRAY[1,1,2,3,5,5])[1 + floor(rnd01(ap.application_id, 21) * 5.999)::int],
    o.ids[1 + floor(rnd01(ap.application_id, 22) * array_length(o.ids, 1))::int],
    s.status,
    sub.submitted_at,
    CASE WHEN s.status IN ('submitted','under_review')
         THEN NULL
         ELSE sub.submitted_at + ((1 + rnd01(ap.application_id, 24) * 25) * INTERVAL '1 day')
    END
FROM application ap
CROSS JOIN officers o
CROSS JOIN LATERAL (
    SELECT * FROM cohort WHERE cohort_id = 1 + ((ap.cohort_id + 17 - 1) % 84)
) c2
CROSS JOIN LATERAL (
    SELECT (c2.opens_on + (rnd01(ap.application_id, 25) * (c2.closes_on - c2.opens_on))::int)::timestamptz
           + (rnd01(ap.application_id, 26) * 9 + 9) * INTERVAL '1 hour' AS submitted_at
) sub
CROSS JOIN LATERAL (
    SELECT CASE
             WHEN rnd01(ap.application_id, 23) < 0.12 THEN 'submitted'
             WHEN rnd01(ap.application_id, 23) < 0.22 THEN 'under_review'
             WHEN rnd01(ap.application_id, 23) < 0.34 THEN 'withdrawn'
             WHEN rnd01(ap.application_id, 23) < 0.58 THEN 'rejected'
             ELSE 'offer_issued'
           END AS status
) s
WHERE ap.applicant_id <= 30000;


-- ---------------------------------------------------------------------
-- 3. Acceptances, capped per cohort so seats_taken <= seat_capacity
-- ---------------------------------------------------------------------
WITH ranked AS (
    SELECT
        ap.application_id,
        row_number() OVER (PARTITION BY ap.cohort_id ORDER BY ap.application_id) AS rn,
        floor(c.seat_capacity * 0.80)::int AS cap
    FROM application ap
    JOIN cohort c ON c.cohort_id = ap.cohort_id
    WHERE ap.status = 'offer_issued'
)
UPDATE application ap
SET status = 'accepted'
FROM ranked r
WHERE ap.application_id = r.application_id
  AND r.rn <= r.cap;


-- ---------------------------------------------------------------------
-- 4. Supporting documents (2-4 per application, no duplicate types)
-- ---------------------------------------------------------------------
INSERT INTO application_document
    (application_id, doc_type, storage_path, uploaded_at,
     verification_status, verified_by, verified_at)
WITH registry AS (
    SELECT array_agg(staff_id ORDER BY staff_id) AS ids
    FROM staff
    WHERE staff_role IN ('registry','admissions_officer')
)
SELECT
    ap.application_id,
    (ARRAY['waec','degree_certificate','transcript','id_card','passport_photo'])[n],
    's3://nou-docs/' || ap.application_id || '/' || n || '.pdf',
    ap.submitted_at + (n * INTERVAL '40 minutes'),
    v.vstatus,
    CASE WHEN v.vstatus = 'pending' THEN NULL
         ELSE rg.ids[1 + floor(rnd01(ap.application_id * 8 + n, 32)
                               * array_length(rg.ids, 1))::int] END,
    CASE WHEN v.vstatus = 'pending' THEN NULL
         ELSE ap.submitted_at + ((2 + rnd01(ap.application_id * 8 + n, 33) * 14)
                                 * INTERVAL '1 day') END
FROM application ap
CROSS JOIN registry rg
CROSS JOIN LATERAL generate_series(1, 2 + (ap.application_id % 3)) AS n
CROSS JOIN LATERAL (
    SELECT CASE
             WHEN ap.status IN ('submitted','under_review')
                  AND rnd01(ap.application_id * 8 + n, 31) < 0.55 THEN 'pending'
             WHEN rnd01(ap.application_id * 8 + n, 31) < 0.67      THEN 'rejected'
             ELSE 'verified'
           END AS vstatus
) v;


-- ---------------------------------------------------------------------
-- 5. Payments
-- ---------------------------------------------------------------------
INSERT INTO payment
    (application_id, payment_ref, purpose, amount, currency,
     status, gateway, initiated_at, settled_at)
SELECT
    ap.application_id,
    'PSK-AF-' || lpad(ap.application_id::text, 10, '0'),
    'application_fee',
    CASE WHEN p.degree_level = 'Postgraduate' THEN 15000.00 ELSE 10000.00 END,
    'NGN',
    st.s,
    (ARRAY['paystack','flutterwave','remita'])
        [1 + floor(rnd01(ap.application_id, 42) * 2.999)::int],
    ap.submitted_at - INTERVAL '35 minutes',
    CASE WHEN st.s = 'pending' THEN NULL
         ELSE ap.submitted_at - INTERVAL '30 minutes' END
FROM application ap
JOIN cohort c    ON c.cohort_id    = ap.cohort_id
JOIN programme p ON p.programme_id = c.programme_id
CROSS JOIN LATERAL (
    SELECT CASE
             WHEN rnd01(ap.application_id, 41) < 0.04 THEN 'failed'
             WHEN rnd01(ap.application_id, 41) < 0.06 THEN 'pending'
             WHEN rnd01(ap.application_id, 41) < 0.07 THEN 'reversed'
             ELSE 'success'
           END AS s
) st;

INSERT INTO payment
    (application_id, payment_ref, purpose, amount, currency,
     status, gateway, initiated_at, settled_at)
SELECT
    ap.application_id,
    'PSK-ACC-' || lpad(ap.application_id::text, 10, '0'),
    'acceptance_fee',
    round(p.tuition_per_semester * 0.25, 2),
    'NGN',
    st.s,
    (ARRAY['paystack','flutterwave','remita'])
        [1 + floor(rnd01(ap.application_id, 52) * 2.999)::int],
    ap.decided_at + INTERVAL '2 days',
    CASE WHEN st.s = 'pending' THEN NULL
         ELSE ap.decided_at + INTERVAL '2 days 20 minutes' END
FROM application ap
JOIN cohort c    ON c.cohort_id    = ap.cohort_id
JOIN programme p ON p.programme_id = c.programme_id
CROSS JOIN LATERAL (
    SELECT CASE
             WHEN rnd01(ap.application_id, 51) < 0.05 THEN 'failed'
             WHEN rnd01(ap.application_id, 51) < 0.08 THEN 'pending'
             ELSE 'success'
           END AS s
) st
WHERE ap.status = 'accepted';


-- ---------------------------------------------------------------------
-- 6. Enrolments : one per accepted application
-- ---------------------------------------------------------------------
INSERT INTO enrolment
    (application_id, learner_no, advisor_id, enrolled_on, status, last_active_at)
WITH advisors AS (
    SELECT array_agg(staff_id ORDER BY staff_id) AS ids
    FROM staff
    WHERE staff_role = 'success_advisor'
)
SELECT
    ap.application_id,
    'NOU/' || to_char(c.starts_on, 'YYYY') || '/' || lpad(ap.application_id::text, 7, '0'),
    ad.ids[1 + floor(rnd01(ap.application_id, 61) * array_length(ad.ids, 1))::int],
    c.starts_on,
    s.st,
    CASE WHEN s.st = 'withdrawn'
         THEN c.starts_on::timestamptz + ((20 + rnd01(ap.application_id, 63) * 90) * INTERVAL '1 day')
         ELSE c.starts_on::timestamptz + ((rnd01(ap.application_id, 63) * 300) * INTERVAL '1 day')
    END
FROM application ap
JOIN cohort c ON c.cohort_id = ap.cohort_id
CROSS JOIN advisors ad
CROSS JOIN LATERAL (
    SELECT CASE
             WHEN c.starts_on > CURRENT_DATE                  THEN 'active'
             WHEN rnd01(ap.application_id, 62) < 0.14         THEN 'withdrawn'
             WHEN rnd01(ap.application_id, 62) < 0.20         THEN 'deferred'
             WHEN rnd01(ap.application_id, 62) < 0.26
                  AND c.starts_on < DATE '2025-06-01'         THEN 'graduated'
             ELSE 'active'
           END AS st
) s
WHERE ap.status = 'accepted';


-- Keep the denormalised seat counter consistent with the enrolment rows.
UPDATE cohort c
SET seats_taken = COALESCE(e.n, 0)
FROM (
    SELECT ap.cohort_id, count(*) AS n
    FROM enrolment en
    JOIN application ap ON ap.application_id = en.application_id
    GROUP BY ap.cohort_id
) e
WHERE e.cohort_id = c.cohort_id;


-- ---------------------------------------------------------------------
-- 7. Course registrations : first two semesters of the learner's programme
-- ---------------------------------------------------------------------
INSERT INTO course_registration
    (enrolment_id, course_id, academic_session, registered_at, score, grade)
SELECT
    en.enrolment_id,
    co.course_id,
    to_char(c.starts_on, 'YYYY') || '/' || to_char(c.starts_on + 365, 'YYYY'),
    c.starts_on::timestamptz
        + ((1 + rnd01(en.enrolment_id * 128 + co.course_id, 71) * 10) * INTERVAL '1 day'),
    sc.score,
    CASE
      WHEN sc.score IS NULL THEN NULL
      WHEN sc.score >= 70   THEN 'A'
      WHEN sc.score >= 60   THEN 'B'
      WHEN sc.score >= 50   THEN 'C'
      WHEN sc.score >= 45   THEN 'D'
      WHEN sc.score >= 40   THEN 'E'
      ELSE 'F'
    END
FROM enrolment en
JOIN application ap ON ap.application_id = en.application_id
JOIN cohort c       ON c.cohort_id       = ap.cohort_id
JOIN course co      ON co.programme_id   = c.programme_id AND co.semester_no <= 2
CROSS JOIN LATERAL (
    SELECT CASE
             WHEN c.starts_on > CURRENT_DATE - 120 THEN NULL     -- not yet graded
             ELSE round((32 + rnd01(en.enrolment_id * 128 + co.course_id, 72) * 62), 2)
           END AS score
) sc;


-- ---------------------------------------------------------------------
-- 8. Advisor interactions (re-modelled as documents in Portfolio 4)
-- ---------------------------------------------------------------------
INSERT INTO advisor_interaction
    (enrolment_id, advisor_id, contact_mode, occurred_at,
     duration_seconds, outcome, notes)
SELECT
    en.enrolment_id,
    en.advisor_id,
    (ARRAY['call','whatsapp','whatsapp','email','video','sms'])
        [1 + floor(rnd01(en.enrolment_id * 32 + n, 81) * 5.999)::int],
    en.enrolled_on::timestamptz
        + ((n * 11 + rnd01(en.enrolment_id * 32 + n, 82) * 9) * INTERVAL '1 day'),
    CASE WHEN rnd01(en.enrolment_id * 32 + n, 83) < 0.25
         THEN 0
         ELSE (45 + rnd01(en.enrolment_id * 32 + n, 84) * 1500)::int END,
    oc.v,
    CASE WHEN rnd01(en.enrolment_id * 32 + n, 85) < 0.35
         THEN 'Discussed ' ||
              (ARRAY['course registration','payment plan','exam readiness',
                     'platform access','study schedule','deferral request'])
                  [1 + floor(rnd01(en.enrolment_id * 32 + n, 86) * 5.999)::int]
         ELSE NULL
    END
FROM enrolment en
CROSS JOIN LATERAL generate_series(1, 1 + (en.enrolment_id % 12)) AS n
CROSS JOIN LATERAL (
    SELECT CASE
             WHEN rnd01(en.enrolment_id * 32 + n, 83) < 0.25 THEN 'no_answer'
             WHEN rnd01(en.enrolment_id * 32 + n, 83) < 0.35 THEN 'rescheduled'
             WHEN rnd01(en.enrolment_id * 32 + n, 83) < 0.42 THEN 'escalated'
             WHEN rnd01(en.enrolment_id * 32 + n, 83) < 0.70 THEN 'reached'
             ELSE 'resolved'
           END AS v
) oc;


-- ---------------------------------------------------------------------
-- 9. Statistics and verification
-- ---------------------------------------------------------------------
ANALYZE;

SELECT 'applicant'            AS table_name, count(*) AS row_count FROM applicant
UNION ALL SELECT 'application',          count(*) FROM application
UNION ALL SELECT 'application_document', count(*) FROM application_document
UNION ALL SELECT 'payment',              count(*) FROM payment
UNION ALL SELECT 'enrolment',            count(*) FROM enrolment
UNION ALL SELECT 'course_registration',  count(*) FROM course_registration
UNION ALL SELECT 'advisor_interaction',  count(*) FROM advisor_interaction
ORDER BY table_name;

SELECT status, count(*) AS applications
FROM application
GROUP BY status
ORDER BY applications DESC;
