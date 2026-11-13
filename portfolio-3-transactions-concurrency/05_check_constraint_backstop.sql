-- =====================================================================
-- Portfolio 3 / Part 5 : the constraint as last line of defence
--
-- Locking and isolation are application-level disciplines -- they work
-- only if every piece of code that touches the table uses them. The
-- CHECK constraint is enforced by the storage engine and cannot be
-- bypassed by a careless script, a manual fix, or a future developer.
-- Single session; no concurrency required.
-- =====================================================================

SET search_path TO nou, public;

-- Force the cohort to full.
UPDATE cohort SET seats_taken = seat_capacity WHERE cohort_id = 999;

SELECT cohort_id, seats_taken, seat_capacity FROM cohort WHERE cohort_id = 999;
-- 999 | 50 | 50

-- Now try to allocate a 51st seat with a direct, unguarded UPDATE --
-- no transaction discipline, no lock, no application logic.
UPDATE cohort SET seats_taken = seats_taken + 1 WHERE cohort_id = 999;

-- ERROR:  new row for relation "cohort" violates check constraint "ck_cohort_seats"
-- DETAIL:  Failing row contains (999, 1, RACE-TEST, ..., 50, 51).
-- SQLSTATE: 23514
--
-- The invariant seats_taken <= seat_capacity holds regardless of how
-- the data is reached. This is why the constraint is declared in the
-- schema (Portfolio 1) rather than checked in application code.
