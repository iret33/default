# Pi-hole Parental Controls Design

## Overview
This feature extends Pi-hole with comprehensive parental controls including service-based blocking, device targeting, time limits, and scheduling.

## Architecture

### Database Schema Extensions

#### 1. Service Categories Table
```sql
CREATE TABLE service_categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    icon TEXT,
    enabled BOOLEAN DEFAULT 1,
    date_added INTEGER NOT NULL,
    date_modified INTEGER NOT NULL
);
```

**Pre-defined categories:**
- YouTube
- Gaming (Minecraft, PSN, Xbox Live, Steam, Epic Games)
- Social Media (Facebook, Instagram, Twitter/X, TikTok, Snapchat)
- Streaming (Netflix, Hulu, Disney+, Prime Video)
- Messaging (WhatsApp, Telegram, Discord)
- Shopping (Amazon, eBay, etc.)
- Adult Content
- General Internet (block all except whitelist)

#### 2. Service Domains Table
```sql
CREATE TABLE service_domains (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    service_category_id INTEGER NOT NULL,
    domain TEXT NOT NULL,
    is_regex BOOLEAN DEFAULT 0,
    enabled BOOLEAN DEFAULT 1,
    date_added INTEGER NOT NULL,
    FOREIGN KEY (service_category_id) REFERENCES service_categories(id) ON DELETE CASCADE
);
CREATE INDEX idx_service_domains_category ON service_domains(service_category_id);
CREATE INDEX idx_service_domains_domain ON service_domains(domain);
```

#### 3. Parental Control Rules Table
```sql
CREATE TABLE parental_rules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT,
    enabled BOOLEAN DEFAULT 1,
    priority INTEGER DEFAULT 0,
    date_added INTEGER NOT NULL,
    date_modified INTEGER NOT NULL
);
```

#### 4. Rule-Service Mapping Table
```sql
CREATE TABLE parental_rule_services (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id INTEGER NOT NULL,
    service_category_id INTEGER NOT NULL,
    action TEXT DEFAULT 'block' CHECK(action IN ('block', 'allow')),
    FOREIGN KEY (rule_id) REFERENCES parental_rules(id) ON DELETE CASCADE,
    FOREIGN KEY (service_category_id) REFERENCES service_categories(id) ON DELETE CASCADE,
    UNIQUE(rule_id, service_category_id)
);
```

#### 5. Rule-Device/Group Mapping Table
```sql
CREATE TABLE parental_rule_targets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id INTEGER NOT NULL,
    target_type TEXT NOT NULL CHECK(target_type IN ('device', 'group')),
    target_id INTEGER NOT NULL,
    FOREIGN KEY (rule_id) REFERENCES parental_rules(id) ON DELETE CASCADE,
    UNIQUE(rule_id, target_type, target_id)
);
```

#### 6. Time Schedules Table
```sql
CREATE TABLE parental_schedules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id INTEGER NOT NULL,
    schedule_type TEXT NOT NULL CHECK(schedule_type IN ('daily', 'weekly', 'once')),
    days_of_week TEXT, -- JSON array: [0,1,2,3,4,5,6] where 0=Sunday
    start_time TEXT NOT NULL, -- HH:MM format
    end_time TEXT NOT NULL, -- HH:MM format
    timezone TEXT DEFAULT 'UTC',
    enabled BOOLEAN DEFAULT 1,
    FOREIGN KEY (rule_id) REFERENCES parental_rules(id) ON DELETE CASCADE
);
CREATE INDEX idx_schedules_rule ON parental_schedules(rule_id);
```

#### 7. Time Limits Table
```sql
CREATE TABLE parental_time_limits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id INTEGER NOT NULL,
    limit_type TEXT NOT NULL CHECK(limit_type IN ('daily', 'weekly', 'session')),
    duration_minutes INTEGER NOT NULL,
    reset_time TEXT DEFAULT '00:00', -- Time to reset daily limits
    enabled BOOLEAN DEFAULT 1,
    FOREIGN KEY (rule_id) REFERENCES parental_rules(id) ON DELETE CASCADE
);
CREATE INDEX idx_time_limits_rule ON parental_time_limits(rule_id);
```

