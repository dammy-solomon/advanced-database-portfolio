-- =====================================================================
-- Portfolio 3 / Part 1 : atomicity -- COMMIT and ROLLBACK
--
-- Single session. Run 00_setup_scenario.sql first.
-- In pgAdmin, run each numbered block separately (select it, then F5).
-- =====================================================================

SET search_path TO nou, public;

-- This part needs TWO free seats: block 1A takes one and commits, and
-- block 1B must be able to take the second so that it fails on the
-- duplicate payment reference rather than on the capacity constraint.
-- (The concurrency demonstrations that follow reset this to 49, leaving
-- exactly one seat, which is what makes them race.)
UPDATE cohort SET seats_taken = 48 WHERE cohort_id = 999;

-- ---------------------------------------------------------------------
-- 1A. A SUCCESSFUL offer acceptance.
--
-- Accepting an offer is not one write. It is four, and they must all
-- happen or none of them: the application changes status, a seat is
-- allocated, the learner is enrolled, and the acceptance fee is
-- recorded. A partial result means a learner with a seat but no record
-- of payment, or a paid learner with no seat.
-- ---------------------------------------------------------------------
BEGIN;

    UPDATE application
       SET status = 'accepted'
     WHERE application_id = (SELECT a.application_id
                               FROM application a
                               JOIN applicant ap ON ap.applicant_id = a.applicant_id
                              WHERE ap.person_ref = 'RACE-A');

    UPDATE cohort
       SET seats_taken = seats_taken + 1
     WHERE cohort_id = 999;

    INSERT INTO enrolment (application_id, learner_no, advisor_id,
                           enrolled_on, status)
    SELECT a.application_id, 'NOU/2026/RACE-A', 41,
           DATE '2026-09-07', 'active'
      FROM application a
      JOIN applicant ap ON ap.applicant_id = a.applicant_id
     WHERE ap.person_ref = 'RACE-A';

    INSERT INTO payment (application_id, payment_ref, purpose, amount,
                         status, gateway, initiated_at, settled_at)
    SELECT a.application_id, 'PSK-RACE-A-001', 'acceptance_fee', 112500.00,
           'success', 'paystack', now(), now()
      FROM application a
      JOIN applicant ap ON ap.applicant_id = a.applicant_id
     WHERE ap.person_ref = 'RACE-A';

COMMIT;

-- Verify: all four effects are present.
SELECT c.seats_taken,
       (SELECT count(*) FROM application WHERE cohort_id = 999 AND status = 'accepted') AS accepted,
       (SELECT count(*) FROM enrolment e JOIN application a
          ON a.application_id = e.application_id WHERE a.cohort_id = 999)              AS enrolments,
       (SELECT count(*) FROM payment p JOIN application a
          ON a.application_id = p.application_id WHERE a.cohort_id = 999)              AS payments
FROM cohort c WHERE c.cohort_id = 999;


-- ---------------------------------------------------------------------
-- 1B. A FAILED offer acceptance -- the whole transaction is undone.
--
-- Same four writes for the second applicant, but the payment reference
-- collides with one that already exists. payment_ref carries a UNIQUE
-- constraint, so the fourth statement raises SQLSTATE 23505.
--
-- The point: the seat increment in statement two is also undone, even
-- though that statement itself succeeded. Note the seats_taken value
-- before and after -- it does not move.
-- ---------------------------------------------------------------------
BEGIN;

    UPDATE application
       SET status = 'accepted'
     WHERE application_id = (SELECT a.application_id
                               FROM application a
                               JOIN applicant ap ON ap.applicant_id = a.applicant_id
                              WHERE ap.person_ref = 'RACE-B');

    UPDATE cohort
       SET seats_taken = seats_taken + 1
     WHERE cohort_id = 999;

    -- This succeeds...
    INSERT INTO enrolment (application_id, learner_no, advisor_id,
                           enrolled_on, status)
    SELECT a.application_id, 'NOU/2026/RACE-B', 41,
           DATE '2026-09-07', 'active'
      FROM application a
      JOIN applicant ap ON ap.applicant_id = a.applicant_id
     WHERE ap.person_ref = 'RACE-B';

    -- ...and this fails: 'PSK-RACE-A-001' was already used in block 1A.
    INSERT INTO payment (application_id, payment_ref, purpose, amount,
                         status, gateway, initiated_at, settled_at)
    SELECT a.application_id, 'PSK-RACE-A-001', 'acceptance_fee', 112500.00,
           'success', 'paystack', now(), now()
      FROM application a
      JOIN applicant ap ON ap.applicant_id = a.applicant_id
     WHERE ap.person_ref = 'RACE-B';

ROLLBACK;

-- Verify: nothing from block 1B survived. Counts are unchanged from 1A.
SELECT c.seats_taken,
       (SELECT count(*) FROM application WHERE cohort_id = 999 AND status = 'accepted') AS accepted,
       (SELECT count(*) FROM enrolment e JOIN application a
          ON a.application_id = e.application_id WHERE a.cohort_id = 999)              AS enrolments,
       (SELECT count(*) FROM payment p JOIN application a
          ON a.application_id = p.application_id WHERE a.cohort_id = 999)              AS payments
FROM cohort c WHERE c.cohort_id = 999;
