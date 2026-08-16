-- Migration: 001_extensions
-- Description: Enables required PostgreSQL extensions (PostGIS for geographical data and pgcrypto for UUID/hash operations).

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
