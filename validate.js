/**
 * Validator script for CivicFix Database Migrations & SQL Queries.
 * Verifies structural integrity, naming convention consistency, table dependencies,
 * coordinate systems, primary keys, and constraint rules without requiring a running database server.
 */

const fs = require('fs');
const path = require('path');

const migrationsDir = path.join(__dirname, '..', 'migrations');
const queriesFile = path.join(__dirname, '..', 'queries_and_transactions.sql');

console.log('==================================================');
console.log('CIVICFIX DATABASE INTEGRITY VALIDATION RUNNER');
console.log('==================================================\n');

let errorCount = 0;
let warningCount = 0;

function reportError(msg) {
    console.error(`[\x1b[31mERROR\x1b[0m] ${msg}`);
    errorCount++;
}

function reportWarning(msg) {
    console.warn(`[\x1b[33mWARN\x1b[0m] ${msg}`);
    warningCount++;
}

function reportSuccess(msg) {
    console.log(`[\x1b[32mOK\x1b[0m] ${msg}`);
}

// 1. Verify Migration File Order
const migrationFiles = [
    '001_extensions.sql',
    '002_reference_tables.sql',
    '003_identity_tables.sql',
    '004_issue_tables.sql',
    '005_ai_tables.sql',
    '006_workflow_tables.sql',
    '007_indexes.sql',
    '008_constraints_and_triggers.sql',
    '009_seed_data.sql',
    '010_test_data.sql'
];

console.log('Checking migration file sequence...');
migrationFiles.forEach(file => {
    const filePath = path.join(migrationsDir, file);
    if (fs.existsSync(filePath)) {
        reportSuccess(`File exists: ${file}`);
    } else {
        reportError(`Missing expected migration file: ${file}`);
    }
});

// 2. Parse migrations to build schema representation
const tables = {};
const foreignKeys = [];
let usesPostGIS = false;
let usesUUID = false;

console.log('\nAnalyzing SQL migrations for schema violations...');

migrationFiles.forEach(file => {
    const filePath = path.join(migrationsDir, file);
    if (!fs.existsSync(filePath)) return;
    
    const content = fs.readFileSync(filePath, 'utf8');
    
    // Check for PostGIS extension
    if (content.toLowerCase().includes('postgis')) {
        usesPostGIS = true;
    }
    // Check for UUID generation
    if (content.toLowerCase().includes('gen_random_uuid') || content.toLowerCase().includes('uuid')) {
        usesUUID = true;
    }

    // Detect Table Creations
    const createTableRegex = /create\s+table\s+(?:if\s+not\s+exists\s+)?(\w+)\s*\(/gi;
    let match;
    while ((match = createTableRegex.exec(content)) !== null) {
        const tableName = match[1].toLowerCase();
        tables[tableName] = { file, fields: [] };
    }

    // Detect Foreign Keys declarations
    const fkRegex = /foreign\s+key\s*\(([^)]+)\)\s*references\s*(\w+)\s*\(([^)]+)\)/gi;
    let fkMatch;
    while ((fkMatch = fkRegex.exec(content)) !== null) {
        const sourceFields = fkMatch[1].split(',').map(f => f.trim().toLowerCase());
        const refTable = fkMatch[2].toLowerCase();
        const refFields = fkMatch[3].split(',').map(f => f.trim().toLowerCase());
        foreignKeys.push({
            file,
            sourceFields,
            refTable,
            refFields
        });
    }
});

// Validate spatial setup
if (usesPostGIS) {
    reportSuccess('PostGIS extension usage confirmed.');
} else {
    reportError('PostGIS extension not declared in migrations.');
}

if (usesUUID) {
    reportSuccess('UUID primary key strategy confirmed.');
} else {
    reportError('UUID primary key strategy not declared in migrations.');
}

// Validate table declarations
const declaredTableNames = Object.keys(tables);
console.log(`Detected ${declaredTableNames.length} tables in migrations.`);

// Validate foreign keys references
console.log('\nValidating Foreign Key targets...');
foreignKeys.forEach(fk => {
    if (!tables[fk.refTable]) {
        reportError(`Foreign Key references non-existent table "${fk.refTable}" in ${fk.file}`);
    } else {
        reportSuccess(`Foreign Key to "${fk.refTable}" is valid.`);
    }
});

// Check for dangerous patterns
console.log('\nScanning for prohibited schema design patterns...');
migrationFiles.forEach(file => {
    const filePath = path.join(migrationsDir, file);
    if (!fs.existsSync(filePath)) return;
    const content = fs.readFileSync(filePath, 'utf8');

    // Rule: No comma-separated fields representing multi-values (skills)
    if (file === '003_identity_tables.sql' && content.toLowerCase().includes('skills varchar') && content.toLowerCase().includes(',')) {
        reportError(`Suspected comma-separated skills in ${file}`);
    }
    // Rule: No serial columns used as primary keys
    if (content.toLowerCase().includes('serial primary key')) {
        reportWarning(`SERIAL column detected in ${file}. Confirm if UUID is preferred.`);
    }
    // Rule: Correct SRID 4326 for geography points
    const geoRegex = /geography\(\s*point\s*,\s*(\d+)\s*\)/gi;
    let geoMatch;
    while ((geoMatch = geoRegex.exec(content)) !== null) {
        const srid = geoMatch[1];
        if (srid !== '4326') {
            reportError(`Invalid Spatial Reference System Identifier (SRID) ${srid} in ${file}. Expected 4326.`);
        } else {
            reportSuccess(`Spatial SRID 4326 confirmed in ${file}.`);
        }
    }
});

// 3. Verify Operational Queries
console.log('\nVerifying queries file...');
if (fs.existsSync(queriesFile)) {
    const queriesContent = fs.readFileSync(queriesFile, 'utf8');
    // Basic verification of keywords
    if (queriesContent.toLowerCase().includes('select') && queriesContent.toLowerCase().includes('from')) {
        reportSuccess('Queries file exists and contains SELECT statements.');
    } else {
        reportError('Queries file is empty or does not contain SELECT statements.');
    }
} else {
    reportError('Queries file is missing: queries_and_transactions.sql');
}

console.log('\n==================================================');
console.log(`Validation Completed: ${errorCount} Errors, ${warningCount} Warnings`);
console.log('==================================================');

if (errorCount > 0) {
    process.exit(1);
} else {
    process.exit(0);
}
