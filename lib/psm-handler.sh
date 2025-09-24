#!/bin/bash

# PSM Certificate Handler Module
# Handles PSM-specific certificate configuration and generation

# Collect PSM configuration
configure_psm() {
    echo -e "${CYAN}=== PSM Certificate Configuration ===${NC}"
    echo "Configuring certificates for Privileged Session Manager (PSM)"
    echo ""
    
    # Number of PSM servers
    echo -e "${BLUE}PSM Server Configuration:${NC}"
    local num_servers
    while true; do
        read -p "How many PSM servers do you have? (1-10): " num_servers
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
        local fqdn=$(get_input "Enter FQDN for PSM server $i" "fqdn" "")
        server_fqdns+=("$fqdn")
    done
    
    # Load balancer configuration
    echo ""
    echo -e "${BLUE}Load Balancer Configuration:${NC}"
    local has_loadbalancer="n"
    local lb_fqdn=""
    
    if [[ $num_servers -gt 1 ]]; then
        while true; do
            read -p "Do you have a load balancer for PSM? (y/n): " has_loadbalancer
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
        echo "1. Single certificate for all PSM servers (with SAN entries)"
        echo "2. Unique certificate for each PSM server"
        
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
    echo -e "${CYAN}=== PSM Configuration Summary ===${NC}"
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
                log_info "Re-configuring PSM..."
                configure_psm
                return $?
                ;;
            *)
                log_error "Please answer y or n"
                ;;
        esac
    done
    
    # Collect additional SANs for PSM
    echo ""
    collect_additional_sans "PSM"
    
    # Generate certificates based on strategy
    if [[ "$cert_strategy" == "1" ]]; then
        generate_psm_single_cert "$lb_fqdn" "${server_fqdns[@]}"
    else
        generate_psm_multiple_certs "${server_fqdns[@]}"
    fi
}

# Generate single certificate for all PSM servers
generate_psm_single_cert() {
    local lb_fqdn="$1"
    shift
    local server_fqdns=("$@")
    
    log_info "Generating single certificate for all PSM servers..."
    
    # Create PSM output directory
    local psm_dir="$OUTPUT_DIR/psm"
    mkdir -p "$psm_dir"
    
    # Copy and modify configuration file
    local config_file="$psm_dir/psm-cert.cnf"
    cp "$SCRIPT_DIR/psm-cert.cnf" "$config_file"
    
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
    local key_file="$psm_dir/psm.key"
    local csr_file="$psm_dir/psm.csr"
    
    if generate_private_key "$key_file" "$KEY_LENGTH" && generate_csr "$key_file" "$config_file" "$csr_file"; then
        log_success "PSM certificate files generated successfully"
        
        # Display file locations
        echo ""
        echo -e "${CYAN}=== Generated PSM Files ===${NC}"
        echo "Private Key: $key_file"
        echo "CSR: $csr_file"
        echo "Configuration: $config_file"
        echo ""
        
        # Verify CSR
        verify_csr "$csr_file"
        
        # Create instructions file
        create_psm_instructions "$psm_dir" "single"
        
        return 0
    else
        log_error "Failed to generate PSM certificate files"
        return 1
    fi
}

