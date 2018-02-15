-- Tests for modifying CTEs and CTEs in modifications
SET citus.next_shard_id TO 1502000;

CREATE SCHEMA with_modifying;
SET search_path TO with_modifying, public;

CREATE TABLE with_modifying.modify_table (id int, val int);
SELECT create_distributed_table('modify_table', 'id');

CREATE TABLE with_modifying.users_table (LIKE public.users_table INCLUDING ALL);
SELECT create_distributed_table('with_modifying.users_table', 'user_id');
INSERT INTO with_modifying.users_table SELECT * FROM public.users_table;

CREATE TABLE with_modifying.summary_table (id int, counter int);
SELECT create_distributed_table('summary_table', 'id');

CREATE TABLE with_modifying.anchor_table (id int);
SELECT create_reference_table('anchor_table');

-- basic insert query in CTE
WITH basic_insert AS (
	INSERT INTO users_table VALUES (1), (2), (3) RETURNING *
)
SELECT
	*
FROM
	basic_insert
ORDER BY
	user_id;

-- single-shard UPDATE in CTE
WITH basic_update AS (
	UPDATE users_table SET value_3=41 WHERE user_id=1 RETURNING *
)
SELECT
	*
FROM
	basic_update
ORDER BY
	user_id,
	time
LIMIT 10;

-- multi-shard UPDATE in CTE
WITH basic_update AS (
	UPDATE users_table SET value_3=42 WHERE value_2=1 RETURNING *
)
SELECT
	*
FROM
	basic_update
ORDER BY
	user_id,
	time
LIMIT 10;

-- single-shard DELETE in CTE
WITH basic_delete AS (
	DELETE FROM users_table WHERE user_id=6 RETURNING *
)
SELECT
	*
FROM
	basic_delete
ORDER BY
	user_id,
	time
LIMIT 10;

-- multi-shard DELETE in CTE
WITH basic_delete AS (
	DELETE FROM users_table WHERE value_3=41 RETURNING *
)
SELECT
	*
FROM
	basic_delete
ORDER BY
	user_id,
	time
LIMIT 10;

-- INSERT...SELECT query in CTE
WITH copy_table AS (
	INSERT INTO users_table SELECT * FROM users_table WHERE user_id = 0 OR user_id = 3 RETURNING *
)
SELECT
	*
FROM
	copy_table
ORDER BY
	user_id,
	time
LIMIT 10;

-- CTEs prior to INSERT...SELECT via the coordinator should work
WITH cte AS (
	SELECT user_id FROM users_table WHERE value_2 IN (1, 2)
)
INSERT INTO modify_table (SELECT * FROM cte);


WITH cte_1 AS (
	SELECT user_id, value_2 FROM users_table WHERE value_2 IN (1, 2, 3, 4)
),
cte_2 AS (
	SELECT user_id, value_2 FROM users_table WHERE value_2 IN (3, 4, 5, 6)
)
INSERT INTO modify_table (SELECT cte_1.user_id FROM cte_1 join cte_2 on cte_1.value_2=cte_2.value_2);


-- even if this is an INSERT...SELECT, the CTE is under SELECT
WITH cte AS (
	SELECT user_id, value_2 FROM users_table WHERE value_2 IN (1, 2)
)
INSERT INTO modify_table (SELECT (SELECT value_2 FROM cte GROUP BY value_2));


-- CTEs prior to any other modification should error out
WITH cte AS (
	SELECT value_2 FROM users_table WHERE user_id IN (1, 2, 3)
)
DELETE FROM modify_table WHERE id IN (SELECT value_2 FROM cte);


WITH cte AS (
	SELECT value_2 FROM users_table WHERE user_id IN (1, 2, 3)
)
UPDATE modify_table SET val=-1 WHERE val IN (SELECT * FROM cte);


WITH cte AS (
	WITH basic AS (
		SELECT value_2 FROM users_table WHERE user_id IN (1, 2, 3)
	)
	INSERT INTO modify_table (SELECT * FROM basic) RETURNING *
)
UPDATE modify_table SET val=-2 WHERE id IN (SELECT id FROM cte);


WITH cte AS (
	WITH basic AS (
		SELECT * FROM events_table WHERE event_type = 5
	),
	basic_2 AS (
		SELECT user_id FROM users_table
	)
	INSERT INTO modify_table (SELECT user_id FROM events_table) RETURNING *
)
SELECT * FROM cte;

WITH user_data AS (
	SELECT user_id, value_2 FROM users_table
)
INSERT INTO modify_table SELECT * FROM user_data;

WITH raw_data AS (
	DELETE FROM modify_table RETURNING *
)
INSERT INTO summary_table SELECT id, COUNT(*) AS counter FROM raw_data GROUP BY id;

SELECT * FROM summary_table ORDER BY id;
SELECT COUNT(*) FROM modify_table;

INSERT INTO modify_table VALUES (1,1), (2, 2), (3,3);

WITH raw_data AS (
	DELETE FROM modify_table RETURNING *
)
INSERT INTO summary_table SELECT id, COUNT(*) AS counter FROM raw_data GROUP BY id;

