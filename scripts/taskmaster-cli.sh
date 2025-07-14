#!/bin/bash
set -euo pipefail

# Taskmaster CLI Wrapper Script
# Provides a clean interface to the Taskmaster CLI with configuration management

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BIN_DIR="$REPO_ROOT/.taskmaster/bin"

# Configuration defaults
DEFAULT_COMPLEXITY_THRESHOLD="${COMPLEXITY_THRESHOLD:-40}"
DEFAULT_MAX_DEPTH="${MAX_DEPTH:-3}"
DEFAULT_OUTPUT_FORMAT="${OUTPUT_FORMAT:-json}"
DEFAULT_PRD_PATH="${PRD_PATH:-docs/initial-release.prd.md}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

# Find Taskmaster binary
find_taskmaster_binary() {
    local binary_name="taskmaster"
    
    # Check if Windows
    if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == CYGWIN* || "$(uname -s)" == MSYS* ]]; then
        binary_name="taskmaster.exe"
    fi
    
    local binary_paths=(
        "$BIN_DIR/$binary_name"
        "$SCRIPT_DIR/$binary_name"
        "$(command -v $binary_name 2>/dev/null || true)"
    )
    
    for path in "${binary_paths[@]}"; do
        if [[ -n "$path" && -x "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# Setup Taskmaster if not found
ensure_taskmaster() {
    local binary_path
    
    if binary_path=$(find_taskmaster_binary); then
        log_info "Found Taskmaster binary: $binary_path"
        echo "$binary_path"
        return 0
    fi
    
    log_warn "Taskmaster binary not found, attempting to download..."
    
    if [[ -f "$SCRIPT_DIR/setup-taskmaster.sh" ]]; then
        if "$SCRIPT_DIR/setup-taskmaster.sh"; then
            if binary_path=$(find_taskmaster_binary); then
                log_success "Successfully downloaded and setup Taskmaster binary"
                echo "$binary_path"
                return 0
            fi
        fi
    fi
    
    log_error "Failed to find or setup Taskmaster binary"
    return 1
}

# Parse PRD file and generate task graph
parse_prd() {
    local prd_file="$1"
    local output_file="${2:-task-graph.json}"
    local complexity_threshold="${3:-$DEFAULT_COMPLEXITY_THRESHOLD}"
    local max_depth="${4:-$DEFAULT_MAX_DEPTH}"
    local additional_args="${5:-}"
    
    log_info "Parsing PRD file: $prd_file"
    log_info "Output file: $output_file"
    log_info "Complexity threshold: $complexity_threshold"
    log_info "Max depth: $max_depth"
    
    local binary_path
    if ! binary_path=$(ensure_taskmaster); then
        log_error "Cannot proceed without Taskmaster binary"
        return 1
    fi
    
    # Validate input file
    if [[ ! -f "$prd_file" ]]; then
        log_error "PRD file not found: $prd_file"
        return 1
    fi
    
    # Prepare command arguments
    local cmd_args=(
        "$binary_path"
        "parse-prd"
        "--input" "$prd_file"
        "--output" "$output_file"
        "--complexity-threshold" "$complexity_threshold"
        "--max-depth" "$max_depth"
        "--format" "$DEFAULT_OUTPUT_FORMAT"
    )
    
    # Add additional arguments if provided
    if [[ -n "$additional_args" ]]; then
        # shellcheck disable=SC2086
        cmd_args+=($additional_args)
    fi
    
    log_info "Executing: ${cmd_args[*]}"
    
    # Execute command
    if "${cmd_args[@]}"; then
        log_success "PRD parsing completed successfully"
        
        # Validate output
        if [[ -f "$output_file" ]]; then
            if jq empty "$output_file" 2>/dev/null; then
                log_success "Generated valid JSON output: $output_file"
                return 0
            else
                log_error "Generated output is not valid JSON: $output_file"
                return 1
            fi
        else
            log_error "Expected output file was not created: $output_file"
            return 1
        fi
    else
        log_error "PRD parsing failed"
        return 1
    fi
}

# Expand specific task by ID
expand_task() {
    local task_id="$1"
    local output_file="${2:-task-graph-expanded.json}"
    local depth="${3:-2}"
    local threshold="${4:-$DEFAULT_COMPLEXITY_THRESHOLD}"
    
    log_info "Expanding task ID: $task_id"
    log_info "Output file: $output_file"
    log_info "Depth: $depth"
    log_info "Threshold: $threshold"
    
    local binary_path
    if ! binary_path=$(ensure_taskmaster); then
        log_error "Cannot proceed without Taskmaster binary"
        return 1
    fi
    
    # For now, use the mock implementation since we don't have the real CLI
    log_warn "Using mock task expansion (real CLI implementation needed)"
    
    cat > "$output_file" << EOF
{
  "version": "0.19.0",
  "expanded_task": "$task_id",
  "metadata": {
    "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "expansion_depth": $depth,
    "complexity_threshold": $threshold
  },
  "subtasks": [
    {
      "id": "${task_id}.1",
      "title": "Subtask 1 for Task $task_id",
      "description": "First subtask generated by expansion",
      "complexity": 20,
      "parent": "$task_id"
    },
    {
      "id": "${task_id}.2", 
      "title": "Subtask 2 for Task $task_id",
      "description": "Second subtask generated by expansion",
      "complexity": 25,
      "parent": "$task_id"
    }
  ]
}
EOF

    log_success "Task expansion completed (mock implementation)"
    return 0
}

# Validate task graph JSON
validate_task_graph() {
    local json_file="$1"
    
    log_info "Validating task graph: $json_file"
    
    if [[ ! -f "$json_file" ]]; then
        log_error "File not found: $json_file"
        return 1
    fi
    
    # Basic JSON validation
    if ! jq empty "$json_file" 2>/dev/null; then
        log_error "Invalid JSON format"
        return 1
    fi
    
    # Validate required fields
    local required_fields=("version" "tasks")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$json_file" >/dev/null 2>&1; then
            log_error "Missing required field: $field"
            return 1
        fi
    done
    
    log_success "Task graph validation passed"
    return 0
}

# Get CLI version
get_version() {
    local binary_path
    
    if binary_path=$(find_taskmaster_binary); then
        "$binary_path" --version 2>/dev/null || echo "Mock Taskmaster CLI v0.19.0"
    else
        echo "Taskmaster CLI not found"
        return 1
    fi
}

# Show help
show_help() {
    cat << EOF
Taskmaster CLI Wrapper

Usage: $0 <command> [options]

Commands:
  parse-prd <file> [output] [threshold] [depth] [args]
    Parse PRD file and generate task graph
    
  expand-task <task-id> [output] [depth] [threshold]
    Expand a specific task into subtasks
    
  validate <json-file>
    Validate task graph JSON format
    
  version
    Show Taskmaster CLI version
    
  setup
    Download and setup Taskmaster CLI binary
    
  help
    Show this help message

Environment Variables:
  COMPLEXITY_THRESHOLD  Default complexity threshold (default: 40)
  MAX_DEPTH            Default maximum depth (default: 3)
  OUTPUT_FORMAT        Output format (default: json)
  PRD_PATH            Default PRD file path

Examples:
  $0 parse-prd docs/my-project.prd.md
  $0 parse-prd docs/my-project.prd.md output.json 30 2
  $0 expand-task "1.2" expanded.json 1 35
  $0 validate task-graph.json
  $0 version

EOF
}

# Main function
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        parse-prd)
            if [[ $# -eq 0 ]]; then
                log_error "PRD file path required"
                echo "Usage: $0 parse-prd <file> [output] [threshold] [depth] [args]"
                exit 1
            fi
            parse_prd "$@"
            ;;
        expand-task)
            if [[ $# -eq 0 ]]; then
                log_error "Task ID required"
                echo "Usage: $0 expand-task <task-id> [output] [depth] [threshold]"
                exit 1
            fi
            expand_task "$@"
            ;;
        validate)
            if [[ $# -eq 0 ]]; then
                log_error "JSON file path required"
                echo "Usage: $0 validate <json-file>"
                exit 1
            fi
            validate_task_graph "$1"
            ;;
        version)
            get_version
            ;;
        setup)
            ensure_taskmaster >/dev/null
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi