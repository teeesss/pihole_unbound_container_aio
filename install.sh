#!/bin/bash

# Pi-hole Docker Installation Script with Enhanced Security and Unbound
# Version: 24.0 (Project Complete)
# Description: Production-ready Pi-hole installation with Unbound DNS resolver

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Default configuration
DEFAULT_WEB_PORT="8088"
DEFAULT_PASSWORD="YourNewSecurePassword"
DEFAULT_TIMEZONE="America/Chicago"

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Logging function
log() {
    echo -e "${2:-$GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$PROJECT_DIR/install.log"
}

# Error handling
error_exit() {
    log "ERROR: $1" "$RED" >&2
    exit 1
}

# Progress indicator
progress() {
    echo -e "${BLUE}[➔]${NC} $1"
}

# Success indicator
success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

# Warning indicator
warning() {
    echo -e "${YELLOW}[⚠️]${NC} $1"
}

# Wait for container to become fully healthy
wait_for_healthy_container() {
    local max_wait=180
    local count=0

    progress "Waiting for container to become healthy (this may take a few minutes on first run)..."

    while [[ $count -lt $max_wait ]]; do
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' pihole 2>/dev/null || echo "starting")
        
        case "$status" in
            "healthy")
                success "Container is healthy! Proceeding with post-install steps."
                sleep 5
                return 0
                ;;
            "unhealthy")
                error_exit "Container reported as unhealthy. Please check logs with 'docker logs pihole'."
                ;;
            *) # starting or other
                echo -n "."
                sleep 5
                ((count += 5))
                ;;
        esac
    done

    error_exit "Container failed to become healthy in time. Please check logs with 'docker logs pihole'."
}

# Function to display the main menu
show_main_menu() {
    clear

    # Print PI-HOLE art in CYAN
    echo -e "${CYAN}"
    cat << 'EOF'
          ██████╗ ██╗      ██╗  ██╗ █████╗ ██╗     ███████╗  
          ██╔══██╗██║      ██║  ██║██╔══██╗██║     ██╔════╝    ██╗
          ██████╔╝██║█████╗███████║██║  ██║██║     █████╗    ██████╗
          ██╔═══╝ ██║╚════╝██╔══██║██║  ██║██║     ██╔══╝    ╚═██╔═╝
          ██║     ██║      ██║  ██║╚█████╔╝███████╗███████╗    ╚═╝
          ╚═╝     ╚═╝      ╚═╝  ╚═╝ ╚════╝ ╚══════╝╚══════╝  
EOF

    echo -e "${CYAN}"
    cat << 'EOF'

          ██╗   ██╗███╗  ██╗██████╗  █████╗ ██╗   ██╗███╗  ██╗██████╗
          ██║   ██║████╗ ██║██╔══██╗██╔══██╗██║   ██║████╗ ██║██╔══██╗
          ██║   ██║██╔██╗██║██████╦╝██║  ██║██║   ██║██╔██╗██║██║  ██║
          ██║   ██║██║╚████║██╔══██╗██║  ██║██║   ██║██║╚████║██║  ██║
          ╚██████╔╝██║ ╚███║██████╦╝╚█████╔╝╚██████╔╝██║ ╚███║██████╔╝
           ╚═════╝ ╚═╝  ╚══╝╚═════╝  ╚════╝  ╚═════╝ ╚═╝  ╚══╝╚═════╝
EOF
    # Reset color back to normal
    echo -e "${NC}"

    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"

    if [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        echo -e "${CYAN}                           PI-HOLE MANAGEMENT MENU${NC}"
        echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}Existing Pi-hole installation detected!${NC}"
        echo
        echo -e "  ${GREEN}1.${NC} Fresh Installation (destroy existing & start over)"
        echo -e "  ${GREEN}2.${NC} Update Container (pull latest image & recreate)"
        echo -e "  ${GREEN}3.${NC} View Status & Run Diagnostics"
        echo -e "  ${GREEN}4.${NC} Reinstall/Repair Installation"
        echo -e "  ${GREEN}5.${NC} Fix Container Permissions & Config"
        echo -e "  ${GREEN}6.${NC} Setup Automatic Permission Fixer (hourly cron)"
        echo -e "  ${GREEN}7.${NC} Change Pi-hole Password"
        echo -e "  ${GREEN}8.${NC} Import Adlists from File"
        echo -e "  ${GREEN}9.${NC} Import Domain Rules from Script"
        echo -e " ${GREEN}10.${NC} Set Custom NTP Server"
        echo -e " ${GREEN}11.${NC} Export Domain Rules to Script"
        echo -e " ${GREEN}12.${NC} Export Adlists to File"
        echo -e " ${GREEN}13.${NC} Test DNSSEC Validation"
        echo -e " ${GREEN}14.${NC} View Pi-hole Logs"
        echo -e " ${GREEN}15.${NC} Uninstall Pi-hole"
        echo -e " ${GREEN}16.${NC} Exit"
    else
        echo -e "${CYAN}                      PI-HOLE INSTALLATION MENU${NC}"
        echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}No existing installation found.${NC}"
        echo
        echo -e "  ${GREEN}1.${NC} Fresh Installation (recommended)"
        echo -e "  ${GREEN}2.${NC} Custom Installation (configure settings)"
        echo -e "  ${GREEN}3.${NC} Exit"
    fi

    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
}