SELECT * FROM summary_table ORDER BY id, counter;
SELECT COUNT(*) FROM modify_table;

WITH insert_reference AS (
	INSERT INTO anchor_table VALUES (1), (2) RETURNING *
)
SELECT id FROM insert_reference ORDER BY id;

WITH anchor_data AS (
	SELECT * FROM anchor_table
),
raw_data AS (
	DELETE FROM modify_table RETURNING *
),
summary_data AS (
	DELETE FROM summary_table RETURNING *
)
INSERT INTO
	summary_table
SELECT id, SUM(counter) FROM (
	(SELECT raw_data.id, COUNT(*) AS counter FROM raw_data, anchor_data
		WHERE raw_data.id = anchor_data.id GROUP BY raw_data.id)
	UNION ALL
	(SELECT * FROM summary_data)) AS all_rows
GROUP BY
	id;

SELECT COUNT(*) FROM modify_table;
SELECT * FROM summary_table ORDER BY id, counter;

WITH added_data AS (
	INSERT INTO modify_table VALUES (1,2), (1,6), (2,4), (3,6) RETURNING *
),
raw_data AS (
	DELETE FROM modify_table WHERE id = 1 AND val = (SELECT MAX(val) FROM added_data) RETURNING *
)
INSERT INTO summary_table SELECT id, COUNT(*) AS counter FROM raw_data GROUP BY id;

SELECT COUNT(*) FROM modify_table;
SELECT * FROM summary_table ORDER BY id, counter;

-- Merge rows in the summary_table
WITH summary_data AS (
	DELETE FROM summary_table RETURNING *
)
INSERT INTO summary_table SELECT id, SUM(counter) AS counter FROM summary_data GROUP BY id;

SELECT * FROM summary_table ORDER BY id, counter;
SELECT * FROM modify_table ORDER BY id, val;
SELECT * FROM anchor_table ORDER BY id;

-- Check an unsupported query type
WITH added_data AS (
	INSERT INTO modify_table VALUES (1,1), (2, 2), (3,3) RETURNING *
),
raw_data AS (
	DELETE FROM modify_table WHERE id = (SELECT min(id) FROM added_data) RETURNING *
)
INSERT INTO summary_table SELECT id, COUNT(*) AS counter FROM raw_data GROUP BY id;

-- Check modifiying CTEs inside a transaction
BEGIN;

WITH raw_data AS (
	DELETE FROM modify_table RETURNING *
)
INSERT INTO summary_table SELECT id, COUNT(*) AS counter FROM raw_data GROUP BY id;

WITH insert_reference AS (
	INSERT INTO anchor_table VALUES (3), (4) RETURNING *
)
SELECT id FROM insert_reference ORDER BY id;

SELECT * FROM summary_table ORDER BY id, counter;
SELECT * FROM modify_table ORDER BY id, val;
SELECT * FROM anchor_table ORDER BY id;

ROLLBACK;

SELECT * FROM summary_table ORDER BY id, counter;
SELECT * FROM modify_table ORDER BY id, val;
SELECT * FROM anchor_table ORDER BY id;

-- Test delete with subqueries
WITH deleted_rows AS (
	DELETE FROM modify_table WHERE id IN (SELECT id FROM modify_table WHERE id = 1) RETURNING *
)
SELECT * FROM deleted_rows;

WITH deleted_rows AS (
	DELETE FROM modify_table WHERE id IN (SELECT id FROM modify_table WHERE val = 4) RETURNING *
)
SELECT * FROM deleted_rows;

WITH deleted_rows AS (
	DELETE FROM modify_table WHERE id IN (2) RETURNING *
)
SELECT * FROM deleted_rows;

WITH deleted_rows AS (
	DELETE FROM modify_table WHERE val IN (SELECT val FROM modify_table WHERE id = 3) RETURNING *
)
SELECT * FROM deleted_rows;

WITH deleted_rows AS (
	DELETE FROM modify_table WHERE val IN (6) RETURNING *
)
SELECT * FROM deleted_rows;

WITH deleted_rows AS (
	DELETE FROM modify_table WHERE ctid IN (SELECT ctid FROM modify_table WHERE id = 1) RETURNING *
)
SELECT * FROM deleted_rows;

-- Test with replication factor 2
SET citus.shard_replication_factor to 2;

DROP TABLE modify_table;
CREATE TABLE with_modifying.modify_table (id int, val int);
SELECT create_distributed_table('modify_table', 'id');
INSERT INTO with_modifying.modify_table SELECT user_id, value_1 FROM public.users_table;

DROP TABLE summary_table;
CREATE TABLE with_modifying.summary_table (id int, counter int);
SELECT create_distributed_table('summary_table', 'id');

SELECT COUNT(*) FROM modify_table;
SELECT * FROM summary_table ORDER BY id, counter;

WITH raw_data AS (
	DELETE FROM modify_table RETURNING *
)
INSERT INTO summary_table SELECT id, COUNT(*) AS counter FROM raw_data GROUP BY id;

SELECT COUNT(*) FROM modify_table;
SELECT * FROM summary_table ORDER BY id, counter;

DROP SCHEMA with_modifying CASCADE;
