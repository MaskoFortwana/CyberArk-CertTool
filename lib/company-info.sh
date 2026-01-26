#!/bin/bash

# Company Information Collection Module
# Handles collection and validation of Distinguished Name (DN) components

# Global variable for load balancer FQDN from organization file
LOAD_BALANCER_FQDN=""

# Create template organization.txt file
create_organization_template() {
    local org_file="$1"
    
    cat > "$org_file" << 'EOF'
# Organization Information for Certificate Generation
# This file contains the Distinguished Name (DN) components for SSL certificates.
# Fill in the values below. Empty fields will be ignored.
# Do not modify the field names in square brackets.

[Country] = US
[State/Province/Country] = California
[Locality] = San Francisco
[Organisation] = ACME Corporation
[Organisational Unit] = IT Department
[Email Address] = certificates@example.com
[Load-Balancer] = lb.example.com

# Field Descriptions:
# [Country]                  - 2-letter ISO country code (e.g., US, GB, DE)
# [State/Province/Country]   - Full name of state or province
# [Locality]                 - City name
# [Organisation]             - Legal name of your organization
# [Organisational Unit]      - Department or division name
# [Email Address]            - Contact email for certificate correspondence
# [Load-Balancer]            - Load balancer FQDN (used for multi-server setups)
EOF
    
    chmod 644 "$org_file"
}

# Parse organization.txt file
parse_organization_file() {
    local org_file="$1"
    local country=""
    local state=""
    local city=""
    local organization=""
    local org_unit=""
    local email=""
    local lb_fqdn=""
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        
        # Parse key-value pairs
        if [[ "$line" =~ ^\[Country\][[:space:]]*=[[:space:]]*(.*)$ ]]; then
            country="${BASH_REMATCH[1]}"
            country="${country## }"
            country="${country%% }"
        elif [[ "$line" =~ ^\[State/Province/Country\][[:space:]]*=[[:space:]]*(.*)$ ]]; then
            state="${BASH_REMATCH[1]}"
            state="${state## }"
            state="${state%% }"
        elif [[ "$line" =~ ^\[Locality\][[:space:]]*=[[:space:]]*(.*)$ ]]; then
            city="${BASH_REMATCH[1]}"
            city="${city## }"
            city="${city%% }"
        elif [[ "$line" =~ ^\[Organisation\][[:space:]]*=[[:space:]]*(.*)$ ]]; then
            organization="${BASH_REMATCH[1]}"
            organization="${organization## }"
            organization="${organization%% }"
        elif [[ "$line" =~ ^\[Organisational[[:space:]]Unit\][[:space:]]*=[[:space:]]*(.*)$ ]]; then
            org_unit="${BASH_REMATCH[1]}"
            org_unit="${org_unit## }"
            org_unit="${org_unit%% }"
        elif [[ "$line" =~ ^\[Email[[:space:]]Address\][[:space:]]*=[[:space:]]*(.*)$ ]]; then
            email="${BASH_REMATCH[1]}"
            email="${email## }"
            email="${email%% }"
        elif [[ "$line" =~ ^\[Load-Balancer\][[:space:]]*=[[:space:]]*(.*)$ ]]; then
            lb_fqdn="${BASH_REMATCH[1]}"
            lb_fqdn="${lb_fqdn## }"
            lb_fqdn="${lb_fqdn%% }"
        fi
    done < "$org_file"
    
    # Validate country code (required)
    if [[ -z "$country" ]]; then
        log_error "Country code is required in organization.txt"
        return 1
    fi
    
    if [[ ! "$country" =~ ^[A-Z]{2}$ ]]; then
        log_error "Invalid country code in organization.txt. Must be 2-letter code (e.g., US, GB)"
        return 1
    fi
    
    # Store company information globally
    COMPANY_INFO=(
        "C=$country"
        "ST=$state"
        "L=$city"
        "O=$organization"
        "OU=$org_unit"
        "emailAddress=$email"
    )
    
    # Store load balancer FQDN globally
    LOAD_BALANCER_FQDN="$lb_fqdn"
    
    return 0
}

# Collect company information from organization.txt file
collect_company_info() {
    local org_file="$OUTPUT_DIR/organization.txt"
    
    echo -e "${CYAN}=== Company Information Collection ===${NC}"
    echo "Looking for organization information file: $org_file"
    echo ""
    
    # Check if organization.txt exists
    if [[ ! -f "$org_file" ]]; then
        log_warning "Organization file not found: $org_file"
        echo ""
        log_info "Creating template organization.txt file..."
        
        create_organization_template "$org_file"
        
        log_success "Template created: $org_file"
        echo ""
        echo -e "${YELLOW}ACTION REQUIRED:${NC}"
        echo "1. Edit the file: $org_file"
        echo "2. Fill in your organization information"
        echo "3. Save the file and re-run this script"
        echo ""
        echo "The template contains example values that you should replace with your actual information."
        echo ""
        
        return 1
    fi
    
    # Parse the organization file
    log_info "Reading organization information from: $org_file"
    
    if ! parse_organization_file "$org_file"; then
        log_error "Failed to parse organization file"
        return 1
    fi
    
    # Display parsed information for confirmation
    echo ""
    echo -e "${CYAN}=== Organization Information ===${NC}"
    for info in "${COMPANY_INFO[@]}"; do
        # Only display non-empty fields
        local key="${info%%=*}"
        local value="${info#*=}"
        if [[ -n "$value" ]]; then
            echo "  $info"
        fi
    done
    
    if [[ -n "$LOAD_BALANCER_FQDN" ]]; then
        echo "  Load-Balancer=$LOAD_BALANCER_FQDN"
    fi
    echo ""
    
    # Ask for confirmation
    while true; do
        read -p "Is this information correct? (y/n): " confirm
        case $confirm in
            [Yy]*)
                log_success "Company information confirmed"
                return 0
                ;;
            [Nn]*)
                echo ""
                log_info "Please edit the file: $org_file"
                log_info "After making changes, re-run this script"
                return 1
                ;;
            *)
                log_error "Please answer y or n"
                ;;
        esac
    done
}

# Update configuration file with company information
update_config_file() {
    local config_file="$1"
    local temp_file=$(mktemp)
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Create a backup
    cp "$config_file" "${config_file}.backup"
    
    # Read the file and update DN fields
    while IFS= read -r line; do
        if [[ "$line" =~ ^C[[:space:]]*= ]]; then
            # Country is required (validated elsewhere); always write
            echo "${COMPANY_INFO[0]}"
        elif [[ "$line" =~ ^ST[[:space:]]*= ]]; then
            # Only write if non-empty
            if [[ -n "${COMPANY_INFO[1]#ST=}" ]]; then echo "${COMPANY_INFO[1]}"; fi
        elif [[ "$line" =~ ^L[[:space:]]*= ]]; then
            if [[ -n "${COMPANY_INFO[2]#L=}" ]]; then echo "${COMPANY_INFO[2]}"; fi
        elif [[ "$line" =~ ^O[[:space:]]*= ]]; then
            if [[ -n "${COMPANY_INFO[3]#O=}" ]]; then echo "${COMPANY_INFO[3]}"; fi
        elif [[ "$line" =~ ^OU[[:space:]]*= ]]; then
            if [[ -n "${COMPANY_INFO[4]#OU=}" ]]; then echo "${COMPANY_INFO[4]}"; fi
        elif [[ "$line" =~ ^emailAddress[[:space:]]*= ]]; then
            if [[ -n "${COMPANY_INFO[5]#emailAddress=}" ]]; then echo "${COMPANY_INFO[5]}"; fi
        else
            echo "$line"
        fi
    done < "$config_file" > "$temp_file"
    
    # Replace the original file
    mv "$temp_file" "$config_file"
    log_info "Updated configuration file: $config_file"
}

# Update all configuration files with company information
update_all_config_files() {
    local config_files=("pvwa-cert.cnf" "psm-cert.cnf" "htmlgw-cert.cnf" "pta-cert.cnf" "vault-cert.cnf")
    
    log_info "Updating all configuration files with company information..."
    
    for config in "${config_files[@]}"; do
        local config_path="$SCRIPT_DIR/$config"
        if [[ -f "$config_path" ]]; then
            update_config_file "$config_path"
        else
            log_warning "Configuration file not found: $config_path"
        fi
    done
    
    log_success "All configuration files updated with company information"
}

# Display current company information
show_company_info() {
    if [[ ${#COMPANY_INFO[@]} -eq 0 ]]; then
        log_warning "No company information configured"
        return 1
    fi
    
    echo -e "${CYAN}=== Current Company Information ===${NC}"
    for info in "${COMPANY_INFO[@]}"; do
        echo "  $info"
    done
    echo ""
}

# Validate text input (non-empty, reasonable length)
validate_text_input() {
    local input="$1"
    local min_length=${2:-1}
    local max_length=${3:-64}
    
    if [[ ${#input} -lt $min_length ]]; then
        return 1
    fi
    
    if [[ ${#input} -gt $max_length ]]; then
        return 1
    fi
    
    # Check for invalid characters (basic validation)
    if [[ "$input" =~ [^a-zA-Z0-9[:space:].,\'-] ]]; then
        return 1
    fi
    
    return 0
}

# Validate email input (basic format validation)
validate_email_input() {
    local input="$1"
    local max_length=${2:-254}  # RFC 5321 limit
    
    # Check length
    if [[ ${#input} -lt 3 || ${#input} -gt $max_length ]]; then
        return 1
    fi
    
    # Basic email format validation (simplified regex)
    if [[ "$input" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    
    return 1
}

# Validate DNS name or IP address for SAN
validate_san_input() {
    local input="$1"
    
    # Check if it's an IP address (basic validation)
    if [[ "$input" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        # Basic IP validation - check ranges
        local IFS='.'
        local ip_parts=($input)
        for part in "${ip_parts[@]}"; do
            if [[ $part -lt 0 || $part -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    
    # Check if it's a valid DNS name/FQDN
    if [[ "$input" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        # Additional checks for DNS name
        if [[ ${#input} -gt 253 ]]; then  # DNS name length limit
            return 1
        fi
        # Check for valid characters and structure
        if [[ "$input" =~ \.\.|\.$ ]]; then  # No consecutive dots or ending dot
            return 1
        fi
        return 0
    fi
    
    return 1
}

# Collect additional SAN entries from user
# Usage: collect_additional_sans component_name
# Populates the global COMPONENT_ADDITIONAL_SANS array
collect_additional_sans() {
    local component_name="${1:-component}"
    
    echo -e "${CYAN}=== Additional Subject Alternative Names (SANs) for $component_name ===${NC}"
    echo "You can specify additional DNS names or IP addresses to be included"
    echo "in the $component_name certificate's Subject Alternative Names section."
    echo ""
    echo "This is useful for:"
    echo "  • Additional hostnames that point to the same server"
    echo "  • IP addresses that clients use to connect"
    echo "  • Alternative domain names"
    echo ""
    echo "Examples:"
    echo "  • DNS names: server2.company.com, app.internal.com"
    echo "  • IP addresses: 192.168.1.100, 10.0.0.50"
    echo ""
    
    COMPONENT_ADDITIONAL_SANS=()
    
    while true; do
        read -p "Do you want to add additional SAN entries for $component_name? (y/n): " add_sans
        case $add_sans in
            [Yy]*)
                break
                ;;
            [Nn]*)
                log_info "No additional SANs will be added for $component_name"
                return 0
                ;;
            *)
                log_error "Please answer y or n"
                ;;
        esac
    done
    
    while true; do
        echo ""
        echo -e "${BLUE}Enter additional SAN for $component_name (DNS name or IP address):${NC}"
        local san_input
        read -p "SAN entry: " san_input
        
        if [[ -z "$san_input" ]]; then
            log_error "SAN entry cannot be empty"
            continue
        fi
        
        if validate_san_input "$san_input"; then
            COMPONENT_ADDITIONAL_SANS+=("$san_input")
            log_success "Added SAN: $san_input"
            
            # Ask if user wants to add more
            local add_more
            while true; do
                read -p "Add another SAN entry for $component_name? (y/n): " add_more
                case $add_more in
                    [Yy]*)
                        break  # Continue with outer loop to add another SAN
                        ;;
                    [Nn]*)
                        # Exit the SAN collection loop
                        break 2
                        ;;
                    *)
                        log_error "Please answer y or n"
                        ;;
                esac
            done
        else
            log_error "Invalid SAN entry. Please enter a valid DNS name or IP address."
            echo "Examples: server.company.com, 192.168.1.100"
        fi
    done
    
    # Display collected SANs for confirmation
    if [[ ${#COMPONENT_ADDITIONAL_SANS[@]} -gt 0 ]]; then
        echo ""
        echo -e "${CYAN}=== Additional SANs Collected for $component_name ===${NC}"
        for ((i=0; i<${#COMPONENT_ADDITIONAL_SANS[@]}; i++)); do
            echo "  $((i+1)). ${COMPONENT_ADDITIONAL_SANS[i]}"
        done
        echo ""
        
        while true; do
            read -p "Are these additional SANs for $component_name correct? (y/n): " confirm
            case $confirm in
                [Yy]*)
                    log_success "Additional SANs saved successfully for $component_name"
                    return 0
                    ;;
                [Nn]*)
                    log_info "Re-collecting additional SANs for $component_name..."
                    collect_additional_sans "$component_name"
                    return 0
                    ;;
                *)
                    log_error "Please answer y or n"
                    ;;
            esac
        done
    fi
}

# Enhanced get_input function for text validation
get_input() {
    local prompt="$1"
    local type="$2"
    local default="$3"
    local input=""
    
    while true; do
        if [[ -n "$default" ]]; then
            read -p "$prompt [$default]: " input
            input="${input:-$default}"
        else
            read -p "$prompt: " input
        fi
        
        case "$type" in
            "text")
                if validate_text_input "$input"; then
                    echo "$input"
                    return 0
                else
                    log_error "Invalid input. Please enter 1-64 characters using only letters, numbers, spaces, and basic punctuation."
                fi
                ;;
            "text_optional")
                # Allow empty; if not empty, validate
                if [[ -z "$input" ]] || validate_text_input "$input"; then
                    echo "$input"
                    return 0
                else
                    log_error "Invalid input. Please use 1-64 allowed characters or leave blank."
                fi
                ;;
            "country")
                if [[ "$input" =~ ^[A-Z]{2}$ ]]; then
                    echo "$input"
                    return 0
                else
                    log_error "Invalid country code. Please enter a 2-letter country code (e.g., US, GB, DE)."
                fi
                ;;
            "email")
                if validate_email_input "$input"; then
                    echo "$input"
                    return 0
                else
                    log_error "Invalid email format. Please enter a valid email address (e.g., user@company.com)."
                fi
                ;;
            "email_optional")
                if [[ -z "$input" ]] || validate_email_input "$input"; then
                    echo "$input"
                    return 0
                else
                    log_error "Invalid email format. Enter a valid address or leave blank."
                fi
                ;;
            "fqdn_optional")
                # Allow empty; if not empty, validate as FQDN
                if [[ -z "$input" ]]; then
                    echo ""
                    return 0
                elif validate_san_input "$input"; then
                    echo "$input"
                    return 0
                else
                    log_error "Invalid FQDN format. Enter a valid domain name or leave blank."
                fi
                ;;
            *)
                # Fall back to original validation from main script
                if validate_input "$input" "$type"; then
                    echo "$input"
                    return 0
                else
                    log_error "Invalid input. Please try again."
                fi
                ;;
        esac
    done
}
