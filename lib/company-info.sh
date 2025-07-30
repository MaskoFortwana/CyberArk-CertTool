#!/bin/bash

# Company Information Collection Module
# Handles collection and validation of Distinguished Name (DN) components

# Collect company information for certificate DN
collect_company_info() {
    echo -e "${CYAN}=== Company Information Collection ===${NC}"
    echo "This information will be used in the Distinguished Name (DN) of all certificates."
    echo ""
    
    # Country (C)
    echo -e "${BLUE}Country Code (C):${NC}"
    echo "This is the 2-letter ISO country code where your organization is located."
    echo "Examples: US (United States), GB (United Kingdom), DE (Germany), CA (Canada)"
    local country=$(get_input "Enter country code" "country" "US")
    
    # State/Province (ST)
    echo ""
    echo -e "${BLUE}State/Province (ST):${NC}"
    echo "The full name of the state or province where your organization is located."
    echo "Examples: California, New York, Ontario, Bavaria"
    local state=$(get_input "Enter state/province name" "text" "")
    
    # City/Locality (L)
    echo ""
    echo -e "${BLUE}City/Locality (L):${NC}"
    echo "The city where your organization is located."
    echo "Examples: San Francisco, New York, Toronto, Munich"
    local city=$(get_input "Enter city/locality name" "text" "")
    
    # Organization (O)
    echo ""
    echo -e "${BLUE}Organization (O):${NC}"
    echo "The legal name of your organization/company."
    echo "Examples: ACME Corporation, Example Bank Ltd, MyCompany Inc"
    local organization=$(get_input "Enter organization name" "text" "")
    
    # Organizational Unit (OU)
    echo ""
    echo -e "${BLUE}Organizational Unit (OU):${NC}"
    echo "The department or division within your organization."
    echo "Examples: IT Department, Information Security, Infrastructure"
    local org_unit=$(get_input "Enter organizational unit" "text" "IT")
    
    # Store company information globally
    COMPANY_INFO=(
        "C=$country"
        "ST=$state"
        "L=$city"
        "O=$organization"
        "OU=$org_unit"
    )
    
    # Display collected information for confirmation
    echo ""
    echo -e "${CYAN}=== Collected Company Information ===${NC}"
    for info in "${COMPANY_INFO[@]}"; do
        echo "  $info"
    done
    echo ""
    
    while true; do
        read -p "Is this information correct? (y/n): " confirm
        case $confirm in
            [Yy]*)
                log_success "Company information saved successfully"
                return 0
                ;;
            [Nn]*)
                log_info "Re-collecting company information..."
                collect_company_info
                return 0
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
            echo "${COMPANY_INFO[0]}"
        elif [[ "$line" =~ ^ST[[:space:]]*= ]]; then
            echo "${COMPANY_INFO[1]}"
        elif [[ "$line" =~ ^L[[:space:]]*= ]]; then
            echo "${COMPANY_INFO[2]}"
        elif [[ "$line" =~ ^O[[:space:]]*= ]]; then
            echo "${COMPANY_INFO[3]}"
        elif [[ "$line" =~ ^OU[[:space:]]*= ]]; then
            echo "${COMPANY_INFO[4]}"
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
    local config_files=("pvwa-cert.cnf" "psm-cert.cnf" "htmlgw-cert.cnf" "pta-cert.cnf")
    
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
            "country")
                if [[ "$input" =~ ^[A-Z]{2}$ ]]; then
                    echo "$input"
                    return 0
                else
                    log_error "Invalid country code. Please enter a 2-letter country code (e.g., US, GB, DE)."
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