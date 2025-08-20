#!/bin/bash

# PTA Certificate Handler Module
# Handles PTA-specific certificate configuration and generation

# Collect PTA configuration
configure_pta() {
    echo -e "${CYAN}=== PTA Certificate Configuration ===${NC}"
    echo "Configuring certificates for Privileged Threat Analytics (PTA)"
    echo ""
    echo -e "${YELLOW}Note: PTA can have a maximum of 2 nodes${NC}"
    echo ""
    
    # Number of PTA servers (max 2)
    echo -e "${BLUE}PTA Server Configuration:${NC}"
    local num_servers
    while true; do
        read -p "How many PTA servers do you have? (1-2): " num_servers
        if [[ "$num_servers" =~ ^[12]$ ]]; then
            break
        else
            log_error "PTA supports maximum 2 servers. Please enter 1 or 2"
        fi
    done
    
    # Collect server FQDNs
    local server_fqdns=()
    for ((i=1; i<=num_servers; i++)); do
        echo ""
        local fqdn=$(get_input "Enter FQDN for PTA server $i" "fqdn" "")
        server_fqdns+=("$fqdn")
    done
    
    # Load balancer configuration
    echo ""
    echo -e "${BLUE}Load Balancer Configuration:${NC}"
    local has_loadbalancer="n"
    local lb_fqdn=""
    
    if [[ $num_servers -eq 2 ]]; then
        while true; do
            read -p "Do you have a load balancer for PTA? (y/n): " has_loadbalancer
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
    if [[ $num_servers -eq 2 ]]; then
        echo "Choose certificate strategy:"
        echo "1. Single certificate for both PTA servers (with SAN entries)"
        echo "2. Unique certificate for each PTA server"
        
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
    echo -e "${CYAN}=== PTA Configuration Summary ===${NC}"
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
                log_info "Re-configuring PTA..."
                configure_pta
                return $?
                ;;
            *)
                log_error "Please answer y or n"
                ;;
        esac
    done
    
    # Generate certificates based on strategy
    if [[ "$cert_strategy" == "1" ]]; then
        generate_pta_single_cert "$lb_fqdn" "${server_fqdns[@]}"
    else
        generate_pta_multiple_certs "${server_fqdns[@]}"
    fi
}

# Generate single certificate for all PTA servers
generate_pta_single_cert() {
    local lb_fqdn="$1"
    shift
    local server_fqdns=("$@")
    
    log_info "Generating single certificate for all PTA servers..."
    
    # Create PTA output directory
    local pta_dir="$OUTPUT_DIR/pta"
    mkdir -p "$pta_dir"
    
    # Copy and modify configuration file
    local config_file="$pta_dir/pta-cert.cnf"
    cp "$SCRIPT_DIR/pta-cert.cnf" "$config_file"
    
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
    
    # Update SAN entries in config file
    update_san_entries "$config_file" "${san_entries[@]}"
    
    # Update key length in config file
    sed_inplace "s/^default_bits = .*/default_bits = $KEY_LENGTH/" "$config_file"
    
    # Generate private key and CSR
    local key_file="$pta_dir/pta.key"
    local csr_file="$pta_dir/pta.csr"
    
    if generate_private_key "$key_file" "$KEY_LENGTH" && generate_csr "$key_file" "$config_file" "$csr_file"; then
        log_success "PTA certificate files generated successfully"
        
        # Display file locations
        echo ""
        echo -e "${CYAN}=== Generated PTA Files ===${NC}"
        echo "Private Key: $key_file"
        echo "CSR: $csr_file"
        echo "Configuration: $config_file"
        echo ""
        
        # Verify CSR
        verify_csr "$csr_file"
        
        # Create instructions file
        create_pta_instructions "$pta_dir" "single"
        
        return 0
    else
        log_error "Failed to generate PTA certificate files"
        return 1
    fi
}

# Generate unique certificates for each PTA server
generate_pta_multiple_certs() {
    local server_fqdns=("$@")
    
    log_info "Generating unique certificates for each PTA server..."
    
    # Create PTA output directory
    local pta_dir="$OUTPUT_DIR/pta"
    mkdir -p "$pta_dir"
    
    for ((i=0; i<${#server_fqdns[@]}; i++)); do
        local server_fqdn="${server_fqdns[i]}"
        local server_num=$((i+1))
        local server_dir="$pta_dir/server$server_num"
        
        log_info "Generating certificate for PTA server $server_num: $server_fqdn"
        
        # Create server-specific directory
        mkdir -p "$server_dir"
        
        # Copy and modify configuration file
        local config_file="$server_dir/pta-server$server_num.cnf"
        cp "$SCRIPT_DIR/pta-cert.cnf" "$config_file"
        
        # Update company information in config
        update_config_file "$config_file"
        
        # Configure CN and SAN for this server
        sed_inplace "s/^CN = .*/CN = $server_fqdn/" "$config_file"
        
        # Update SAN entry
        local san_entries=("DNS.1 = $server_fqdn")
        update_san_entries "$config_file" "${san_entries[@]}"
        
        # Update key length in config file
        sed_inplace "s/^default_bits = .*/default_bits = $KEY_LENGTH/" "$config_file"
        
        # Generate private key and CSR
        local key_file="$server_dir/pta-server$server_num.key"
        local csr_file="$server_dir/pta-server$server_num.csr"
        
        if generate_private_key "$key_file" "$KEY_LENGTH" && generate_csr "$key_file" "$config_file" "$csr_file"; then
            log_success "Certificate files generated for PTA server $server_num"
        else
            log_error "Failed to generate certificate files for PTA server $server_num"
            return 1
        fi
    done
    
    # Display summary
    echo ""
    echo -e "${CYAN}=== Generated PTA Files Summary ===${NC}"
    for ((i=0; i<${#server_fqdns[@]}; i++)); do
        local server_num=$((i+1))
        local server_dir="$pta_dir/server$server_num"
        echo "Server $server_num (${server_fqdns[i]}):"
        echo "  Private Key: $server_dir/pta-server$server_num.key"
        echo "  CSR: $server_dir/pta-server$server_num.csr"
        echo "  Configuration: $server_dir/pta-server$server_num.cnf"
    done
    echo ""
    
    # Create instructions file
    create_pta_instructions "$pta_dir" "multiple" "${#server_fqdns[@]}"
    
    return 0
}

# Create PTA instructions file
create_pta_instructions() {
    local pta_dir="$1"
    local cert_type="$2"
    local num_servers="${3:-0}"
    
    local instructions_file="$pta_dir/PTA-INSTRUCTIONS.txt"
    
    cat > "$instructions_file" << EOF
PTA Certificate Instructions
===========================

Generated on: $(date)
Certificate Type: $cert_type certificate(s)

1. SUBMIT CSR(s) TO YOUR CORPORATE CA
   =====================================

EOF

    if [[ "$cert_type" == "single" ]]; then
        cat >> "$instructions_file" << EOF
   Submit the following CSR to your Certificate Authority:
   - $pta_dir/pta.csr

2. DOWNLOAD SIGNED CERTIFICATE
   ============================
   
   After your CA signs the CSR, download the signed certificate and save it as:
   - $pta_dir/pta.crt
   
   Also download your CA certificate chain and save it as:
   - $pta_dir/ca-chain.crt

3. CONVERT TO REQUIRED FORMATS
   ============================
   
   After placing the signed certificate files, run the conversion tool:
   $ ./cyberark-cert-tool.sh
   
   Select option 3 (Convert Signed Certificates) and choose PTA.
   
   This will generate:
   - $pta_dir/pta.pfx (PFX file; password protection optional)
   - $pta_dir/pta-password.txt (if password protection enabled)
   - $pta_dir/pta.key (private key in Base64 format)
   - $pta_dir/pta.crt (certificate in Base64 format)
   - $pta_dir/ca-chain.crt (CA chain in Base64 format)

EOF
    else
        cat >> "$instructions_file" << EOF
   Submit the following CSRs to your Certificate Authority:
EOF
        for ((i=1; i<=num_servers; i++)); do
            cat >> "$instructions_file" << EOF
   - $pta_dir/server$i/pta-server$i.csr
EOF
        done
        
        cat >> "$instructions_file" << EOF

2. DOWNLOAD SIGNED CERTIFICATES
   =============================
   
   After your CA signs the CSRs, download the signed certificates and save them as:
EOF
        for ((i=1; i<=num_servers; i++)); do
            cat >> "$instructions_file" << EOF
   - $pta_dir/server$i/pta-server$i.crt
EOF
        done
        
        cat >> "$instructions_file" << EOF
   
   Also download your CA certificate chain and save it in each server directory as:
EOF
        for ((i=1; i<=num_servers; i++)); do
            cat >> "$instructions_file" << EOF
   - $pta_dir/server$i/ca-chain.crt
EOF
        done
        
        cat >> "$instructions_file" << EOF

3. CONVERT TO REQUIRED FORMATS
   ============================
   
   After placing the signed certificate files, run the conversion tool:
   $ ./cyberark-cert-tool.sh
   
   Select option 3 (Convert Signed Certificates) and choose PTA.
   
This will generate for each server:
EOF
        for ((i=1; i<=num_servers; i++)); do
            cat >> "$instructions_file" << EOF
   - $pta_dir/server$i/pta-server$i.pfx (PFX file; password protection optional)
   - $pta_dir/server$i/pta-server$i-password.txt (if password protection enabled)
   - $pta_dir/server$i/pta-server$i.key (private key in Base64 format)
   - $pta_dir/server$i/pta-server$i.crt (certificate in Base64 format)
   - $pta_dir/server$i/ca-chain.crt (CA chain in Base64 format)
EOF
        done
    fi
    
    cat >> "$instructions_file" << EOF

4. DEPLOY TO PTA SERVERS
   =======================
   
   Copy the generated certificate files to your PTA server(s) and follow the
   CyberArk documentation for certificate installation.

IMPORTANT NOTES:
- Keep private key files (.key) secure and never share them
- PTA PFX creation is supported during conversion; password is optional
- Certificate/key files are kept in Base64 (PEM) format alongside PFX
- Ensure proper file permissions on certificate and password files
- Test the certificates in a non-production environment first

EOF
    
    log_success "PTA instructions created: $instructions_file"
}