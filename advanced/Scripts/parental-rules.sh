#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2025 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Parental Controls - Rules Management
# Create and manage parental control rules
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

readonly PI_HOLE_SCRIPT_DIR="/opt/pihole"
readonly gravityDBfile="/etc/pihole/gravity.db"

# Source utils for database functions
# shellcheck source=utils.sh
source "${PI_HOLE_SCRIPT_DIR}/utils.sh"

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

# Function to check if database exists
check_database() {
    if [[ ! -f "${gravityDBfile}" ]]; then
        echo -e "${CROSS} Database not found: ${gravityDBfile}"
        return 1
    fi
    return 0
}

# Function to list all rules
list_rules() {
    check_database || return 1

    local verbose="${1:-false}"

    echo -e "${INFO} Parental Control Rules:"
    echo ""

    local query="SELECT id, name, description, enabled, priority FROM parental_rules ORDER BY priority DESC, name"

    local result
    result=$(sqlite3 "${gravityDBfile}" "${query}" 2>&1)

    if [[ -z "${result}" ]]; then
        echo -e "${INFO} No rules found. Use 'pihole parental rule add' to create one."
        return 0
    fi

    # Print header
    printf "%-5s %-30s %-10s %-10s %s\n" "ID" "Name" "Priority" "Enabled" "Description"
    printf "%s\n" "--------------------------------------------------------------------------------"

    # Print each rule
    while IFS='|' read -r id name desc enabled priority; do
        local status
        if [[ "${enabled}" == "1" ]]; then
            status="${COL_LIGHT_GREEN}Yes${COL_NC}"
        else
            status="${COL_LIGHT_RED}No${COL_NC}"
        fi

        printf "%-5s %-30s %-10s %-10b %s\n" "${id}" "${name}" "${priority}" "${status}" "${desc}"

        # Show details if verbose
        if [[ "${verbose}" == "true" ]]; then
            # Show services
            local services
            services=$(sqlite3 "${gravityDBfile}" "SELECT sc.name, prs.action FROM parental_rule_services prs
                                                    JOIN service_categories sc ON prs.service_category_id = sc.id
                                                    WHERE prs.rule_id = ${id}")
            if [[ -n "${services}" ]]; then
                echo "  Services:"
                while IFS='|' read -r svc_name action; do
                    echo "    - ${svc_name} (${action})"
                done <<< "${services}"
            fi

            # Show targets
            local targets
            targets=$(sqlite3 "${gravityDBfile}" "SELECT target_type, target_id FROM parental_rule_targets WHERE rule_id = ${id}")
            if [[ -n "${targets}" ]]; then
                echo "  Targets:"
                while IFS='|' read -r target_type target_id; do
                    if [[ "${target_type}" == "all" ]]; then
                        echo "    - All devices"
                    elif [[ "${target_type}" == "group" ]]; then
                        local group_name
                        group_name=$(sqlite3 "${gravityDBfile}" "SELECT name FROM 'group' WHERE id = ${target_id}")
                        echo "    - Group: ${group_name}"
                    elif [[ "${target_type}" == "device" ]]; then
                        local client_ip
                        client_ip=$(sqlite3 "${gravityDBfile}" "SELECT ip FROM client WHERE id = ${target_id}")
                        echo "    - Device: ${client_ip}"
                    fi
                done <<< "${targets}"
            fi

            # Show schedules
            local schedules
            schedules=$(sqlite3 "${gravityDBfile}" "SELECT schedule_type, start_time, end_time, days_of_week FROM parental_schedules
                                                     WHERE rule_id = ${id} AND enabled = 1")
            if [[ -n "${schedules}" ]]; then
                echo "  Schedules:"
                while IFS='|' read -r sched_type start_time end_time days; do
                    echo "    - ${sched_type}: ${start_time} - ${end_time} ${days}"
                done <<< "${schedules}"
            fi

            # Show time limits
            local limits
            limits=$(sqlite3 "${gravityDBfile}" "SELECT limit_type, duration_minutes FROM parental_time_limits
                                                  WHERE rule_id = ${id} AND enabled = 1")
            if [[ -n "${limits}" ]]; then
                echo "  Time Limits:"
                while IFS='|' read -r limit_type duration; do
                    echo "    - ${limit_type}: ${duration} minutes"
                done <<< "${limits}"
            fi

            echo ""
        fi
    done <<< "${result}"

    if [[ "${verbose}" == "false" ]]; then
        echo ""
        echo "Use 'pihole parental rule show <id>' for detailed information"
    fi
}

# Function to add a rule
add_rule() {
    check_database || return 1

    local name="${1}"
    local description="${2}"
    local priority="${3:-0}"

    if [[ -z "${name}" ]]; then
        echo -e "${CROSS} Rule name is required"
        echo "Usage: pihole parental rule add <name> [description] [priority]"
        return 1
    fi

    local timestamp
    timestamp=$(date +%s)

    local query="INSERT INTO parental_rules (name, description, enabled, priority, date_added, date_modified)
                 VALUES ('${name}', '${description}', 1, ${priority}, ${timestamp}, ${timestamp})"

    if sqlite3 "${gravityDBfile}" "${query}" 2>&1; then
        local rule_id
        rule_id=$(sqlite3 "${gravityDBfile}" "SELECT last_insert_rowid()")
        echo -e "${TICK} Rule '${name}' added successfully (ID: ${rule_id})"
        echo -e "${INFO} Use 'pihole parental rule attach' to configure the rule"
        return 0
    else
        echo -e "${CROSS} Failed to add rule '${name}'"
        return 1
    fi
}

# Function to remove a rule
remove_rule() {
    check_database || return 1

    local rule_id="${1}"

    if [[ -z "${rule_id}" ]]; then
        echo -e "${CROSS} Rule ID is required"
        echo "Usage: pihole parental rule remove <id>"
        return 1
    fi

    # Check if rule exists
    local rule_name
    rule_name=$(sqlite3 "${gravityDBfile}" "SELECT name FROM parental_rules WHERE id = ${rule_id}")

    if [[ -z "${rule_name}" ]]; then
        echo -e "${CROSS} Rule ID ${rule_id} not found"
        return 1
    fi

    # First, unapply the rule to clean up domain lists
    unapply_rule "${rule_id}"

    # Delete rule (CASCADE will remove all associations)
    if sqlite3 "${gravityDBfile}" "DELETE FROM parental_rules WHERE id = ${rule_id}" 2>&1; then
        echo -e "${TICK} Rule '${rule_name}' removed successfully"
        return 0
    else
        echo -e "${CROSS} Failed to remove rule"
        return 1
    fi
}

# Function to enable/disable a rule
toggle_rule() {
    check_database || return 1

    local rule_id="${1}"
    local action="${2}" # enable or disable

    if [[ -z "${rule_id}" ]] || [[ -z "${action}" ]]; then
        echo -e "${CROSS} Rule ID and action are required"
        echo "Usage: pihole parental rule <enable|disable> <id>"
        return 1
    fi

    local enabled
    if [[ "${action}" == "enable" ]]; then
        enabled=1
    else
        enabled=0
    fi

    local timestamp
    timestamp=$(date +%s)

    if sqlite3 "${gravityDBfile}" "UPDATE parental_rules SET enabled = ${enabled}, date_modified = ${timestamp} WHERE id = ${rule_id}" 2>&1; then
        echo -e "${TICK} Rule ${action}d successfully"

        # Apply or unapply the rule
        if [[ "${action}" == "enable" ]]; then
            apply_rule "${rule_id}"
        else
            unapply_rule "${rule_id}"
        fi

        return 0
    else
        echo -e "${CROSS} Failed to ${action} rule"
        return 1
    fi
}

# Function to attach service to rule
attach_service() {
    check_database || return 1

    local rule_id="${1}"
    local service_id="${2}"
    local action="${3:-block}"

    if [[ -z "${rule_id}" ]] || [[ -z "${service_id}" ]]; then
        echo -e "${CROSS} Rule ID and Service ID are required"
        echo "Usage: pihole parental rule attach service <rule_id> <service_id> [block|allow]"
        return 1
    fi

    local query="INSERT OR REPLACE INTO parental_rule_services (rule_id, service_category_id, action)
                 VALUES (${rule_id}, ${service_id}, '${action}')"

    if sqlite3 "${gravityDBfile}" "${query}" 2>&1; then
        echo -e "${TICK} Service attached to rule successfully"

        # Reapply rule if it's enabled
        local is_enabled
        is_enabled=$(sqlite3 "${gravityDBfile}" "SELECT enabled FROM parental_rules WHERE id = ${rule_id}")
        if [[ "${is_enabled}" == "1" ]]; then
            apply_rule "${rule_id}"
        fi

        return 0
    else
        echo -e "${CROSS} Failed to attach service"
        return 1
    fi
}

# Function to detach service from rule
detach_service() {
    check_database || return 1

    local rule_id="${1}"
    local service_id="${2}"

    if [[ -z "${rule_id}" ]] || [[ -z "${service_id}" ]]; then
        echo -e "${CROSS} Rule ID and Service ID are required"
        echo "Usage: pihole parental rule detach service <rule_id> <service_id>"
        return 1
    fi

    if sqlite3 "${gravityDBfile}" "DELETE FROM parental_rule_services WHERE rule_id = ${rule_id} AND service_category_id = ${service_id}" 2>&1; then
        echo -e "${TICK} Service detached from rule successfully"

        # Reapply rule if it's enabled
        local is_enabled
        is_enabled=$(sqlite3 "${gravityDBfile}" "SELECT enabled FROM parental_rules WHERE id = ${rule_id}")
        if [[ "${is_enabled}" == "1" ]]; then
            apply_rule "${rule_id}"
        fi

        return 0
    else
        echo -e "${CROSS} Failed to detach service"
        return 1
    fi
}

# Function to attach target (device or group) to rule
attach_target() {
    check_database || return 1

    local rule_id="${1}"
    local target_type="${2}"
    local target_id="${3}"

    if [[ -z "${rule_id}" ]] || [[ -z "${target_type}" ]]; then
        echo -e "${CROSS} Rule ID and target type are required"
        echo "Usage: pihole parental rule attach target <rule_id> <all|group|device> [id]"
        return 1
    fi

    if [[ "${target_type}" != "all" ]] && [[ -z "${target_id}" ]]; then
        echo -e "${CROSS} Target ID is required for group and device targets"
        return 1
    fi

    local query="INSERT OR IGNORE INTO parental_rule_targets (rule_id, target_type, target_id)
                 VALUES (${rule_id}, '${target_type}', ${target_id:-NULL})"

    if sqlite3 "${gravityDBfile}" "${query}" 2>&1; then
        echo -e "${TICK} Target attached to rule successfully"

        # Reapply rule if it's enabled
        local is_enabled
        is_enabled=$(sqlite3 "${gravityDBfile}" "SELECT enabled FROM parental_rules WHERE id = ${rule_id}")
        if [[ "${is_enabled}" == "1" ]]; then
            apply_rule "${rule_id}"
        fi

        return 0
    else
        echo -e "${CROSS} Failed to attach target"
        return 1
    fi
}

# Function to add schedule to rule
add_schedule() {
    check_database || return 1

    local rule_id="${1}"
    local schedule_type="${2}"
    local start_time="${3}"
    local end_time="${4}"
    local days_of_week="${5}"

    if [[ -z "${rule_id}" ]] || [[ -z "${schedule_type}" ]] || [[ -z "${start_time}" ]] || [[ -z "${end_time}" ]]; then
        echo -e "${CROSS} Rule ID, schedule type, start time, and end time are required"
        echo "Usage: pihole parental rule schedule <rule_id> <daily|weekly|always> <start_time> <end_time> [days]"
        return 1
    fi

    local query="INSERT INTO parental_schedules (rule_id, schedule_type, start_time, end_time, days_of_week, enabled)
                 VALUES (${rule_id}, '${schedule_type}', '${start_time}', '${end_time}', '${days_of_week}', 1)"

    if sqlite3 "${gravityDBfile}" "${query}" 2>&1; then
        local schedule_id
        schedule_id=$(sqlite3 "${gravityDBfile}" "SELECT last_insert_rowid()")
        echo -e "${TICK} Schedule added successfully (ID: ${schedule_id})"
        return 0
    else
        echo -e "${CROSS} Failed to add schedule"
        return 1
    fi
}

# Function to set time limit
set_time_limit() {
    check_database || return 1

    local rule_id="${1}"
    local limit_type="${2}"
    local duration_minutes="${3}"

    if [[ -z "${rule_id}" ]] || [[ -z "${limit_type}" ]] || [[ -z "${duration_minutes}" ]]; then
        echo -e "${CROSS} Rule ID, limit type, and duration are required"
        echo "Usage: pihole parental rule limit <rule_id> <daily|weekly|monthly> <minutes>"
        return 1
    fi

    local query="INSERT OR REPLACE INTO parental_time_limits (rule_id, limit_type, duration_minutes, enabled)
                 VALUES (${rule_id}, '${limit_type}', ${duration_minutes}, 1)"

    if sqlite3 "${gravityDBfile}" "${query}" 2>&1; then
        echo -e "${TICK} Time limit set successfully"
        return 0
    else
        echo -e "${CROSS} Failed to set time limit"
        return 1
    fi
}

# Function to apply rule (add domains to Pi-hole blocklist)
apply_rule() {
    local rule_id="${1}"

    if [[ -z "${rule_id}" ]]; then
        echo -e "${CROSS} Rule ID is required"
        return 1
    fi

    # Get all domains for services in this rule
    local domains
    domains=$(sqlite3 "${gravityDBfile}" "SELECT DISTINCT sd.domain, sd.is_regex, prs.action
                                           FROM parental_rule_services prs
                                           JOIN service_domains sd ON prs.service_category_id = sd.service_category_id
                                           WHERE prs.rule_id = ${rule_id} AND sd.enabled = 1")

    if [[ -z "${domains}" ]]; then
        echo -e "${INFO} No domains to apply for this rule"
        return 0
    fi

    local timestamp
    timestamp=$(date +%s)

    # Get rule targets
    local targets
    targets=$(sqlite3 "${gravityDBfile}" "SELECT target_type, target_id FROM parental_rule_targets WHERE rule_id = ${rule_id}")

    if [[ -z "${targets}" ]]; then
        echo -e "${WARN} No targets assigned to this rule"
        return 0
    fi

    # For each target, add domains to domainlist
    while IFS='|' read -r target_type target_id; do
        # Determine group_id
        local group_id
        if [[ "${target_type}" == "all" ]]; then
            group_id=0 # Default group
        elif [[ "${target_type}" == "group" ]]; then
            group_id="${target_id}"
        elif [[ "${target_type}" == "device" ]]; then
            # Get or create a group for this device
            group_id=$(sqlite3 "${gravityDBfile}" "SELECT group_id FROM client_by_group WHERE client_id = ${target_id} LIMIT 1")
            if [[ -z "${group_id}" ]]; then
                group_id=0
            fi
        fi

        # Add domains
        while IFS='|' read -r domain is_regex action; do
            local domain_type
            if [[ "${is_regex}" == "1" ]]; then
                domain_type=3 # regex blocklist
            else
                domain_type=1 # exact blocklist
            fi

            # Only add if action is block
            if [[ "${action}" == "block" ]]; then
                # Check if domain already exists
                local exists
                exists=$(sqlite3 "${gravityDBfile}" "SELECT id FROM domainlist WHERE domain = '${domain}' AND type = ${domain_type}")

                if [[ -z "${exists}" ]]; then
                    # Insert domain
                    sqlite3 "${gravityDBfile}" "INSERT INTO domainlist (type, domain, enabled, date_added, date_modified, comment)
                                                 VALUES (${domain_type}, '${domain}', 1, ${timestamp}, ${timestamp}, 'Parental Control Rule ${rule_id}')" 2>&1
                    local domain_id
                    domain_id=$(sqlite3 "${gravityDBfile}" "SELECT last_insert_rowid()")

                    # Link to group
                    sqlite3 "${gravityDBfile}" "INSERT OR IGNORE INTO domainlist_by_group (domainlist_id, group_id)
                                                 VALUES (${domain_id}, ${group_id})" 2>&1
                fi
            fi
        done <<< "${domains}"
    done <<< "${targets}"

    # Signal FTL to reload
    pkill -SIGRTMIN pihole-FTL 2>/dev/null || true

    echo -e "${TICK} Rule applied successfully"
}

# Function to unapply rule (remove domains from Pi-hole blocklist)
unapply_rule() {
    local rule_id="${1}"

    if [[ -z "${rule_id}" ]]; then
        echo -e "${CROSS} Rule ID is required"
        return 1
    fi

    # Remove domains added by this rule
    sqlite3 "${gravityDBfile}" "DELETE FROM domainlist WHERE comment = 'Parental Control Rule ${rule_id}'" 2>&1

    # Signal FTL to reload
    pkill -SIGRTMIN pihole-FTL 2>/dev/null || true

    echo -e "${TICK} Rule unapplied successfully"
}

# Function to show rule details
show_rule() {
    check_database || return 1

    local rule_id="${1}"

    if [[ -z "${rule_id}" ]]; then
        echo -e "${CROSS} Rule ID is required"
        echo "Usage: pihole parental rule show <id>"
        return 1
    fi

    # Get rule details
    local rule
    rule=$(sqlite3 "${gravityDBfile}" "SELECT name, description, enabled, priority, date_added, date_modified
                                        FROM parental_rules WHERE id = ${rule_id}")

    if [[ -z "${rule}" ]]; then
        echo -e "${CROSS} Rule ID ${rule_id} not found"
        return 1
    fi

    IFS='|' read -r name desc enabled priority date_added date_modified <<< "${rule}"

    echo -e "${INFO} Rule Details:"
    echo ""
    echo "ID: ${rule_id}"
    echo "Name: ${name}"
    echo "Description: ${desc}"
    echo "Enabled: ${enabled}"
    echo "Priority: ${priority}"
    echo "Created: $(date -d @${date_added} 2>/dev/null || echo ${date_added})"
    echo "Modified: $(date -d @${date_modified} 2>/dev/null || echo ${date_modified})"
    echo ""

    # Show services
    echo "Services:"
    local services
    services=$(sqlite3 "${gravityDBfile}" "SELECT sc.id, sc.name, prs.action
                                            FROM parental_rule_services prs
                                            JOIN service_categories sc ON prs.service_category_id = sc.id
                                            WHERE prs.rule_id = ${rule_id}")
    if [[ -n "${services}" ]]; then
        while IFS='|' read -r svc_id svc_name action; do
            echo "  - ${svc_name} (ID: ${svc_id}, Action: ${action})"
        done <<< "${services}"
    else
        echo "  (none)"
    fi
    echo ""

    # Show targets
    echo "Targets:"
    local targets
    targets=$(sqlite3 "${gravityDBfile}" "SELECT target_type, target_id FROM parental_rule_targets WHERE rule_id = ${rule_id}")
    if [[ -n "${targets}" ]]; then
        while IFS='|' read -r target_type target_id; do
            if [[ "${target_type}" == "all" ]]; then
                echo "  - All devices"
            elif [[ "${target_type}" == "group" ]]; then
                local group_name
                group_name=$(sqlite3 "${gravityDBfile}" "SELECT name FROM 'group' WHERE id = ${target_id}")
                echo "  - Group: ${group_name} (ID: ${target_id})"
            elif [[ "${target_type}" == "device" ]]; then
                local client_ip
                client_ip=$(sqlite3 "${gravityDBfile}" "SELECT ip FROM client WHERE id = ${target_id}")
                echo "  - Device: ${client_ip} (ID: ${target_id})"
            fi
        done <<< "${targets}"
    else
        echo "  (none)"
    fi
    echo ""

    # Show schedules
    echo "Schedules:"
    local schedules
    schedules=$(sqlite3 "${gravityDBfile}" "SELECT id, schedule_type, start_time, end_time, days_of_week, enabled
                                             FROM parental_schedules WHERE rule_id = ${rule_id}")
    if [[ -n "${schedules}" ]]; then
        while IFS='|' read -r sched_id sched_type start_time end_time days sched_enabled; do
            local status=""
            [[ "${sched_enabled}" == "0" ]] && status=" (disabled)"
            echo "  - ${sched_type}: ${start_time} - ${end_time}${status}"
            [[ -n "${days}" ]] && echo "    Days: ${days}"
        done <<< "${schedules}"
    else
        echo "  (none)"
    fi
    echo ""

    # Show time limits
    echo "Time Limits:"
    local limits
    limits=$(sqlite3 "${gravityDBfile}" "SELECT id, limit_type, duration_minutes, enabled
                                          FROM parental_time_limits WHERE rule_id = ${rule_id}")
    if [[ -n "${limits}" ]]; then
        while IFS='|' read -r limit_id limit_type duration limit_enabled; do
            local status=""
            [[ "${limit_enabled}" == "0" ]] && status=" (disabled)"
            echo "  - ${limit_type}: ${duration} minutes${status}"
        done <<< "${limits}"
    else
        echo "  (none)"
    fi
}

# Main function
main() {
    local action="${1}"
    shift

    case "${action}" in
        "list")
            list_rules "$@"
            ;;
        "add")
            add_rule "$@"
            ;;
        "remove"|"delete")
            remove_rule "$@"
            ;;
        "enable")
            toggle_rule "$1" "enable"
            ;;
        "disable")
            toggle_rule "$1" "disable"
            ;;
        "show"|"details")
            show_rule "$@"
            ;;
        "attach")
            local attach_type="${1}"
            shift
            case "${attach_type}" in
                "service")
                    attach_service "$@"
                    ;;
                "target")
                    attach_target "$@"
                    ;;
                *)
                    echo "Usage: pihole parental rule attach <service|target> [options]"
                    return 1
                    ;;
            esac
            ;;
        "detach")
            local detach_type="${1}"
            shift
            case "${detach_type}" in
                "service")
                    detach_service "$@"
                    ;;
                *)
                    echo "Usage: pihole parental rule detach <service> [options]"
                    return 1
                    ;;
            esac
            ;;
        "schedule")
            add_schedule "$@"
            ;;
        "limit")
            set_time_limit "$@"
            ;;
        "apply")
            apply_rule "$@"
            ;;
        "unapply")
            unapply_rule "$@"
            ;;
        *)
            echo "Pi-hole Parental Controls - Rules Management"
            echo ""
            echo "Usage: pihole parental rule <action> [options]"
            echo ""
            echo "Actions:"
            echo "  list                          List all rules"
            echo "  add <name> [description] [priority]"
            echo "                                Add a new rule"
            echo "  remove <id>                   Remove a rule"
            echo "  enable <id>                   Enable a rule"
            echo "  disable <id>                  Disable a rule"
            echo "  show <id>                     Show rule details"
            echo "  attach service <rule_id> <service_id> [block|allow]"
            echo "                                Attach service to rule"
            echo "  detach service <rule_id> <service_id>"
            echo "                                Detach service from rule"
            echo "  attach target <rule_id> <all|group|device> [id]"
            echo "                                Attach target to rule"
            echo "  schedule <rule_id> <type> <start> <end> [days]"
            echo "                                Add schedule to rule"
            echo "  limit <rule_id> <type> <minutes>"
            echo "                                Set time limit"
            echo "  apply <rule_id>               Apply rule (activate blocking)"
            echo "  unapply <rule_id>             Unapply rule (deactivate blocking)"
            echo ""
            echo "Examples:"
            echo "  pihole parental rule add 'Bedtime' 'Block gaming at night' 10"
            echo "  pihole parental rule attach service 1 2 block"
            echo "  pihole parental rule attach target 1 device 5"
            echo "  pihole parental rule schedule 1 daily 20:00 07:00"
            echo "  pihole parental rule limit 1 daily 120"
            return 1
            ;;
    esac
}

main "$@"
