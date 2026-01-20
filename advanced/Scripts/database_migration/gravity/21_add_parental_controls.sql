-- Pi-hole Parental Controls Database Migration
-- Version: 21
-- Description: Add tables for parental controls with service categories, rules, schedules, and time limits

PRAGMA foreign_keys=ON;

BEGIN TRANSACTION;

-- 1. Service Categories Table
CREATE TABLE IF NOT EXISTS service_categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    icon TEXT,
    enabled BOOLEAN DEFAULT 1,
    date_added INTEGER NOT NULL,
    date_modified INTEGER NOT NULL
);

-- 2. Service Domains Table
CREATE TABLE IF NOT EXISTS service_domains (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    service_category_id INTEGER NOT NULL,
    domain TEXT NOT NULL,
    is_regex BOOLEAN DEFAULT 0,
    enabled BOOLEAN DEFAULT 1,
    date_added INTEGER NOT NULL,
    FOREIGN KEY (service_category_id) REFERENCES service_categories(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_service_domains_category ON service_domains(service_category_id);
CREATE INDEX IF NOT EXISTS idx_service_domains_domain ON service_domains(domain);

-- 3. Parental Control Rules Table
CREATE TABLE IF NOT EXISTS parental_rules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT,
    enabled BOOLEAN DEFAULT 1,
    priority INTEGER DEFAULT 0,
    date_added INTEGER NOT NULL,
    date_modified INTEGER NOT NULL
);

-- 4. Rule-Service Mapping Table
CREATE TABLE IF NOT EXISTS parental_rule_services (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id INTEGER NOT NULL,
    service_category_id INTEGER NOT NULL,
    action TEXT DEFAULT 'block' CHECK(action IN ('block', 'allow')),
    FOREIGN KEY (rule_id) REFERENCES parental_rules(id) ON DELETE CASCADE,
    FOREIGN KEY (service_category_id) REFERENCES service_categories(id) ON DELETE CASCADE,
    UNIQUE(rule_id, service_category_id)
);

-- 5. Rule-Device/Group Mapping Table
CREATE TABLE IF NOT EXISTS parental_rule_targets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id INTEGER NOT NULL,
    target_type TEXT NOT NULL CHECK(target_type IN ('device', 'group', 'all')),
    target_id INTEGER, -- NULL for 'all' type
    FOREIGN KEY (rule_id) REFERENCES parental_rules(id) ON DELETE CASCADE,
    UNIQUE(rule_id, target_type, target_id)
);

-- 6. Time Schedules Table
CREATE TABLE IF NOT EXISTS parental_schedules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id INTEGER NOT NULL,
    schedule_type TEXT NOT NULL CHECK(schedule_type IN ('daily', 'weekly', 'once', 'always')),
    days_of_week TEXT, -- JSON array: [0,1,2,3,4,5,6] where 0=Sunday
    date_specific TEXT, -- YYYY-MM-DD for 'once' type
    start_time TEXT NOT NULL, -- HH:MM format
    end_time TEXT NOT NULL, -- HH:MM format
    timezone TEXT DEFAULT 'UTC',
    enabled BOOLEAN DEFAULT 1,
    FOREIGN KEY (rule_id) REFERENCES parental_rules(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_schedules_rule ON parental_schedules(rule_id);

-- 7. Time Limits Table
CREATE TABLE IF NOT EXISTS parental_time_limits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id INTEGER NOT NULL,
    limit_type TEXT NOT NULL CHECK(limit_type IN ('daily', 'weekly', 'monthly')),
    duration_minutes INTEGER NOT NULL,
    reset_time TEXT DEFAULT '00:00', -- Time to reset daily limits (HH:MM)
    enabled BOOLEAN DEFAULT 1,
    FOREIGN KEY (rule_id) REFERENCES parental_rules(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_time_limits_rule ON parental_time_limits(rule_id);

-- 8. Usage Tracking Table
CREATE TABLE IF NOT EXISTS parental_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id INTEGER NOT NULL,
    target_type TEXT NOT NULL,
    target_id INTEGER,
    service_category_id INTEGER,
    date TEXT NOT NULL, -- YYYY-MM-DD
    minutes_used INTEGER DEFAULT 0,
    queries_count INTEGER DEFAULT 0,
    last_updated INTEGER NOT NULL,
    FOREIGN KEY (rule_id) REFERENCES parental_rules(id) ON DELETE CASCADE,
    FOREIGN KEY (service_category_id) REFERENCES service_categories(id) ON DELETE CASCADE,
    UNIQUE(rule_id, target_type, target_id, service_category_id, date)
);
CREATE INDEX IF NOT EXISTS idx_usage_date ON parental_usage(date);
CREATE INDEX IF NOT EXISTS idx_usage_rule ON parental_usage(rule_id);

-- 9. Parental Controls Metadata Table
CREATE TABLE IF NOT EXISTS parental_metadata (
    key TEXT PRIMARY KEY,
    value TEXT,
    date_modified INTEGER NOT NULL
);

-- Insert default metadata
INSERT OR IGNORE INTO parental_metadata (key, value, date_modified) VALUES
    ('enabled', '1', strftime('%s', 'now')),
    ('version', '1.0', strftime('%s', 'now')),
    ('last_sync', '0', strftime('%s', 'now'));

-- 10. Active Blocks Tracking Table (for current blocking state)
CREATE TABLE IF NOT EXISTS parental_active_blocks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id INTEGER NOT NULL,
    target_type TEXT NOT NULL,
    target_id INTEGER,
    service_category_id INTEGER,
    blocked_at INTEGER NOT NULL,
    block_reason TEXT, -- 'schedule', 'time_limit', 'manual'
    FOREIGN KEY (rule_id) REFERENCES parental_rules(id) ON DELETE CASCADE,
    FOREIGN KEY (service_category_id) REFERENCES service_categories(id) ON DELETE CASCADE,
    UNIQUE(rule_id, target_type, target_id, service_category_id)
);
CREATE INDEX IF NOT EXISTS idx_active_blocks_rule ON parental_active_blocks(rule_id);

-- Update database version
UPDATE info SET value = 21 WHERE property = 'version';

COMMIT;
