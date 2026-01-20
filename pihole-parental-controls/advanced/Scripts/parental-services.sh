#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2025 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Parental Controls - Service Management
# Manage service categories and their associated domains
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

# Function to list all service categories
list_services() {
    check_database || return 1

    local show_domains="${1:-false}"

    echo -e "${INFO} Service Categories:"
    echo ""

    local query="SELECT id, name, description, enabled,
                 (SELECT COUNT(*) FROM service_domains WHERE service_category_id = service_categories.id) as domain_count
                 FROM service_categories
                 ORDER BY name"

    local result
    result=$(sqlite3 "${gravityDBfile}" "${query}" 2>&1)

    if [[ -z "${result}" ]]; then
        echo -e "${INFO} No service categories found. Use 'pihole parental service add' to create one."
        return 0
    fi

    # Print header
    printf "%-5s %-25s %-15s %-10s %s\n" "ID" "Name" "Domains" "Enabled" "Description"
    printf "%s\n" "--------------------------------------------------------------------------------"

    # Print each service
    while IFS='|' read -r id name desc enabled domain_count; do
        local status
        if [[ "${enabled}" == "1" ]]; then
            status="${COL_LIGHT_GREEN}Yes${COL_NC}"
        else
            status="${COL_LIGHT_RED}No${COL_NC}"
        fi

        printf "%-5s %-25s %-15s %-10b %s\n" "${id}" "${name}" "${domain_count}" "${status}" "${desc}"

        # Show domains if requested
        if [[ "${show_domains}" == "true" ]]; then
            local domains
            domains=$(sqlite3 "${gravityDBfile}" "SELECT domain, is_regex FROM service_domains WHERE service_category_id = ${id} AND enabled = 1 ORDER BY domain")
            if [[ -n "${domains}" ]]; then
                echo "  Domains:"
                while IFS='|' read -r domain is_regex; do
                    if [[ "${is_regex}" == "1" ]]; then
                        echo "    - ${domain} (regex)"
                    else
                        echo "    - ${domain}"
                    fi
                done <<< "${domains}"
            fi
            echo ""
        fi
    done <<< "${result}"
}

# Function to add a service category
add_service() {
    check_database || return 1

    local name="${1}"
    local description="${2}"

    if [[ -z "${name}" ]]; then
        echo -e "${CROSS} Service name is required"
        echo "Usage: pihole parental service add <name> [description]"
        return 1
    fi

    local timestamp
    timestamp=$(date +%s)

    local query="INSERT INTO service_categories (name, description, enabled, date_added, date_modified)
                 VALUES ('${name}', '${description}', 1, ${timestamp}, ${timestamp})"

    if sqlite3 "${gravityDBfile}" "${query}" 2>&1; then
        local service_id
        service_id=$(sqlite3 "${gravityDBfile}" "SELECT last_insert_rowid()")
        echo -e "${TICK} Service category '${name}' added successfully (ID: ${service_id})"
        return 0
    else
        echo -e "${CROSS} Failed to add service category '${name}'"
        return 1
    fi
}

# Function to remove a service category
remove_service() {
    check_database || return 1

    local service_id="${1}"

    if [[ -z "${service_id}" ]]; then
        echo -e "${CROSS} Service ID is required"
        echo "Usage: pihole parental service remove <id>"
        return 1
    fi

    # Check if service exists
    local service_name
    service_name=$(sqlite3 "${gravityDBfile}" "SELECT name FROM service_categories WHERE id = ${service_id}")

    if [[ -z "${service_name}" ]]; then
        echo -e "${CROSS} Service ID ${service_id} not found"
        return 1
    fi

    # Delete service (CASCADE will remove domains and mappings)
    if sqlite3 "${gravityDBfile}" "DELETE FROM service_categories WHERE id = ${service_id}" 2>&1; then
        echo -e "${TICK} Service category '${service_name}' removed successfully"
        return 0
    else
        echo -e "${CROSS} Failed to remove service category"
        return 1
    fi
}

