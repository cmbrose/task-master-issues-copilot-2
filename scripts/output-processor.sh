#!/bin/bash
set -euo pipefail

# Output Format Validation and Processing
# Handles validation, parsing, and conversion of Taskmaster CLI outputs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Required tools check
check_dependencies() {
    local missing_tools=()
    
    # Check for required tools
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "Error: Missing required tools: ${missing_tools[*]}" >&2
        echo "Please install the missing tools before continuing" >&2
        return 1
    fi
}

# Validate JSON format
validate_json() {
    local file="$1"
    local schema_mode="${2:-basic}"
    
    echo "Validating JSON format: $file"
    
    if [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file" >&2
        return 1
    fi
    
    # Basic JSON syntax validation
    if ! jq empty "$file" 2>/dev/null; then
        echo "Error: Invalid JSON syntax in $file" >&2
        return 1
    fi
    
    case "$schema_mode" in
        basic)
            validate_basic_json_schema "$file"
            ;;
        taskgraph)
            validate_taskgraph_schema "$file"
            ;;
        expanded)
            validate_expanded_schema "$file"
            ;;
        *)
            echo "Warning: Unknown schema mode: $schema_mode" >&2
            ;;
    esac
}

# Validate basic JSON schema
validate_basic_json_schema() {
    local file="$1"
    
    echo "Validating basic JSON schema..."
    
    # Check for required top-level fields
    local required_fields=("version")
    
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$file" >/dev/null 2>&1; then
            echo "Error: Missing required field: $field" >&2
            return 1
        fi
    done
    
    echo "✓ Basic JSON schema validation passed"
    return 0
}

# Validate task graph schema
validate_taskgraph_schema() {
    local file="$1"
    
    echo "Validating task graph schema..."
    
    # Required fields for task graph
    local required_fields=("version" "metadata" "tasks")
    
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$file" >/dev/null 2>&1; then
            echo "Error: Missing required field: $field" >&2
            return 1
        fi
    done
    
    # Validate metadata structure
    local metadata_fields=("prd_path" "generated_at" "complexity_threshold" "max_depth")
    
    for field in "${metadata_fields[@]}"; do
        if ! jq -e ".metadata.$field" "$file" >/dev/null 2>&1; then
            echo "Warning: Missing metadata field: $field" >&2
        fi
    done
    
    # Validate tasks array
    if ! jq -e '.tasks | type == "array"' "$file" >/dev/null 2>&1; then
        echo "Error: 'tasks' must be an array" >&2
        return 1
    fi
    
    # Validate individual tasks
    local task_count
    task_count=$(jq '.tasks | length' "$file")
    
    echo "Validating $task_count tasks..."
    
    for ((i=0; i<task_count; i++)); do
        if ! validate_task_object "$file" "$i"; then
            echo "Error: Invalid task at index $i" >&2
            return 1
        fi
    done
    
    echo "✓ Task graph schema validation passed"
    return 0
}

# Validate individual task object
validate_task_object() {
    local file="$1"
    local index="$2"
    
    local task_fields=("id" "title" "description" "complexity" "priority")
    
    for field in "${task_fields[@]}"; do
        if ! jq -e ".tasks[$index].$field" "$file" >/dev/null 2>&1; then
            echo "Error: Task $index missing required field: $field" >&2
            return 1
        fi
    done
    
    # Validate complexity is a number
    local complexity
    complexity=$(jq -r ".tasks[$index].complexity" "$file")
    
    if ! [[ "$complexity" =~ ^[0-9]+$ ]]; then
        echo "Error: Task $index complexity must be a number, got: $complexity" >&2
        return 1
    fi
    
    # Validate priority is valid
    local priority
    priority=$(jq -r ".tasks[$index].priority" "$file")
    
    if [[ ! "$priority" =~ ^(high|medium|low)$ ]]; then
        echo "Error: Task $index priority must be high/medium/low, got: $priority" >&2
        return 1
    fi
    
    return 0
}

# Validate expanded task schema
validate_expanded_schema() {
    local file="$1"
    
    echo "Validating expanded task schema..."
    
    # Required fields for expanded output
    local required_fields=("version" "expanded_task" "subtasks")
    
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$file" >/dev/null 2>&1; then
            echo "Error: Missing required field: $field" >&2
            return 1
        fi
    done
    
    # Validate subtasks array
    if ! jq -e '.subtasks | type == "array"' "$file" >/dev/null 2>&1; then
        echo "Error: 'subtasks' must be an array" >&2
        return 1
    fi
    
    echo "✓ Expanded task schema validation passed"
    return 0
}

# Convert JSON to YAML (if yq is available)
convert_json_to_yaml() {
    local input_file="$1"
    local output_file="$2"
    
    echo "Converting JSON to YAML: $input_file -> $output_file"
    
    if command -v yq >/dev/null 2>&1; then
        yq eval -P "$input_file" > "$output_file"
        echo "✓ Conversion completed"
    else
        echo "Warning: yq not available, cannot convert to YAML" >&2
        return 1
    fi
}