# Enhanced status function
show_status() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                           PI-HOLE STATUS${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"

    if [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        echo -e "${GREEN}Configuration found in: $PROJECT_DIR${NC}"
        echo
        echo -e "${BLUE}Docker Compose Status:${NC}"
        cd "$PROJECT_DIR"
        docker compose ps

        echo
        local container_status
        container_status=$(docker inspect --format='{{.State.Health.Status}}' pihole 2>/dev/null || echo "unknown")
        echo -e "${BLUE}Container Health State: ${NC}$container_status"

        case "$container_status" in
            "healthy")
                success "Container is running and healthy!"
                verify_installation
                ;;
            *)
                warning "Container is not healthy. Please check logs."
                ;;
        esac
    else
        echo -e "${RED}No Pi-hole installation found in current directory${NC}"
    fi

    echo
    echo -e "${YELLOW}Press Enter to return to main menu...${NC}"
    read -r
}

# Get host IP
get_host_ip() {
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1
}

# View logs function
view_logs() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                      VIEWING PI-HOLE LOGS${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"

    if docker ps --format "{{.Names}}" | grep -q "^pihole$"; then
        echo -e "${BLUE}Recent Pi-hole logs (last 50 lines):${NC}"
        echo
        docker logs --tail=50 pihole
        echo
        echo -e "${BLUE}Live log streaming (Press Ctrl+C to stop):${NC}"
        docker logs -f pihole
    else
        echo -e "${RED}Pi-hole container not found!${NC}"
    fi

    echo
    echo -e "${YELLOW}Press Enter to return to main menu...${NC}"
    read -r
}

