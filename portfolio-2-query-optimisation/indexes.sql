-- =====================================================================
-- Portfolio 2 : indexes added after reviewing the baseline plans
--
-- Each index below is justified in performance-analysis.md against the
-- specific query and plan node it was created to fix.
-- =====================================================================

SET search_path TO nou, public;

-- Q2: officer's open queue. Composite, ordered most-selective-first.
CREATE INDEX idx_application_officer_cohort_status
    ON application (officer_id, cohort_id, status);

-- Q1 and general cohort reporting. PostgreSQL does NOT create indexes on
-- foreign key columns automatically; cohort_id was unindexed.
CREATE INDEX idx_application_cohort
    ON application (cohort_id);

-- Q3 outer side: only 22% of applications are accepted, so a partial
-- index is far smaller than a full one and the planner can use it to
-- drive the anti-join.
CREATE INDEX idx_application_accepted
    ON application (cohort_id, application_id)
    WHERE status = 'accepted';

-- Q3 inner side: the anti-join probes for a very specific combination.
-- Both predicates go in the WHERE clause rather than the key, so the
-- index holds only the ~30k rows that can ever match.
CREATE INDEX idx_payment_acceptance_success
    ON payment (application_id)
    WHERE purpose = 'acceptance_fee' AND status = 'success';

-- Q4: advisor + time range. Equality column first, range column second,
-- which lets one index satisfy both the filter and the ORDER BY.
CREATE INDEX idx_interaction_advisor_time
    ON advisor_interaction (advisor_id, occurred_at);

ANALYZE;

-- ---------------------------------------------------------------------
-- Indexes deliberately NOT created
-- ---------------------------------------------------------------------
-- course_registration (enrolment_id)
--     Already served by uq_registration (enrolment_id, course_id,
--     academic_session). enrolment_id is the leading column, so a
--     separate index would duplicate it and slow every write.
--
-- application (applicant_id)
--     Already served by uq_application_per_cohort (applicant_id,
--     cohort_id), same leading-column reasoning.
--
-- application (submitted_at)
--     Tested and rejected. The reporting queries scan a third to a half
--     of the table, which is past the point where an index scan beats a
--     sequential scan. See performance-analysis.md.