# Function to enable/disable a service category
toggle_service() {
    check_database || return 1

    local service_id="${1}"
    local action="${2}" # enable or disable

    if [[ -z "${service_id}" ]] || [[ -z "${action}" ]]; then
        echo -e "${CROSS} Service ID and action are required"
        echo "Usage: pihole parental service <enable|disable> <id>"
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

    if sqlite3 "${gravityDBfile}" "UPDATE service_categories SET enabled = ${enabled}, date_modified = ${timestamp} WHERE id = ${service_id}" 2>&1; then
        echo -e "${TICK} Service category ${action}d successfully"
        return 0
    else
        echo -e "${CROSS} Failed to ${action} service category"
        return 1
    fi
}

# Function to add domain to service
add_domain() {
    check_database || return 1

    local service_id="${1}"
    local domain="${2}"
    local is_regex="${3:-0}"

    if [[ -z "${service_id}" ]] || [[ -z "${domain}" ]]; then
        echo -e "${CROSS} Service ID and domain are required"
        echo "Usage: pihole parental service domain add <service_id> <domain> [--regex]"
        return 1
    fi

    # Check if service exists
    local service_name
    service_name=$(sqlite3 "${gravityDBfile}" "SELECT name FROM service_categories WHERE id = ${service_id}")

    if [[ -z "${service_name}" ]]; then
        echo -e "${CROSS} Service ID ${service_id} not found"
        return 1
    fi

    local timestamp
    timestamp=$(date +%s)

    local query="INSERT INTO service_domains (service_category_id, domain, is_regex, enabled, date_added)
                 VALUES (${service_id}, '${domain}', ${is_regex}, 1, ${timestamp})"

    if sqlite3 "${gravityDBfile}" "${query}" 2>&1; then
        echo -e "${TICK} Domain '${domain}' added to service '${service_name}'"
        return 0
    else
        echo -e "${CROSS} Failed to add domain (may already exist)"
        return 1
    fi
}

# Function to remove domain from service
remove_domain() {
    check_database || return 1

    local domain_id="${1}"

    if [[ -z "${domain_id}" ]]; then
        echo -e "${CROSS} Domain ID is required"
        echo "Usage: pihole parental service domain remove <domain_id>"
        return 1
    fi

    if sqlite3 "${gravityDBfile}" "DELETE FROM service_domains WHERE id = ${domain_id}" 2>&1; then
        echo -e "${TICK} Domain removed successfully"
        return 0
    else
        echo -e "${CROSS} Failed to remove domain"
        return 1
    fi
}

# Function to list domains for a service
list_domains() {
    check_database || return 1

    local service_id="${1}"

    if [[ -z "${service_id}" ]]; then
        echo -e "${CROSS} Service ID is required"
        echo "Usage: pihole parental service domains <service_id>"
        return 1
    fi

    # Get service name
    local service_name
    service_name=$(sqlite3 "${gravityDBfile}" "SELECT name FROM service_categories WHERE id = ${service_id}")

    if [[ -z "${service_name}" ]]; then
        echo -e "${CROSS} Service ID ${service_id} not found"
        return 1
    fi

    echo -e "${INFO} Domains for service: ${service_name}"
    echo ""

    local query="SELECT id, domain, is_regex, enabled FROM service_domains
                 WHERE service_category_id = ${service_id}
                 ORDER BY domain"

    local result
    result=$(sqlite3 "${gravityDBfile}" "${query}" 2>&1)

    if [[ -z "${result}" ]]; then
        echo -e "${INFO} No domains found for this service"
        return 0
    fi

    # Print header
    printf "%-8s %-50s %-10s %s\n" "ID" "Domain" "Type" "Enabled"
    printf "%s\n" "--------------------------------------------------------------------------------"

    # Print each domain
    while IFS='|' read -r id domain is_regex enabled; do
        local domain_type
        if [[ "${is_regex}" == "1" ]]; then
            domain_type="Regex"
        else
            domain_type="Exact"
        fi

        local status
        if [[ "${enabled}" == "1" ]]; then
            status="${COL_LIGHT_GREEN}Yes${COL_NC}"
        else
            status="${COL_LIGHT_RED}No${COL_NC}"
        fi

        printf "%-8s %-50s %-10s %b\n" "${id}" "${domain}" "${domain_type}" "${status}"
    done <<< "${result}"
}