#### 8. Usage Tracking Table
```sql
CREATE TABLE parental_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_id INTEGER NOT NULL,
    target_type TEXT NOT NULL,
    target_id INTEGER NOT NULL,
    service_category_id INTEGER,
    date TEXT NOT NULL, -- YYYY-MM-DD
    minutes_used INTEGER DEFAULT 0,
    last_updated INTEGER NOT NULL,
    FOREIGN KEY (rule_id) REFERENCES parental_rules(id) ON DELETE CASCADE,
    FOREIGN KEY (service_category_id) REFERENCES service_categories(id) ON DELETE CASCADE,
    UNIQUE(rule_id, target_type, target_id, service_category_id, date)
);
CREATE INDEX idx_usage_date ON parental_usage(date);
```

### Component Architecture

```
┌─────────────────────────────────────────────┐
│      Web UI / CLI (parental controls)       │
│  - Manage service categories                │
│  - Create/edit rules                        │
│  - Set schedules & time limits              │
│  - View usage reports                       │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────┴──────────────────────────┐
│    Parental Controls API (parental.sh)      │
│  - CRUD for categories, rules, schedules    │
│  - Apply/remove blocking rules              │
│  - Query usage statistics                   │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────┴──────────────────────────┐
│  Scheduler Daemon (parental-scheduler.sh)   │
│  - Check schedules every minute             │
│  - Apply time-based blocking                │
│  - Track usage time                         │
│  - Enforce time limits                      │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────┴──────────────────────────┐
│   Domain List Manager (parental-domains.sh) │
│  - Map services to domain lists             │
│  - Apply to Pi-hole groups                  │
│  - Dynamic blocklist updates                │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────┴──────────────────────────┐
│      Existing Pi-hole Components            │
│  - FTL DNS Server                           │
│  - SQLite Database (gravity.db)             │
│  - Group-based blocking                     │
└─────────────────────────────────────────────┘
```

## Implementation Strategy

### Phase 1: Database Schema
1. Create database migration script
2. Add all new tables with indexes
3. Populate default service categories
4. Create views for easier querying

### Phase 2: Core Scripts
1. **parental-domains.sh**: Manage service domain lists
   - Add/remove domains for services
   - Apply domains to Pi-hole domainlist table
   - Link to device groups

2. **parental-rules.sh**: Manage parental control rules
   - CRUD operations for rules
   - Link services, devices, schedules, limits
   - Enable/disable rules

3. **parental-scheduler.sh**: Background daemon
   - Run as systemd service
   - Check schedules every minute
   - Apply/remove blocking based on time
   - Track usage and enforce limits
   - Generate usage reports

4. **parental-api.sh**: API interface
   - REST endpoints for web UI
   - Authentication integration
   - JSON responses

### Phase 3: CLI Integration
Extend main `pihole` command with:
```bash
pihole parental list                    # List all rules
pihole parental add <name>              # Create new rule
pihole parental remove <id>             # Delete rule
pihole parental enable <id>             # Enable rule
pihole parental disable <id>            # Disable rule
pihole parental service list            # List services
pihole parental service add <name>      # Add service category
pihole parental service domains <id>    # List domains for service
pihole parental schedule add <rule-id>  # Add schedule to rule
pihole parental limit set <rule-id>     # Set time limit
pihole parental usage <device>          # View usage stats
pihole parental block-all <device>      # Block entire internet
pihole parental unblock-all <device>    # Restore access
```

