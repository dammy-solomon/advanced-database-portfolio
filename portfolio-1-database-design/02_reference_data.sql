-- =====================================================================
-- Northgate Open University (NOU)
-- Portfolio 1 : reference (lookup) data
--
-- Run after 01_schema.sql:  psql -d nou -f 02_reference_data.sql
-- =====================================================================

SET search_path TO nou, public;


-- ---------------------------------------------------------------------
-- Channels
-- ---------------------------------------------------------------------
INSERT INTO channel (channel_id, channel_name, is_paid_media) VALUES
    (1, 'Website',          FALSE),
    (2, 'Walk-in',          FALSE),
    (3, 'Paid Social',      TRUE ),
    (4, 'Search Ads',       TRUE ),
    (5, 'Student Referral', FALSE),
    (6, 'Education Agent',  TRUE );


-- ---------------------------------------------------------------------
-- Faculties
-- ---------------------------------------------------------------------
INSERT INTO faculty (faculty_id, faculty_name) VALUES
    (1, 'Computing and Applied Sciences'),
    (2, 'Management and Social Sciences'),
    (3, 'Health and Allied Sciences'),
    (4, 'Education');


-- ---------------------------------------------------------------------
-- Programmes
-- ---------------------------------------------------------------------
INSERT INTO programme
    (programme_id, programme_code, programme_name, faculty_id,
     degree_level, duration_semesters, tuition_per_semester) VALUES
    ( 1, 'BSC-CS',   'B.Sc. Computer Science',                 1, 'Undergraduate', 8,  450000.00),
    ( 2, 'BSC-SE',   'B.Sc. Software Engineering',             1, 'Undergraduate', 8,  450000.00),
    ( 3, 'BSC-CYB',  'B.Sc. Cyber Security',                   1, 'Undergraduate', 8,  480000.00),
    ( 4, 'BSC-DS',   'B.Sc. Data Science',                     1, 'Undergraduate', 8,  480000.00),
    ( 5, 'BSC-ACC',  'B.Sc. Accounting',                       2, 'Undergraduate', 8,  380000.00),
    ( 6, 'BSC-BA',   'B.Sc. Business Administration',          2, 'Undergraduate', 8,  380000.00),
    ( 7, 'BSC-ECO',  'B.Sc. Economics',                        2, 'Undergraduate', 8,  380000.00),
    ( 8, 'BSC-PH',   'B.Sc. Public Health',                    3, 'Undergraduate', 8,  420000.00),
    ( 9, 'BSC-NUR',  'B.Sc. Nursing Science',                  3, 'Undergraduate', 10, 560000.00),
    (10, 'BED-EDU',  'B.Ed. Educational Technology',           4, 'Undergraduate', 8,  340000.00),
    (11, 'MSC-CS',   'M.Sc. Computer Science',                 1, 'Postgraduate',  4,  720000.00),
    (12, 'MSC-IT',   'M.Sc. Information Technology',           1, 'Postgraduate',  4,  720000.00),
    (13, 'MBA-GEN',  'Master of Business Administration',      2, 'Postgraduate',  4,  950000.00),
    (14, 'MPH-GEN',  'Master of Public Health',                3, 'Postgraduate',  4,  780000.00);


-- ---------------------------------------------------------------------
-- Cohorts : three intakes a year across 2025 and 2026
-- ---------------------------------------------------------------------
INSERT INTO cohort
    (cohort_id, programme_id, intake_code, opens_on, closes_on, starts_on,
     seat_capacity, seats_taken)
SELECT
    (row_number() OVER (ORDER BY p.programme_id, w.ord))::smallint       AS cohort_id,
    p.programme_id,
    w.intake_code,
    w.opens_on,
    w.closes_on,
    w.starts_on,
    -- Postgraduate cohorts are deliberately smaller than undergraduate ones.
    CASE WHEN p.degree_level = 'Postgraduate' THEN 220 ELSE 600 END      AS seat_capacity,
    0                                                                    AS seats_taken
