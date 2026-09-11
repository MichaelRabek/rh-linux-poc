#!/bin/bash
# Build RPM with mock and replace it in an ISO file
# This script provides the same functionality as the Makefile but as a standalone tool

set -e

# Script directory
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions from vm-lib
VM_LIB="${DIR}/../../vm-lib"
source "${VM_LIB}/colors.sh"

# Build directories
BUILD_ROOT="${DIR}/build"
MOCK_ROOT="${BUILD_ROOT}/mock-root"
ISO_WORK_DIR="${BUILD_ROOT}/iso-work"
ISO_MOUNT_DIR="${BUILD_ROOT}/iso-mount"
ISO_OUTPUT_DIR="${BUILD_ROOT}/iso-output"

# Function to print display_help
display_help() {
    cat <<EOF
Usage: $0 [OPTIONS] [COMMAND]

Build RPM packages with mock and replace them in ISO files.

COMMANDS:
    build       Build RPM package only
    replace     Replace RPM in ISO only (requires prior build)
    clean       Clean build artifacts
    (default)   Build and replace (complete workflow if no command specified)

OPTIONS:
    -e, --mock-env ENV      Mock environment (e.g., fedora-43-x86_64)
    -s, --spec FILE         Spec file path
    -p, --package NAME      Package name
    -i, --iso FILE          ISO file path
    -l, --label LABEL       Custom ISO volume label
    -h, --help              Show this help message

EXAMPLES:
    # Build and replace (complete workflow)
    $0 -e fedora-43-x86_64 -s nvme-cli.spec -p nvme-cli -i /path/to/original.iso

    # Build RPM only
    $0 build -e fedora-43-x86_64 -s nvme-cli.spec -p nvme-cli

    # Replace in ISO only
    $0 replace -p nvme-cli -i /path/to/original.iso

    # Clean artifacts
    $0 clean
EOF
    exit 1
}

