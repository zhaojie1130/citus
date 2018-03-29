/* citus--7.4-1--7.4-2 */
SET search_path = 'pg_catalog';

DROP FUNCTION IF EXISTS worker_hash_partition_table(bigint, integer, text, text, oid, integer);

CREATE FUNCTION worker_hash_partition_table(bigint, integer, text, text, oid, anyarray)
    RETURNS void
    LANGUAGE C STRICT
    AS 'MODULE_PATHNAME', $$worker_hash_partition_table$$;
COMMENT ON FUNCTION worker_hash_partition_table(bigint, integer, text, text, oid,
                                                anyarray)
    IS 'hash partition query results';

RESET search_path;
