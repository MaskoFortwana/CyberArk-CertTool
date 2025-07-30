#!/bin/bash

# Certificate Conversion Module
# Handles conversion of signed certificates to required formats for each CyberArk component

# Main certificate conversion function
convert_certificates() {
    echo -e "${CYAN}=== Certificate Conversion ===${NC}"
    echo "Convert signed certificates to required formats for CyberArk components"
    echo ""
    
    if [[ -z "$OUTPUT_DIR" ]]; then
        log_error "Output directory not configured. Please configure global settings first."
        return 1
    fi
    
    # Display available components for conversion
    echo "Available components for conversion:"
    local components=()
    local component_dirs=()
    
    if [[ -d "$OUTPUT_DIR/pvwa" ]]; then
        components+=("PVWA")
        component_dirs+=("$OUTPUT_DIR/pvwa")
    fi
    
    if [[ -d "$OUTPUT_DIR/psm" ]]; then
        components+=("PSM")
        component_dirs+=("$OUTPUT_DIR/psm")
    fi
    
    if [[ -d "$OUTPUT_DIR/htmlgw" ]]; then
        components+=("HTML5GW")
        component_dirs+=("$OUTPUT_DIR/htmlgw")
    fi
    
    if [[ -d "$OUTPUT_DIR/pta" ]]; then
        components+=("PTA")
        component_dirs+=("$OUTPUT_DIR/pta")
    fi
    
    if [[ ${#components[@]} -eq 0 ]]; then
        log_error "No certificate directories found. Generate certificates first."
        return 1
    fi
    
    # Display component menu
    echo ""
    for ((i=0; i<${#components[@]}; i++)); do
        echo "$((i+1)). ${components[i]}"
    done
    echo "$((${#components[@]}+1)). Convert All Components"
    echo "$((${#components[@]}+2)). Back to Main Menu"
    echo ""
    
    while true; do
        read -p "Select component to convert (1-$((${#components[@]}+2))): " choice
        
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [[ "$choice" -le $((${#components[@]}+2)) ]]; then
            if [[ "$choice" -eq $((${#components[@]}+1)) ]]; then
                # Convert all components
                for ((i=0; i<${#components[@]}; i++)); do
                    convert_component_certificates "${components[i]}" "${component_dirs[i]}"
                done
                break
            elif [[ "$choice" -eq $((${#components[@]}+2)) ]]; then
                # Back to main menu
                return 0
            else
                # Convert specific component
                local selected_index=$((choice-1))
                convert_component_certificates "${components[selected_index]}" "${component_dirs[selected_index]}"
                break
            fi
        else
            log_error "Invalid choice. Please select a valid option."
        fi
    done
}

# Convert certificates for a specific component
convert_component_certificates() {
    local component="$1"
    local component_dir="$2"
    
    log_info "Converting certificates for $component..."
    
    case "$component" in
        "PVWA")
            convert_pvwa_certificates "$component_dir"
            ;;
        "PSM")
            convert_psm_certificates "$component_dir"
            ;;
        "HTML5GW")
            convert_htmlgw_certificates "$component_dir"
            ;;
        "PTA")
            convert_pta_certificates "$component_dir"
            ;;
        *)
            log_error "Unknown component: $component"
            return 1
            ;;
    esac
}

# Convert PVWA certificates (unprotected PFX)
convert_pvwa_certificates() {
    local pvwa_dir="$1"
    
    log_info "Converting PVWA certificates to unprotected PFX format..."
    
    # Check for single certificate or multiple certificates
    if [[ -f "$pvwa_dir/pvwa.crt" ]]; then
        # Single certificate
        convert_single_pvwa_cert "$pvwa_dir"
    else
        # Multiple certificates
        for server_dir in "$pvwa_dir"/server*; do
            if [[ -d "$server_dir" ]]; then
                convert_single_pvwa_cert "$server_dir"
            fi
        done
    fi
}

# Convert single PVWA certificate
convert_single_pvwa_cert() {
    local cert_dir="$1"
    local base_name=""
    
    # Determine base name based on directory structure
    if [[ "$cert_dir" == */server* ]]; then
        local server_num=$(basename "$cert_dir" | sed 's/server//')
        base_name="pvwa-server$server_num"
    else
        base_name="pvwa"
    fi
    
    local cert_file="$cert_dir/${base_name}.crt"
    local key_file="$cert_dir/${base_name}.key"
    local ca_file="$cert_dir/ca-chain.crt"
    local pfx_file="$cert_dir/${base_name}.pfx"
    
    # Check required files
    if [[ ! -f "$cert_file" ]]; then
        log_error "Certificate file not found: $cert_file"
        log_error "Please place the signed certificate from your CA in this location"
        return 1
    fi
    
    if [[ ! -f "$key_file" ]]; then
        log_error "Private key file not found: $key_file"
        return 1
    fi
    
    # Create unprotected PFX
    if create_pfx "$cert_file" "$key_file" "$ca_file" "$pfx_file" ""; then
        log_success "PVWA PFX created: $pfx_file"
        
        # Verify the PFX
        if verify_pfx "$pfx_file" ""; then
            log_success "PVWA PFX verification successful"
        fi
    else
        log_error "Failed to create PVWA PFX"
        return 1
    fi
}

# Convert PSM certificates (unprotected PFX)
convert_psm_certificates() {
    local psm_dir="$1"
    
    log_info "Converting PSM certificates to unprotected PFX format..."
    
    # Check for single certificate or multiple certificates
    if [[ -f "$psm_dir/psm.crt" ]]; then
        # Single certificate
        convert_single_psm_cert "$psm_dir"
    else
        # Multiple certificates
        for server_dir in "$psm_dir"/server*; do
            if [[ -d "$server_dir" ]]; then
                convert_single_psm_cert "$server_dir"
            fi
        done
    fi
}

# Convert single PSM certificate
convert_single_psm_cert() {
    local cert_dir="$1"
    local base_name=""
    
    # Determine base name based on directory structure
    if [[ "$cert_dir" == */server* ]]; then
        local server_num=$(basename "$cert_dir" | sed 's/server//')
        base_name="psm-server$server_num"
    else
        base_name="psm"
    fi
    
    local cert_file="$cert_dir/${base_name}.crt"
    local key_file="$cert_dir/${base_name}.key"
    local ca_file="$cert_dir/ca-chain.crt"
    local pfx_file="$cert_dir/${base_name}.pfx"
    
    # Check required files
    if [[ ! -f "$cert_file" ]]; then
        log_error "Certificate file not found: $cert_file"
        log_error "Please place the signed certificate from your CA in this location"
        return 1
    fi
    
    if [[ ! -f "$key_file" ]]; then
        log_error "Private key file not found: $key_file"
        return 1
    fi
    
    # Create unprotected PFX
    if create_pfx "$cert_file" "$key_file" "$ca_file" "$pfx_file" ""; then
        log_success "PSM PFX created: $pfx_file"
        
        # Verify the PFX
        if verify_pfx "$pfx_file" ""; then
            log_success "PSM PFX verification successful"
        fi
    else
        log_error "Failed to create PSM PFX"
        return 1
    fi
}

# Convert HTML5GW certificates (password-protected PFX + separate files)
convert_htmlgw_certificates() {
    local htmlgw_dir="$1"
    
    log_info "Converting HTML5GW certificates to required formats..."
    
    # Check for single certificate or multiple certificates
    if [[ -f "$htmlgw_dir/htmlgw.crt" ]]; then
        # Single certificate
        convert_single_htmlgw_cert "$htmlgw_dir"
    else
        # Multiple certificates
        for server_dir in "$htmlgw_dir"/server*; do
            if [[ -d "$server_dir" ]]; then
                convert_single_htmlgw_cert "$server_dir"
            fi
        done
    fi
}

# Convert single HTML5GW certificate
convert_single_htmlgw_cert() {
    local cert_dir="$1"
    local base_name=""
    
    # Determine base name based on directory structure
    if [[ "$cert_dir" == */server* ]]; then
        local server_num=$(basename "$cert_dir" | sed 's/server//')
        base_name="htmlgw-server$server_num"
    else
        base_name="htmlgw"
    fi
    
    local cert_file="$cert_dir/${base_name}.crt"
    local key_file="$cert_dir/${base_name}.key"
    local ca_file="$cert_dir/ca-chain.crt"
    local pfx_file="$cert_dir/${base_name}.pfx"
    local password_file="$cert_dir/${base_name}-password.txt"
    
    # Check required files
    if [[ ! -f "$cert_file" ]]; then
        log_error "Certificate file not found: $cert_file"
        log_error "Please place the signed certificate from your CA in this location"
        return 1
    fi
    
    if [[ ! -f "$key_file" ]]; then
        log_error "Private key file not found: $key_file"
        return 1
    fi
    
    # Generate random password for PFX
    local pfx_password=$(generate_random_password 24)
    echo "$pfx_password" > "$password_file"
    chmod 600 "$password_file"
    
    # Create password-protected PFX
    if create_pfx "$cert_file" "$key_file" "$ca_file" "$pfx_file" "$pfx_password"; then
        log_success "HTML5GW PFX created: $pfx_file"
        log_success "Password saved to: $password_file"
        
        # Verify the PFX
        if verify_pfx "$pfx_file" "$pfx_password"; then
            log_success "HTML5GW PFX verification successful"
        fi
        
        # Ensure certificate and key are in Base64 format
        ensure_base64_format "$cert_file"
        ensure_base64_format "$key_file"
        if [[ -f "$ca_file" ]]; then
            ensure_base64_format "$ca_file"
        fi
        
        log_success "HTML5GW certificate files prepared in Base64 format"
    else
        log_error "Failed to create HTML5GW PFX"
        return 1
    fi
}

# Convert PTA certificates (separate key/cert files only)
convert_pta_certificates() {
    local pta_dir="$1"
    
    log_info "Converting PTA certificates to Base64 format..."
    
    # Check for single certificate or multiple certificates
    if [[ -f "$pta_dir/pta.crt" ]]; then
        # Single certificate
        convert_single_pta_cert "$pta_dir"
    else
        # Multiple certificates
        for server_dir in "$pta_dir"/server*; do
            if [[ -d "$server_dir" ]]; then
                convert_single_pta_cert "$server_dir"
            fi
        done
    fi
}

# Convert single PTA certificate
convert_single_pta_cert() {
    local cert_dir="$1"
    local base_name=""
    
    # Determine base name based on directory structure
    if [[ "$cert_dir" == */server* ]]; then
        local server_num=$(basename "$cert_dir" | sed 's/server//')
        base_name="pta-server$server_num"
    else
        base_name="pta"
    fi
    
    local cert_file="$cert_dir/${base_name}.crt"
    local key_file="$cert_dir/${base_name}.key"
    local ca_file="$cert_dir/ca-chain.crt"
    
    # Check required files
    if [[ ! -f "$cert_file" ]]; then
        log_error "Certificate file not found: $cert_file"
        log_error "Please place the signed certificate from your CA in this location"
        return 1
    fi
    
    if [[ ! -f "$key_file" ]]; then
        log_error "Private key file not found: $key_file"
        return 1
    fi
    
    # Ensure all files are in Base64 format
    ensure_base64_format "$cert_file"
    ensure_base64_format "$key_file"
    if [[ -f "$ca_file" ]]; then
        ensure_base64_format "$ca_file"
    fi
    
    # Verify certificate and key match
    if verify_key_cert_match "$key_file" "$cert_file"; then
        log_success "PTA certificate files prepared in Base64 format"
    else
        log_error "Certificate and key verification failed"
        return 1
    fi
}

# Ensure file is in Base64 (PEM) format
ensure_base64_format() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    # Check if file is already in PEM format
    if head -1 "$file" | grep -q "^-----BEGIN"; then
        log_info "File already in Base64 format: $file"
        return 0
    fi
    
    # If it's a certificate file, try to convert from DER
    if [[ "$file" == *.crt ]] || [[ "$file" == *.cer ]]; then
        local temp_file=$(mktemp)
        if convert_cert_format "$file" "$temp_file" "DER" "PEM"; then
            mv "$temp_file" "$file"
            log_success "Converted certificate to Base64 format: $file"
            return 0
        fi
        rm -f "$temp_file"
    fi
    
    log_warning "Could not convert file to Base64 format: $file"
    return 1
}

# Verify PFX file
verify_pfx() {
    local pfx_file="$1"
    local password="$2"
    
    if [[ ! -f "$pfx_file" ]]; then
        log_error "PFX file not found: $pfx_file"
        return 1
    fi
    
    local openssl_cmd="openssl pkcs12 -in \"$pfx_file\" -noout"
    
    if [[ -n "$password" ]]; then
        openssl_cmd="$openssl_cmd -passin pass:\"$password\""
    else
        openssl_cmd="$openssl_cmd -passin pass:"
    fi
    
    if eval "$openssl_cmd" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Display conversion summary
show_conversion_summary() {
    local component_dir="$1"
    local component="$2"
    
    echo ""
    echo -e "${CYAN}=== $component Conversion Summary ===${NC}"
    echo "Component Directory: $component_dir"
    echo ""
    
    case "$component" in
        "PVWA"|"PSM")
            echo "Generated Files:"
            find "$component_dir" -name "*.pfx" -type f | while read file; do
                echo "  PFX: $file"
            done
            ;;
        "HTML5GW")
            echo "Generated Files:"
            find "$component_dir" -name "*.pfx" -type f | while read file; do
                echo "  PFX: $file"
            done
            find "$component_dir" -name "*-password.txt" -type f | while read file; do
                echo "  Password: $file"
            done
            ;;
        "PTA")
            echo "Certificate Files (Base64 format):"
            find "$component_dir" -name "*.crt" -type f | while read file; do
                echo "  Certificate: $file"
            done
            find "$component_dir" -name "*.key" -type f | while read file; do
                echo "  Private Key: $file"
            done
            ;;
    esac
    echo ""
}