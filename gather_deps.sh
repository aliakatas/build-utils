#!/bin/bash

# Binary Dependency Gatherer Script
# Usage: ./gather_deps.sh <binary_file> <output_directory>

set -e  # Exit on any error

# Function to display usage
usage() {
    echo "Usage: $0 <binary_file> <output_directory>"
    echo "  binary_file: Path to the executable or shared library"
    echo "  output_directory: Directory where dependencies will be copied"
    echo ""
    echo "Example: $0 /usr/bin/firefox /tmp/firefox_deps"
    exit 1
}

# Function to check if a file is a valid binary
is_binary() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    # Check if it's an ELF file
    if file "$file" | grep -q "ELF"; then
        return 0
    fi
    return 1
}

# Function to resolve symlinks and get the real path
resolve_path() {
    local path="$1"
    if [[ -L "$path" ]]; then
        readlink -f "$path"
    else
        echo "$path"
    fi
}

# Function to copy file preserving directory structure
copy_with_structure() {
    local src="$1"
    local dest_base="$2"
    local dest_path="$dest_base$src"
    
    # Create destination directory
    mkdir -p "$(dirname "$dest_path")"
    
    # Copy the file if it doesn't exist or is different
    if [[ ! -f "$dest_path" ]] || ! cmp -s "$src" "$dest_path"; then
        cp "$src" "$dest_path"
        echo "Copied: $src -> $dest_path"
    fi
}

# Function to gather dependencies recursively
gather_deps() {
    local binary="$1"
    local output_dir="$2"
    local processed_file="$3"
    
    # Skip if already processed
    if grep -Fxq "$binary" "$processed_file" 2>/dev/null; then
        return
    fi
    
    # Mark as processed
    echo "$binary" >> "$processed_file"
    
    # Get dependencies using ldd
    local deps
    if ! deps=$(ldd "$binary" 2>/dev/null); then
        # If ldd fails, try with objdump for static binaries
        echo "Warning: ldd failed for $binary, checking if it's statically linked..."
        if objdump -p "$binary" 2>/dev/null | grep -q "NEEDED"; then
            echo "Error: Could not analyze dependencies for $binary"
            return 1
        else
            echo "Note: $binary appears to be statically linked"
            return 0
        fi
    fi
    
    # Parse ldd output and extract library paths
    while IFS= read -r line; do
        # Skip virtual DSO entries
        if [[ "$line" == *"linux-vdso.so"* ]] || [[ "$line" == *"ld-linux"* ]]; then
            continue
        fi
        
        # Extract library path
        local lib_path=""
        if [[ "$line" =~ ^[[:space:]]*([^[:space:]]+)[[:space:]]*=\>[[:space:]]*([^[:space:]]+) ]]; then
            # Format: libname => /path/to/lib
            lib_path="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^[[:space:]]*(/[^[:space:]]+) ]]; then
            # Format: /path/to/lib (address)
            lib_path="${BASH_REMATCH[1]}"
        fi
        
        # Process valid library paths
        if [[ -n "$lib_path" && -f "$lib_path" ]]; then
            # Resolve symlinks
            local real_path
            real_path=$(resolve_path "$lib_path")
            
            # Copy the library
            copy_with_structure "$real_path" "$output_dir"
            
            # Also copy the symlink if it's different from the real path
            if [[ "$lib_path" != "$real_path" ]]; then
                copy_with_structure "$lib_path" "$output_dir"
            fi
            
            # Recursively process this library's dependencies
            gather_deps "$real_path" "$output_dir" "$processed_file"
        fi
    done <<< "$deps"
}

# Main script
main() {
    # Check arguments
    if [[ $# -ne 2 ]]; then
        usage
    fi
    
    local binary_file="$1"
    local output_dir="$2"
    
    # Validate input binary
    if [[ ! -f "$binary_file" ]]; then
        echo "Error: Binary file '$binary_file' not found!"
        exit 1
    fi
    
    if ! is_binary "$binary_file"; then
        echo "Error: '$binary_file' is not a valid binary file!"
        exit 1
    fi
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Resolve binary path
    local binary_path
    binary_path=$(resolve_path "$binary_file")
    
    echo "Gathering dependencies for: $binary_path"
    echo "Output directory: $output_dir"
    echo ""
    
    # Copy the main binary
    copy_with_structure "$binary_path" "$output_dir"
    if [[ "$binary_file" != "$binary_path" ]]; then
        copy_with_structure "$binary_file" "$output_dir"
    fi
    
    # Create temporary file to track processed binaries
    local temp_file
    temp_file=$(mktemp)
    trap "rm -f $temp_file" EXIT
    
    # Gather all dependencies
    gather_deps "$binary_path" "$output_dir" "$temp_file"
    
    echo ""
    echo "Dependency gathering complete!"
    echo "All files copied to: $output_dir"
    
    # Show summary
    local total_files
    total_files=$(find "$output_dir" -type f | wc -l)
    echo "Total files copied: $total_files"
    
    # Create a simple manifest
    local manifest="$output_dir/MANIFEST.txt"
    echo "Dependency manifest for: $binary_path" > "$manifest"
    echo "Generated on: $(date)" >> "$manifest"
    echo "Files:" >> "$manifest"
    find "$output_dir" -type f ! -name "MANIFEST.txt" | sort >> "$manifest"
    echo "Manifest created: $manifest"
}

# Run main function
main "$@"
