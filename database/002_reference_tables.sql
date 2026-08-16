-- Migration: 002_reference_tables
-- Description: Creates the reference, lookup, and mapping tables for system static configuration.

-- 1. System Roles Table
CREATE TABLE IF NOT EXISTS roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 2. Issue Categories Table
CREATE TABLE IF NOT EXISTS issue_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) UNIQUE NOT NULL,
    code VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 3. Departments Table
CREATE TABLE IF NOT EXISTS departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) UNIQUE NOT NULL,
    code VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 4. Department-Category Mapping Table
CREATE TABLE IF NOT EXISTS department_categories (
    department_id UUID NOT NULL,
    category_id UUID NOT NULL,
    is_preferred BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT pk_department_categories PRIMARY KEY (department_id, category_id),
    CONSTRAINT fk_dept_cat_department FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE CASCADE,
    CONSTRAINT fk_dept_cat_category FOREIGN KEY (category_id) REFERENCES issue_categories(id) ON DELETE CASCADE
);

-- 5. Skills Table
CREATE TABLE IF NOT EXISTS skills (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 6. Issue Status Lookup Table
CREATE TABLE IF NOT EXISTS issue_statuses (
    id VARCHAR(50) PRIMARY KEY,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 7. Severity Levels Lookup Table
CREATE TABLE IF NOT EXISTS severity_levels (
    id VARCHAR(50) PRIMARY KEY,
    weight INTEGER UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 8. Priority Levels Lookup Table
CREATE TABLE IF NOT EXISTS priority_levels (
    id VARCHAR(50) PRIMARY KEY,
    weight INTEGER UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 9. Assignment Statuses Lookup Table
CREATE TABLE IF NOT EXISTS assignment_statuses (
    id VARCHAR(50) PRIMARY KEY,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 10. Resolution Proof Statuses Lookup Table
CREATE TABLE IF NOT EXISTS resolution_proof_statuses (
    id VARCHAR(50) PRIMARY KEY,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 11. Issue Relationship Types Lookup Table
CREATE TABLE IF NOT EXISTS relationship_types (
    id VARCHAR(50) PRIMARY KEY,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);
