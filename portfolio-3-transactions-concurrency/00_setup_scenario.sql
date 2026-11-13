-- =====================================================================
-- Portfolio 3 : controlled scenario setup
--
-- Creates a deliberately scarce cohort (one seat left) so that two
-- concurrent offer acceptances genuinely contend for the same row.
-- Safe to re-run between demonstrations.
--
-- Teardown order matters: enrolment -> application -> cohort, because
-- enrolment.application_id and application.cohort_id are both enforced
-- foreign keys and enrolment has no ON DELETE CASCADE.
-- =====================================================================

SET search_path TO nou, public;

-- 1. Tear down in dependency order.
DELETE FROM enrolment e
 USING application a
 WHERE a.application_id = e.application_id
   AND a.cohort_id = 999;

DELETE FROM application WHERE cohort_id = 999;
DELETE FROM cohort      WHERE cohort_id = 999;
DELETE FROM applicant   WHERE person_ref IN ('RACE-A','RACE-B');

-- 2. A sandbox cohort with exactly ONE seat remaining.
INSERT INTO cohort (cohort_id, programme_id, intake_code, opens_on,
                    closes_on, starts_on, seat_capacity, seats_taken)
VALUES (999, 1, 'RACE-TEST', DATE '2026-05-11', DATE '2026-08-21',
        DATE '2026-09-07', 50, 49);

-- 3. Two applicants holding offers on that cohort, ready to accept.
INSERT INTO applicant (person_ref, first_name, last_name, email)
VALUES ('RACE-A','Ada','Testcase','ada.race@mailbox.example.net'),
       ('RACE-B','Bola','Testcase','bola.race@mailbox.example.net');

INSERT INTO application (applicant_id, cohort_id, channel_id, officer_id,
                         status, submitted_at, decided_at)
SELECT applicant_id, 999, 1, 1, 'offer_issued',
       TIMESTAMPTZ '2026-06-01 10:00+01', TIMESTAMPTZ '2026-06-10 10:00+01'
FROM applicant WHERE person_ref IN ('RACE-A','RACE-B')
ORDER BY person_ref;

-- 4. Show the starting position.
SELECT c.cohort_id, c.seat_capacity, c.seats_taken,
       c.seat_capacity - c.seats_taken AS seats_remaining
FROM cohort c WHERE c.cohort_id = 999;

SELECT a.application_id, ap.person_ref, a.status
FROM application a
JOIN applicant ap ON ap.applicant_id = a.applicant_id
WHERE a.cohort_id = 999
ORDER BY ap.person_ref;