# Password change function
change_password() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                            CHANGE PI-HOLE PASSWORD${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"

    if ! docker ps --format "{{.Names}}" | grep -q "^pihole$"; then
        echo -e "${RED}Pi-hole container not running!${NC}"
        echo
        echo -e "${YELLOW}Press Enter to return to main menu...${NC}"
        read -r
        return
    fi

    echo
    while true; do
        echo -n -e "${YELLOW}Enter new Pi-hole admin password: ${NC}"
        read -s new_password1
        echo
        echo -n -e "${YELLOW}Confirm new Pi-hole admin password: ${NC}"
        read -s new_password2
        echo
        echo

        if [[ "$new_password1" == "$new_password2" ]]; then
            if [[ ${#new_password1} -lt 8 ]]; then
                echo -e "${RED}Password should be at least 8 characters long.${NC}"
                echo
                continue
            fi

            progress "Setting password in container..."
            if docker exec pihole pihole setpassword "$new_password1" >/dev/null 2>&1; then
                success "Password successfully updated!"
                if [[ -f "$PROJECT_DIR/.env" ]]; then
                    sed -i "s/^WEBPASSWORD=.*/WEBPASSWORD=$new_password1/" "$PROJECT_DIR/.env"
                    success "Password also updated in .env file"
                fi
            else
                echo -e "${RED}Failed to set password in container.${NC}"
            fi
            break
        else
            echo -e "${RED}Passwords do not match. Please try again.${NC}"
            echo
        fi
    done

    echo
    echo -e "${YELLOW}Press Enter to return to main menu...${NC}"
    read -r
}

# Function to get user/group IDs
get_user_ids() {
    USER_ID=$(id -u)
    GROUP_ID=$(id -g)

    if [[ "$USER_ID" == "0" ]]; then
        USER_ID="1026"
        GROUP_ID="100"
        warning "Running as root, using default UID:GID $USER_ID:$GROUP_ID"
    fi
}

# Function to set default configuration
set_default_config() {
    WEB_PORT="$DEFAULT_WEB_PORT"
    WEB_PASSWORD="$DEFAULT_PASSWORD"
    TIMEZONE="$DEFAULT_TIMEZONE"
}

# Function to get custom configuration
get_custom_config() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                              CUSTOM CONFIGURATION${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo

    echo -e "${YELLOW}Web UI Port Configuration:${NC}"
    echo -n -e "${YELLOW}Web UI Port [press Enter for default $DEFAULT_WEB_PORT]: ${NC}"
    read -r user_port
    WEB_PORT="${user_port:-$DEFAULT_WEB_PORT}"

    echo
    echo -e "${YELLOW}Admin Password Configuration:${NC}"
    echo -n -e "${YELLOW}Admin Password [press Enter for default]: ${NC}"
    read -r user_password
    WEB_PASSWORD="${user_password:-$DEFAULT_PASSWORD}"

    echo
    echo -e "${YELLOW}Timezone Configuration:${NC}"
    echo -n -e "${YELLOW}Timezone [press Enter for default $DEFAULT_TIMEZONE]: ${NC}"
    read -r user_timezone
    TIMEZONE="${user_timezone:-$DEFAULT_TIMEZONE}"

    echo
    echo -e "${GREEN}Configuration Summary:${NC}"
    echo -e "  Web UI Port: $WEB_PORT, Admin Password: [hidden], Timezone: $TIMEZONE"
    echo
}

# Function to show confirmation
show_confirmation() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                                   CONFIRMATION${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"

    echo -e "${GREEN}This script will create a new Pi-hole installation in the current directory:${NC}"
    echo -e "  $PROJECT_DIR"
    echo
    echo -e "${GREEN}Using the following settings:${NC}"
    echo -e "  ${BLUE}- Networking:${NC}         Bridge mode with exposed ports"
    echo -e "  ${BLUE}- Web UI Port:${NC}        $WEB_PORT"
    echo -e "  ${BLUE}- Web Password:${NC}       (from .env file)"
    echo -e "  ${BLUE}- Timezone:${NC}           $TIMEZONE"
    echo -e "  ${BLUE}- Upstream DNS:${NC}       Unbound via FTLCONF (127.0.0.1#5335)"
    echo -e "  ${BLUE}- User/Group ID:${NC}      $USER_ID:$GROUP_ID"
    echo
    warning "SECURITY NOTE: This script will configure Pi-hole to listen on all interfaces"
    warning "within its container. This is standard practice for Docker and is secure as long"
    warning "as your HOST machine's firewall does not expose port 53 to the internet."
    echo
    echo -n -e "${YELLOW}Are these settings correct? [y/N] ${NC}"
    read -r confirmation
    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Installation cancelled by user.${NC}"
        exit 0
    fi
}

# Function to clean up existing installation
cleanup_existing() {
    if [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        progress "Stopping and removing existing container and its volumes..."
        cd "$PROJECT_DIR"
        docker compose down --remove-orphans -v 2>/dev/null || true
        success "Existing container and its volumes stopped and removed."

        progress "Removing old configuration files and directories..."
        rm -f "$PROJECT_DIR/docker-compose.yml" "$PROJECT_DIR/.env"
        sudo rm -rf "$PROJECT_DIR/etc-pihole" "$PROJECT_DIR/etc-dnsmasq.d"
        success "Old configuration removed."
    fi
}

# Function to check prerequisites
check_prerequisites() {
    local missing_deps=()
    for tool in docker curl dig systemctl jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_deps+=("$tool")
        fi
    done
    if ! docker compose version >/dev/null 2>&1; then
        missing_deps+=("docker-compose")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}. Please install them first (e.g., 'sudo apt-get install jq')."
    fi

    if ! docker info >/dev/null 2>&1; then
        error_exit "Cannot connect to Docker daemon. Please ensure Docker is running and you have proper permissions."
    fi
}

# Function to prepare host
prepare_host() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                      STEP 1: Preparing Host${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"

    progress "Disabling systemd-resolved stub listener..."
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        if [[ ! -f /etc/systemd/resolved.conf.backup ]]; then
            sudo cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.backup
            success "Backed up original systemd-resolved config"
        fi
        sudo tee /etc/systemd/resolved.conf >/dev/null << 'EOF'
[Resolve]
DNS=1.1.1.1
DNSStubListener=no
EOF
        sudo systemctl restart systemd-resolved
        success "systemd-resolved configured to free up port 53"
    else
        success "systemd-resolved not running, no configuration needed"
    fi
}

# Function to create project configuration files
create_project_files() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                      STEP 2: Creating Project Configuration Files${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"

    mkdir -p "$PROJECT_DIR/etc-pihole"
    mkdir -p "$PROJECT_DIR/etc-dnsmasq.d"
    success "Volume directories created."

    progress "Creating .env file for secrets..."
    cat > "$PROJECT_DIR/.env" << EOF
# This file stores secrets and should be added to .gitignore
WEBPASSWORD=${WEB_PASSWORD}
EOF
    success ".env file created."

    progress "Creating docker-compose.yml..."
    cat > "$PROJECT_DIR/docker-compose.yml" << EOF
services:
  pihole:
    image: mpgirro/pihole-unbound:latest
    container_name: pihole
    hostname: pihole
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "${WEB_PORT}:80/tcp"
      - "443:443/tcp"
    env_file: .env
    environment:
      TZ: '${TIMEZONE}'
      PIHOLE_UID: '${USER_ID}'
      PIHOLE_GID: '${GROUP_ID}'
      FTLCONF_dns_upstreams: '127.0.0.1#5335'
      FTLCONF_dns_dnssec: 'true'
      FTLCONF_ntp_ipv4_active: 'false'
      FTLCONF_ntp_ipv6_active: 'false'
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
    cap_add:
      - NET_ADMIN
      - SYS_NICE
      - SYS_TIME
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "dig @127.0.0.1 -p 5335 google.com || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
EOF

    success "Docker Compose file created."
}

# Function to create example files
create_example_files() {
    if [[ ! -f "$PROJECT_DIR/domains-example.txt" ]]; then
        progress "Creating example domain file: domains-example.txt"
        cat > "$PROJECT_DIR/domains-example.txt" << 'EOF'
# This is an example file for importing custom domain and regex rules.
# The format uses simple "key: value" pairs for each domain.
# Blocks of rules are separated by one or more blank lines.
# Lines starting with # are ignored.

domain: (\.|^)good-domain\.com$
type:   regex-allow
comment: Allow this essential service
groups: Default

domain: bad-tracker.com
type:   exact-deny
comment: A known ad server
groups: Default,Marketing
EOF
    fi
    if [[ ! -f "$PROJECT_DIR/adlists-example.txt" ]]; then
        progress "Creating example adlist file: adlists-example.txt"
        cat > "$PROJECT_DIR/adlists-example.txt" << 'EOF'
# This is an example file for importing custom adlists.
# The format for each line is: <url>|<comment>
# Lines starting with # are ignored.

https://some.other.list/hosts.txt|My custom adlist
EOF
    fi
}

# Post-install function to patch config files
post_install_configuration() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                      STEP 4: Post-Install Configuration${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"

    progress "Forcing Pi-hole listening mode to 'ALL'..."
    if docker exec pihole sed -i 's/listeningMode = "LOCAL"/listeningMode = "ALL"/' /etc/pihole/pihole.toml; then
        success "Successfully set listeningMode to ALL."
    else
        warning "Could not patch pihole.toml. Manual check may be needed."
    fi

    progress "Restarting Pi-hole container for changes to take effect..."
    if docker compose restart >/dev/null; then
        success "Container restarted successfully."
        wait_for_healthy_container
    else
        error_exit "Failed to restart the container. Please check docker logs."
    fi
}

# Final verification function
verify_installation() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                      STEP 5: DNS Service Verification${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    local host_ip
    host_ip=$(get_host_ip)
    local all_ok=true

    if [[ -z "$host_ip" ]]; then
        error_exit "Could not determine host IP for verification."
    fi

    echo -n -e "  ${BLUE}•${NC} Testing standard DNS resolution (google.com)... "
    if dig @"$host_ip" google.com +short > /dev/null 2>&1; then
        echo -e "${GREEN}SUCCESS${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        all_ok=false
    fi

    echo -n -e "  ${BLUE}•${NC} Testing DNSSEC validation (sigfail.verteiltesysteme.net)... "
    if dig @"$host_ip" sigfail.verteiltesysteme.net +time=5 +tries=1 2>&1 | grep -q "SERVFAIL"; then
        echo -e "${GREEN}SUCCESS${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        all_ok=false
    fi

    if [[ "$all_ok" == "false" ]]; then
        echo
        error_exit "One or more core DNS verification tests failed. The installation is not working correctly."
    fi
    return 0
}

# Internal function to run the initial adlist import
run_initial_adlist_import() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                      STEP 6: Importing Default Adlists${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    
    # This function uses a hardcoded default list for a reliable first run.
    declare -a default_adlists=(
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts|StevenBlack Default"
        "https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/BaseFilter/sections/adservers.txt|Adguard"
        "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext|Adservers"
        "https://someonewhocares.org/hosts/zero/hosts|Someonewhocares"
        "https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/TrackingFilter/sections/general_url.txt|AdguardTeam Tracking"
        "https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/SocialFilter/sections/general_url.txt|AdguardFilters Social"
        "https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/MobileFilter/sections/adservers.txt|AdguardFilters Mobile"
        "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt|WindowsSpyBlocker"
        "https://raw.githubusercontent.com/hoshsadiq/adblock-nocoin-list/master/hosts.txt|Adblock Nocoin"
        "https://zerodot1.gitlab.io/CoinBlockerLists/hosts_browser|CoinBlockerLists"
        "https://www.github.developerdan.com/hosts/lists/ads-and-tracking-extended.txt|DeveloperDan"
        "https://raw.githubusercontent.com/durablenapkin/scamblocklist/master/hosts.txt|DurableNapkin"
        "https://phishing.army/download/phishing_army_blocklist_extended.txt|Phishing Army"
        "https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-malware.txt|NoTrack"
        "https://raw.githubusercontent.com/Spam404/lists/master/main-blacklist.txt|Spam404"
        "https://raw.githubusercontent.com/FadeMind/hosts.extras/master/UncheckyAds/hosts|Fademind"
        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt|hagezi"
    )

    import_adlists_logic "default_adlists[@]" "built-in list"
    
    progress "Running gravity update..."
    docker exec pihole pihole -g >/dev/null
    
    progress "Restarting container for a clean state after gravity update..."
    docker compose restart >/dev/null
    wait_for_healthy_container
    success "Initial adlist import and final restart complete."
}


# Core logic for importing adlists from a source (array name or filename)
import_adlists_logic() {
    local source_ref="$1"
    local source_desc="$2"
    
    local adlist_array=()
    if [[ -f "$source_ref" ]]; then
        mapfile -t adlist_array < "$source_ref"
    else
        eval "adlist_array=(\"\${$source_ref}\")"
    fi

    progress "Checking for existing adlists from $source_desc..."
    
    if ! docker ps --format "{{.Names}}" | grep -q "^pihole$"; then error_exit "Pi-hole container not running."; fi

    progress "Ensuring sqlite3 is available in container..."
    if ! docker exec pihole which sqlite3 >/dev/null 2>&1; then
        if docker exec pihole apk add --no-cache sqlite >/dev/null; then success "sqlite3 installed."; else error_exit "Failed to install sqlite3."; fi
    fi

    local added_count=0; local existing_count=0; local lists_to_add=()
    
    set +e
    for item in "${adlist_array[@]}"; do
        if [[ "$item" =~ ^# || -z "$item" ]]; then continue; fi
        local url comment; IFS='|' read -r url comment <<< "$item"
        local exists_output; exists_output=$(docker exec pihole sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM adlist WHERE address = '$url';")
        if [ "$?" -eq 0 ] && [ "$exists_output" = "0" ]; then
            local comment_escaped="${comment//\'/\'\'}"; lists_to_add+=("('$url', 1, '$comment_escaped')"); ((added_count++))
        else
            ((existing_count++))
        fi
    done
    set -e

    if [ ${#lists_to_add[@]} -gt 0 ]; then
        progress "Adding ${#lists_to_add[@]} new adlists in a single transaction..."
        local values_string; values_string=$(printf ",%s" "${lists_to_add[@]}"); values_string=${values_string:1}
        docker exec pihole pihole disable 2>/dev/null
        if docker exec pihole sqlite3 /etc/pihole/gravity.db "INSERT INTO adlist (address, enabled, comment) VALUES $values_string;"; then success "Bulk insert successful."; else warning "Bulk insert failed."; fi
        docker exec pihole pihole enable 2>/dev/null
    fi

    echo; echo -e "${GREEN}Adlist Import Summary:${NC}"; echo -e "${CYAN}  ✓ Added: $added_count new adlists${NC}"; echo -e "${CYAN}  ○ Skipped: $existing_count existing adlists${NC}"
    progress "Verifying total adlists in database..."; local adlist_count; adlist_count=$(docker exec pihole sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM adlist WHERE enabled = 1;" 2>/dev/null || echo "Error")
    success "Verification successful: Found ${adlist_count} enabled adlists in gravity.db."
}


# User-facing function for the adlist import menu
import_adlists_from_file() {
    local adlist_file="adlists.txt"
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                      IMPORT ADLISTS FROM FILE${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -n -e "${YELLOW}Enter filename for adlists [press Enter for default: adlists.txt]: ${NC}"
    read -r user_file
    adlist_file="${user_file:-$adlist_file}"

    if [[ ! -f "$adlist_file" ]]; then error_exit "File not found: $adlist_file"; fi
    
    import_adlists_logic "$adlist_file" "file '$adlist_file'"
    
    progress "Updating gravity database... (This may take several minutes)"
    docker exec pihole pihole -g
    success "Gravity database updated successfully!"

    echo
    echo -e "${YELLOW}Press Enter to return to main menu...${NC}"
    read -r
}

# Function to export domain rules to an executable backup script
export_domains() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                      EXPORT DOMAIN RULES TO SCRIPT${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"

    if ! docker ps --format "{{.Names}}" | grep -q "^pihole$"; then error_exit "Pi-hole container not running."; fi
    
    local backup_file="domains-backup.sh"
    progress "Exporting domain rules to executable script '$backup_file'..."

    # Use the proven sqlite3 query with a tab separator and the corrected awk script
    local raw_data
    raw_data=$(sudo docker exec pihole sqlite3 -separator $'\t' /etc/pihole/gravity.db \
    "SELECT d.domain, CASE WHEN d.type IN (1,3) THEN 'allow' ELSE 'deny' END, CASE WHEN d.type IN (0,1) THEN 'exact' ELSE 'regex' END, d.comment, GROUP_CONCAT(g.name) FROM domainlist d JOIN domainlist_by_group dbg ON d.id = dbg.domainlist_id JOIN \"group\" g ON g.id = dbg.group_id GROUP BY d.id;")
    
    if [ -n "$raw_data" ]; then
        # Create the header of the script
        {
            echo "#!/bin/bash"
            echo "# This is an auto-generated script of your domain rules."
            echo "# You can use the import function (which defaults to this filename) to restore these settings."
            echo ""
        } > "$backup_file"

        # Use AWK with the tab delimiter to format the data into function calls
        echo "$raw_data" | awk 'BEGIN {
            FS="\t";
            q = "'\''";
        }
        {
            # Escape backslashes and single quotes for shell safety
            gsub(/\\/, "\\\\", $1); gsub(q, q "\\" q q, $1);
            gsub(/\\/, "\\\\", $4); gsub(q, q "\\" q q, $4);
            
            # Build the group ID lookup string dynamically
            groups_str = ""
            n = split($5, groups, ",")
            for (i=1; i<=n; i++) {
                groups_str = groups_str "[${group_id_map[\"" groups[i] "\"]}]"
                if (i < n) {
                    groups_str = groups_str ","
                }
            }

            printf "add_domain %s%s%s %s%s%s %s%s%s %s%s%s %s[%s]%s\n", q, $1, q, q, $2, q, q, $3, q, q, $4, q, q, groups_str, q;
        }' >> "$backup_file"
        
        success "Successfully exported domain rules to '$backup_file'."
    else
        warning "No domain rules found to export."
    fi
    
    echo
    echo -e "${YELLOW}Press Enter to return to main menu...${NC}"; read -r
}

# Function to export adlists to a backup file
export_adlists() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                        EXPORT ADLISTS TO FILE${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"

    if ! docker ps --format "{{.Names}}" | grep -q "^pihole$"; then error_exit "Pi-hole container not running."; fi
    
    local backup_file="adlists-backup.txt"
    progress "Exporting adlists to '$backup_file'..."

    local export_data
    export_data=$(sudo docker exec pihole sqlite3 /etc/pihole/gravity.db "SELECT address || '|' || comment FROM adlist;")

    if [ -n "$export_data" ]; then
        echo "$export_data" > "$backup_file"
        success "Successfully exported adlists to '$backup_file'."
    else
        warning "No adlists found to export."
    fi

    echo
    echo -e "${YELLOW}Press Enter to return to main menu...${NC}"; read -r
}

# Function to import custom domain rules from a file via direct database access
manage_domains() {
    # Temporarily disable 'exit on error' for this function to prevent the main script
    # from exiting on non-critical, recoverable errors from docker exec.
    set +e

    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                      IMPORT DOMAIN RULES FROM FILE${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}This function reads a 'key: value' formatted file and writes directly to the database.${NC}"
    echo

    local pihole_container="pihole"
    if ! docker ps -f "name=${pihole_container}" --format '{{.Names}}' | grep -q "^${pihole_container}$"; then
        error_exit "Pi-hole container named '$pihole_container' is not running."
    fi

    progress "Ensuring sqlite3 is available in container..."
    if ! docker exec "$pihole_container" which sqlite3 >/dev/null 2>&1; then
        if docker exec "$pihole_container" apk add --no-cache sqlite >/dev/null; then success "sqlite3 installed in container."; else
            error_exit "Failed to install sqlite3 in the container. Cannot proceed."
        fi
    else
        success "sqlite3 is already available in container."
    fi

    local domain_file="domains.txt"
    echo -n -e "${YELLOW}Enter filename with domain rules [press Enter for default: $domain_file]: ${NC}"
    read -r user_file < /dev/tty
    domain_file="${user_file:-${domain_file}}"
    if [[ ! -f "$domain_file" ]]; then error_exit "File not found: '$domain_file'"; fi
    if [[ ! -r "$domain_file" ]]; then error_exit "File not readable: '$domain_file'"; fi

    # Internal helper function to process a single, complete record
    _process_record() {
        local domain="$1" type="$2" groups="$3" comment="$4"
        if [[ -z "$domain" || -z "$type" ]]; then return 0; fi
        ((record_count++))
        echo "────────────────────────────────────────────────────────"
        echo -e "Processing record ${CYAN}#${record_count}${NC}: ${BLUE}${domain}${NC}"
        local type_id
        case "$type" in
            "exact-deny") type_id=0;; "exact-allow") type_id=1;;
            "regex-deny") type_id=2;; "regex-allow") type_id=3;;
            *) warning "  Invalid type: '$type'. Skipping."; return 1;;
        esac
        local escaped_domain="${domain//\'/\'\'}" escaped_comment="${comment//\'/\'\'}"
        local existing_id
        existing_id=$(docker exec "$pihole_container" sqlite3 /etc/pihole/gravity.db "SELECT id FROM domainlist WHERE domain = '${escaped_domain}';")
        
        if [[ -n "$existing_id" ]]; then
            echo -e "  ${YELLOW}○${NC} Domain already exists. Checking groups."
            ((skipped_count++))
        else
            docker exec "$pihole_container" sqlite3 /etc/pihole/gravity.db "INSERT INTO domainlist (type, domain, comment, enabled) VALUES (${type_id}, '${escaped_domain}', '${escaped_comment}', 1);"
            echo -e "  ${GREEN}✓${NC} Added domain to database."
            ((added_count++))
        fi
        local domain_id
        domain_id=$(docker exec "$pihole_container" sqlite3 /etc/pihole/gravity.db "SELECT id FROM domainlist WHERE domain = '${escaped_domain}';")
        if [[ -z "$domain_id" ]]; then warning "  Could not retrieve Domain ID. Skipping group assignment."; return 1; fi
        if [[ -n "$groups" ]]; then
            echo -e "  ${BLUE}➔${NC} Assigning to groups: ${groups}"
            IFS=',' read -ra group_array <<< "$groups"
            for group_name in "${group_array[@]}"; do
                group_name="${group_name#"${group_name%%[![:space:]]*}"}"; group_name="${group_name%"${group_name##*[![:space:]]}"}"
                if [[ -z "$group_name" ]]; then continue; fi
                local group_id
                group_id=$(docker exec "$pihole_container" sqlite3 /etc/pihole/gravity.db "SELECT id FROM \"group\" WHERE name = '${group_name}';")
                if [[ -z "$group_id" ]]; then warning "    Group '$group_name' not found. Skipping."; continue; fi
                local existing_assignment
                existing_assignment=$(docker exec "$pihole_container" sqlite3 /etc/pihole/gravity.db "SELECT domainlist_id FROM domainlist_by_group WHERE domainlist_id = ${domain_id} AND group_id = ${group_id};")
                if [[ -n "$existing_assignment" ]]; then echo "    ○ Already in group '$group_name'."; else
                    docker exec "$pihole_container" sqlite3 /etc/pihole/gravity.db "INSERT INTO domainlist_by_group (domainlist_id, group_id) VALUES (${domain_id}, ${group_id});"
                    echo -e "    ${GREEN}✓${NC} Assigned to group '$group_name'."
                fi
            done
        fi
        return 0
    }

    local added_count=0 skipped_count=0 record_count=0
    local current_domain="" current_type="" current_groups="" current_comment=""
    progress "Starting to process file: $domain_file"
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
        if [[ -z "$line" || ${line:0:1} == "#" ]]; then
            _process_record "$current_domain" "$current_type" "$current_groups" "$current_comment"
            current_domain="" current_type="" current_groups="" current_comment=""
            continue
        fi
        key_raw="${line%%:*}"; value_raw="${line#*:}"; key="${key_raw#"${key_raw%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
        value="${value_raw#"${value_raw%%[![:space:]]*}"}"; value="${value%"${value##*[![:space:]]}"}"
        case "$key" in
            "domain")  current_domain="$value" ;; "type")    current_type="$value" ;;
            "groups")  current_groups="$value" ;; "comment") current_comment="$value" ;;
        esac
    done < "$domain_file"
    _process_record "$current_domain" "$current_type" "$current_groups" "$current_comment"

    echo
    echo "────────────────────────────────────────────────────────"
    echo -e "${GREEN}Domain Import Summary:${NC}"
    echo -e "  ${GREEN}✓ Added:${NC}   $added_count new domains"
    echo -e "  ${YELLOW}○ Skipped:${NC} $skipped_count existing domains"
    echo -e "  ${BLUE}📄 Total:${NC}   $record_count records found in file"
    echo "────────────────────────────────────────────────────────"

    if [[ "$added_count" -gt 0 ]]; then
        progress "Applying changes to Pi-hole..."
        if docker exec "$pihole_container" pihole restartdns >/dev/null 2>&1; then
            success "Pi-hole's DNS resolver has been restarted."
        else
            warning "Could not restart Pi-hole DNS. Please run 'pihole restartdns' manually."
        fi
    else
        success "No new domains were added, no restart needed."
    fi

    # Restore the script's original error handling setting before exiting the function
    set -e
    
    echo
    echo -e "${YELLOW}Press Enter to return to main menu...${NC}"
    read -r
}

#
# Function to launch containers and run all setup steps
#

# Function to set a custom NTP server
set_ntp_server() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                          SET CUSTOM NTP SERVER${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"

    local current_ntp
    current_ntp=$(grep 'FTLCONF_ntp_sync_server' "$PROJECT_DIR/docker-compose.yml" 2>/dev/null | cut -d"'" -f2 || echo "Pi-hole Default")
    echo -e "${BLUE}Current NTP Sync Server: ${GREEN}$current_ntp${NC}"
    echo
    echo -e "${YELLOW}Enter new NTP server (e.g., 192.168.0.1), leave blank for Pi-hole default, or type 'disable' to turn off NTP sync:${NC}"
    read -r new_ntp

    sed -i '/FTLCONF_ntp_sync_server/d' "$PROJECT_DIR/docker-compose.yml"
    sed -i '/FTLCONF_ntp_sync_active/d' "$PROJECT_DIR/docker-compose.yml"

    if [[ "$new_ntp" == "disable" ]]; then
        progress "Disabling NTP client sync..."
        sed -i "/environment:/a \ \ \ \ \ \ FTLCONF_ntp_sync_active: 'false'" "$PROJECT_DIR/docker-compose.yml"
    elif [[ -n "$new_ntp" ]]; then
        progress "Setting FTLCONF_ntp_sync_server to '$new_ntp'..."
        sed -i "/environment:/a \ \ \ \ \ \ FTLCONF_ntp_sync_server: '${new_ntp}'" "$PROJECT_DIR/docker-compose.yml"
    else
        progress "Removing custom NTP server setting, will use Pi-hole default."
    fi

    progress "Restarting container to apply changes..."
    if docker compose up -d --force-recreate >/dev/null; then
        success "NTP configuration updated and container restarted."
    else
        error_exit "Failed to apply NTP configuration."
    fi

    echo
    echo -e "${YELLOW}Press Enter to return to main menu...${NC}"
	    read -r
}

launch_containers() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                      STEP 3: Launching Container${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"

    cd "$PROJECT_DIR"
    sudo chown -R "$USER_ID:$GROUP_ID" "$PROJECT_DIR/etc-pihole" 2>/dev/null || true
    sudo chown -R "$USER_ID:$GROUP_ID" "$PROJECT_DIR/etc-dnsmasq.d" 2>/dev/null || true

    progress "Pulling the latest image..."
    docker compose pull

    progress "Starting container..."
    docker compose up -d

    wait_for_healthy_container
    post_install_configuration
    verify_installation
    run_initial_adlist_import
    create_example_files

    success "Installation and verification completed successfully!"
    show_completion
}

# Function to show completion message
show_completion() {
    local host_ip=$(get_host_ip)

    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                              🎉 INSTALLATION COMPLETE! 🎉${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${GREEN}✅ Pi-hole with Unbound DNS is now running and verified!${NC}"
    echo
    echo -e "${BLUE}📋 ACCESS INFORMATION:${NC}"
    echo -e "   🌐 Web Interface: ${GREEN}http://${host_ip}:${WEB_PORT}/admin${NC} or ${GREEN}https://${host_ip}/admin${NC}"
    echo -e "   🔑 Admin Password: ${GREEN}${WEB_PASSWORD}${NC}"
    echo
    echo -e "${BLUE}🔧 DNS CONFIGURATION:${NC}"
    echo -e "   📡 Primary DNS for your network: ${GREEN}${host_ip}${NC}"
    echo
    echo -e "${BLUE}📊 MANAGEMENT COMMANDS (run in '$PROJECT_DIR'):${NC}"
    echo -e "   📈 View Status: ${YELLOW}docker compose ps${NC}"
    echo -e "   📋 View Logs: ${YELLOW}docker compose logs -f pihole${NC}"
    echo
    echo -e "${GREEN}🎯 Your network is now protected!${NC}"
    echo
    echo -e "${YELLOW}Press Enter to return to main menu...${NC}"
    read -r
}

# Function to perform installation
perform_installation() {
    check_prerequisites
    cleanup_existing
    prepare_host
    create_project_files
    launch_containers
}

# Function to handle fresh installation with confirmation
fresh_installation() {
    if [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        echo
        warning "This will completely destroy your existing installation!"
        echo -n -e "${RED}Are you sure? Type 'YES' to confirm: ${NC}"
        read -r confirmation
        if [[ "$confirmation" != "YES" ]]; then
            echo -e "${GREEN}Operation cancelled.${NC}"
            return
        fi
    fi

    set_default_config
    get_user_ids
    show_confirmation
    perform_installation
}

# Function to update container
update_container() {
    echo
    progress "Updating Pi-hole container..."
    cd "$PROJECT_DIR"
    docker compose pull
    docker compose up -d --force-recreate
    success "Container updated successfully!"
    wait_for_healthy_container
    post_install_configuration
    verify_installation
    echo
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Function to fix permissions and config
fix_permissions_and_config() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                  FIXING CONTAINER PERMISSIONS & CONFIGURATION${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"

    if ! docker ps --format "{{.Names}}" | grep -q "^pihole$"; then
        echo -e "${RED}Pi-hole container not running!${NC}"
        echo
        echo -e "${YELLOW}Press Enter to return to main menu...${NC}"
        read -r
        return
    fi

    progress "Setting correct ownership inside container..."
    docker exec pihole chown -R pihole:pihole /etc/pihole/ /etc/dnsmasq.d/ 2>/dev/null || true

    get_user_ids
    progress "Setting correct permissions on host volumes..."
    sudo chown -R "$USER_ID:$GROUP_ID" "$PROJECT_DIR/etc-pihole" "$PROJECT_DIR/etc-dnsmasq.d" 2>/dev/null || true
    
    post_install_configuration
    verify_installation
    
    success "Permissions and configuration checks completed!"

    echo
    echo -e "${YELLOW}Press Enter to return to main menu...${NC}"
    read -r
}

# Function to setup automatic permission fixer
setup_permission_cron() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                        SETUP AUTOMATIC PERMISSION FIXER${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"

    local cron_command="cd $PROJECT_DIR && docker exec pihole chown -R pihole:pihole /etc/pihole/ /etc/dnsmasq.d/ > /dev/null 2>&1"
    local cron_job="0 * * * * ${cron_command}"

    progress "Installing hourly cron job to fix container permissions..."
    local existing_cron=$(crontab -l 2>/dev/null || true)
    if ! echo "$existing_cron" | grep -qF "${cron_command}"; then
        (echo "$existing_cron"; echo "${cron_job}") | crontab -
        success "Automated permission fix cron job installed!"
    else
        success "Permission fix cron job already exists."
    fi

    echo
    echo -e "${YELLOW}Press Enter to return to main menu...${NC}"
    read -r
}

# Function to test DNSSEC
test_dnssec() {
    verify_installation
    echo
    echo -e "${YELLOW}Press Enter to return to main menu...${NC}"
    read -r
}

# Function to uninstall Pi-hole
uninstall_pihole() {
    echo
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                              UNINSTALL PI-HOLE${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"

    warning "This will completely remove Pi-hole and all its data!"
    echo -n -e "${RED}Are you sure you want to uninstall? Type 'YES' to confirm: ${NC}"
    read -r confirmation

    if [[ "$confirmation" != "YES" ]]; then
        echo -e "${GREEN}Uninstall cancelled.${NC}"
        return
    fi

    if [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        cd "$PROJECT_DIR"
        progress "Stopping and removing containers and volumes..."
        docker compose down -v
        progress "Removing data directories..."
        sudo rm -rf "$PROJECT_DIR/etc-pihole" "$PROJECT_DIR/etc-dnsmasq.d"
        progress "Removing configuration files..."
        rm -f "$PROJECT_DIR/docker-compose.yml" "$PROJECT_DIR/install.log" "$PROJECT_DIR/.env" "$PROJECT_DIR/adlists.txt" "$PROJECT_DIR/adlists-example.txt" "$PROJECT_DIR/domains-example.txt" "$PROJECT_DIR/domains.txt"
        if [[ -f /etc/systemd/resolved.conf.backup ]]; then
            progress "Restoring systemd-resolved configuration..."
            sudo cp /etc/systemd/resolved.conf.backup /etc/systemd/resolved.conf
            sudo systemctl restart systemd-resolved
            sudo rm -f /etc/systemd/resolved.conf.backup
        fi
        success "Pi-hole has been completely uninstalled."
    else
        warning "No Pi-hole installation found in current directory."
    fi

    echo
    echo -e "${YELLOW}Press Enter to exit...${NC}"
    read -r
    exit 0
}

# Main function
main() {
    while true; do
        show_main_menu

        if [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
            # Management menu
            echo -n -e "${YELLOW}Enter your choice [1-16]: ${NC}"
            read -r choice

                       # This is the corrected 'case' block for the main function
            case $choice in
                1) fresh_installation ;;
                2) update_container ;;
                3) show_status ;;
                4)
                    set_default_config
                    get_user_ids
                    show_confirmation
                    perform_installation
                    ;;
                5) fix_permissions_and_config ;;
                6) setup_permission_cron ;;
                7) change_password ;;
                8) import_adlists_from_file ;;
                9) manage_domains ;;
                10) set_ntp_server ;;
                11) export_domains ;;
                12) export_adlists ;;
                13) test_dnssec ;;
                14) view_logs ;;
                15) uninstall_pihole ;;
                16)
                    echo -e "${GREEN}Goodbye!${NC}"
                    exit 0
                    ;;
                *)
                    echo -e "${RED}Invalid choice. Please enter 1-16.${NC}"
                    sleep 2
                    ;;
            esac		
        else
            # Installation menu
            echo -n -e "${YELLOW}Enter your choice [1-3]: ${NC}"
            read -r choice

            case $choice in
                1)
                    set_default_config
                    get_user_ids
                    show_confirmation
                    perform_installation
                    ;;
                2)
                    get_custom_config
                    get_user_ids
                    show_confirmation
                    perform_installation
                    ;;
                3)
                    echo -e "${GREEN}Goodbye!${NC}"
                    exit 0
                    ;;
                *)
                    echo -e "${RED}Invalid choice. Please enter 1-3.${NC}"
                    sleep 2
                    ;;
            esac
        fi
    done
}

# Run main function
main "$@"
