-- =====================================================================
-- Portfolio 3 / Part 3 : FIX ONE -- pessimistic locking
--
-- Same two-session setup and the same race, with one change:
-- SELECT ... FOR UPDATE takes a row-level exclusive lock on the cohort
-- row at read time, so the second session cannot read a stale value.
-- =====================================================================

-- ---------- reset to one free seat ----------
UPDATE nou.cohort SET seats_taken = 49 WHERE cohort_id = 999;
DELETE FROM nou.enrolment e USING nou.application a
 WHERE a.application_id = e.application_id AND a.cohort_id = 999;
UPDATE nou.application SET status='offer_issued', decided_at=now()
 WHERE cohort_id = 999;
COMMIT;


-- =====================================================================
-- SESSION A                                     -- STEP 1
-- =====================================================================
BEGIN;
SET search_path TO nou, public;
SELECT seats_taken, seat_capacity
  FROM cohort WHERE cohort_id = 999
   FOR UPDATE;              -- <-- the only change, and it is the fix
-- Returns 49 / 50. The row is now locked until A commits or rolls back.


-- =====================================================================
-- SESSION B                                     -- STEP 2
-- =====================================================================
BEGIN;
SET search_path TO nou, public;
SELECT seats_taken, seat_capacity
  FROM cohort WHERE cohort_id = 999
   FOR UPDATE;
-- This HANGS. The query tool shows it still running. That is correct
-- behaviour, not a crash -- B is waiting for A's lock.
-- Screenshot this waiting state: it is the evidence of the control
-- mechanism working.


-- =====================================================================
-- SESSION A                                     -- STEP 3
-- =====================================================================
UPDATE cohort SET seats_taken = seats_taken + 1 WHERE cohort_id = 999;

UPDATE application SET status = 'accepted'
 WHERE application_id = (SELECT a.application_id FROM application a
                         JOIN applicant ap ON ap.applicant_id = a.applicant_id
                         WHERE ap.person_ref = 'RACE-A');

INSERT INTO enrolment (application_id, learner_no, advisor_id, enrolled_on, status)
SELECT a.application_id, 'NOU/2026/LOCK-A', 41, DATE '2026-09-07', 'active'
  FROM application a JOIN applicant ap ON ap.applicant_id = a.applicant_id
 WHERE ap.person_ref = 'RACE-A';

COMMIT;
-- The moment this commits, Session B's query returns.


-- =====================================================================
-- SESSION B                                     -- STEP 4
-- =====================================================================
-- B's SELECT now returns 50 / 50 -- the fresh value, not the stale 49.
-- Application logic checks remaining seats and finds none:
ROLLBACK;
-- B is correctly refused. In a real system this is where the user sees
-- "this intake is now full" rather than silently becoming the 51st
-- learner in a 50-seat cohort.


-- =====================================================================
-- EITHER SESSION                                -- STEP 5 : verify
-- =====================================================================
SELECT c.seats_taken, c.seat_capacity,
       (SELECT count(*) FROM enrolment e JOIN application a
          ON a.application_id = e.application_id WHERE a.cohort_id = 999) AS actual_enrolments
FROM cohort c WHERE c.cohort_id = 999;
-- RESULT: seats_taken = 50, actual_enrolments = 1. Counter and reality agree.
