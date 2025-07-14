#!/bin/bash
set -euo pipefail

# Taskmaster Configuration Management
# Handles configuration parameters, validation, and persistence

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$REPO_ROOT/.taskmaster"
CONFIG_FILE="$CONFIG_DIR/action-config.json"

# Default configuration values
declare -A DEFAULT_CONFIG=(
    ["complexity_threshold"]="40"
    ["max_depth"]="3"
    ["breakdown_max_depth"]="2"
    ["prd_path_glob"]="docs/**.prd.md"
    ["output_format"]="json"
    ["taskmaster_version"]="v0.19.0"
    ["taskmaster_repo"]="cmbrose/taskmaster"
    ["cache_enabled"]="true"
    ["validation_enabled"]="true"
    ["debug_mode"]="false"
)

# Configuration validation rules
declare -A VALIDATION_RULES=(
    ["complexity_threshold"]="integer:1:100"
    ["max_depth"]="integer:1:10"
    ["breakdown_max_depth"]="integer:1:5"
    ["prd_path_glob"]="string:nonempty"
    ["output_format"]="enum:json,yaml,xml"
    ["taskmaster_version"]="string:nonempty"
    ["taskmaster_repo"]="string:nonempty"
    ["cache_enabled"]="boolean"
    ["validation_enabled"]="boolean"
    ["debug_mode"]="boolean"
)

# Logging functions
log_info() {
    echo "[INFO] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

# Validate a single configuration value
validate_value() {
    local key="$1"
    local value="$2"
    local rule="${VALIDATION_RULES[$key]:-}"
    
    if [[ -z "$rule" ]]; then
        log_warn "No validation rule for key: $key"
        return 0
    fi
    
    local rule_type="${rule%%:*}"
    local rule_params="${rule#*:}"
    
    case "$rule_type" in
        integer)
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                log_error "Value '$value' for '$key' must be an integer"
                return 1
            fi
            
            if [[ "$rule_params" == *":"* ]]; then
                local min="${rule_params%%:*}"
                local max="${rule_params#*:}"
                
                if [[ "$value" -lt "$min" || "$value" -gt "$max" ]]; then
                    log_error "Value '$value' for '$key' must be between $min and $max"
                    return 1
                fi
            fi
            ;;
        string)
            case "$rule_params" in
                nonempty)
                    if [[ -z "$value" ]]; then
                        log_error "Value for '$key' cannot be empty"
                        return 1
                    fi
                    ;;
            esac
            ;;
        enum)
            local valid_values="${rule_params//,/ }"
            if [[ ! " $valid_values " =~ " $value " ]]; then
                log_error "Value '$value' for '$key' must be one of: $rule_params"
                return 1
            fi
            ;;
        boolean)
            if [[ ! "$value" =~ ^(true|false|yes|no|1|0)$ ]]; then
                log_error "Value '$value' for '$key' must be a boolean (true/false/yes/no/1/0)"
                return 1
            fi
            ;;
        *)
            log_warn "Unknown validation rule type: $rule_type"
            ;;
    esac
    
    return 0
}

# Normalize boolean values
normalize_boolean() {
    local value="$1"
    
    case "${value,,}" in  # Convert to lowercase
        true|yes|1) echo "true" ;;
        false|no|0) echo "false" ;;
        *) echo "$value" ;;
    esac
}

# Initialize configuration file with defaults
init_config() {
    mkdir -p "$CONFIG_DIR"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Configuration file already exists: $CONFIG_FILE"
        return 0
    fi
    
    log_info "Creating default configuration file: $CONFIG_FILE"
    
    cat > "$CONFIG_FILE" << EOF
{
  "_comment": "Taskmaster Action Configuration",
  "_generated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "complexity_threshold": ${DEFAULT_CONFIG["complexity_threshold"]},
  "max_depth": ${DEFAULT_CONFIG["max_depth"]},
  "breakdown_max_depth": ${DEFAULT_CONFIG["breakdown_max_depth"]},
  "prd_path_glob": "${DEFAULT_CONFIG["prd_path_glob"]}",
  "output_format": "${DEFAULT_CONFIG["output_format"]}",
  "taskmaster_version": "${DEFAULT_CONFIG["taskmaster_version"]}",
  "taskmaster_repo": "${DEFAULT_CONFIG["taskmaster_repo"]}",
  "cache_enabled": ${DEFAULT_CONFIG["cache_enabled"]},
  "validation_enabled": ${DEFAULT_CONFIG["validation_enabled"]},
  "debug_mode": ${DEFAULT_CONFIG["debug_mode"]}
}
EOF
    
    log_info "Configuration file created successfully"
}

# Get configuration value
get_config() {
    local key="$1"
    local default_value="${2:-}"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        init_config
    fi
    
    # Try to get value from JSON file
    local value
    if value=$(jq -r ".$key // empty" "$CONFIG_FILE" 2>/dev/null); then
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
            return 0
        fi
    fi
    
    # Fall back to default
    if [[ -n "$default_value" ]]; then
        echo "$default_value"
    elif [[ -n "${DEFAULT_CONFIG[$key]:-}" ]]; then
        echo "${DEFAULT_CONFIG[$key]}"
    else
        log_error "No value or default found for key: $key"
        return 1
    fi
}

# Set configuration value
set_config() {
    local key="$1"
    local value="$2"
    local validate="${3:-true}"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        init_config
    fi
    
    # Validate value if requested
    if [[ "$validate" == "true" ]]; then
        if ! validate_value "$key" "$value"; then
            return 1
        fi
    fi
    
    # Normalize boolean values
    if [[ "${VALIDATION_RULES[$key]:-}" == "boolean" ]]; then
        value=$(normalize_boolean "$value")
    fi
    
    log_info "Setting configuration: $key = $value"
    
    # Update JSON file using jq
    local temp_file
    temp_file=$(mktemp)
    
    if jq ".$key = \"$value\"" "$CONFIG_FILE" > "$temp_file"; then
        mv "$temp_file" "$CONFIG_FILE"
        log_info "Configuration updated successfully"
    else
        rm -f "$temp_file"
        log_error "Failed to update configuration"
        return 1
    fi
}

# Load configuration from environment variables
load_env_config() {
    log_info "Loading configuration from environment variables"
    
    # Map environment variables to config keys
    declare -A ENV_MAP=(
        ["COMPLEXITY_THRESHOLD"]="complexity_threshold"
        ["MAX_DEPTH"]="max_depth"
        ["BREAKDOWN_MAX_DEPTH"]="breakdown_max_depth"
        ["PRD_PATH_GLOB"]="prd_path_glob"
        ["OUTPUT_FORMAT"]="output_format"
        ["TASKMASTER_VERSION"]="taskmaster_version"
        ["TASKMASTER_REPO"]="taskmaster_repo"
        ["CACHE_ENABLED"]="cache_enabled"
        ["VALIDATION_ENABLED"]="validation_enabled"
        ["DEBUG_MODE"]="debug_mode"
    )
    
    local updated=false
    
    for env_var in "${!ENV_MAP[@]}"; do
        local config_key="${ENV_MAP[$env_var]}"
        local env_value="${!env_var:-}"
        
        if [[ -n "$env_value" ]]; then
            log_info "Found environment variable: $env_var = $env_value"
            if set_config "$config_key" "$env_value" true; then
                updated=true
            fi
        fi
    done
    
    if [[ "$updated" == "true" ]]; then
        log_info "Configuration updated from environment variables"
    else
        log_info "No environment variables found to update configuration"
    fi
}

# Export configuration to environment variables
export_env_config() {
    log_info "Exporting configuration to environment variables"
    
    declare -A EXPORT_MAP=(
        ["complexity_threshold"]="COMPLEXITY_THRESHOLD"
        ["max_depth"]="MAX_DEPTH"
        ["breakdown_max_depth"]="BREAKDOWN_MAX_DEPTH"
        ["prd_path_glob"]="PRD_PATH_GLOB"
        ["output_format"]="OUTPUT_FORMAT"
        ["taskmaster_version"]="TASKMASTER_VERSION"
        ["taskmaster_repo"]="TASKMASTER_REPO"
        ["cache_enabled"]="CACHE_ENABLED"
        ["validation_enabled"]="VALIDATION_ENABLED"
        ["debug_mode"]="DEBUG_MODE"
    )
    
    for config_key in "${!EXPORT_MAP[@]}"; do
        local env_var="${EXPORT_MAP[$config_key]}"
        local value
        
        if value=$(get_config "$config_key"); then
            export "$env_var=$value"
            echo "export $env_var=\"$value\""
        fi
    done
}

# Validate entire configuration
validate_config() {
    log_info "Validating configuration file: $CONFIG_FILE"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found"
        return 1
    fi
    
    # Validate JSON syntax
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        log_error "Configuration file contains invalid JSON"
        return 1
    fi
    
    local exit_code=0
    
    # Validate each configuration key
    for key in "${!DEFAULT_CONFIG[@]}"; do
        local value
        if value=$(get_config "$key"); then
            if ! validate_value "$key" "$value"; then
                exit_code=1
            fi
        else
            log_error "Missing configuration key: $key"
            exit_code=1
        fi
    done
    
    if [[ $exit_code -eq 0 ]]; then
        log_info "Configuration validation passed"
    else
        log_error "Configuration validation failed"
    fi
    
    return $exit_code
}

# Show current configuration
show_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        init_config
    fi
    
    echo "Current Configuration:"
    echo "===================="
    
    for key in "${!DEFAULT_CONFIG[@]}"; do
        local value
        if value=$(get_config "$key"); then
            printf "%-20s: %s\n" "$key" "$value"
        else
            printf "%-20s: ERROR\n" "$key"
        fi
    done
    
    echo
    echo "Configuration file: $CONFIG_FILE"
}

# Reset configuration to defaults
reset_config() {
    log_warn "Resetting configuration to defaults"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        mv "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing configuration"
    fi
    
    init_config
    log_info "Configuration reset to defaults"
}

# Main function
main() {
    local command="${1:-show}"
    shift || true
    
    case "$command" in
        init)
            init_config
            ;;
        get)
            if [[ $# -eq 0 ]]; then
                echo "Usage: $0 get <key> [default]"
                exit 1
            fi
            get_config "$@"
            ;;
        set)
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 set <key> <value> [validate=true]"
                exit 1
            fi
            set_config "$@"
            ;;
        load-env)
            load_env_config
            ;;
        export-env)
            export_env_config
            ;;
        validate)
            validate_config
            ;;
        show)
            show_config
            ;;
        reset)
            reset_config
            ;;
        *)
            echo "Error: Unknown command: $command"
            echo "Available commands: init, get, set, load-env, export-env, validate, show, reset"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi