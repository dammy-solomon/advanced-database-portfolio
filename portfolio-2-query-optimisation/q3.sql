-- Q3: Accepted applicants who never completed an acceptance-fee payment.
SELECT a.application_id, ap.person_ref, ap.email, c.intake_code
FROM nou.application a
JOIN nou.applicant ap ON ap.applicant_id = a.applicant_id
JOIN nou.cohort    c  ON c.cohort_id     = a.cohort_id
WHERE a.status = 'accepted'
  AND NOT EXISTS (
        SELECT 1
        FROM nou.payment p
        WHERE p.application_id = a.application_id
          AND p.purpose        = 'acceptance_fee'
          AND p.status         = 'success')
ORDER BY c.intake_code, a.application_id;