# Function to import domains from file
import_domains() {
    check_database || return 1

    local service_id="${1}"
    local file="${2}"
    local is_regex="${3:-0}"

    if [[ -z "${service_id}" ]] || [[ -z "${file}" ]]; then
        echo -e "${CROSS} Service ID and file path are required"
        echo "Usage: pihole parental service import <service_id> <file> [--regex]"
        return 1
    fi

    if [[ ! -f "${file}" ]]; then
        echo -e "${CROSS} File not found: ${file}"
        return 1
    fi

    # Check if service exists
    local service_name
    service_name=$(sqlite3 "${gravityDBfile}" "SELECT name FROM service_categories WHERE id = ${service_id}")

    if [[ -z "${service_name}" ]]; then
        echo -e "${CROSS} Service ID ${service_id} not found"
        return 1
    fi

    local count=0
    local failed=0

    echo -e "${INFO} Importing domains from ${file}..."

    while IFS= read -r domain; do
        # Skip empty lines and comments
        [[ -z "${domain}" ]] || [[ "${domain}" =~ ^[[:space:]]*# ]] && continue

        # Clean the domain
        domain=$(echo "${domain}" | tr -d '\r' | xargs)

        local timestamp
        timestamp=$(date +%s)

        local query="INSERT OR IGNORE INTO service_domains (service_category_id, domain, is_regex, enabled, date_added)
                     VALUES (${service_id}, '${domain}', ${is_regex}, 1, ${timestamp})"

        if sqlite3 "${gravityDBfile}" "${query}" 2>&1; then
            ((count++))
        else
            ((failed++))
        fi
    done < "${file}"

    echo -e "${TICK} Imported ${count} domains successfully"
    if [[ ${failed} -gt 0 ]]; then
        echo -e "${WARN} ${failed} domains failed to import (may be duplicates)"
    fi
}

# Main function
main() {
    local action="${1}"
    shift

    case "${action}" in
        "list")
            list_services "$@"
            ;;
        "add")
            add_service "$@"
            ;;
        "remove"|"delete")
            remove_service "$@"
            ;;
        "enable")
            toggle_service "$1" "enable"
            ;;
        "disable")
            toggle_service "$1" "disable"
            ;;
        "domain")
            local domain_action="${1}"
            shift
            case "${domain_action}" in
                "add")
                    add_domain "$@"
                    ;;
                "remove"|"delete")
                    remove_domain "$@"
                    ;;
                "list")
                    list_domains "$@"
                    ;;
                *)
                    echo "Usage: pihole parental service domain <add|remove|list> [options]"
                    return 1
                    ;;
            esac
            ;;
        "domains")
            list_domains "$@"
            ;;
        "import")
            import_domains "$@"
            ;;
        *)
            echo "Pi-hole Parental Controls - Service Management"
            echo ""
            echo "Usage: pihole parental service <action> [options]"
            echo ""
            echo "Actions:"
            echo "  list                          List all service categories"
            echo "  add <name> [description]      Add a new service category"
            echo "  remove <id>                   Remove a service category"
            echo "  enable <id>                   Enable a service category"
            echo "  disable <id>                  Disable a service category"
            echo "  domains <service_id>          List domains for a service"
            echo "  domain add <service_id> <domain> [--regex]"
            echo "                                Add a domain to a service"
            echo "  domain remove <domain_id>     Remove a domain from a service"
            echo "  import <service_id> <file> [--regex]"
            echo "                                Import domains from a file"
            echo ""
            echo "Examples:"
            echo "  pihole parental service list"
            echo "  pihole parental service add YouTube 'Video streaming service'"
            echo "  pihole parental service domains 1"
            echo "  pihole parental service domain add 1 youtube.com"
            echo "  pihole parental service domain add 1 '.*youtube.*' --regex"
            echo "  pihole parental service import 1 /path/to/domains.txt"
            return 1
            ;;
    esac
}

main "$@"
