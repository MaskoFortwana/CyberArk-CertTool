#!/bin/bash

# HTML5GW Certificate Handler Module  
# Handles HTML5GW-specific certificate configuration and generation

# Collect HTML5GW configuration
configure_htmlgw() {
    echo -e "${CYAN}=== HTML5GW Certificate Configuration ===${NC}"
    echo "Configuring certificates for HTML5 Gateway (HTML5GW)"
    echo ""
    
    # Number of HTML5GW servers
    echo -e "${BLUE}HTML5GW Server Configuration:${NC}"
    local num_servers
    while true; do
        read -p "How many HTML5GW servers do you have? (1-10): " num_servers
        if [[ "$num_servers" =~ ^[1-9]$|^10$ ]]; then
            break
        else
            log_error "Please enter a number between 1 and 10"
        fi
    done
    
    # Collect server FQDNs
    local server_fqdns=()
    for ((i=1; i<=num_servers; i++)); do
        echo ""
        local fqdn=$(get_input "Enter FQDN for HTML5GW server $i" "fqdn" "")
        server_fqdns+=("$fqdn")
    done
    
    # Load balancer configuration
    echo ""
    echo -e "${BLUE}Load Balancer Configuration:${NC}"
    local has_loadbalancer="n"
    local lb_fqdn=""
    
    if [[ $num_servers -gt 1 ]]; then
        while true; do
            read -p "Do you have a load balancer for HTML5GW? (y/n): " has_loadbalancer
            case $has_loadbalancer in
                [Yy]*)
                    lb_fqdn=$(get_input "Enter load balancer FQDN" "fqdn" "")
                    break
                    ;;
                [Nn]*)
                    break
                    ;;
                *)
                    log_error "Please answer y or n"
                    ;;
            esac
        done
    fi
    
    # Certificate strategy
    echo ""
    echo -e "${BLUE}Certificate Strategy:${NC}"
    local cert_strategy
    if [[ $num_servers -gt 1 ]]; then
        echo "Choose certificate strategy:"
        echo "1. Single certificate for all HTML5GW servers (with SAN entries)"
        echo "2. Unique certificate for each HTML5GW server"
        
        while true; do
            read -p "Select strategy (1 or 2): " cert_strategy
            if [[ "$cert_strategy" =~ ^[12]$ ]]; then
                break
            else
                log_error "Please select 1 or 2"
            fi
        done
    else
        cert_strategy="1"  # Single server, single certificate
    fi
    
    # Display configuration summary
    echo ""
    echo -e "${CYAN}=== HTML5GW Configuration Summary ===${NC}"
    echo "Number of servers: $num_servers"
    echo "Server FQDNs:"
    for ((i=0; i<${#server_fqdns[@]}; i++)); do
        echo "  Server $((i+1)): ${server_fqdns[i]}"
    done
    
    if [[ "$has_loadbalancer" == [Yy]* ]]; then
        echo "Load balancer: $lb_fqdn"
    else
        echo "Load balancer: Not configured"
    fi
    
    if [[ "$cert_strategy" == "1" ]]; then
        echo "Certificate strategy: Single certificate for all servers"
    else
        echo "Certificate strategy: Unique certificate per server"
    fi
    echo ""
    
    # Confirm configuration
    while true; do
        read -p "Is this configuration correct? (y/n): " confirm
        case $confirm in
            [Yy]*)
                break
                ;;
            [Nn]*)
                log_info "Re-configuring HTML5GW..."
                configure_htmlgw
                return $?
                ;;
            *)
                log_error "Please answer y or n"
                ;;
        esac
    done
    
    # Collect additional SANs for HTML5GW
    echo ""
    collect_additional_sans "HTML5GW"
    
    # Generate certificates based on strategy
    if [[ "$cert_strategy" == "1" ]]; then
        generate_htmlgw_single_cert "$lb_fqdn" "${server_fqdns[@]}"
    else
        generate_htmlgw_multiple_certs "${server_fqdns[@]}"
    fi
}

# Generate single certificate for all HTML5GW servers
generate_htmlgw_single_cert() {
    local lb_fqdn="$1"
    shift
    local server_fqdns=("$@")
    
    log_info "Generating single certificate for all HTML5GW servers..."
    
    # Create HTML5GW output directory
    local htmlgw_dir="$OUTPUT_DIR/htmlgw"
    mkdir -p "$htmlgw_dir"
    
    # Copy and modify configuration file
    local config_file="$htmlgw_dir/htmlgw-cert.cnf"
    cp "$SCRIPT_DIR/htmlgw-cert.cnf" "$config_file"
    
    # Update company information in config
    update_config_file "$config_file"
    
    # Configure CN and SAN
    local cn_value=""
    local san_entries=()
    
    if [[ -n "$lb_fqdn" ]]; then
        cn_value="$lb_fqdn"
        san_entries+=("DNS.1 = $lb_fqdn")
        
        # Add server FQDNs to SAN
        for ((i=0; i<${#server_fqdns[@]}; i++)); do
            san_entries+=("DNS.$((i+2)) = ${server_fqdns[i]}")
        done
    else
        # No load balancer, use first server as CN
        cn_value="${server_fqdns[0]}"
        
        # Add all servers to SAN
        for ((i=0; i<${#server_fqdns[@]}; i++)); do
            san_entries+=("DNS.$((i+1)) = ${server_fqdns[i]}")
        done
    fi
    
    # Update CN in config file
    sed_inplace "s/^CN = .*/CN = $cn_value/" "$config_file"
    
    # Merge additional SANs with existing SANs
    merge_additional_sans san_entries
    
    # Update SAN entries in config file
    update_san_entries "$config_file" "${san_entries[@]}"
    
    # Update key length in config file
    sed_inplace "s/^default_bits = .*/default_bits = $KEY_LENGTH/" "$config_file"
    
    # Generate private key and CSR
    local key_file="$htmlgw_dir/htmlgw.key"
    local csr_file="$htmlgw_dir/htmlgw.csr"
    
    if generate_private_key "$key_file" "$KEY_LENGTH" && generate_csr "$key_file" "$config_file" "$csr_file"; then
        log_success "HTML5GW certificate files generated successfully"
        
        # Display file locations
        echo ""
        echo -e "${CYAN}=== Generated HTML5GW Files ===${NC}"
        echo "Private Key: $key_file"
        echo "CSR: $csr_file"
        echo "Configuration: $config_file"
        echo ""
        
        # Verify CSR
        verify_csr "$csr_file"
        
        # Create instructions file
        create_htmlgw_instructions "$htmlgw_dir" "single"
        
        return 0
    else
        log_error "Failed to generate HTML5GW certificate files"
        return 1
    fi
}

# Generate unique certificates for each HTML5GW server
generate_htmlgw_multiple_certs() {
    local server_fqdns=("$@")
    
    log_info "Generating unique certificates for each HTML5GW server..."
    
    # Create HTML5GW output directory
    local htmlgw_dir="$OUTPUT_DIR/htmlgw"
    mkdir -p "$htmlgw_dir"
    
    for ((i=0; i<${#server_fqdns[@]}; i++)); do
        local server_fqdn="${server_fqdns[i]}"
        local server_num=$((i+1))
        local server_dir="$htmlgw_dir/server$server_num"
        
        log_info "Generating certificate for HTML5GW server $server_num: $server_fqdn"
        
        # Create server-specific directory
        mkdir -p "$server_dir"
        
        # Copy and modify configuration file
        local config_file="$server_dir/htmlgw-server$server_num.cnf"
        cp "$SCRIPT_DIR/htmlgw-cert.cnf" "$config_file"
        
        # Update company information in config
        update_config_file "$config_file"
        
        # Configure CN and SAN for this server
        sed_inplace "s/^CN = .*/CN = $server_fqdn/" "$config_file"
        
        # Update SAN entry
        local san_entries=("DNS.1 = $server_fqdn")
        
        # Merge additional SANs with existing SANs
        merge_additional_sans san_entries
        
        update_san_entries "$config_file" "${san_entries[@]}"
        
        # Update key length in config file
        sed_inplace "s/^default_bits = .*/default_bits = $KEY_LENGTH/" "$config_file"
        
        # Generate private key and CSR
        local key_file="$server_dir/htmlgw-server$server_num.key"
        local csr_file="$server_dir/htmlgw-server$server_num.csr"
        
        if generate_private_key "$key_file" "$KEY_LENGTH" && generate_csr "$key_file" "$config_file" "$csr_file"; then
            log_success "Certificate files generated for HTML5GW server $server_num"
        else
            log_error "Failed to generate certificate files for HTML5GW server $server_num"
            return 1
        fi
    done
    
    # Display summary
    echo ""
    echo -e "${CYAN}=== Generated HTML5GW Files Summary ===${NC}"
    for ((i=0; i<${#server_fqdns[@]}; i++)); do
        local server_num=$((i+1))
        local server_dir="$htmlgw_dir/server$server_num"
        echo "Server $server_num (${server_fqdns[i]}):"
        echo "  Private Key: $server_dir/htmlgw-server$server_num.key"
        echo "  CSR: $server_dir/htmlgw-server$server_num.csr"
        echo "  Configuration: $server_dir/htmlgw-server$server_num.cnf"
    done
    echo ""
    
    # Create instructions file
    create_htmlgw_instructions "$htmlgw_dir" "multiple" "${#server_fqdns[@]}"
    
    return 0
}

# Create HTML5GW instructions file
create_htmlgw_instructions() {
    local htmlgw_dir="$1"
    local cert_type="$2"
    local num_servers="${3:-0}"
    
    local instructions_file="$htmlgw_dir/HTML5GW-INSTRUCTIONS.txt"
    
    cat > "$instructions_file" << EOF
HTML5GW Certificate Instructions
===============================

Generated on: $(date)
Certificate Type: $cert_type certificate(s)

1. SUBMIT CSR(s) TO YOUR CORPORATE CA
   =====================================

EOF

    if [[ "$cert_type" == "single" ]]; then
        cat >> "$instructions_file" << EOF
   Submit the following CSR to your Certificate Authority:
   - $htmlgw_dir/htmlgw.csr

2. DOWNLOAD SIGNED CERTIFICATE
   ============================
   
   After your CA signs the CSR, download the signed certificate and save it as:
   - $htmlgw_dir/htmlgw.crt
   
   Also download your CA certificate chain and save it as:
   - $htmlgw_dir/ca-chain.crt

3. CONVERT TO REQUIRED FORMATS
   ============================
   
   After placing the signed certificate files, run the conversion tool:
   $ ./cyberark-cert-tool.sh
   
   Select option 3 (Convert Signed Certificates) and choose HTML5GW.
   
   This will generate:
   - $htmlgw_dir/htmlgw.pfx (password-protected PFX file)
   - $htmlgw_dir/htmlgw.key (private key in Base64 format)
   - $htmlgw_dir/htmlgw.crt (certificate in Base64 format)
   - $htmlgw_dir/ca-chain.crt (CA chain in Base64 format)
   - $htmlgw_dir/htmlgw-password.txt (randomly generated PFX password)

EOF
    else
        cat >> "$instructions_file" << EOF
   Submit the following CSRs to your Certificate Authority:
EOF
        for ((i=1; i<=num_servers; i++)); do
            cat >> "$instructions_file" << EOF
   - $htmlgw_dir/server$i/htmlgw-server$i.csr
EOF
        done
        
        cat >> "$instructions_file" << EOF

2. DOWNLOAD SIGNED CERTIFICATES
   =============================
   
   After your CA signs the CSRs, download the signed certificates and save them as:
EOF
        for ((i=1; i<=num_servers; i++)); do
            cat >> "$instructions_file" << EOF
   - $htmlgw_dir/server$i/htmlgw-server$i.crt
EOF
        done
        
        cat >> "$instructions_file" << EOF
   
   Also download your CA certificate chain and save it in each server directory as:
EOF
        for ((i=1; i<=num_servers; i++)); do
            cat >> "$instructions_file" << EOF
   - $htmlgw_dir/server$i/ca-chain.crt
EOF
        done
        
        cat >> "$instructions_file" << EOF

3. CONVERT TO REQUIRED FORMATS
   ============================
   
   After placing the signed certificate files, run the conversion tool:
   $ ./cyberark-cert-tool.sh
   
   Select option 3 (Convert Signed Certificates) and choose HTML5GW.
   
   This will generate for each server:
EOF
        for ((i=1; i<=num_servers; i++)); do
            cat >> "$instructions_file" << EOF
   - $htmlgw_dir/server$i/htmlgw-server$i.pfx (password-protected PFX file)
   - $htmlgw_dir/server$i/htmlgw-server$i.key (private key in Base64 format)
   - $htmlgw_dir/server$i/htmlgw-server$i.crt (certificate in Base64 format)
   - $htmlgw_dir/server$i/ca-chain.crt (CA chain in Base64 format)
   - $htmlgw_dir/server$i/htmlgw-server$i-password.txt (randomly generated PFX password)
EOF
        done
    fi
    
    cat >> "$instructions_file" << EOF

4. DEPLOY TO HTML5GW SERVERS
   ===========================
   
   Copy the generated certificate files to your HTML5GW server(s) and follow the
   CyberArk documentation for certificate installation.

IMPORTANT NOTES:
- Keep private key files (.key) secure and never share them
- The PFX files are password protected for HTML5GW security requirements
- The password for each PFX file is stored in the corresponding password file
- All certificate files are in Base64 (PEM) format as required by HTML5GW
- Ensure proper file permissions on certificate files
- Test the certificates in a non-production environment first

EOF
    
    log_success "HTML5GW instructions created: $instructions_file"
}