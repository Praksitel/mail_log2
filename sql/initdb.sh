#!/bin/sh
PG_HOST=mail_log_db
PG_USER=mail_log
PG_DB=mail_log

PGPASSWORD=$POSTGRES_PASSWORD psql -U ${PG_USER} -h ${PG_HOST} -f sql/users.sql
PGPASSWORD=$POSTGRES_PASSWORD psql -U ${PG_USER} -h ${PG_HOST} -f sql/db.sql
PGPASSWORD=$POSTGRES_PASSWORD psql -U ${PG_USER} -h ${PG_HOST} ${PG_DB} -f sql/create_tables.sql
