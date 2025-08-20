# CyberArk Certificate Tool

A comprehensive command-line utility for generating SSL/TLS certificates for CyberArk infrastructure components.

## Overview

This tool streamlines the certificate generation process for CyberArk environments by automating:
- Certificate Signing Request (CSR) generation
- Private key creation
- Certificate format conversion
- Multi-server and load balancer configurations

## Supported Components

- PVWA (Password Vault Web Access) — PFX files (password optional)
- PSM (Privileged Session Manager) — PFX files (password optional)
- HTML5GW (HTML5 Gateway) — PFX files (password optional) + separate Base64 files
- PTA (Privileged Threat Analytics) — PFX files (password optional) + Base64 key/cert files; optional CA chain embedding
- Vault (Digital Vault) — PFX files (password required)


## Prerequisites

- Linux/Unix environment with Bash 4.0+ OR macOS
- OpenSSL 1.1.1 or higher
- Write permissions for certificate output directories
- Access to corporate Certificate Authority for CSR signing

## Quick Start

1. **Make the script executable:**
   ```bash
   chmod +x cyberark-cert-tool.sh
   ```

2. **Run the tool:**
   ```bash
   ./cyberark-cert-tool.sh
   ```

3. **Follow the interactive prompts:**
   - Configure global settings (key length, output directory)
   - Generate certificates for desired components
   - Submit CSRs to your corporate CA
   - Place signed certificates back in generated directories
   - Convert certificates to required formats

## Workflow

### 1. Initial Setup
- Configure key length (4096+ bits recommended)
- Set output directory for all certificate files
- Enter company information for Distinguished Name

### 2. Certificate Generation
- Select CyberArk components to configure
- Specify server FQDNs and load balancer settings
- Choose certificate strategy (single vs multiple certificates)
- Private keys and CSRs are generated automatically

### 3. Corporate CA Signing
- Submit generated .csr files to your Certificate Authority
- Follow your organization's certificate signing process
- Download signed certificates and CA chain files

### 4. Certificate Placement
- Copy signed certificates to component directories
- Follow naming conventions in instruction files
- Place CA chain files in appropriate locations

### 5. Format Conversion
- Convert signed certificates to component-specific formats (Option 3)
- Choose per component whether to password-protect the PFX (Vault is always protected)
- HTML5GW and PTA also keep Base64 key/cert files alongside PFX for deployment flexibility

## Directory Structure

```
$OUTPUT_DIR/
├── pvwa/                   # PVWA certificates
│   ├── pvwa.key            # Private key
│   ├── pvwa.csr            # Certificate signing request
│   ├── pvwa.crt            # Signed certificate (after CA)
│   ├── pvwa.pfx            # Final PFX file
│   ├── pvwa-password.txt   # Present if password protection enabled
│   └── PVWA-INSTRUCTIONS.txt
├── psm/                    # PSM certificates
│   ├── psm.key
│   ├── psm.csr
│   ├── psm.crt
│   ├── psm.pfx
│   ├── psm-password.txt    # Present if password protection enabled
│   └── PSM-INSTRUCTIONS.txt
├── htmlgw/                 # HTML5GW certificates
│   ├── htmlgw.key
│   ├── htmlgw.csr
│   ├── htmlgw.crt
│   ├── htmlgw.pfx
│   ├── htmlgw-password.txt # Present if password protection enabled
│   └── HTML5GW-INSTRUCTIONS.txt
└── pta/                    # PTA certificates
    ├── pta.key
    ├── pta.csr
    ├── pta.crt
    ├── pta.pfx
    ├── pta-password.txt    # Present if password protection enabled
    └── PTA-INSTRUCTIONS.txt
```

## Certificate Strategies

### Single Certificate
- One certificate with multiple Subject Alternative Names (SAN)
- Suitable when all servers share the same certificate
- Requires load balancer or wildcard configuration

### Multiple Certificates
- Unique certificate for each server
- Individual server directories created
- Better security isolation per server

## Component-Specific Requirements

### PVWA & PSM
- Format: PFX files (password optional). If enabled, a random password is generated and stored next to the PFX (chmod 600).
- Deployment: Copy the PFX to the server and follow CyberArk documentation.

### HTML5GW
- Formats:
  - PFX file (password optional)
  - Separate key/cert files in Base64 format
  - CA chain in Base64 format
- Security: If password enabled, a random password is generated and stored alongside the PFX.
- Deployment: Use both PFX and separate files as needed.

### PTA
- Formats:
  - PFX file (password optional)
  - Base64 key/cert files retained
- Optional chain embedding: During conversion, you may provide paths to Intermediate and/or Root CA certificates; they will be embedded in the PFX if provided. If none are provided, the tool will use ca-chain.crt in the PTA directory when available.
- Limitation: Maximum 2 PTA nodes supported.
- Deployment: Use the PFX, and keep Base64 files as needed for integrations.

### Vault
- Format: PFX files (password required, generated automatically and stored next to the PFX).
- Deployment: Copy per-node PFX files as required by your Vault procedure.

## Multi-Server Configurations

### Load Balancer Setup
When using load balancers:
- **CN (Common Name):** Load balancer FQDN
- **SAN DNS.1:** Load balancer FQDN  
- **SAN DNS.2+:** Individual server FQDNs

### Non-Load Balanced
When not using load balancers:
- **CN:** Primary server FQDN
- **SAN DNS.1+:** All server FQDNs

## Security Considerations

- Private key files (.key) are created with 600 permissions
- PFX passwords, when enabled, are randomly generated (24 characters) and stored in -password.txt files with chmod 600
- Vault PFX is always password-protected
- Company information is validated for proper DN formatting
- Certificate and key matching is verified before conversion

## Troubleshooting

### Common Issues

1. **OpenSSL not found**
   ```bash
   sudo apt-get install openssl  # Ubuntu/Debian
   sudo yum install openssl      # RHEL/CentOS
   ```

2. **Permission denied**
   - Ensure write permissions to output directory
   - Check script executable permissions

3. **Certificate validation failed**
   - Verify signed certificate matches generated CSR
   - Check CA chain file format and completeness

4. **Invalid FQDN format**
   - Use fully qualified domain names (e.g., server.company.com)
   - Avoid IP addresses in FQDN fields

### File Naming Conventions

When placing signed certificates from CA:
- Use the exact base name from generated .csr files
- Replace .csr extension with .crt for signed certificates
- Place CA chain files as 'ca-chain.crt' in each directory

### Validation Commands

Verify certificate and key match:
```bash
openssl rsa -noout -modulus -in certificate.key | openssl md5
openssl x509 -noout -modulus -in certificate.crt | openssl md5
# Both outputs should be identical
```

Check certificate details:
```bash
openssl x509 -in certificate.crt -text -noout
```

Verify CSR information:
```bash
openssl req -in certificate.csr -text -noout
```

## Support

For issues related to:
- **Certificate generation:** Check OpenSSL installation and permissions
- **CyberArk deployment:** Refer to official CyberArk documentation
- **Corporate CA:** Contact your PKI administrator

## Version History

- v1.1.0
  - Option 3 enhancements: optional PFX passwords for PVWA/PSM/HTML5GW; Vault PFX mandatory; PTA now produces PFX
  - PTA conversion can embed Intermediate and/or Root CA in PFX when paths are provided
  - Updated help text and instructions accordingly
- v1.0.0 — Initial release

## License

This tool is provided as-is for CyberArk environments. Please test thoroughly in non-production environments before deployment.
