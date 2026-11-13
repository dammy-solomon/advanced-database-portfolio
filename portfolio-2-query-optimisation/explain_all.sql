-- =====================================================================
-- Portfolio 2 : run all five queries under EXPLAIN (ANALYZE, BUFFERS)
--
-- Run this file TWICE. Use the output of the SECOND run: the first run
-- warms the cache and would overstate the improvement.
-- =====================================================================

SET search_path TO nou, public;

\echo '====================== Q1 : officer conversion (reporting) ======================'
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.staff_no, s.full_name,
       count(*) AS applications_handled,
       count(*) FILTER (WHERE a.status = 'accepted') AS accepted,
       round(100.0 * count(*) FILTER (WHERE a.status = 'accepted') / count(*), 2) AS conversion_pct
FROM nou.application a
JOIN nou.staff  s ON s.staff_id  = a.officer_id
JOIN nou.cohort c ON c.cohort_id = a.cohort_id
WHERE c.intake_code IN ('MAY-2026','SEP-2026')
GROUP BY s.staff_no, s.full_name
ORDER BY conversion_pct DESC, applications_handled DESC;

\echo ''
\echo '====================== Q2 : officer review queue (operational) =================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.application_id, ap.person_ref, ap.first_name, ap.last_name,
       a.status, a.submitted_at
FROM nou.application a
JOIN nou.applicant ap ON ap.applicant_id = a.applicant_id
WHERE a.officer_id = 7
  AND a.cohort_id  = 6
  AND a.status IN ('submitted','under_review')
ORDER BY a.submitted_at;

\echo ''
\echo '====================== Q3 : accepted without acceptance payment ================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.application_id, ap.person_ref, ap.email, c.intake_code
FROM nou.application a
JOIN nou.applicant ap ON ap.applicant_id = a.applicant_id
JOIN nou.cohort    c  ON c.cohort_id     = a.cohort_id
WHERE a.status = 'accepted'
  AND NOT EXISTS (SELECT 1 FROM nou.payment p
                   WHERE p.application_id = a.application_id
                     AND p.purpose = 'acceptance_fee'
                     AND p.status  = 'success')
ORDER BY c.intake_code, a.application_id;

\echo ''
\echo '====================== Q4 : advisor contact history (operational) ==============='
EXPLAIN (ANALYZE, BUFFERS)
SELECT i.occurred_at, i.contact_mode, i.outcome,
       i.duration_seconds, e.learner_no
FROM nou.advisor_interaction i
JOIN nou.enrolment e ON e.enrolment_id = i.enrolment_id
WHERE i.advisor_id   = 45
  AND i.occurred_at >= TIMESTAMPTZ '2026-01-01'
  AND i.occurred_at <  TIMESTAMPTZ '2026-04-01'
ORDER BY i.occurred_at DESC;

\echo ''
\echo '====================== Q5 : learner lookup (point query) ========================'
EXPLAIN (ANALYZE, BUFFERS)
SELECT ap.person_ref, ap.first_name, ap.last_name,
       a.status, c.intake_code, e.learner_no,
       count(cr.registration_id) AS courses_registered
FROM nou.applicant ap
JOIN nou.application a         ON a.applicant_id   = ap.applicant_id
JOIN nou.cohort c              ON c.cohort_id      = a.cohort_id
LEFT JOIN nou.enrolment e      ON e.application_id = a.application_id
LEFT JOIN nou.course_registration cr ON cr.enrolment_id = e.enrolment_id
WHERE ap.person_ref = 'NOU-P-00057431'
GROUP BY ap.person_ref, ap.first_name, ap.last_name,
         a.status, c.intake_code, e.learner_no;