# Function to build RPM
build_rpm() {
    local mock_env="$1"
    local spec="$2"
    local package="$3"

    [ -z "$mock_env" ] && error "Mock environment not specified"
    [ -z "$spec" ] && error "Spec file not specified"
    [ -z "$package" ] && error "Package name not specified"
    [ ! -f "$spec" ] && error "Spec file not found: $spec"

    local results_dir="${BUILD_ROOT}/results/${package}"

    info "Building RPM package: $package"
    echo "Mock environment: $mock_env"
    echo "Spec file: $spec"

    mkdir -p "$MOCK_ROOT" "$results_dir"

    # Initialize mock environment if needed
    if [ ! -d "${MOCK_ROOT}/${mock_env}" ]; then
        warning "Initializing mock environment..."
        mock -r "$mock_env" --rootdir="${MOCK_ROOT}/${mock_env}" --init
    fi

    # Copy spec file
    cp "$spec" "$results_dir/"

    # Handle sources: use local if available, otherwise download from upstream
    echo "Preparing sources..."
    local has_local_sources=false

    # Copy any local source files if they exist (developer may have modified sources)
    if [ -d "$package" ] && [ -n "$(ls -A "$package" 2>/dev/null)" ]; then
        info "Found local source directory: $package/"
        cp -r "$package"/* "$results_dir/" 2>/dev/null || true
        has_local_sources=true
        echo "  Using local sources (may include developer modifications)"
    fi

    # Check if we need to download sources from spec file
    if ! $has_local_sources || [ -z "$(find "$results_dir" -name "*.tar.*" -o -name "*.tgz" -o -name "*.zip" 2>/dev/null)" ]; then
        echo "Downloading sources from upstream..."
        if command -v spectool &>/dev/null; then
            # Download missing sources only (spectool -g won't overwrite existing files)
            spectool -g -C "$results_dir" "$spec" 2>&1 | grep -v "File.*already exists" || true
        else
            warning "spectool not found - install rpmdevtools package"
            warning "Mock will attempt to download sources during build"
        fi
    else
        info "Using existing local sources"
    fi

    # Extract version for macro
    local pkg_version
    pkg_version=$(grep -E "^Version:" "$spec" | awk '{print $2}' | head -1)

    # Build SRPM
    warning "Building SRPM..."
    mock -r "$mock_env" \
        --rootdir="${MOCK_ROOT}/${mock_env}" \
        --resultdir="$results_dir" \
        --buildsrpm \
        --spec="${results_dir}/$(basename "$spec")" \
        --sources="$results_dir" \
        --define "version_no_tilde ${pkg_version//\~/-}"

    # Build RPM from SRPM
    warning "Building RPM from SRPM..."
    local srpm
    srpm=$(ls -t "$results_dir"/*.src.rpm 2>/dev/null | head -1)

    if [ -z "$srpm" ]; then
        error "SRPM not found"
    fi

    mock -r "$mock_env" \
        --rootdir="${MOCK_ROOT}/${mock_env}" \
        --resultdir="$results_dir" \
        --rebuild "$srpm" \
        --define "version_no_tilde ${pkg_version//\~/-}" \
        --define "dist .fc43"

    info "Build complete! RPMs available in: $results_dir"
    ls -lh "$results_dir"/*.rpm 2>/dev/null || true
}

# Function to extract ISO
extract_iso() {
    local iso="$1"

    [ -z "$iso" ] && error "ISO file not specified"
    [ ! -f "$iso" ] && error "ISO file not found: $iso"

    info "Extracting ISO: $iso"

    mkdir -p "$ISO_WORK_DIR" "$ISO_MOUNT_DIR"

    # Unmount if already mounted
    if mountpoint -q "$ISO_MOUNT_DIR" 2>/dev/null; then
        warning "Unmounting existing mount..."
        sudo umount "$ISO_MOUNT_DIR"
    fi

    # Mount the ISO
    warning "Mounting ISO..."
    sudo mount -o loop,ro "$iso" "$ISO_MOUNT_DIR"

    # Copy ISO contents
    warning "Copying ISO contents..."
    rm -rf "${ISO_WORK_DIR:?}"/*
    sudo cp -aT "$ISO_MOUNT_DIR" "$ISO_WORK_DIR"
    sudo umount "$ISO_MOUNT_DIR"

    # Make files writable
    sudo chmod -R u+w "$ISO_WORK_DIR"
    sudo chown -R "$USER:$USER" "$ISO_WORK_DIR"

    info "ISO extracted to: $ISO_WORK_DIR"
}

# Function to replace RPM in extracted ISO
replace_rpm() {
    local package="$1"

    [ -z "$package" ] && error "Package name not specified"

    local results_dir="${BUILD_ROOT}/results/${package}"
    [ ! -d "$results_dir" ] && error "Build results not found. Run build command first."

    info "Replacing $package RPMs in ISO"

    # Find RPM packages
    local rpms
    rpms=$(find "$results_dir" -name "${package}-[0-9]*.rpm" \
        -not -name "*.src.rpm" \
        -not -name "*-debuginfo-*" \
        -not -name "*-debugsource-*")

    [ -z "$rpms" ] && error "No RPM packages found for $package"

    # Replace each RPM
    while IFS= read -r rpm; do
        local rpm_name
        rpm_name=$(basename "$rpm")
        warning "Processing: $rpm_name"

        local pkg_basename
        pkg_basename=$(rpm -qp --queryformat '%{NAME}' "$rpm" 2>/dev/null)
        echo "  Package basename: $pkg_basename"

        # Remove old RPMs
        local old_rpms
        old_rpms=$(find "$ISO_WORK_DIR" -name "${pkg_basename}-[0-9]*.rpm" 2>/dev/null || true)

        if [ -n "$old_rpms" ]; then
            while IFS= read -r old_rpm; do
                echo "  Removing old: $(basename "$old_rpm")"
                rm -f "$old_rpm"
            done <<< "$old_rpms"
        fi

        # Find RPM directory in ISO
        local rpm_dir
        rpm_dir=$(find "$ISO_WORK_DIR" -type d \( -name "Packages" -o -name "BaseOS" -o -name "AppStream" \) 2>/dev/null | head -1)

        if [ -z "$rpm_dir" ]; then
            rpm_dir=$(find "$ISO_WORK_DIR" -type f -name "*.rpm" -exec dirname {} \; 2>/dev/null | head -1)
        fi

        if [ -n "$rpm_dir" ]; then
            echo "  Copying to: $rpm_dir"
            cp "$rpm" "$rpm_dir/"
        else
            warning "  Could not find RPM directory in ISO"
        fi
    done <<< "$rpms"

    # Update repository metadata
    warning "Updating repository metadata..."
    local repo_dirs
    repo_dirs=$(find "$ISO_WORK_DIR" -type d -name "repodata" -exec dirname {} \; 2>/dev/null || true)

    if [ -n "$repo_dirs" ]; then
        while IFS= read -r repo_dir; do
            echo "  Updating: $repo_dir"
            rm -rf "$repo_dir/repodata"
            createrepo_c "$repo_dir"
        done <<< "$repo_dirs"
    fi

    info "RPM replacement complete"
}

# Function to repack ISO
repack_iso() {
    local iso="$1"
    local iso_label="${2:-}"

    [ -z "$iso" ] && error "ISO file not specified"
    [ ! -f "$iso" ] && error "ISO file not found: $iso"

    info "Repacking ISO"

    mkdir -p "$ISO_OUTPUT_DIR"

    # Detect ISO label
    if [ -z "$iso_label" ]; then
        iso_label=$(isoinfo -d -i "$iso" 2>/dev/null | grep "Volume id:" | cut -d: -f2 | xargs || echo "MODIFIED_ISO")
    fi

    echo "ISO Label: $iso_label"

    local output_iso="${ISO_OUTPUT_DIR}/$(basename "$iso" .iso)-modified.iso"
    echo "Output ISO: $output_iso"

    # Create bootable ISO based on detected boot method
    if [ -f "$ISO_WORK_DIR/isolinux/isolinux.bin" ]; then
        warning "Creating bootable ISO (BIOS)..."
        genisoimage -o "$output_iso" \
            -b isolinux/isolinux.bin \
            -c isolinux/boot.cat \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            -J -R -V "$iso_label" \
            "$ISO_WORK_DIR"

        isohybrid "$output_iso" 2>/dev/null || true
    elif [ -f "$ISO_WORK_DIR/images/efiboot.img" ]; then
        warning "Creating bootable ISO (UEFI)..."
        xorriso -as mkisofs \
            -o "$output_iso" \
            -V "$iso_label" \
            -J -R \
            -e images/efiboot.img \
            -no-emul-boot \
            "$ISO_WORK_DIR"
    else
        warning "Creating non-bootable ISO..."
        genisoimage -o "$output_iso" \
            -J -R -V "$iso_label" \
            "$ISO_WORK_DIR"
    fi

    if [ -f "$output_iso" ]; then
        info "ISO created successfully: $output_iso"
        ls -lh "$output_iso"
    else
        error "Failed to create ISO"
    fi
}

# Function to clean build artifacts
clean_all() {
    info "Cleaning all build artifacts..."

    if mountpoint -q "$ISO_MOUNT_DIR" 2>/dev/null; then
        sudo umount "$ISO_MOUNT_DIR"
    fi

    rm -rf "$BUILD_ROOT"
    info "All artifacts cleaned"
}

# Main script logic
main() {
    local command=""
    local mock_env=""
    local spec=""
    local package=""
    local iso=""
    local iso_label=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            build|replace|clean)
                command="$1"
                shift
                ;;
            -e|--mock-env)
                mock_env="$2"
                shift 2
                ;;
            -s|--spec)
                spec="$2"
                shift 2
                ;;
            -p|--package)
                package="$2"
                shift 2
                ;;
            -i|--iso)
                iso="$2"
                shift 2
                ;;
            -l|--label)
                iso_label="$2"
                shift 2
                ;;
            -h|--help)
                display_help
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    # Default to full workflow if no command specified
    [ -z "$command" ] && command="all"

    # Change to script directory
    cd "$DIR"

    # Execute command
    case $command in
        build)
            build_rpm "$mock_env" "$spec" "$package"
            ;;
        replace)
            extract_iso "$iso"
            replace_rpm "$package"
            repack_iso "$iso" "$iso_label"
            info "ISO modification complete!"
            ;;
        all)
            build_rpm "$mock_env" "$spec" "$package"
            extract_iso "$iso"
            replace_rpm "$package"
            repack_iso "$iso" "$iso_label"
            info "All tasks completed successfully!"
            ;;
        clean)
            clean_all
            ;;
        *)
            error "Unknown command: $command"
            ;;
    esac
}

# Run main function
main "$@"
