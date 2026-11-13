-- =====================================================================
-- Portfolio 5 / Part 1 : horizontal partitioning in PostgreSQL
--
-- Partitioning is single-node sharding: the same idea of splitting one
-- logical table across several physical stores by a partition key, but
-- without the network. It is the concept a distributed system applies
-- across machines, demonstrable on one laptop.
--
-- Here `application` is range-partitioned by submitted_at, one
-- partition per intake year. The payoff is PARTITION PRUNING: a query
-- bounded to one year never touches the other partitions at all.
--
-- Run from Command Prompt:
--   psql.exe -p 5433 -U postgres -d nou -f 01_partitioning_postgres.sql
-- =====================================================================

SET search_path TO nou, public;

DROP TABLE IF EXISTS application_part CASCADE;

CREATE TABLE application_part (
    application_id BIGINT      NOT NULL,
    applicant_id   BIGINT      NOT NULL,
    cohort_id      SMALLINT    NOT NULL,
    channel_id     SMALLINT    NOT NULL,
    officer_id     INTEGER,
    status         VARCHAR(16) NOT NULL,
    submitted_at   TIMESTAMPTZ NOT NULL,
    decided_at     TIMESTAMPTZ,
    -- The partition key MUST be part of the primary key. This is a real
    -- constraint of declarative partitioning, not a design choice:
    -- PostgreSQL cannot enforce global uniqueness across partitions.
    PRIMARY KEY (application_id, submitted_at)
) PARTITION BY RANGE (submitted_at);

CREATE TABLE application_2024 PARTITION OF application_part
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE application_2025 PARTITION OF application_part
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
CREATE TABLE application_2026 PARTITION OF application_part
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
CREATE TABLE application_2027 PARTITION OF application_part
    FOR VALUES FROM ('2027-01-01') TO ('2028-01-01');

INSERT INTO application_part
SELECT application_id, applicant_id, cohort_id, channel_id,
       officer_id, status, submitted_at, decided_at
FROM application;

CREATE INDEX ON application_part (cohort_id);

ANALYZE application_part;


-- ---------------------------------------------------------------------
-- How the rows distributed across partitions
-- ---------------------------------------------------------------------
SELECT c.relname                                   AS partition,
       to_char(s.n_live_tup, 'FM999,999,999')      AS rows,
       pg_size_pretty(pg_relation_size(c.oid))     AS size
FROM pg_class c
JOIN pg_stat_user_tables s ON s.relid = c.oid
WHERE c.relname LIKE 'application_20%'
ORDER BY c.relname;


-- ---------------------------------------------------------------------
-- PARTITION PRUNING : a query bounded to 2026 reads ONE partition
-- ---------------------------------------------------------------------
\echo ''
\echo '=== PRUNED : single year, should scan only application_2026 ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), count(*) FILTER (WHERE status = 'accepted') AS accepted
FROM application_part
WHERE submitted_at >= TIMESTAMPTZ '2026-01-01'
  AND submitted_at <  TIMESTAMPTZ '2027-01-01';


-- ---------------------------------------------------------------------
-- NOT PRUNED : no bound on the partition key, so every partition is read
-- ---------------------------------------------------------------------
\echo ''
\echo '=== NOT PRUNED : no partition key predicate, scans all four ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), count(*) FILTER (WHERE status = 'accepted') AS accepted
FROM application_part;


-- ---------------------------------------------------------------------
-- The same query against the UNPARTITIONED table, for comparison
-- ---------------------------------------------------------------------
\echo ''
\echo '=== BASELINE : unpartitioned application table, same 2026 filter ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), count(*) FILTER (WHERE status = 'accepted') AS accepted
FROM application
WHERE submitted_at >= TIMESTAMPTZ '2026-01-01'
  AND submitted_at <  TIMESTAMPTZ '2027-01-01';
