#!/bin/bash

# Debian Package Installer Builder
# Usage: ./build_deb.sh <deps_directory> <package_name> [version] [description]

set -e  # Exit on any error

# Default values
DEFAULT_VERSION="1.0.0"
DEFAULT_MAINTAINER="$(whoami) <$(whoami)@$(hostname)>"
DEFAULT_ARCHITECTURE="amd64"
DEFAULT_SECTION="misc"
DEFAULT_PRIORITY="optional"

# Function to display usage
usage() {
    echo "Usage: $0 <deps_directory> <package_name> [version] [description]"
    echo ""
    echo "Arguments:"
    echo "  deps_directory: Directory containing the gathered dependencies"
    echo "  package_name: Name of the package (lowercase, no spaces)"
    echo "  version: Package version (default: $DEFAULT_VERSION)"
    echo "  description: Package description (default: auto-generated)"
    echo ""
    echo "Examples:"
    echo "  $0 /tmp/firefox_deps my-firefox-bundle"
    echo "  $0 /tmp/app_deps my-app 2.1.0 'My custom application bundle'"
    echo ""
    echo "The script will create a .deb package with all dependencies included."
    exit 1
}

# Function to validate package name
validate_package_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9+.-]*$ ]]; then
        echo "Error: Package name must be lowercase and contain only letters, numbers, hyphens, periods, and plus signs"
        echo "Invalid name: $name"
        exit 1
    fi
}

# Function to detect architecture
detect_architecture() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;;
        i386|i686) echo "i386" ;;
        armv7*) echo "armhf" ;;
        aarch64) echo "arm64" ;;
        *) echo "all" ;;
    esac
}