# Generate unique certificates for each PSM server
generate_psm_multiple_certs() {
    local server_fqdns=("$@")
    
    log_info "Generating unique certificates for each PSM server..."
    
    # Create PSM output directory
    local psm_dir="$OUTPUT_DIR/psm"
    mkdir -p "$psm_dir"
    
    for ((i=0; i<${#server_fqdns[@]}; i++)); do
        local server_fqdn="${server_fqdns[i]}"
        local server_num=$((i+1))
        local server_dir="$psm_dir/server$server_num"
        
        log_info "Generating certificate for PSM server $server_num: $server_fqdn"
        
        # Create server-specific directory
        mkdir -p "$server_dir"
        
        # Copy and modify configuration file
        local config_file="$server_dir/psm-server$server_num.cnf"
        cp "$SCRIPT_DIR/psm-cert.cnf" "$config_file"
        
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
        local key_file="$server_dir/psm-server$server_num.key"
        local csr_file="$server_dir/psm-server$server_num.csr"
        
        if generate_private_key "$key_file" "$KEY_LENGTH" && generate_csr "$key_file" "$config_file" "$csr_file"; then
            log_success "Certificate files generated for PSM server $server_num"
        else
            log_error "Failed to generate certificate files for PSM server $server_num"
            return 1
        fi
    done
    
    # Display summary
    echo ""
    echo -e "${CYAN}=== Generated PSM Files Summary ===${NC}"
    for ((i=0; i<${#server_fqdns[@]}; i++)); do
        local server_num=$((i+1))
        local server_dir="$psm_dir/server$server_num"
        echo "Server $server_num (${server_fqdns[i]}):"
        echo "  Private Key: $server_dir/psm-server$server_num.key"
        echo "  CSR: $server_dir/psm-server$server_num.csr"
        echo "  Configuration: $server_dir/psm-server$server_num.cnf"
    done
    echo ""
    
    # Create instructions file
    create_psm_instructions "$psm_dir" "multiple" "${#server_fqdns[@]}"
    
    return 0
}

# Create PSM instructions file
create_psm_instructions() {
    local psm_dir="$1"
    local cert_type="$2"
    local num_servers="${3:-0}"
    
    local instructions_file="$psm_dir/PSM-INSTRUCTIONS.txt"
    
    cat > "$instructions_file" << EOF
PSM Certificate Instructions
===========================

Generated on: $(date)
Certificate Type: $cert_type certificate(s)

1. SUBMIT CSR(s) TO YOUR CORPORATE CA
   =====================================

EOF

    if [[ "$cert_type" == "single" ]]; then
        cat >> "$instructions_file" << EOF
   Submit the following CSR to your Certificate Authority:
   - $psm_dir/psm.csr

2. DOWNLOAD SIGNED CERTIFICATE
   ============================
   
   After your CA signs the CSR, download the signed certificate and save it as:
   - $psm_dir/psm.crt
   
   Also download your CA certificate chain and save it as:
   - $psm_dir/ca-chain.crt

3. CONVERT TO PFX FORMAT
   ======================
   
   After placing the signed certificate files, run the conversion tool:
   $ ./cyberark-cert-tool.sh
   
   Select option 3 (Convert Signed Certificates) and choose PSM.
   
   This will generate:
   - $psm_dir/psm.pfx (unprotected PFX file for PSM)

EOF
    else
        cat >> "$instructions_file" << EOF
   Submit the following CSRs to your Certificate Authority:
EOF
        for ((i=1; i<=num_servers; i++)); do
            cat >> "$instructions_file" << EOF
   - $psm_dir/server$i/psm-server$i.csr
EOF
        done
        
        cat >> "$instructions_file" << EOF

2. DOWNLOAD SIGNED CERTIFICATES
   =============================
   
   After your CA signs the CSRs, download the signed certificates and save them as:
EOF
        for ((i=1; i<=num_servers; i++)); do
            cat >> "$instructions_file" << EOF
   - $psm_dir/server$i/psm-server$i.crt
EOF
        done
        
        cat >> "$instructions_file" << EOF
   
   Also download your CA certificate chain and save it in each server directory as:
EOF
        for ((i=1; i<=num_servers; i++)); do
            cat >> "$instructions_file" << EOF
   - $psm_dir/server$i/ca-chain.crt
EOF
        done
        
        cat >> "$instructions_file" << EOF

3. CONVERT TO PFX FORMAT
   ======================
   
   After placing the signed certificate files, run the conversion tool:
   $ ./cyberark-cert-tool.sh
   
   Select option 3 (Convert Signed Certificates) and choose PSM.
   
   This will generate PFX files for each server:
EOF
        for ((i=1; i<=num_servers; i++)); do
            cat >> "$instructions_file" << EOF
   - $psm_dir/server$i/psm-server$i.pfx (unprotected PFX file)
EOF
        done
    fi
    
    cat >> "$instructions_file" << EOF

4. DEPLOY TO PSM SERVERS
   ======================
   
   Copy the generated PFX file(s) to your PSM server(s) and follow the
   CyberArk documentation for certificate installation.

IMPORTANT NOTES:
- Keep private key files (.key) secure and never share them
- The PFX files are not password protected as required by PSM
- Ensure proper file permissions on certificate files
- Test the certificates in a non-production environment first

EOF
    
    log_success "PSM instructions created: $instructions_file"
}