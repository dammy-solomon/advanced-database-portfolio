-- =====================================================================
-- Portfolio 3 / Part 4 : FIX TWO -- SERIALIZABLE isolation
--
-- Optimistic rather than pessimistic. No locks are taken at read time.
-- PostgreSQL tracks read/write dependencies between transactions and
-- aborts one if committing both would produce a result no serial order
-- could have produced.
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
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SET search_path TO nou, public;
SELECT seats_taken FROM cohort WHERE cohort_id = 999;   -- 49, no lock taken


-- =====================================================================
-- SESSION B                                     -- STEP 2
-- =====================================================================
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SET search_path TO nou, public;
SELECT seats_taken FROM cohort WHERE cohort_id = 999;   -- 49, also no lock
-- Note: this does NOT block, unlike FOR UPDATE.


-- =====================================================================
-- SESSION A                                     -- STEP 3
-- =====================================================================
UPDATE cohort SET seats_taken = seats_taken + 1 WHERE cohort_id = 999;
UPDATE application SET status = 'accepted'
 WHERE application_id = (SELECT a.application_id FROM application a
                         JOIN applicant ap ON ap.applicant_id = a.applicant_id
                         WHERE ap.person_ref = 'RACE-A');
COMMIT;                                                  -- succeeds


-- =====================================================================
-- SESSION B                                     -- STEP 4 : the abort
-- =====================================================================
UPDATE cohort SET seats_taken = seats_taken + 1 WHERE cohort_id = 999;

-- ERROR:  could not serialize access due to concurrent update
-- SQLSTATE: 40001
--
-- Screenshot this error. It is the evidence for this section.
-- 40001 is not a bug and not corruption -- it is the database refusing
-- to let a lost update happen.

ROLLBACK;
-- Real application code catches SQLSTATE 40001 and retries the whole
-- transaction. On retry, B reads 50, finds no seats, and declines
-- cleanly.


-- =====================================================================
-- EITHER SESSION                                -- STEP 5 : verify
-- =====================================================================
SELECT c.seats_taken, c.seat_capacity,
       (SELECT count(*) FROM application WHERE cohort_id = 999 AND status = 'accepted') AS accepted
FROM cohort c WHERE c.cohort_id = 999;
-- RESULT: seats_taken = 50, accepted = 1.
