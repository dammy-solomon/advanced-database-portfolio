-- Q1: Admissions officer conversion rate for the two 2026 intakes.
SELECT s.staff_no,
       s.full_name,
       count(*)                                              AS applications_handled,
       count(*) FILTER (WHERE a.status = 'accepted')         AS accepted,
       round(100.0 * count(*) FILTER (WHERE a.status = 'accepted')
             / count(*), 2)                                  AS conversion_pct
FROM nou.application a
JOIN nou.staff  s ON s.staff_id  = a.officer_id
JOIN nou.cohort c ON c.cohort_id = a.cohort_id
WHERE c.intake_code IN ('MAY-2026','SEP-2026')
GROUP BY s.staff_no, s.full_name
ORDER BY conversion_pct DESC, applications_handled DESC;
