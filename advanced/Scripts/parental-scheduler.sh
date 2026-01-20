#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2025 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Parental Controls - Scheduler Daemon
# Background service to handle time-based controls, schedules, and limits
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

readonly PI_HOLE_SCRIPT_DIR="/opt/pihole"
readonly gravityDBfile="/etc/pihole/gravity.db"
readonly logfile="/var/log/pihole/parental-scheduler.log"
readonly pidfile="/run/pihole/parental-scheduler.pid"

# Check interval in seconds (default: 60 seconds)
readonly CHECK_INTERVAL=60

# Source utils for database functions
# shellcheck source=utils.sh
source "${PI_HOLE_SCRIPT_DIR}/utils.sh"

# Logging function
log_message() {
    local level="${1}"
    local message="${2}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "${logfile}"
}

# Check if scheduler is already running
check_running() {
    if [[ -f "${pidfile}" ]]; then
        local pid
        pid=$(cat "${pidfile}")
        if kill -0 "${pid}" 2>/dev/null; then
            log_message "ERROR" "Scheduler already running with PID ${pid}"
            echo "Parental Controls Scheduler is already running (PID: ${pid})"
            exit 1
        else
            # Stale PID file
            rm -f "${pidfile}"
        fi
    fi
}

# Write PID file
write_pid() {
    echo $$ > "${pidfile}"
    log_message "INFO" "Scheduler started with PID $$"
}

# Cleanup on exit
cleanup() {
    log_message "INFO" "Scheduler stopping..."
    rm -f "${pidfile}"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Function to check if current time matches schedule
check_schedule() {
    local schedule_type="${1}"
    local start_time="${2}"
    local end_time="${3}"
    local days_of_week="${4}"
    local date_specific="${5}"

    local current_time
    current_time=$(date '+%H:%M')
    local current_day
    current_day=$(date '+%w') # 0=Sunday, 6=Saturday
    local current_date
    current_date=$(date '+%Y-%m-%d')

    # Check schedule type
    case "${schedule_type}" in
        "always")
            return 0 # Always active
            ;;
        "once")
            # Check if it's the specific date
            if [[ "${current_date}" == "${date_specific}" ]]; then
                # Check time range
                if [[ "${start_time}" < "${end_time}" ]]; then
                    # Same day range (e.g., 09:00 - 17:00)
                    if [[ "${current_time}" >= "${start_time}" ]] && [[ "${current_time}" < "${end_time}" ]]; then
                        return 0
                    fi
                else
                    # Overnight range (e.g., 20:00 - 07:00)
                    if [[ "${current_time}" >= "${start_time}" ]] || [[ "${current_time}" < "${end_time}" ]]; then
                        return 0
                    fi
                fi
            fi
            return 1
            ;;
        "daily")
            # Active every day
            if [[ "${start_time}" < "${end_time}" ]]; then
                # Same day range
                if [[ "${current_time}" >= "${start_time}" ]] && [[ "${current_time}" < "${end_time}" ]]; then
                    return 0
                fi
            else
                # Overnight range
                if [[ "${current_time}" >= "${start_time}" ]] || [[ "${current_time}" < "${end_time}" ]]; then
                    return 0
                fi
            fi
            return 1
            ;;
        "weekly")
            # Check if current day is in the allowed days
            if [[ -n "${days_of_week}" ]] && [[ "${days_of_week}" == *"${current_day}"* ]]; then
                # Check time range
                if [[ "${start_time}" < "${end_time}" ]]; then
                    # Same day range
                    if [[ "${current_time}" >= "${start_time}" ]] && [[ "${current_time}" < "${end_time}" ]]; then
                        return 0
                    fi
                else
                    # Overnight range
                    if [[ "${current_time}" >= "${start_time}" ]] || [[ "${current_time}" < "${end_time}" ]]; then
                        return 0
                    fi
                fi
            fi
            return 1
            ;;
    esac

    return 1
}

# Function to get usage for today
get_usage_today() {
    local rule_id="${1}"
    local target_type="${2}"
    local target_id="${3}"
    local service_category_id="${4}"

    local today
    today=$(date '+%Y-%m-%d')

    local query="SELECT COALESCE(SUM(minutes_used), 0) FROM parental_usage
                 WHERE rule_id = ${rule_id}
                 AND target_type = '${target_type}'
                 AND target_id = ${target_id}
                 AND service_category_id = ${service_category_id}
                 AND date = '${today}'"

    local usage
    usage=$(sqlite3 "${gravityDBfile}" "${query}" 2>&1)

    echo "${usage}"
}

# Function to check time limits
check_time_limit() {
    local rule_id="${1}"
    local target_type="${2}"
    local target_id="${3}"

    # Get time limits for this rule
    local limits
    limits=$(sqlite3 "${gravityDBfile}" "SELECT limit_type, duration_minutes FROM parental_time_limits
                                          WHERE rule_id = ${rule_id} AND enabled = 1")

    if [[ -z "${limits}" ]]; then
        return 0 # No limits, allow
    fi

    # Check each limit type
    while IFS='|' read -r limit_type duration_minutes; do
        case "${limit_type}" in
            "daily")
                # Get total usage today for all services in this rule
                local services
                services=$(sqlite3 "${gravityDBfile}" "SELECT service_category_id FROM parental_rule_services WHERE rule_id = ${rule_id}")

                local total_usage=0
                while IFS= read -r service_id; do
                    local usage
                    usage=$(get_usage_today "${rule_id}" "${target_type}" "${target_id}" "${service_id}")
                    total_usage=$((total_usage + usage))
                done <<< "${services}"

                if [[ ${total_usage} -ge ${duration_minutes} ]]; then
                    log_message "INFO" "Time limit exceeded for rule ${rule_id}, target ${target_type}:${target_id}"
                    return 1 # Limit exceeded, block
                fi
                ;;
        esac
    done <<< "${limits}"

    return 0 # Limits not exceeded
}

# Function to apply blocking for a rule
apply_rule_blocking() {
    local rule_id="${1}"
    local reason="${2:-schedule}"

    log_message "INFO" "Applying blocking for rule ${rule_id} (reason: ${reason})"

    # Get all domains for services in this rule
    local domains
    domains=$(sqlite3 "${gravityDBfile}" "SELECT DISTINCT sd.domain, sd.is_regex, prs.action
                                           FROM parental_rule_services prs
                                           JOIN service_domains sd ON prs.service_category_id = sd.service_category_id
                                           WHERE prs.rule_id = ${rule_id} AND sd.enabled = 1 AND prs.action = 'block'")

    if [[ -z "${domains}" ]]; then
        return 0
    fi

    local timestamp
    timestamp=$(date +%s)

    # Get rule targets
    local targets
    targets=$(sqlite3 "${gravityDBfile}" "SELECT target_type, target_id FROM parental_rule_targets WHERE rule_id = ${rule_id}")

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

            # Check if domain already exists
            local exists
            exists=$(sqlite3 "${gravityDBfile}" "SELECT id FROM domainlist WHERE domain = '${domain}' AND type = ${domain_type} AND comment = 'Parental Control Rule ${rule_id}'")

            if [[ -z "${exists}" ]]; then
                # Insert domain
                sqlite3 "${gravityDBfile}" "INSERT INTO domainlist (type, domain, enabled, date_added, date_modified, comment)
                                             VALUES (${domain_type}, '${domain}', 1, ${timestamp}, ${timestamp}, 'Parental Control Rule ${rule_id}')" 2>&1
                local domain_id
                domain_id=$(sqlite3 "${gravityDBfile}" "SELECT last_insert_rowid()")

                # Link to group
                sqlite3 "${gravityDBfile}" "INSERT OR IGNORE INTO domainlist_by_group (domainlist_id, group_id)
                                             VALUES (${domain_id}, ${group_id})" 2>&1
            else
                # Re-enable if it was disabled
                sqlite3 "${gravityDBfile}" "UPDATE domainlist SET enabled = 1 WHERE id = ${exists}" 2>&1
            fi
        done <<< "${domains}"

        # Mark as actively blocked
        sqlite3 "${gravityDBfile}" "INSERT OR REPLACE INTO parental_active_blocks (rule_id, target_type, target_id, service_category_id, blocked_at, block_reason)
                                     SELECT ${rule_id}, '${target_type}', ${target_id}, service_category_id, ${timestamp}, '${reason}'
                                     FROM parental_rule_services WHERE rule_id = ${rule_id}" 2>&1
    done <<< "${targets}"

    # Signal FTL to reload
    pkill -SIGRTMIN pihole-FTL 2>/dev/null || true
}

# Function to remove blocking for a rule
remove_rule_blocking() {
    local rule_id="${1}"

    log_message "INFO" "Removing blocking for rule ${rule_id}"

    # Disable domains added by this rule
    sqlite3 "${gravityDBfile}" "UPDATE domainlist SET enabled = 0 WHERE comment = 'Parental Control Rule ${rule_id}'" 2>&1

    # Remove from active blocks
    sqlite3 "${gravityDBfile}" "DELETE FROM parental_active_blocks WHERE rule_id = ${rule_id}" 2>&1

    # Signal FTL to reload
    pkill -SIGRTMIN pihole-FTL 2>/dev/null || true
}

# Function to check and apply/remove rules based on schedules
process_schedules() {
    # Get all enabled rules
    local rules
    rules=$(sqlite3 "${gravityDBfile}" "SELECT id FROM parental_rules WHERE enabled = 1")

    if [[ -z "${rules}" ]]; then
        return 0
    fi

    while IFS= read -r rule_id; do
        # Get schedules for this rule
        local schedules
        schedules=$(sqlite3 "${gravityDBfile}" "SELECT schedule_type, start_time, end_time, days_of_week, date_specific
                                                 FROM parental_schedules
                                                 WHERE rule_id = ${rule_id} AND enabled = 1")

        local should_block=0

        if [[ -z "${schedules}" ]]; then
            # No schedules means always active
            should_block=1
        else
            # Check if any schedule is active
            while IFS='|' read -r schedule_type start_time end_time days_of_week date_specific; do
                if check_schedule "${schedule_type}" "${start_time}" "${end_time}" "${days_of_week}" "${date_specific}"; then
                    should_block=1
                    break
                fi
            done <<< "${schedules}"
        fi

        # Check if rule is currently blocking
        local is_blocking
        is_blocking=$(sqlite3 "${gravityDBfile}" "SELECT COUNT(*) FROM parental_active_blocks WHERE rule_id = ${rule_id}")

        if [[ ${should_block} -eq 1 ]] && [[ ${is_blocking} -eq 0 ]]; then
            # Should block but not currently blocking
            apply_rule_blocking "${rule_id}" "schedule"
        elif [[ ${should_block} -eq 0 ]] && [[ ${is_blocking} -gt 0 ]]; then
            # Should not block but currently blocking
            remove_rule_blocking "${rule_id}"
        fi
    done <<< "${rules}"
}

# Function to track usage (simplified - in production would parse FTL queries)
track_usage() {
    # This is a placeholder - in a full implementation, this would:
    # 1. Query FTL for recent DNS queries
    # 2. Match queries against service domains
    # 3. Calculate session duration
    # 4. Update parental_usage table
    # 5. Check against time limits

    # For now, we'll just log that tracking is running
    log_message "DEBUG" "Usage tracking cycle complete"
}

# Main scheduler loop
scheduler_loop() {
    log_message "INFO" "Scheduler loop started"

    while true; do
        # Process schedules
        process_schedules

        # Track usage and check limits
        track_usage

        # Sleep for the check interval
        sleep "${CHECK_INTERVAL}"
    done
}

# Main function
main() {
    local action="${1:-start}"

    case "${action}" in
        "start")
            # Create log directory if it doesn't exist
            mkdir -p "$(dirname "${logfile}")"
            mkdir -p "$(dirname "${pidfile}")"

            # Check if already running
            check_running

            # Write PID file
            write_pid

            # Start scheduler loop
            scheduler_loop
            ;;
        "stop")
            if [[ -f "${pidfile}" ]]; then
                local pid
                pid=$(cat "${pidfile}")
                if kill -0 "${pid}" 2>/dev/null; then
                    echo "Stopping Parental Controls Scheduler (PID: ${pid})..."
                    kill "${pid}"
                    rm -f "${pidfile}"
                    echo "Stopped."
                else
                    echo "Scheduler not running (stale PID file)"
                    rm -f "${pidfile}"
                fi
            else
                echo "Scheduler not running"
            fi
            ;;
        "status")
            if [[ -f "${pidfile}" ]]; then
                local pid
                pid=$(cat "${pidfile}")
                if kill -0 "${pid}" 2>/dev/null; then
                    echo "Parental Controls Scheduler is running (PID: ${pid})"
                    exit 0
                else
                    echo "Scheduler not running (stale PID file)"
                    rm -f "${pidfile}"
                    exit 1
                fi
            else
                echo "Scheduler not running"
                exit 1
            fi
            ;;
        "restart")
            "$0" stop
            sleep 2
            "$0" start
            ;;
        *)
            echo "Usage: $0 {start|stop|status|restart}"
            exit 1
            ;;
    esac
}

main "$@"
