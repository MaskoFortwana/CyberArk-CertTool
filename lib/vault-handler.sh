#!/bin/bash

# Vault Certificate Handler Module
# Generates unique key and CSR for 1-5 CyberArk Vault nodes

# Local helper: update SAN entries to include specified entries only
vault_update_san_entries() {
    local config_file="$1"
    shift
    local san_entries=("$@")

    local tmp=$(mktemp)
    local in_alt_names=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^\[alt_names\] ]]; then
            echo "$line"
            in_alt_names=true
            # Write our SAN entries
            for e in "${san_entries[@]}"; do
                echo "$e"
            done
            continue
        fi

        if [[ "$in_alt_names" == true ]]; then
            # If next section starts, stop skipping
            if [[ "$line" =~ ^\[.*\] ]]; then
                in_alt_names=false
                echo "$line"
            fi
            # Skip any existing DNS./IP. lines while in alt_names
            if [[ "$line" =~ ^DNS\.|^IP\. ]]; then
                continue
            fi
            # Otherwise, don't echo lines within alt_names (since we already wrote ours)
            continue
        fi

        echo "$line"
    done < "$config_file" > "$tmp"

    mv "$tmp" "$config_file"
}

# Prompt for 1-3 IP addresses (returns space-separated list on stdout)
vault_collect_ips() {
    local ips=()
    local ip

    # At least 1 IP
    while true; do
        read -p "Enter IP address 1 (required): " ip
        if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            ips+=("$ip")
            break
        else
            log_error "Invalid IPv4 address format."
        fi
    done

    # Optional IP 2
    read -p "Enter IP address 2 (optional, press Enter to skip): " ip || true
    if [[ -n "$ip" ]]; then
        if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            ips+=("$ip")
        else
            log_warning "IP 2 ignored (invalid format)"
        fi
    fi

    # Optional IP 3
    read -p "Enter IP address 3 (optional, press Enter to skip): " ip || true
    if [[ -n "$ip" ]]; then
        if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            ips+=("$ip")
        else
            log_warning "IP 3 ignored (invalid format)"
        fi
    fi

    echo "${ips[@]}"
}

# Collect Vault configuration
configure_vault() {
    echo -e "${CYAN}=== Vault Certificate Configuration ===${NC}"
    echo "Configuring keys and CSRs for the CyberArk Vault"
    echo ""

    # Number of Vault nodes
    local num_nodes
    while true; do
        read -p "How many Vault nodes do you have? (1-5): " num_nodes
        if [[ "$num_nodes" =~ ^[1-5]$ ]]; then
            break
        else
            log_error "Please enter a number between 1 and 5"
        fi
    done

    # Collect per-node details
    local node_fqdns=()
    local node_hosts=()
    local node_ips=()

    for ((i=1; i<=num_nodes; i++)); do
        echo ""
        local fqdn=$(get_input "Enter FQDN for Vault node $i" "fqdn" "")
        node_fqdns+=("$fqdn")

        local host
        while true; do
            read -p "Enter hostname for node $i (no domain): " host
            if [[ "$host" =~ ^[a-zA-Z0-9-]+$ ]]; then
                node_hosts+=("$host")
                break
            else
                log_error "Invalid hostname. Use letters, digits, hyphens."
            fi
        done

        echo "Enter IP addresses for node $i (1 to 3):"
        local ips=( $(vault_collect_ips) )
        node_ips+=("${ips[*]}")
    done

    # Summary
    echo ""
    echo -e "${CYAN}=== Vault Configuration Summary ===${NC}"
    echo "Number of nodes: $num_nodes"
    for ((i=0; i<num_nodes; i++)); do
        echo "Node $((i+1)):"
        echo "  FQDN: ${node_fqdns[i]}"
        echo "  Hostname: ${node_hosts[i]}"
        echo "  IPs: ${node_ips[i]}"
    done
    echo ""

    while true; do
        read -p "Is this configuration correct? (y/n): " confirm
        case $confirm in
            [Yy]*)
                break
                ;;
            [Nn]*)
                log_info "Re-configuring Vault..."
                configure_vault
                return $?
                ;;
            *)
                log_error "Please answer y or n"
                ;;
        esac
    done
    
    # Collect additional SANs for Vault
    echo ""
    collect_additional_sans "Vault"

    generate_vault_certs "$num_nodes" "${node_fqdns[@]}" '|' "${node_hosts[@]}" '|' "${node_ips[@]}"
}

# Generate unique key and CSR for each Vault node
# Args: num_nodes, fqdns..., '|', hosts..., '|', ips-list...
generate_vault_certs() {
    local num_nodes="$1"; shift

    # Split arrays using sentinels
    local fqdns=()
    local hosts=()
    local ips_group=()

    while [[ "$#" -gt 0 && "$1" != '|' ]]; do
        fqdns+=("$1"); shift
    done
    shift  # past first '|'
    while [[ "$#" -gt 0 && "$1" != '|' ]]; do
        hosts+=("$1"); shift
    done
    shift  # past second '|'
    while [[ "$#" -gt 0 ]]; do
        ips_group+=("$1"); shift
    done

    log_info "Generating unique keys and CSRs for Vault nodes..."

    local vault_dir="$OUTPUT_DIR/vault"
    mkdir -p "$vault_dir"

    for ((i=0; i<num_nodes; i++)); do
        local fqdn="${fqdns[i]}"
        local host="${hosts[i]}"
        IFS=' ' read -r -a ips <<< "${ips_group[i]}"

        local node_num=$((i+1))
        local node_dir="$vault_dir/node$node_num"
        mkdir -p "$node_dir"

        log_info "Generating for Vault node $node_num: $fqdn"

        local config_file="$node_dir/vault-node$node_num.cnf"
        cp "$SCRIPT_DIR/vault-cert.cnf" "$config_file"

        # Apply company info
        update_config_file "$config_file"

        # Subject must be FQDN
        sed_inplace "s/^CN = .*/CN = $fqdn/" "$config_file"

        # Build SAN entries: FQDN, hostname, IPs
        local san_entries=("DNS.1 = $fqdn" "DNS.2 = $host")
        local ip_index=1
        for ip in "${ips[@]}"; do
            san_entries+=("IP.$ip_index = $ip")
            ((ip_index++))
        done
        
        # Merge additional SANs with existing SANs
        merge_additional_sans san_entries

        vault_update_san_entries "$config_file" "${san_entries[@]}"

        # Key length
        sed_inplace "s/^default_bits = .*/default_bits = $KEY_LENGTH/" "$config_file"

        # Generate key and CSR
        local key_file="$node_dir/vault-node$node_num.key"
        local csr_file="$node_dir/vault-node$node_num.csr"

        if generate_private_key "$key_file" "$KEY_LENGTH" && generate_csr "$key_file" "$config_file" "$csr_file"; then
            log_success "Generated for node $node_num"
            verify_csr "$csr_file"
        else
            log_error "Failed generating for node $node_num"
            return 1
        fi
    done

    # Instructions
    create_vault_instructions "$vault_dir" "$num_nodes"

    # Summary
    echo ""
    echo -e "${CYAN}=== Generated Vault Files Summary ===${NC}"
    for ((i=1; i<=num_nodes; i++)); do
        local node_dir="$vault_dir/node$i"
        echo "Node $i:"
        echo "  Private Key: $node_dir/vault-node$i.key"
        echo "  CSR: $node_dir/vault-node$i.csr"
        echo "  Configuration: $node_dir/vault-node$i.cnf"
    done
    echo ""

    return 0
}

# Create Vault instructions file
create_vault_instructions() {
    local vault_dir="$1"
    local num_nodes="${2:-0}"
    local instructions_file="$vault_dir/VAULT-INSTRUCTIONS.txt"

    cat > "$instructions_file" << EOF
Vault Certificate Instructions
=============================

Generated on: $(date)
Nodes: $num_nodes

1. SUBMIT CSR(s) TO YOUR CORPORATE CA
   ==================================
   Submit the following CSR(s) to your Certificate Authority:
EOF

    for ((i=1; i<=num_nodes; i++)); do
        echo "   - $vault_dir/node$i/vault-node$i.csr" >> "$instructions_file"
    done

    cat >> "$instructions_file" << EOF

2. DOWNLOAD SIGNED CERTIFICATE(S)
   ===============================
   After your CA signs the CSR(s), download the signed certificate(s) and save them as:
EOF

    for ((i=1; i<=num_nodes; i++)); do
        echo "   - $vault_dir/node$i/vault-node$i.crt" >> "$instructions_file"
    done

    cat >> "$instructions_file" << EOF

   Also download your CA certificate chain (if applicable) for each node as:
EOF

    for ((i=1; i<=num_nodes; i++)); do
        echo "   - $vault_dir/node$i/ca-chain.crt" >> "$instructions_file"
    done

    cat >> "$instructions_file" << EOF

3. CONVERT TO PFX FORMAT
   ======================
   
   After placing the signed certificate files for each node, run the conversion tool:
   $ ./cyberark-cert-tool.sh
   
   Select option 3 (Convert Signed Certificates) and choose Vault.
   
   This will generate for each node:
   - vault-nodeX.pfx (password-protected PFX file)
   - vault-nodeX-password.txt (randomly generated PFX password; chmod 600)

IMPORTANT NOTES:
- Each node has a unique private key (.key)
- PFX password protection is mandatory for Vault and is generated automatically
- Keep private keys and password files secure and never share them
- Ensure proper file permissions on certificate and password files
- Test in non-production before deploying

EOF

    log_success "Vault instructions created: $instructions_file"
}
