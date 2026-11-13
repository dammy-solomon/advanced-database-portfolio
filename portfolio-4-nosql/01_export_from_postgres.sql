-- =====================================================================
-- Portfolio 4 : export the learner engagement model from PostgreSQL
--
-- Produces one JSON document per LEARNER, with that learner's advisor
-- interactions EMBEDDED as an array. This is the whole point of the
-- exercise: in PostgreSQL these live in seven tables and answering
-- "show me this learner and everything we know about them" needs a
-- six-way join. As a document it is a single read.
--
-- Output is JSON Lines (one document per line), which MongoDB Compass
-- imports directly.
--
-- Run from Command Prompt, NOT from inside psql:
--   psql.exe -p 5433 -U postgres -d nou -f 01_export_from_postgres.sql
-- =====================================================================

SET search_path TO nou, public;

\t on
\a
\pset format unaligned

\o 'C:/Users/damilare.solomon/Desktop/MIT/MIT 8103/CA/advanced_database_portfolio/portfolio-4-nosql/learner_engagement.json'

SELECT row_to_json(doc)
FROM (
    SELECT
        e.learner_no                                        AS "_id",
        ap.person_ref                                       AS person_ref,
        json_build_object(
            'first', ap.first_name,
            'last',  ap.last_name
        )                                                   AS name,
        ap.email                                            AS email,
        ap.state_of_origin                                  AS state_of_origin,
        json_build_object(
            'code',    p.programme_code,
            'name',    p.programme_name,
            'faculty', f.faculty_name,
            'level',   p.degree_level
        )                                                   AS programme,
        json_build_object(
            'intake_code', c.intake_code,
            'starts_on',   to_char(c.starts_on, 'YYYY-MM-DD')
        )                                                   AS cohort,
        ch.channel_name                                     AS acquisition_channel,
        json_build_object(
            'enrolled_on', to_char(e.enrolled_on, 'YYYY-MM-DD'),
            'status',      e.status,
            'advisor',     adv.full_name,
            'advisor_no',  adv.staff_no
        )                                                   AS enrolment,
        COALESCE(ix.items, '[]'::json)                      AS interactions,
        COALESCE(ix.n, 0)                                   AS interaction_count,
        COALESCE(ix.reached, 0)                             AS reached_count
    FROM enrolment e
    JOIN application a   ON a.application_id = e.application_id
    JOIN applicant  ap   ON ap.applicant_id  = a.applicant_id
    JOIN cohort     c    ON c.cohort_id      = a.cohort_id
    JOIN programme  p    ON p.programme_id   = c.programme_id
    JOIN faculty    f    ON f.faculty_id     = p.faculty_id
    JOIN channel    ch   ON ch.channel_id    = a.channel_id
    LEFT JOIN staff adv  ON adv.staff_id     = e.advisor_id
    LEFT JOIN LATERAL (
        SELECT
            json_agg(
                json_build_object(
                    'occurred_at',      to_char(i.occurred_at, 'YYYY-MM-DD"T"HH24:MI:SS'),
                    'year_month',       to_char(i.occurred_at, 'YYYY-MM'),
                    'mode',             i.contact_mode,
                    'outcome',          i.outcome,
                    'duration_seconds', i.duration_seconds,
                    'notes',            i.notes
                ) ORDER BY i.occurred_at
            )                                               AS items,
            count(*)                                        AS n,
            count(*) FILTER (WHERE i.outcome IN ('reached','resolved')) AS reached
        FROM advisor_interaction i
        WHERE i.enrolment_id = e.enrolment_id
    ) ix ON TRUE
) doc;

\o
\t off
