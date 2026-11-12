-- Q2: An admissions officer's open review queue for one cohort (operational).
SELECT a.application_id, ap.person_ref, ap.first_name, ap.last_name,
       a.status, a.submitted_at
FROM nou.application a
JOIN nou.applicant ap ON ap.applicant_id = a.applicant_id
WHERE a.officer_id = 7
  AND a.cohort_id  = 6
  AND a.status IN ('submitted','under_review')
ORDER BY a.submitted_at;
