#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2025 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Parental Controls - Setup and Installation
# Initialize parental controls features
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

readonly PI_HOLE_SCRIPT_DIR="/opt/pihole"
readonly gravityDBfile="/etc/pihole/gravity.db"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
if [[ -t 1 ]] && [[ $(tput colors) -ge 8 ]]; then
    COL_NC='\e[0m'
    COL_LIGHT_GREEN='\e[1;32m'
    COL_LIGHT_RED='\e[1;31m'
    COL_YELLOW='\e[1;33m'
    COL_LIGHT_BLUE='\e[1;34m'
    TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
    CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
    INFO="[${COL_LIGHT_BLUE}i${COL_NC}]"
    WARN="[${COL_YELLOW}!${COL_NC}]"
else
    COL_NC=''
    TICK="[✓]"
    CROSS="[✗]"
    INFO="[i]"
    WARN="[!]"
fi

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${CROSS} This script must be run as root"
        exit 1
    fi
}

# Check if database exists
check_database() {
    if [[ ! -f "${gravityDBfile}" ]]; then
        echo -e "${CROSS} Pi-hole database not found. Please install Pi-hole first."
        exit 1
    fi
}

# Apply database migration
apply_migration() {
    echo -e "${INFO} Applying database migration..."

    local migration_file="${SCRIPT_DIR}/../database_migration/gravity/21_add_parental_controls.sql"

    if [[ ! -f "${migration_file}" ]]; then
        echo -e "${CROSS} Migration file not found: ${migration_file}"
        return 1
    fi

    if sqlite3 "${gravityDBfile}" < "${migration_file}" 2>&1; then
        echo -e "${TICK} Database migration applied successfully"
        return 0
    else
        echo -e "${CROSS} Failed to apply database migration"
        return 1
    fi
}

# Add default service categories
add_default_services() {
    echo -e "${INFO} Adding default service categories..."

    local timestamp
    timestamp=$(date +%s)

    # Check if services already exist
    local existing
    existing=$(sqlite3 "${gravityDBfile}" "SELECT COUNT(*) FROM service_categories")

    if [[ ${existing} -gt 0 ]]; then
        echo -e "${INFO} Service categories already exist, skipping..."
        return 0
    fi

    # Add default categories
    sqlite3 "${gravityDBfile}" <<EOF
INSERT INTO service_categories (name, description, enabled, date_added, date_modified) VALUES
    ('YouTube', 'Video streaming platform', 1, ${timestamp}, ${timestamp}),
    ('Gaming', 'Gaming platforms (Minecraft, PlayStation, Xbox, Steam, Epic Games)', 1, ${timestamp}, ${timestamp}),
    ('Social Media', 'Social networking sites (Facebook, Instagram, Twitter, TikTok, Snapchat)', 1, ${timestamp}, ${timestamp}),
    ('Streaming', 'Video streaming services (Netflix, Hulu, Disney+, Prime Video)', 1, ${timestamp}, ${timestamp}),
    ('Messaging', 'Messaging apps (WhatsApp, Telegram, Discord)', 1, ${timestamp}, ${timestamp}),
    ('Shopping', 'E-commerce sites (Amazon, eBay)', 1, ${timestamp}, ${timestamp}),
    ('Adult Content', 'Adult websites and content', 1, ${timestamp}, ${timestamp}),
    ('Ads & Tracking', 'Advertising and tracking domains', 1, ${timestamp}, ${timestamp});
EOF

    echo -e "${TICK} Default service categories added"
}

# Load service domains from file
load_service_domains() {
    echo -e "${INFO} Loading service domains..."

    local domains_file="${SCRIPT_DIR}/parental-domains-default.txt"

    if [[ ! -f "${domains_file}" ]]; then
        echo -e "${WARN} Default domains file not found, skipping..."
        return 0
    fi

    # Import domains for each service
    "${PI_HOLE_SCRIPT_DIR}/parental-services.sh" import 1 "${domains_file}" 2>/dev/null || true

    echo -e "${TICK} Service domains loaded"
}

# Install systemd service
install_systemd_service() {
    echo -e "${INFO} Installing systemd service..."

    local service_file="${SCRIPT_DIR}/../Templates/pihole-parental-scheduler.service"
    local target_file="/etc/systemd/system/pihole-parental-scheduler.service"

    if [[ ! -f "${service_file}" ]]; then
        echo -e "${CROSS} Service file not found: ${service_file}"
        return 1
    fi

    # Copy service file
    cp "${service_file}" "${target_file}"

    # Reload systemd
    systemctl daemon-reload

    # Enable service
    systemctl enable pihole-parental-scheduler.service

    echo -e "${TICK} Systemd service installed and enabled"
}

# Start scheduler service
start_scheduler() {
    echo -e "${INFO} Starting parental controls scheduler..."

    if systemctl start pihole-parental-scheduler.service; then
        echo -e "${TICK} Scheduler started successfully"
        return 0
    else
        echo -e "${CROSS} Failed to start scheduler"
        return 1
    fi
}

# Main setup function
main() {
    echo ""
    echo "Pi-hole Parental Controls Setup"
    echo "================================"
    echo ""

    # Check prerequisites
    check_root
    check_database

    # Run setup steps
    apply_migration || exit 1
    add_default_services || exit 1
    load_service_domains || exit 1
    install_systemd_service || exit 1
    start_scheduler || exit 1

    echo ""
    echo -e "${TICK} Parental Controls setup completed successfully!"
    echo ""
    echo "You can now use the following commands:"
    echo "  pihole parental service list      - List service categories"
    echo "  pihole parental rule add <name>   - Create a new rule"
    echo "  pihole parental scheduler status  - Check scheduler status"
    echo ""
    echo "For more information, run: pihole parental"
    echo ""
}

# Uninstall function
uninstall() {
    echo ""
    echo "Pi-hole Parental Controls Uninstall"
    echo "===================================="
    echo ""

    check_root

    # Stop and disable service
    echo -e "${INFO} Stopping scheduler service..."
    systemctl stop pihole-parental-scheduler.service 2>/dev/null || true
    systemctl disable pihole-parental-scheduler.service 2>/dev/null || true
    rm -f /etc/systemd/system/pihole-parental-scheduler.service
    systemctl daemon-reload

    # Remove database tables (optional - commented out for safety)
    # echo -e "${INFO} Removing database tables..."
    # sqlite3 "${gravityDBfile}" <<EOF
    # DROP TABLE IF EXISTS parental_active_blocks;
    # DROP TABLE IF EXISTS parental_usage;
    # DROP TABLE IF EXISTS parental_time_limits;
    # DROP TABLE IF EXISTS parental_schedules;
    # DROP TABLE IF EXISTS parental_rule_targets;
    # DROP TABLE IF EXISTS parental_rule_services;
    # DROP TABLE IF EXISTS parental_rules;
    # DROP TABLE IF EXISTS service_domains;
    # DROP TABLE IF EXISTS service_categories;
    # DROP TABLE IF EXISTS parental_metadata;
    # EOF

    echo -e "${TICK} Parental Controls uninstalled"
    echo -e "${WARN} Database tables were preserved. To remove them, edit this script and uncomment the DROP TABLE commands."
}

# Handle command line arguments
case "${1}" in
    "install"|"setup"|"")
        main
        ;;
    "uninstall")
        uninstall
        ;;
    *)
        echo "Usage: $0 {install|uninstall}"
        exit 1
        ;;
esac