### Phase 4: Systemd Service
Create `/etc/systemd/system/pihole-parental-scheduler.service`:
```ini
[Unit]
Description=Pi-hole Parental Controls Scheduler
After=pihole-FTL.service
Requires=pihole-FTL.service

[Service]
Type=simple
User=pihole
ExecStart=/opt/pihole/parental-scheduler.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

## Blocking Strategy

### Service-Based Blocking
1. When rule is enabled:
   - Get all domains for selected services
   - Add domains to Pi-hole's `domainlist` table
   - Set type=1 (blocklist) with group assignment
   - Signal FTL to reload: `pkill -SIGRTMIN pihole-FTL`

2. When rule is disabled:
   - Remove domains from `domainlist` table
   - Signal FTL to reload

### Device Targeting
- Use Pi-hole's existing `group` and `client` tables
- Map devices to groups
- Apply service blocklists to specific groups
- Support wildcard blocking (all devices)

### Time-Based Control
1. **Schedules**: Activate/deactivate rules at specific times
   - Cron-like scheduling
   - Support daily, weekly, one-time schedules
   - Multiple schedules per rule

2. **Time Limits**: Enforce usage duration
   - Track DNS queries per device/service
   - Calculate accumulated time
   - Auto-block when limit exceeded
   - Reset counters daily/weekly

### Full Internet Block
Special handling for "block all internet" on device:
1. Create catch-all regex: `.*` in blocklist
2. Apply to device's group only
3. Optional whitelist for essential services (emergency, school, etc.)

## Usage Tracking

Monitor DNS queries from FTL logs:
1. Parse query log for blocked service domains
2. Attribute to device and service category
3. Calculate session duration (queries within 5-min window)
4. Store in `parental_usage` table
5. Check against time limits
6. Generate reports for parents

## API Endpoints

```
POST   /api/parental/rules                 # Create rule
GET    /api/parental/rules                 # List rules
GET    /api/parental/rules/:id             # Get rule details
PUT    /api/parental/rules/:id             # Update rule
DELETE /api/parental/rules/:id             # Delete rule
POST   /api/parental/rules/:id/enable      # Enable rule
POST   /api/parental/rules/:id/disable     # Disable rule

GET    /api/parental/services              # List service categories
POST   /api/parental/services              # Create service
GET    /api/parental/services/:id/domains  # Get domains for service
POST   /api/parental/services/:id/domains  # Add domain to service
DELETE /api/parental/services/:id/domains/:domain_id

POST   /api/parental/schedules             # Add schedule to rule
DELETE /api/parental/schedules/:id         # Remove schedule

POST   /api/parental/limits                # Set time limit
PUT    /api/parental/limits/:id            # Update limit
DELETE /api/parental/limits/:id            # Remove limit

GET    /api/parental/usage                 # Get usage stats
GET    /api/parental/usage/:device         # Device-specific usage

POST   /api/parental/block-all/:device     # Emergency block
POST   /api/parental/unblock-all/:device   # Remove emergency block
```

## Web UI Components

1. **Dashboard**
   - Active rules overview
   - Current blocking status
   - Quick enable/disable toggles
   - Usage summary

2. **Rules Management**
   - Create/edit rules
   - Select services to block
   - Assign to devices/groups
   - Set schedules and limits

3. **Service Categories**
   - Pre-defined categories
   - Custom categories
   - Domain management
   - Import/export domain lists

4. **Schedules**
   - Calendar view
   - Time picker
   - Recurring schedules
   - One-time blocks

5. **Usage Reports**
   - Per-device statistics
   - Service usage breakdown
   - Time limit monitoring
   - Historical trends

## Security Considerations

1. **Authentication**: Require Pi-hole admin password
2. **Bypass Prevention**:
   - Block DNS over HTTPS (DoH) domains
   - Block VPN/proxy domains
   - Monitor for DNS changes
3. **Tamper Protection**:
   - Run scheduler as system service
   - Restrict file permissions
   - Log all rule changes
4. **Emergency Override**: Admin PIN for temporary access

## Future Enhancements

1. Mobile app integration
2. Real-time notifications
3. Content filtering levels
4. Bedtime routines
5. Reward system (earn internet time)
6. Safe search enforcement
7. YouTube restricted mode
8. App-level blocking (beyond DNS)
9. Geofencing (block/allow based on location)
10. AI-powered content analysis
