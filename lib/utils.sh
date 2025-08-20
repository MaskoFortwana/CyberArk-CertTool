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
