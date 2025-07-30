#!/bin/bash

# CyberArk Certificate Tool
# Interactive tool for generating SSL certificates for CyberArk components
# Version: 1.0.0

set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR=""
KEY_LENGTH=4096
COMPANY_INFO=()
SELECTED_COMPONENTS=()

# Source library modules
source "$SCRIPT_DIR/lib/company-info.sh"
source "$SCRIPT_DIR/lib/openssl-integration.sh"
source "$SCRIPT_DIR/lib/pvwa-handler.sh"
source "$SCRIPT_DIR/lib/psm-handler.sh"
source "$SCRIPT_DIR/lib/htmlgw-handler.sh"
source "$SCRIPT_DIR/lib/pta-handler.sh"
source "$SCRIPT_DIR/lib/cert-converter.sh"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Display banner
show_banner() {
    echo -e "${CYAN}"
    echo "=============================================="
    echo "    CyberArk Certificate Generation Tool    "
    echo "=============================================="
    echo -e "${NC}"
    echo "This tool helps you generate SSL certificates for:"
    echo "  • PVWA (Password Vault Web Access)"
    echo "  • PSM (Privileged Session Manager)"
    echo "  • HTML5GW (HTML5 Gateway)"
    echo "  • PTA (Privileged Threat Analytics)"
    echo ""
}

# Display main menu
show_main_menu() {
    echo -e "${CYAN}=== Main Menu ===${NC}"
    echo "1. Configure Global Settings"
    echo "2. Generate Certificates"
    echo "3. Convert Signed Certificates"
    echo "4. View Configuration"
    echo "5. Help & Instructions"
    echo "6. Exit"
    echo ""
}

# Display component selection menu
show_component_menu() {
    echo -e "${CYAN}=== Select CyberArk Components ===${NC}"
    echo "Choose which components you need certificates for:"
    echo "1. PVWA (Password Vault Web Access)"
    echo "2. PSM (Privileged Session Manager)"  
    echo "3. HTML5GW (HTML5 Gateway)"
    echo "4. PTA (Privileged Threat Analytics)"
    echo "5. All Components"
    echo "6. Back to Main Menu"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if OpenSSL is installed
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Please install OpenSSL and try again."
        exit 1
    fi
    
    # Check OpenSSL version
    local openssl_version=$(openssl version | cut -d' ' -f2)
    log_info "OpenSSL version: $openssl_version"
    
    # Check if configuration files exist
    local config_files=("pvwa-cert.cnf" "psm-cert.cnf" "htmlgw-cert.cnf" "pta-cert.cnf")
    for config in "${config_files[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$config" ]]; then
            log_error "Configuration file $config not found in $SCRIPT_DIR"
            exit 1
        fi
    done
    
    log_success "Prerequisites check completed successfully"
}

# Validate input
validate_input() {
    local input="$1"
    local type="$2"
    
    case "$type" in
        "menu_choice")
            if [[ ! "$input" =~ ^[1-6]$ ]]; then
                return 1
            fi
            ;;
        "component_choice")
            if [[ ! "$input" =~ ^[1-6]$ ]]; then
                return 1
            fi
            ;;
        "key_length")
            if [[ ! "$input" =~ ^[0-9]+$ ]] || [[ "$input" -lt 4096 ]]; then
                return 1
            fi
            ;;
        "directory")
            if [[ ! -d "$input" ]] && [[ ! "$input" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
                return 1
            fi
            ;;
        "fqdn")
            if [[ ! "$input" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                return 1
            fi
            ;;
        "country")
            if [[ ! "$input" =~ ^[A-Z]{2}$ ]]; then
                return 1
            fi
            ;;
        *)
            return 0
            ;;
    esac
    return 0
}

# Get user input with validation
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
        
        if validate_input "$input" "$type"; then
            echo "$input"
            return 0
        else
            case "$type" in
                "key_length")
                    log_error "Invalid key length. Must be 4096 or higher."
                    ;;
                "fqdn")
                    log_error "Invalid FQDN format. Please enter a valid domain name (e.g., server.company.com)."
                    ;;
                "country")
                    log_error "Invalid country code. Please enter a 2-letter country code (e.g., US, GB, DE)."
                    ;;
                *)
                    log_error "Invalid input. Please try again."
                    ;;
            esac
        fi
    done
}

# Configure global settings
configure_global_settings() {
    echo -e "${CYAN}=== Global Settings Configuration ===${NC}"
    
    # Key length configuration
    echo ""
    echo "Key Length Configuration:"
    echo "Recommended: 4096 bits (minimum)"
    echo "Higher values provide better security but slower performance"
    KEY_LENGTH=$(get_input "Enter key length in bits" "key_length" "4096")
    
    # Output directory configuration
    echo ""
    echo "Output Directory Configuration:"
    echo "This is where all generated certificates will be stored"
    local default_output="$HOME/cyberark-certificates"
    OUTPUT_DIR=$(get_input "Enter output directory path" "directory" "$default_output")
    
    # Create output directory if it doesn't exist
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        mkdir -p "$OUTPUT_DIR"
        log_success "Created output directory: $OUTPUT_DIR"
    fi
    
    log_success "Global settings configured successfully"
}

# Generate certificates menu
generate_certificates_menu() {
    echo -e "${CYAN}=== Certificate Generation ===${NC}"
    echo "Select CyberArk components for certificate generation:"
    echo ""
    
    show_component_menu
    
    while true; do
        choice=$(get_input "Select an option" "component_choice" "")
        
        case $choice in
            1)
                collect_company_info
                configure_pvwa
                break
                ;;
            2)
                collect_company_info
                configure_psm
                break
                ;;
            3)
                collect_company_info
                configure_htmlgw
                break
                ;;
            4)
                collect_company_info
                configure_pta
                break
                ;;
            5)
                collect_company_info
                log_info "Generating certificates for all components..."
                configure_pvwa
                configure_psm
                configure_htmlgw
                configure_pta
                break
                ;;
            6)
                return 0
                ;;
            *)
                log_error "Invalid choice. Please select 1-6."
                ;;
        esac
    done
}

# Show current configuration
show_current_configuration() {
    echo -e "${CYAN}=== Current Configuration ===${NC}"
    echo "Key Length: $KEY_LENGTH bits"
    echo "Output Directory: ${OUTPUT_DIR:-'Not configured'}"
    echo ""
    
    # Show company information if configured
    if [[ ${#COMPANY_INFO[@]} -gt 0 ]]; then
        echo "Company Information:"
        for info in "${COMPANY_INFO[@]}"; do
            echo "  $info"
        done
    else
        echo "Company Information: Not configured"
    fi
    echo ""
    
    # Show available certificate directories
    if [[ -n "$OUTPUT_DIR" ]] && [[ -d "$OUTPUT_DIR" ]]; then
        echo "Generated Certificate Directories:"
        local found_dirs=false
        for component in pvwa psm htmlgw pta; do
            if [[ -d "$OUTPUT_DIR/$component" ]]; then
                echo "  $component: $OUTPUT_DIR/$component"
                found_dirs=true
            fi
        done
        if [[ "$found_dirs" == false ]]; then
            echo "  No certificate directories found"
        fi
    fi
    echo ""
}

# Show help and instructions
show_help_instructions() {
    echo -e "${CYAN}=== Help & Instructions ===${NC}"
    echo ""
    echo -e "${BLUE}CyberArk Certificate Tool Usage:${NC}"
    echo ""
    echo "1. Configure Global Settings"
    echo "   - Set key length (4096+ bits recommended)"
    echo "   - Choose output directory for certificates"
    echo ""
    echo "2. Generate Certificates"
    echo "   - Select CyberArk components (PVWA, PSM, HTML5GW, PTA)"
    echo "   - Enter company information for Distinguished Name"
    echo "   - Configure server FQDNs and load balancer settings"
    echo "   - Choose certificate strategy (single vs multiple certificates)"
    echo ""
    echo "3. Submit CSRs to Corporate CA"
    echo "   - Take generated .csr files to your Certificate Authority"
    echo "   - Follow your organization's certificate signing process"
    echo "   - Download signed certificates and CA chain"
    echo ""
    echo "4. Place Signed Certificates"
    echo "   - Copy signed certificates to the generated directories"
    echo "   - Follow naming conventions in the instructions files"
    echo "   - Place CA chain files in each component directory"
    echo ""
    echo "5. Convert Signed Certificates"
    echo "   - Use option 3 to convert certificates to required formats:"
    echo "     • PVWA: Unprotected PFX files"
    echo "     • PSM: Unprotected PFX files"
    echo "     • HTML5GW: Password-protected PFX + separate Base64 files"
    echo "     • PTA: Separate key/cert files in Base64 format"
    echo ""
    echo -e "${YELLOW}Important Notes:${NC}"
    echo "- Keep private key files (.key) secure"
    echo "- Test certificates in non-production environment first"
    echo "- Follow CyberArk documentation for certificate installation"
    echo "- Check instruction files in each component directory"
    echo ""
    echo -e "${BLUE}Certificate Format Requirements:${NC}"
    echo "- PVWA: PFX file (no password protection)"
    echo "- PSM: PFX file (no password protection)"
    echo "- HTML5GW: PFX file (password protected) + separate key/cert files"
    echo "- PTA: Separate key and certificate files (Base64 format only)"
    echo ""
    echo -e "${BLUE}File Organization:${NC}"
    echo "Output directory structure:"
    echo "  \$OUTPUT_DIR/"
    echo "  ├── pvwa/           # PVWA certificates and keys"
    echo "  ├── psm/            # PSM certificates and keys"
    echo "  ├── htmlgw/         # HTML5GW certificates and keys"
    echo "  └── pta/            # PTA certificates and keys"
    echo ""
    echo "Each component directory contains:"
    echo "- Private keys (.key files)"
    echo "- Certificate Signing Requests (.csr files)"
    echo "- Configuration files (.cnf files)"
    echo "- Instructions file (COMPONENT-INSTRUCTIONS.txt)"
    echo "- Signed certificates (.crt files) - after CA signing"
    echo "- Final certificate files (.pfx, etc.) - after conversion"
    echo ""
}

# Main function
main() {
    show_banner
    check_prerequisites
    
    while true; do
        show_main_menu
        choice=$(get_input "Select an option" "menu_choice" "")
        
        case $choice in
            1)
                configure_global_settings
                ;;
            2)
                if [[ -z "$OUTPUT_DIR" ]]; then
                    log_warning "Please configure global settings first"
                    continue
                fi
                generate_certificates_menu
                ;;
            3)
                if [[ -z "$OUTPUT_DIR" ]]; then
                    log_warning "Please configure global settings first"
                    continue
                fi
                convert_certificates
                ;;
            4)
                # Display current configuration
                show_current_configuration
                ;;
            5)
                show_help_instructions
                ;;
            6)
                log_info "Goodbye!"
                exit 0
                ;;
            *)
                log_error "Invalid choice. Please select 1-6."
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
        clear
    done
}

# Run main function
main "$@"