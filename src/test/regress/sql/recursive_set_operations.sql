CREATE SCHEMA recursive_union;
SET search_path TO recursive_union, public;

CREATE TABLE recursive_union.test (x int, y int);
SELECT create_distributed_table('test', 'x');

CREATE TABLE recursive_union.ref (a int, b int);
SELECT create_reference_table('ref');

INSERT INTO test VALUES (1,1), (2,2);
INSERT INTO ref VALUES (2,2), (3,3);

-- top-level set operations are supported through recursive planning
SET client_min_messages TO DEBUG;

(SELECT * FROM test) UNION (SELECT * FROM test) ORDER BY 1,2;
(SELECT * FROM test) UNION (SELECT * FROM ref) ORDER BY 1,2;
(SELECT * FROM ref) UNION (SELECT * FROM ref) ORDER BY 1,2;

(SELECT * FROM test) UNION ALL (SELECT * FROM test) ORDER BY 1,2;
(SELECT * FROM test) UNION ALL (SELECT * FROM ref) ORDER BY 1,2;
(SELECT * FROM ref) UNION ALL (SELECT * FROM ref) ORDER BY 1,2;

(SELECT * FROM test) INTERSECT (SELECT * FROM test) ORDER BY 1,2;
(SELECT * FROM test) INTERSECT (SELECT * FROM ref) ORDER BY 1,2;
(SELECT * FROM ref) INTERSECT (SELECT * FROM ref) ORDER BY 1,2;

(SELECT * FROM test) EXCEPT (SELECT * FROM test) ORDER BY 1,2;
(SELECT * FROM test) EXCEPT (SELECT * FROM ref) ORDER BY 1,2;
(SELECT * FROM ref) EXCEPT (SELECT * FROM ref) ORDER BY 1,2;

-- more complex set operation trees are supported
(SELECT * FROM test)
INTERSECT
(SELECT * FROM ref)
UNION ALL
(SELECT s, s FROM generate_series(1,10) s)
EXCEPT
(SELECT 1,1)
UNION
(SELECT * FROM test LEFT JOIN ref ON (x = a))
ORDER BY 1,2;

-- within a subquery, some unions can be pushed down
SELECT * FROM ((SELECT * FROM test) UNION (SELECT * FROM test)) u ORDER BY 1,2;
SELECT * FROM ((SELECT * FROM test) UNION (SELECT * FROM ref)) u ORDER BY 1,2;
SELECT * FROM ((SELECT * FROM ref) UNION (SELECT * FROM ref)) u ORDER BY 1,2;

SELECT * FROM ((SELECT * FROM test) UNION ALL (SELECT * FROM test)) u ORDER BY 1,2;
SELECT * FROM ((SELECT * FROM test) UNION ALL (SELECT * FROM ref)) u ORDER BY 1,2;
SELECT * FROM ((SELECT * FROM ref) UNION ALL (SELECT * FROM ref)) u ORDER BY 1,2;

SELECT * FROM ((SELECT * FROM test) INTERSECT (SELECT * FROM test)) u ORDER BY 1,2;
SELECT * FROM ((SELECT * FROM test) INTERSECT (SELECT * FROM ref)) u ORDER BY 1,2;
SELECT * FROM ((SELECT * FROM ref) INTERSECT (SELECT * FROM ref)) u ORDER BY 1,2;

SELECT * FROM ((SELECT * FROM test) EXCEPT (SELECT * FROM test)) u ORDER BY 1,2;
SELECT * FROM ((SELECT * FROM test) EXCEPT (SELECT * FROM ref)) u ORDER BY 1,2;
SELECT * FROM ((SELECT * FROM ref) EXCEPT (SELECT * FROM ref)) u ORDER BY 1,2;

-- unions can even be pushed down within a join
SELECT * FROM ((SELECT * FROM test) UNION (SELECT * FROM test)) u JOIN test USING (x) ORDER BY 1,2;
SELECT * FROM ((SELECT * FROM test) UNION ALL (SELECT * FROM test)) u LEFT JOIN test USING (x) ORDER BY 1,2;

-- unions cannot be pushed down if one leaf recurs
SELECT * FROM ((SELECT * FROM test) UNION (SELECT * FROM test ORDER BY x LIMIT 1)) u JOIN test USING (x) ORDER BY 1,2;
SELECT * FROM ((SELECT * FROM test) UNION ALL (SELECT * FROM test ORDER BY x LIMIT 1)) u LEFT JOIN test USING (x) ORDER BY 1,2;

-- other set operations in joins also cannot be pushed down
SELECT * FROM ((SELECT * FROM test) EXCEPT (SELECT * FROM test ORDER BY x LIMIT 1)) u JOIN test USING (x) ORDER BY 1,2;
SELECT * FROM ((SELECT * FROM test) INTERSECT (SELECT * FROM test ORDER BY x LIMIT 1)) u LEFT JOIN test USING (x) ORDER BY 1,2;

-- distributed table in WHERE clause, but not FROM clause still disallowed
SELECT * FROM ((SELECT * FROM test) UNION (SELECT * FROM ref WHERE a IN (SELECT x FROM test))) u ORDER BY 1,2;

RESET client_min_messages;
DROP SCHEMA recursive_union CASCADE;
