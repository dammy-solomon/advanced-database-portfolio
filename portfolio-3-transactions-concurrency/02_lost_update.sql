-- =====================================================================
-- Portfolio 3 / Part 2 : THE PROBLEM -- lost update at READ COMMITTED
--
-- Requires TWO sessions. In pgAdmin open two Query Tool tabs on the
-- `nou` database and TURN OFF AUTOCOMMIT in both (Query Tool toolbar ->
-- the ... menu -> Auto commit). Without that, each statement commits on
-- its own and no transaction is ever held open.
--
-- Run the numbered steps in the order shown, alternating between tabs.
-- =====================================================================

-- ---------- BOTH SESSIONS: reset to one free seat ----------
-- (run 00_setup_scenario.sql first, then this in either tab)
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
SELECT seats_taken, seat_capacity, seat_capacity - seats_taken AS remaining
  FROM cohort WHERE cohort_id = 999;
-- Returns 49 / 50 / 1.  A sees one free seat.  DO NOT COMMIT YET.


-- =====================================================================
-- SESSION B                                     -- STEP 2
-- =====================================================================
BEGIN;
SET search_path TO nou, public;
SELECT seats_taken, seat_capacity, seat_capacity - seats_taken AS remaining
  FROM cohort WHERE cohort_id = 999;
-- Also returns 49 / 50 / 1.  B sees the SAME free seat.
-- This read is not blocked: readers do not block readers.


-- =====================================================================
-- SESSION A                                     -- STEP 3
-- =====================================================================
-- A writes back the value it read (49) plus one. This is what
-- application code does when it reads a value, computes in memory, and
-- writes the result -- the classic read-modify-write.
UPDATE cohort SET seats_taken = 50 WHERE cohort_id = 999;

UPDATE application SET status = 'accepted'
 WHERE application_id = (SELECT a.application_id FROM application a
                         JOIN applicant ap ON ap.applicant_id = a.applicant_id
                         WHERE ap.person_ref = 'RACE-A');

INSERT INTO enrolment (application_id, learner_no, advisor_id, enrolled_on, status)
SELECT a.application_id, 'NOU/2026/LOST-A', 41, DATE '2026-09-07', 'active'
  FROM application a JOIN applicant ap ON ap.applicant_id = a.applicant_id
 WHERE ap.person_ref = 'RACE-A';

COMMIT;


-- =====================================================================
-- SESSION B                                     -- STEP 4
-- =====================================================================
-- B still holds 49 in memory and writes 50 as well, overwriting A.
UPDATE cohort SET seats_taken = 50 WHERE cohort_id = 999;

UPDATE application SET status = 'accepted'
 WHERE application_id = (SELECT a.application_id FROM application a
                         JOIN applicant ap ON ap.applicant_id = a.applicant_id
                         WHERE ap.person_ref = 'RACE-B');

INSERT INTO enrolment (application_id, learner_no, advisor_id, enrolled_on, status)
SELECT a.application_id, 'NOU/2026/LOST-B', 41, DATE '2026-09-07', 'active'
  FROM application a JOIN applicant ap ON ap.applicant_id = a.applicant_id
 WHERE ap.person_ref = 'RACE-B';

COMMIT;


-- =====================================================================
-- EITHER SESSION                                -- STEP 5 : the damage
-- =====================================================================
SELECT c.seats_taken,
       c.seat_capacity,
       (SELECT count(*) FROM enrolment e JOIN application a
          ON a.application_id = e.application_id WHERE a.cohort_id = 999) AS actual_enrolments
FROM cohort c WHERE c.cohort_id = 999;

-- RESULT: seats_taken = 50, actual_enrolments = 2.
-- Two learners were enrolled but the counter advanced by one. A's write
-- was lost. Neither session saw an error. Nothing in the database
-- reports that anything went wrong -- which is what makes the lost
-- update dangerous.
