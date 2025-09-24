#!/bin/bash

# Utility functions shared across modules

# Portable in-place sed replacement compatible with GNU sed and BSD sed (macOS)
# Usage: sed_inplace 's/pattern/replacement/' file
sed_inplace() {
    local expr="$1"
    local file="$2"

    if sed --version >/dev/null 2>&1; then
        # GNU sed available
        sed -i "$expr" "$file"
    else
        # Likely BSD sed (macOS)
        sed -i '' "$expr" "$file"
    fi
}

# Merge additional SANs with existing SAN entries
# Usage: merge_additional_sans existing_sans_array_name
# Updates the san_entries array with additional SANs appended
# Compatible with bash 3.2+
merge_additional_sans() {
    local array_name="$1"
    
    # Get current array contents using indirect expansion
    local current_sans
    eval "current_sans=(\"\${${array_name}[@]}\")"
    
    local merged_sans=("${current_sans[@]}")
    
    # Count existing DNS and IP entries to determine next indices
    local dns_count=0
    local ip_count=0
    
    for entry in "${current_sans[@]}"; do
        if [[ "$entry" =~ ^DNS\. ]]; then
            ((dns_count++))
        elif [[ "$entry" =~ ^IP\. ]]; then
            ((ip_count++))
        fi
    done
    
    # Add additional SANs from component-specific COMPONENT_ADDITIONAL_SANS array
    if [[ ${#COMPONENT_ADDITIONAL_SANS[@]} -gt 0 ]]; then
        for san in "${COMPONENT_ADDITIONAL_SANS[@]}"; do
            # Check if it's an IP address
            if [[ "$san" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                ((ip_count++))
                merged_sans+=("IP.$ip_count = $san")
            else
                # Assume it's a DNS name
                ((dns_count++))
                merged_sans+=("DNS.$dns_count = $san")
            fi
        done
    fi
    
    # Update the original array using indirect assignment
    eval "${array_name}=(\"\${merged_sans[@]}\")"
}