FROM programme p
CROSS JOIN (VALUES
        (1, 'JAN-2025', DATE '2024-09-15', DATE '2024-12-20', DATE '2025-01-13'),
        (2, 'MAY-2025', DATE '2025-01-20', DATE '2025-04-18', DATE '2025-05-05'),
        (3, 'SEP-2025', DATE '2025-05-12', DATE '2025-08-22', DATE '2025-09-08'),
        (4, 'JAN-2026', DATE '2025-09-15', DATE '2025-12-19', DATE '2026-01-12'),
        (5, 'MAY-2026', DATE '2026-01-19', DATE '2026-04-17', DATE '2026-05-04'),
        (6, 'SEP-2026', DATE '2026-05-11', DATE '2026-08-21', DATE '2026-09-07')
    ) AS w(ord, intake_code, opens_on, closes_on, starts_on);


-- ---------------------------------------------------------------------
-- Staff : admissions officers, success advisors, registry
-- ---------------------------------------------------------------------
INSERT INTO staff (staff_no, full_name, work_email, staff_role, team, hired_on, is_active)
SELECT
    'NOU-S-' || lpad(g::text, 4, '0'),
    fn.v || ' ' || ln.v,
    lower(fn.v) || '.' || lower(ln.v) || g || '@nou.example.edu',
    r.role_name,
    r.team_name,
    DATE '2022-01-10' + (g * 9 % 1400),
    (g % 17 <> 0)                      -- roughly 6% of staff have left
FROM generate_series(1, 72) AS g
CROSS JOIN LATERAL (
    SELECT (ARRAY['Chidi','Aisha','Tunde','Ngozi','Emeka','Fatima','Seyi','Blessing',
                  'Ibrahim','Chioma','Yusuf','Adaeze','Kelechi','Hauwa','Olumide',
                  'Zainab','Obinna','Temitope','Musa','Uchenna'])
           [1 + ((g * 7) % 20)] AS v
) fn
CROSS JOIN LATERAL (
    SELECT (ARRAY['Okafor','Bello','Adeyemi','Nwosu','Lawal','Eze','Balogun','Umar',
                  'Ogunleye','Danjuma','Iweala','Salami','Chukwu','Abubakar','Oyelaran',
                  'Nnamdi'])
           [1 + ((g * 11) % 16)] AS v
) ln
CROSS JOIN LATERAL (
    SELECT CASE
             WHEN g <= 40 THEN 'admissions_officer'
             WHEN g <= 66 THEN 'success_advisor'
             ELSE 'registry'
           END AS role_name,
           CASE
             WHEN g <= 20 THEN 'Admissions - Undergraduate'
             WHEN g <= 40 THEN 'Admissions - Postgraduate'
             WHEN g <= 53 THEN 'Learner Success - Cohort A'
             WHEN g <= 66 THEN 'Learner Success - Cohort B'
             ELSE 'Registry'
           END AS team_name
) r;


-- ---------------------------------------------------------------------
-- Courses : 8 per programme, spread across the first four semesters
-- ---------------------------------------------------------------------
INSERT INTO course (course_code, course_title, credit_units, programme_id, semester_no)
SELECT
    p.programme_code || '-' || lpad(n::text, 3, '0'),
    p.programme_name || ' Module ' || n,
    2 + (n % 3),
    p.programme_id,
    1 + ((n - 1) / 2)
FROM programme p
CROSS JOIN generate_series(1, 8) AS n;


-- ---------------------------------------------------------------------
-- Sanity check
-- ---------------------------------------------------------------------
SELECT 'channel'   AS table_name, count(*) AS rows FROM channel
UNION ALL SELECT 'faculty',   count(*) FROM faculty
UNION ALL SELECT 'programme', count(*) FROM programme
UNION ALL SELECT 'cohort',    count(*) FROM cohort
UNION ALL SELECT 'staff',     count(*) FROM staff
UNION ALL SELECT 'course',    count(*) FROM course
ORDER BY table_name;
