-- De-duplicate UsersGroup and prevent recurrence.
--
-- Background: the REST API paginated lists at 100 rows and the COmanage
-- provisioner read one page, so memberships of groups with more than 100
-- members were re-inserted on every sync (35,971 rows for 962 real
-- memberships in October 2026). See docs/rest-api.md.
--
-- Run ONLY after the API fix (cosmicexplorer/rest-dcc >= 1.2.2) and the
-- plugin fix are deployed; otherwise the unique key makes the next sync fail
-- loudly on the first duplicate insert. Run inside the database container:
--
--   DB=$(docker ps -q -f name=dcc_docdb-database)
--   PW=$(docker exec $DB cat /run/secrets/mariadb_root_password)
--   docker cp scripts/dedupe-usersgroup.sql $DB:/tmp/
--   docker exec -e MYSQL_PWD="$PW" $DB sh -c 'mysql -uroot dcc_docdb < /tmp/dedupe-usersgroup.sql'
--
-- Nothing here touches the web service; no downtime is needed. Rows are not
-- lost: one row per distinct (EmailUserID, GroupID) is kept.

-- 1. Keep a copy of the table as it was.
CREATE TABLE IF NOT EXISTS UsersGroup_before_dedupe AS SELECT * FROM UsersGroup;

-- 2. Remove duplicates, keeping the lowest UsersGroupID of each membership.
DELETE u FROM UsersGroup u
  JOIN UsersGroup d
    ON d.EmailUserID = u.EmailUserID
   AND d.GroupID     = u.GroupID
   AND d.UsersGroupID < u.UsersGroupID;

-- 3. Make the mistake impossible to repeat.
ALTER TABLE UsersGroup ADD UNIQUE KEY EmailUserGroup (EmailUserID, GroupID);

-- 4. Verify: both counts must be equal (962 as of October 2026).
SELECT COUNT(*) AS rows_now, COUNT(DISTINCT EmailUserID, GroupID) AS memberships FROM UsersGroup;
