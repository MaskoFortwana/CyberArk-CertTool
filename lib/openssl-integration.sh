#!/bin/bash

# OpenSSL Integration Module
# Handles all OpenSSL operations for key and certificate generation

# Generate private key
generate_private_key() {
    local output_file="$1"
    local key_length="$2"
    
    log_info "Generating ${key_length}-bit RSA private key..."
    
    if openssl genrsa -out "$output_file" "$key_length" 2>/dev/null; then
        log_success "Private key generated: $output_file"
        
        # Set proper permissions for private key
        chmod 600 "$output_file"
        
        return 0
    else
        log_error "Failed to generate private key"
        return 1
    fi
}

# Generate Certificate Signing Request (CSR)
generate_csr() {
    local key_file="$1"
    local config_file="$2"
    local output_file="$3"
    
    log_info "Generating Certificate Signing Request (CSR)..."
    
    if [[ ! -f "$key_file" ]]; then
        log_error "Private key file not found: $key_file"
        return 1
    fi
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    if openssl req -new -key "$key_file" -config "$config_file" -out "$output_file" 2>/dev/null; then
        log_success "CSR generated: $output_file"
        return 0
    else
        log_error "Failed to generate CSR"
        return 1
    fi
}

# Verify CSR content
verify_csr() {
    local csr_file="$1"
    
    if [[ ! -f "$csr_file" ]]; then
        log_error "CSR file not found: $csr_file"
        return 1
    fi
    
    echo -e "${CYAN}=== CSR Information ===${NC}"
    echo "File: $csr_file"
    echo ""
    
    # Display CSR details
    openssl req -in "$csr_file" -text -noout 2>/dev/null | grep -E "(Subject:|DNS:|IP Address:)" || {
        log_error "Failed to verify CSR"
        return 1
    }
    
    echo ""
    return 0
}

# Verify private key
verify_private_key() {
    local key_file="$1"
    
    if [[ ! -f "$key_file" ]]; then
        log_error "Private key file not found: $key_file"
        return 1
    fi
    
    # Check if private key is valid
    if openssl rsa -in "$key_file" -check -noout 2>/dev/null; then
        log_success "Private key verification successful"
        
        # Display key information
        local key_size=$(openssl rsa -in "$key_file" -text -noout 2>/dev/null | grep "Private-Key" | grep -o '[0-9]\+')
        log_info "Key size: ${key_size} bits"
        
        return 0
    else
        log_error "Private key verification failed"
        return 1
    fi
}

# Check if certificate and key match
verify_key_cert_match() {
    local key_file="$1"
    local cert_file="$2"
    
    if [[ ! -f "$key_file" ]]; then
        log_error "Private key file not found: $key_file"
        return 1
    fi
    
    if [[ ! -f "$cert_file" ]]; then
        log_error "Certificate file not found: $cert_file"
        return 1
    fi
    
    # Get modulus from key and certificate
    local key_modulus=$(openssl rsa -noout -modulus -in "$key_file" 2>/dev/null | openssl md5 2>/dev/null)
    local cert_modulus=$(openssl x509 -noout -modulus -in "$cert_file" 2>/dev/null | openssl md5 2>/dev/null)
    
    if [[ "$key_modulus" == "$cert_modulus" ]] && [[ -n "$key_modulus" ]]; then
        log_success "Private key and certificate match"
        return 0
    else
        log_error "Private key and certificate do not match"
        return 1
    fi
}

# Convert certificate to PFX format
create_pfx() {
    local cert_file="$1"
    local key_file="$2"
    local ca_file="$3"
    local output_file="$4"
    local password="$5"
    
    log_info "Creating PFX file: $output_file"
    
    # Build OpenSSL command
    local openssl_cmd="openssl pkcs12 -export -out \"$output_file\" -inkey \"$key_file\" -in \"$cert_file\""
    
    # Add CA chain if provided
    if [[ -n "$ca_file" ]] && [[ -f "$ca_file" ]]; then
        openssl_cmd="$openssl_cmd -certfile \"$ca_file\""
    fi
    
    # Add password protection
    if [[ -n "$password" ]]; then
        openssl_cmd="$openssl_cmd -passout pass:\"$password\""
    else
        openssl_cmd="$openssl_cmd -passout pass:"
    fi
    
    # Execute the command
    if eval "$openssl_cmd" 2>/dev/null; then
        log_success "PFX file created: $output_file"
        return 0
    else
        log_error "Failed to create PFX file"
        return 1
    fi
}

