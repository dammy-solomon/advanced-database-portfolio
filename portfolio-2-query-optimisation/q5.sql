-- Q5: Single-learner lookup by stable person reference (point query).
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
