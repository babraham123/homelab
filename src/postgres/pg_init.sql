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

--- Set up Grafana DB for first time ---
\set pw4 `echo "'$GRAFANA_POSTGRES_PASSWORD'"`
CREATE USER grafana WITH ENCRYPTED PASSWORD :pw4;
CREATE DATABASE grafana;
GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana;

--- Set up Home Assistant DB for first time ---
-- For now HA uses sqlite
-- \set pw4 `echo "'$HASS_POSTGRES_PASSWORD'"`
-- CREATE USER hass WITH ENCRYPTED PASSWORD :pw5;
-- CREATE DATABASE hass 
--   ENCODING 'UTF8'
--   LC_COLLATE = 'en_US.UTF-8'
--   LC_CTYPE = 'en_US.UTF-8';
-- GRANT ALL PRIVILEGES ON DATABASE hass TO hass;