# Extract certificate from PFX
extract_cert_from_pfx() {
    local pfx_file="$1"
    local cert_file="$2"
    local password="$3"
    
    log_info "Extracting certificate from PFX: $pfx_file"
    
    local openssl_cmd="openssl pkcs12 -in \"$pfx_file\" -clcerts -nokeys -out \"$cert_file\""
    
    if [[ -n "$password" ]]; then
        openssl_cmd="$openssl_cmd -passin pass:\"$password\""
    else
        openssl_cmd="$openssl_cmd -passin pass:"
    fi
    
    if eval "$openssl_cmd" 2>/dev/null; then
        log_success "Certificate extracted: $cert_file"
        return 0
    else
        log_error "Failed to extract certificate from PFX"
        return 1
    fi
}

# Extract private key from PFX
extract_key_from_pfx() {
    local pfx_file="$1"
    local key_file="$2"
    local password="$3"
    
    log_info "Extracting private key from PFX: $pfx_file"
    
    local openssl_cmd="openssl pkcs12 -in \"$pfx_file\" -nocerts -nodes -out \"$key_file\""
    
    if [[ -n "$password" ]]; then
        openssl_cmd="$openssl_cmd -passin pass:\"$password\""
    else
        openssl_cmd="$openssl_cmd -passin pass:"
    fi
    
    if eval "$openssl_cmd" 2>/dev/null; then
        log_success "Private key extracted: $key_file"
        
        # Set proper permissions
        chmod 600 "$key_file"
        
        return 0
    else
        log_error "Failed to extract private key from PFX"
        return 1
    fi
}

# Create certificate chain file
create_cert_chain() {
    local cert_file="$1"
    local ca_file="$2"
    local output_file="$3"
    
    log_info "Creating certificate chain file: $output_file"
    
    if [[ ! -f "$cert_file" ]]; then
        log_error "Certificate file not found: $cert_file"
        return 1
    fi
    
    # Start with the server certificate
    cat "$cert_file" > "$output_file"
    
    # Add CA certificates if provided
    if [[ -n "$ca_file" ]] && [[ -f "$ca_file" ]]; then
        cat "$ca_file" >> "$output_file"
    fi
    
    log_success "Certificate chain created: $output_file"
    return 0
}

# Convert certificate format (PEM to DER or vice versa)
convert_cert_format() {
    local input_file="$1"
    local output_file="$2"
    local input_format="$3"  # PEM or DER
    local output_format="$4" # PEM or DER
    
    log_info "Converting certificate from $input_format to $output_format"
    
    if [[ "$input_format" == "PEM" ]] && [[ "$output_format" == "DER" ]]; then
        openssl x509 -in "$input_file" -outform DER -out "$output_file"
    elif [[ "$input_format" == "DER" ]] && [[ "$output_format" == "PEM" ]]; then
        openssl x509 -in "$input_file" -inform DER -out "$output_file"
    else
        log_error "Unsupported conversion: $input_format to $output_format"
        return 1
    fi
    
    if [[ $? -eq 0 ]]; then
        log_success "Certificate converted: $output_file"
        return 0
    else
        log_error "Certificate conversion failed"
        return 1
    fi
}

# Generate random password
generate_random_password() {
    local length="${1:-32}"
    
    # Generate a random password using /dev/urandom
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

# Display certificate information
show_cert_info() {
    local cert_file="$1"
    
    if [[ ! -f "$cert_file" ]]; then
        log_error "Certificate file not found: $cert_file"
        return 1
    fi
    
    echo -e "${CYAN}=== Certificate Information ===${NC}"
    echo "File: $cert_file"
    echo ""
    
    # Display certificate details
    openssl x509 -in "$cert_file" -text -noout 2>/dev/null | grep -E "(Subject:|Issuer:|Not Before|Not After|DNS:|IP Address:)" || {
        log_error "Failed to read certificate information"
        return 1
    }
    
    echo ""
    return 0
}

# Validate certificate chain
validate_cert_chain() {
    local cert_file="$1"
    local ca_file="$2"
    
    log_info "Validating certificate chain..."
    
    if [[ -n "$ca_file" ]] && [[ -f "$ca_file" ]]; then
        if openssl verify -CAfile "$ca_file" "$cert_file" 2>/dev/null; then
            log_success "Certificate chain validation successful"
            return 0
        else
            log_error "Certificate chain validation failed"
            return 1
        fi
    else
        log_warning "No CA file provided, skipping chain validation"
        return 0
    fi
}