# Function to find the main executable
find_main_executable() {
    local deps_dir="$1"
    local executables=()
    
    # Look for executables in common directories
    for dir in "$deps_dir/usr/bin" "$deps_dir/bin" "$deps_dir/usr/local/bin"; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r -d '' file; do
                if [[ -x "$file" && -f "$file" ]]; then
                    executables+=("$file")
                fi
            done < <(find "$dir" -type f -executable -print0 2>/dev/null)
        fi
    done
    
    # Return the first executable found, or empty if none
    if [[ ${#executables[@]} -gt 0 ]]; then
        echo "${executables[0]}"
    fi
}

# Function to create postinst script
create_postinst() {
    local package_dir="$1"
    local main_exe="$2"
    
    cat > "$package_dir/DEBIAN/postinst" << 'EOF'
#!/bin/bash
# Post-installation script

set -e

# Update ldconfig cache to recognize new libraries
if command -v ldconfig >/dev/null 2>&1; then
    ldconfig
fi

# Create desktop entry if we have a GUI application
MAIN_EXE="__MAIN_EXE__"
PACKAGE_NAME="__PACKAGE_NAME__"

if [[ -n "$MAIN_EXE" && -f "$MAIN_EXE" ]]; then
    # Check if it's a GUI application (very basic check)
    if ldd "$MAIN_EXE" 2>/dev/null | grep -q -E "(gtk|qt|X11|wayland)"; then
        DESKTOP_FILE="/usr/share/applications/${PACKAGE_NAME}.desktop"
        
        # Create desktop entry if it doesn't exist
        if [[ ! -f "$DESKTOP_FILE" ]]; then
            mkdir -p /usr/share/applications
            cat > "$DESKTOP_FILE" << EOD
[Desktop Entry]
Version=1.0
Type=Application
Name=${PACKAGE_NAME}
Comment=Bundled application with dependencies
Exec=${MAIN_EXE}
Terminal=false
Categories=Application;
EOD
            echo "Created desktop entry: $DESKTOP_FILE"
        fi
    fi
fi

echo "Installation completed successfully!"
echo "Package: $PACKAGE_NAME"
if [[ -n "$MAIN_EXE" ]]; then
    echo "Main executable: $MAIN_EXE"
fi

exit 0
EOF

    # Replace placeholders
    sed -i "s|__MAIN_EXE__|$main_exe|g" "$package_dir/DEBIAN/postinst"
    sed -i "s|__PACKAGE_NAME__|$(basename "$package_dir")|g" "$package_dir/DEBIAN/postinst"
    
    chmod 755 "$package_dir/DEBIAN/postinst"
}

# Function to create prerm script
create_prerm() {
    local package_dir="$1"
    local package_name="$2"
    
    cat > "$package_dir/DEBIAN/prerm" << EOF
#!/bin/bash
# Pre-removal script

set -e

# Remove desktop entry if it exists
DESKTOP_FILE="/usr/share/applications/${package_name}.desktop"
if [[ -f "\$DESKTOP_FILE" ]]; then
    rm -f "\$DESKTOP_FILE"
    echo "Removed desktop entry: \$DESKTOP_FILE"
fi

exit 0
EOF

    chmod 755 "$package_dir/DEBIAN/prerm"
}

# Function to calculate installed size
calculate_size() {
    local dir="$1"
    du -sk "$dir" | cut -f1
}

# Function to create control file
create_control_file() {
    local package_dir="$1"
    local package_name="$2"
    local version="$3"
    local description="$4"
    local deps_dir="$5"
    
    local arch
    arch=$(detect_architecture)
    
    local size
    size=$(calculate_size "$deps_dir")
    
    # Create DEBIAN directory
    mkdir -p "$package_dir/DEBIAN"
    
    # Create control file
    cat > "$package_dir/DEBIAN/control" << EOF
Package: $package_name
Version: $version
Section: $DEFAULT_SECTION
Priority: $DEFAULT_PRIORITY
Architecture: $arch
Installed-Size: $size
Maintainer: $DEFAULT_MAINTAINER
Description: $description
 This package contains a bundled application with all its dependencies
 included to ensure compatibility across different systems.
 .
 Generated automatically by debian package builder script.
EOF

    echo "Created control file with package info:"
    echo "  Name: $package_name"
    echo "  Version: $version"
    echo "  Architecture: $arch"
    echo "  Size: ${size}KB"
}

# Function to create copyright file
create_copyright() {
    local package_dir="$1"
    local package_name="$2"
    
    mkdir -p "$package_dir/usr/share/doc/$package_name"
    
    cat > "$package_dir/usr/share/doc/$package_name/copyright" << EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: $package_name
Source: Generated by dependency bundler

Files: *
Copyright: $(date +%Y) $DEFAULT_MAINTAINER
License: Custom
 This package bundles an application with its dependencies.
 Individual components may have their own licenses.
 Please refer to the original software documentation for
 specific license information.
EOF
}

# Function to create changelog
create_changelog() {
    local package_dir="$1"
    local package_name="$2"
    local version="$3"
    
    mkdir -p "$package_dir/usr/share/doc/$package_name"
    
    cat > "$package_dir/usr/share/doc/$package_name/changelog.Debian" << EOF
$package_name ($version) unstable; urgency=low

  * Initial package creation with bundled dependencies
  * Automatically generated from dependency gatherer

 -- $DEFAULT_MAINTAINER  $(date -R)
EOF

    # Compress changelog
    gzip -9 "$package_dir/usr/share/doc/$package_name/changelog.Debian"
}

# Main function
main() {
    # Check arguments
    if [[ $# -lt 2 || $# -gt 4 ]]; then
        usage
    fi
    
    local deps_dir="$1"
    local package_name="$2"
    local version="${3:-$DEFAULT_VERSION}"
    local description="${4:-Bundled application with dependencies for $package_name}"
    
    # Validate inputs
    if [[ ! -d "$deps_dir" ]]; then
        echo "Error: Dependencies directory '$deps_dir' not found!"
        exit 1
    fi
    
    validate_package_name "$package_name"
    
    # Check for required tools
    for tool in dpkg-deb fakeroot; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "Error: Required tool '$tool' not found!"
            echo "Please install it with: sudo apt-get install dpkg-dev fakeroot"
            exit 1
        fi
    done
    
    echo "Building Debian package..."
    echo "Package name: $package_name"
    echo "Version: $version"
    echo "Dependencies directory: $deps_dir"
    echo ""
    
    # Create temporary package directory
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    local package_dir="$temp_dir/$package_name"
    mkdir -p "$package_dir"
    
    # Copy all dependencies to package directory
    echo "Copying dependencies..."
    cp -a "$deps_dir"/* "$package_dir/"
    
    # Find main executable
    local main_exe
    main_exe=$(find_main_executable "$package_dir")
    if [[ -n "$main_exe" ]]; then
        # Convert absolute path to relative to package root
        main_exe="${main_exe#$package_dir}"
        echo "Detected main executable: $main_exe"
    fi
    
    # Create package metadata
    echo "Creating package metadata..."
    create_control_file "$package_dir" "$package_name" "$version" "$description" "$deps_dir"
    create_postinst "$package_dir" "$main_exe"
    create_prerm "$package_dir" "$package_name"
    create_copyright "$package_dir" "$package_name"
    create_changelog "$package_dir" "$package_name" "$version"
    
    # Build the package
    local output_file="${package_name}_${version}_$(detect_architecture).deb"
    echo ""
    echo "Building package: $output_file"
    
    # Use fakeroot to build as non-root user
    if ! fakeroot dpkg-deb --build "$package_dir" "$output_file"; then
        echo "Error: Failed to build package"
        exit 1
    fi
    
    # Verify the package
    echo ""
    echo "Package built successfully!"
    echo "File: $output_file"
    echo "Size: $(du -h "$output_file" | cut -f1)"
    echo ""
    
    # Show package info
    echo "Package information:"
    dpkg-deb --info "$output_file"
    
    echo ""
    echo "Package contents:"
    dpkg-deb --contents "$output_file" | head -20
    
    if [[ $(dpkg-deb --contents "$output_file" | wc -l) -gt 20 ]]; then
        echo "... ($(dpkg-deb --contents "$output_file" | wc -l) total files)"
    fi
    
    echo ""
    echo "Installation command:"
    echo "  sudo dpkg -i $output_file"
    echo ""
    echo "If there are dependency issues, run:"
    echo "  sudo apt-get install -f"
}

# Run main function
main "$@"
