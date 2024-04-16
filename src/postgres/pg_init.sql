-- /var/opt/db/pg_init.sql

-- \set var `echo "$ENV_VAR"`

--- Set up LLDAP DB for first time ---
\set pw1 `echo "'$LLDAP_POSTGRES_PASSWORD'"`
CREATE USER lldap WITH ENCRYPTED PASSWORD :pw1;
CREATE DATABASE lldap;
GRANT ALL PRIVILEGES ON DATABASE lldap TO lldap;

--- Set up Authelia DB for first time ---
\set pw2 `echo "'$AUTHELIA_POSTGRES_PASSWORD'"`
CREATE USER authelia WITH ENCRYPTED PASSWORD :pw2;
CREATE DATABASE authelia;
GRANT ALL PRIVILEGES ON DATABASE authelia TO authelia;

--- Set up Gatus DB for first time ---
\set pw3 `echo "'$GATUS_POSTGRES_PASSWORD'"`
CREATE USER gatus WITH ENCRYPTED PASSWORD :pw3;
CREATE DATABASE gatus;
GRANT ALL PRIVILEGES ON DATABASE gatus TO gatus;