# Convert JSON to XML (basic conversion)
convert_json_to_xml() {
    local input_file="$1"
    local output_file="$2"
    
    echo "Converting JSON to XML: $input_file -> $output_file"
    
    # Basic XML conversion using jq
    cat > "$output_file" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<taskgraph>
EOF
    
    # Use jq to extract data and format as XML
    jq -r '
        "<version>" + .version + "</version>",
        if .metadata then
            "<metadata>",
            "  <prd_path>" + .metadata.prd_path + "</prd_path>",
            "  <generated_at>" + .metadata.generated_at + "</generated_at>",
            "  <complexity_threshold>" + (.metadata.complexity_threshold | tostring) + "</complexity_threshold>",
            "  <max_depth>" + (.metadata.max_depth | tostring) + "</max_depth>",
            "</metadata>"
        else empty end,
        if .tasks then
            "<tasks>",
            (.tasks[] | 
                "  <task>",
                "    <id>" + .id + "</id>",
                "    <title>" + .title + "</title>",
                "    <description>" + .description + "</description>",
                "    <complexity>" + (.complexity | tostring) + "</complexity>",
                "    <priority>" + .priority + "</priority>",
                "  </task>"
            ),
            "</tasks>"
        else empty end
    ' "$input_file" >> "$output_file"
    
    echo "</taskgraph>" >> "$output_file"
    
    echo "✓ Basic XML conversion completed"
}

# Sanitize output (remove sensitive information)
sanitize_output() {
    local input_file="$1"
    local output_file="$2"
    local mode="${3:-basic}"
    
    echo "Sanitizing output: $input_file -> $output_file"
    
    case "$mode" in
        basic)
            # Remove potential sensitive fields
            jq 'del(.secrets, .tokens, .credentials)' "$input_file" > "$output_file"
            ;;
        strict)
            # More aggressive sanitization
            jq 'del(.secrets, .tokens, .credentials, .metadata.api_keys, .metadata.auth)' "$input_file" > "$output_file"
            ;;
        *)
            cp "$input_file" "$output_file"
            ;;
    esac
    
    echo "✓ Output sanitization completed"
}

# Extract task summary
extract_task_summary() {
    local input_file="$1"
    local output_file="$2"
    
    echo "Extracting task summary: $input_file -> $output_file"
    
    jq '{
        version: .version,
        total_tasks: (.tasks | length),
        complexity_distribution: {
            high: [.tasks[] | select(.complexity > 70)] | length,
            medium: [.tasks[] | select(.complexity > 30 and .complexity <= 70)] | length,
            low: [.tasks[] | select(.complexity <= 30)] | length
        },
        priority_distribution: {
            high: [.tasks[] | select(.priority == "high")] | length,
            medium: [.tasks[] | select(.priority == "medium")] | length,
            low: [.tasks[] | select(.priority == "low")] | length
        },
        tasks: [.tasks[] | {id: .id, title: .title, complexity: .complexity, priority: .priority}]
    }' "$input_file" > "$output_file"
    
    echo "✓ Task summary extraction completed"
}

# Validate and process output file
process_output() {
    local input_file="$1"
    local format="${2:-json}"
    local validation_mode="${3:-taskgraph}"
    local output_dir="${4:-.}"
    
    echo "Processing output file: $input_file (format: $format, validation: $validation_mode)"
    
    # Validate input
    case "$format" in
        json)
            if ! validate_json "$input_file" "$validation_mode"; then
                return 1
            fi
            ;;
        *)
            echo "Warning: Validation not implemented for format: $format" >&2
            ;;
    esac
    
    # Generate additional formats if requested
    local base_name
    base_name="$(basename "$input_file" .json)"
    
    # Create sanitized version
    sanitize_output "$input_file" "$output_dir/${base_name}-sanitized.json" "basic"
    
    # Create summary
    extract_task_summary "$input_file" "$output_dir/${base_name}-summary.json"
    
    # Convert to other formats if tools are available
    if command -v yq >/dev/null 2>&1; then
        convert_json_to_yaml "$input_file" "$output_dir/${base_name}.yaml"
    fi
    
    convert_json_to_xml "$input_file" "$output_dir/${base_name}.xml"
    
    echo "✓ Output processing completed"
    return 0
}

# Main function
main() {
    local command="${1:-validate}"
    shift || true
    
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    case "$command" in
        validate)
            if [[ $# -eq 0 ]]; then
                echo "Usage: $0 validate <file> [schema_mode]"
                echo "Schema modes: basic, taskgraph, expanded"
                exit 1
            fi
            validate_json "$@"
            ;;
        convert)
            if [[ $# -lt 3 ]]; then
                echo "Usage: $0 convert <input> <output> <format>"
                echo "Formats: yaml, xml"
                exit 1
            fi
            local input="$1" output="$2" format="$3"
            case "$format" in
                yaml) convert_json_to_yaml "$input" "$output" ;;
                xml) convert_json_to_xml "$input" "$output" ;;
                *) echo "Error: Unsupported format: $format" >&2; exit 1 ;;
            esac
            ;;
        sanitize)
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 sanitize <input> <output> [mode]"
                echo "Modes: basic, strict"
                exit 1
            fi
            sanitize_output "$@"
            ;;
        summary)
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 summary <input> <output>"
                exit 1
            fi
            extract_task_summary "$1" "$2"
            ;;
        process)
            if [[ $# -eq 0 ]]; then
                echo "Usage: $0 process <input> [format] [validation_mode] [output_dir]"
                exit 1
            fi
            process_output "$@"
            ;;
        *)
            echo "Error: Unknown command: $command"
            echo "Available commands: validate, convert, sanitize, summary, process"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi