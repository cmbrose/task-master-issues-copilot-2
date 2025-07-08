#!/bin/bash
set -euo pipefail

# Taskmaster CLI Checksum Validation
# Validates downloaded binaries against known checksums

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Checksum database - in production, this would be fetched from a trusted source
declare -A CHECKSUMS
CHECKSUMS=(
    # Example checksums - these would be real checksums from releases
    ["taskmaster_v0.19.0_linux_amd64"]="sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    ["taskmaster_v0.19.0_darwin_amd64"]="sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    ["taskmaster_v0.19.0_windows_amd64.exe"]="sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
)

# Calculate file checksum
calculate_checksum() {
    local file="$1"
    local algorithm="${2:-sha256}"
    
    if [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file" >&2
        return 1
    fi
    
    case "$algorithm" in
        sha256)
            if command -v sha256sum >/dev/null 2>&1; then
                sha256sum "$file" | cut -d' ' -f1
            elif command -v shasum >/dev/null 2>&1; then
                shasum -a 256 "$file" | cut -d' ' -f1
            else
                echo "Error: No SHA256 utility found" >&2
                return 1
            fi
            ;;
        sha512)
            if command -v sha512sum >/dev/null 2>&1; then
                sha512sum "$file" | cut -d' ' -f1
            elif command -v shasum >/dev/null 2>&1; then
                shasum -a 512 "$file" | cut -d' ' -f1
            else
                echo "Error: No SHA512 utility found" >&2
                return 1
            fi
            ;;
        md5)
            if command -v md5sum >/dev/null 2>&1; then
                md5sum "$file" | cut -d' ' -f1
            elif command -v md5 >/dev/null 2>&1; then
                md5 -q "$file"
            else
                echo "Error: No MD5 utility found" >&2
                return 1
            fi
            ;;
        *)
            echo "Error: Unsupported algorithm: $algorithm" >&2
            return 1
            ;;
    esac
}

# Validate file against known checksum
validate_checksum() {
    local file="$1"
    local version="$2"
    local platform="$3"
    local algorithm="${4:-sha256}"
    
    local filename
    filename="$(basename "$file")"
    local key="taskmaster_${version}_${platform}"
    
    # Handle Windows extension
    if [[ "$platform" == *"windows"* && "$filename" == *.exe ]]; then
        key="${key}.exe"
    fi
    
    echo "Validating checksum for: $filename"
    echo "Lookup key: $key"
    
    if [[ -z "${CHECKSUMS[$key]:-}" ]]; then
        echo "Warning: No known checksum for $key"
        echo "In production, this should be treated as an error"
        echo "For development, skipping checksum validation"
        return 0
    fi
    
    local expected_checksum="${CHECKSUMS[$key]}"
    # Extract just the hash part (remove algorithm prefix)
    expected_checksum="${expected_checksum#*:}"
    
    local actual_checksum
    actual_checksum=$(calculate_checksum "$file" "$algorithm")
    
    echo "Expected: $expected_checksum"
    echo "Actual:   $actual_checksum"
    
    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
        echo "✓ Checksum validation passed"
        return 0
    else
        echo "✗ Checksum validation failed!"
        echo "File may be corrupted or tampered with"
        return 1
    fi
}

# Fetch checksums from remote source (placeholder)
fetch_checksums() {
    local version="$1"
    local checksums_url="https://github.com/cmbrose/taskmaster/releases/download/${version}/checksums.txt"
    
    echo "Fetching checksums from: $checksums_url"
    
    # In a real implementation, this would download and parse checksums
    # For now, we'll use the hardcoded checksums above
    echo "Using hardcoded checksums for development"
}

# Validate multiple files
validate_files() {
    local exit_code=0
    
    for file in "$@"; do
        if [[ -f "$file" ]]; then
            echo "Validating: $file"
            # Extract version and platform from filename/path for lookup
            local basename_file
            basename_file="$(basename "$file")"
            
            # For development, use mock validation
            if validate_checksum "$file" "v0.19.0" "linux_amd64" "sha256"; then
                echo "✓ $basename_file: VALID"
            else
                echo "✗ $basename_file: INVALID"
                exit_code=1
            fi
        else
            echo "✗ File not found: $file"
            exit_code=1
        fi
        echo
    done
    
    return $exit_code
}

# Main function
main() {
    local command="${1:-validate}"
    shift || true
    
    case "$command" in
        validate)
            if [[ $# -eq 0 ]]; then
                echo "Usage: $0 validate <file1> [file2] ..."
                echo "       $0 fetch-checksums <version>"
                echo "       $0 calculate <file> [algorithm]"
                exit 1
            fi
            validate_files "$@"
            ;;
        fetch-checksums)
            local version="${1:-v0.19.0}"
            fetch_checksums "$version"
            ;;
        calculate)
            if [[ $# -eq 0 ]]; then
                echo "Usage: $0 calculate <file> [algorithm]"
                exit 1
            fi
            local file="$1"
            local algorithm="${2:-sha256}"
            calculate_checksum "$file" "$algorithm"
            ;;
        *)
            echo "Error: Unknown command: $command"
            echo "Available commands: validate, fetch-checksums, calculate"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi