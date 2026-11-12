-- Q4: One success advisor's contact history over a 90-day window (operational).
SELECT i.occurred_at, i.contact_mode, i.outcome,
       i.duration_seconds, e.learner_no
FROM nou.advisor_interaction i
JOIN nou.enrolment e ON e.enrolment_id = i.enrolment_id
WHERE i.advisor_id   = 45
  AND i.occurred_at >= TIMESTAMPTZ '2026-01-01'
  AND i.occurred_at <  TIMESTAMPTZ '2026-04-01'
ORDER BY i.occurred_at DESC;
