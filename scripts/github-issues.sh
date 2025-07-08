#!/bin/bash
set -euo pipefail

# GitHub Issues Management
# Creates and manages GitHub Issues from task graph data

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
DEFAULT_LABELS=("task")
BLOCKED_LABEL="blocked"
DRY_RUN="${DRY_RUN:-false}"

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

log_success() {
    echo "[SUCCESS] $*" >&2
}

# Check if GitHub CLI is available
check_github_cli() {
    if ! command -v gh >/dev/null 2>&1; then
        log_error "GitHub CLI (gh) is not available"
        log_info "Falling back to curl for GitHub API calls"
        return 1
    fi
    return 0
}

# Validate GitHub token
validate_github_token() {
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log_error "GITHUB_TOKEN environment variable is required"
        return 1
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Skipping GitHub token validation"
        return 0
    fi
    
    log_info "Validating GitHub token..."
    
    # Test API access
    if check_github_cli; then
        if gh api user >/dev/null 2>&1; then
            log_success "GitHub CLI authentication successful"
            return 0
        fi
    fi
    
    # Fall back to curl
    local response
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/user")
    
    if echo "$response" | jq -e '.login' >/dev/null 2>&1; then
        log_success "GitHub API authentication successful"
        return 0
    else
        log_error "GitHub API authentication failed"
        return 1
    fi
}

# Get repository information
get_repo_info() {
    if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
        echo "$GITHUB_REPOSITORY"
        return 0
    fi
    
    # Try to get from git remote
    local remote_url
    if remote_url=$(git remote get-url origin 2>/dev/null); then
        # Extract owner/repo from URL
        if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
            echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
            return 0
        fi
    fi
    
    log_error "Could not determine repository information"
    return 1
}

# Check if issue exists by title
issue_exists() {
    local title="$1"
    local repo="$2"
    
    log_info "Checking if issue exists: $title"
    
    if check_github_cli; then
        # Use GitHub CLI
        if gh issue list --repo "$repo" --search "\"$title\"" --limit 1 --json number | jq -e '.[0].number' >/dev/null 2>&1; then
            return 0
        fi
    else
        # Use curl
        local encoded_title
        encoded_title=$(printf '%s' "$title" | jq -sRr @uri)
        
        local response
        response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                        -H "Accept: application/vnd.github.v3+json" \
                        "https://api.github.com/search/issues?q=repo:$repo+\"$encoded_title\"+in:title")
        
        if echo "$response" | jq -e '.items[0].number' >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    return 1
}

# Create GitHub issue
create_issue() {
    local title="$1"
    local body="$2"
    local labels="$3"
    local repo="$4"
    
    log_info "Creating GitHub issue: $title"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create issue '$title'"
        echo "{\"number\": 999, \"title\": \"$title\", \"url\": \"https://github.com/$repo/issues/999\"}"
        return 0
    fi
    
    # Check if issue already exists
    if issue_exists "$title" "$repo"; then
        log_warn "Issue already exists: $title"
        return 0
    fi
    
    if check_github_cli; then
        # Use GitHub CLI
        local label_args=()
        IFS=',' read -ra LABEL_ARRAY <<< "$labels"
        for label in "${LABEL_ARRAY[@]}"; do
            label_args+=(--label "${label// /}")
        done
        
        local result
        result=$(gh issue create --repo "$repo" \
                                --title "$title" \
                                --body "$body" \
                                "${label_args[@]}" \
                                --json number,title,url)
        
        if [[ $? -eq 0 ]]; then
            log_success "Created issue: $(echo "$result" | jq -r '.url')"
            echo "$result"
        else
            log_error "Failed to create issue: $title"
            return 1
        fi
    else
        # Use curl
        local payload
        payload=$(jq -n \
            --arg title "$title" \
            --arg body "$body" \
            --argjson labels "[$(printf '"%s",' ${labels//,/ } | sed 's/,$//')]" \
            '{title: $title, body: $body, labels: $labels}')
        
        local response
        response=$(curl -s -X POST \
                        -H "Authorization: token $GITHUB_TOKEN" \
                        -H "Accept: application/vnd.github.v3+json" \
                        -H "Content-Type: application/json" \
                        -d "$payload" \
                        "https://api.github.com/repos/$repo/issues")
        
        if echo "$response" | jq -e '.number' >/dev/null 2>&1; then
            log_success "Created issue: $(echo "$response" | jq -r '.html_url')"
            echo "$response"
        else
            log_error "Failed to create issue: $title"
            log_error "API response: $response"
            return 1
        fi
    fi
}

# Create issue from task data
create_task_issue() {
    local task_json="$1"
    local repo="$2"
    
    local id title description complexity priority dependencies
    
    id=$(echo "$task_json" | jq -r '.id')
    title=$(echo "$task_json" | jq -r '.title')
    description=$(echo "$task_json" | jq -r '.description // ""')
    complexity=$(echo "$task_json" | jq -r '.complexity // 0')
    priority=$(echo "$task_json" | jq -r '.priority // "medium"')
    dependencies=$(echo "$task_json" | jq -r '.dependencies // [] | join(",")')
    
    log_info "Creating issue for task $id: $title"
    
    # Generate YAML front-matter
    local yaml_frontmatter
    yaml_frontmatter="---
id: $id
parent: null
dependents: [$dependencies]
complexity: $complexity
priority: $priority
generated_by: taskmaster-action
generated_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
---"
    
    # Generate issue body
    local issue_body
    issue_body="$yaml_frontmatter

## Description

$description

## Task Details

- **ID**: $id
- **Complexity Score**: $complexity
- **Priority**: $priority"
    
    if [[ -n "$dependencies" && "$dependencies" != "null" ]]; then
        issue_body="${issue_body}
- **Dependencies**: $dependencies"
    fi
    
    issue_body="${issue_body}

## Implementation Notes

This issue was automatically generated from a PRD file using the Taskmaster Action.

Please update this issue as you work on it, and close it when the task is complete."
    
    # Determine labels
    local labels="${DEFAULT_LABELS[*]}"
    
    # Add blocked label if there are dependencies
    if [[ -n "$dependencies" && "$dependencies" != "null" && "$dependencies" != "" ]]; then
        labels="$labels,$BLOCKED_LABEL"
    fi
    
    # Add priority label
    labels="$labels,priority:$priority"
    
    # Create the issue
    create_issue "$title" "$issue_body" "$labels" "$repo"
}

# Process task graph file
process_task_graph() {
    local task_graph_file="$1"
    local repo="$2"
    
    log_info "Processing task graph: $task_graph_file"
    
    if [[ ! -f "$task_graph_file" ]]; then
        log_error "Task graph file not found: $task_graph_file"
        return 1
    fi
    
    # Validate JSON
    if ! jq empty "$task_graph_file" 2>/dev/null; then
        log_error "Invalid JSON in task graph file"
        return 1
    fi
    
    # Get tasks array
    local task_count
    task_count=$(jq '.tasks | length' "$task_graph_file")
    
    log_info "Found $task_count tasks to process"
    
    local created_issues=0
    local failed_issues=0
    
    # Process each task
    for ((i=0; i<task_count; i++)); do
        local task_json
        task_json=$(jq ".tasks[$i]" "$task_graph_file")
        
        if create_task_issue "$task_json" "$repo"; then
            ((created_issues++))
        else
            ((failed_issues++))
        fi
        
        # Add delay to avoid rate limiting
        if [[ "$DRY_RUN" != "true" ]]; then
            sleep 1
        fi
    done
    
    log_info "Issue creation completed:"
    log_info "  Created: $created_issues"
    log_info "  Failed: $failed_issues"
    
    # Set action outputs
    echo "task-count=$task_count" >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "issues-created=$created_issues" >> "${GITHUB_OUTPUT:-/dev/null}"
    
    return 0
}

# Setup required labels in repository
setup_labels() {
    local repo="$1"
    
    log_info "Setting up required labels in repository: $repo"
    
    # Define labels with colors
    declare -A labels=(
        ["task"]="0075ca"
        ["blocked"]="d93f0b"
        ["priority:high"]="d93f0b"
        ["priority:medium"]="fbca04"
        ["priority:low"]="0e8a16"
    )
    
    for label in "${!labels[@]}"; do
        local color="${labels[$label]}"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "DRY RUN: Would create/update label: $label (color: #$color)"
            continue
        fi
        
        log_info "Creating/updating label: $label"
        
        if check_github_cli; then
            # Check if label exists
            if gh label list --repo "$repo" --limit 100 | grep -q "^$label"; then
                log_info "Label already exists: $label"
            else
                if gh label create "$label" --color "$color" --repo "$repo" 2>/dev/null; then
                    log_success "Created label: $label"
                else
                    log_warn "Failed to create label: $label"
                fi
            fi
        else
            # Use curl to create label
            local payload
            payload=$(jq -n --arg name "$label" --arg color "$color" \
                        '{name: $name, color: $color}')
            
            local response
            response=$(curl -s -X POST \
                            -H "Authorization: token $GITHUB_TOKEN" \
                            -H "Accept: application/vnd.github.v3+json" \
                            -H "Content-Type: application/json" \
                            -d "$payload" \
                            "https://api.github.com/repos/$repo/labels" 2>/dev/null)
            
            if echo "$response" | jq -e '.name' >/dev/null 2>&1; then
                log_success "Created label: $label"
            else
                log_info "Label may already exist: $label"
            fi
        fi
    done
}

# Main function
main() {
    local command="${1:-process}"
    shift || true
    
    case "$command" in
        process)
            if [[ $# -lt 1 ]]; then
                echo "Usage: $0 process <task-graph-file> [repo]"
                exit 1
            fi
            
            local task_graph_file="$1"
            local repo="${2:-$(get_repo_info)}"
            
            if ! validate_github_token; then
                exit 1
            fi
            
            setup_labels "$repo"
            process_task_graph "$task_graph_file" "$repo"
            ;;
        create-issue)
            if [[ $# -lt 3 ]]; then
                echo "Usage: $0 create-issue <title> <body> <labels> [repo]"
                exit 1
            fi
            
            local title="$1" body="$2" labels="$3"
            local repo="${4:-$(get_repo_info)}"
            
            if ! validate_github_token; then
                exit 1
            fi
            
            create_issue "$title" "$body" "$labels" "$repo"
            ;;
        setup-labels)
            local repo="${1:-$(get_repo_info)}"
            
            if ! validate_github_token; then
                exit 1
            fi
            
            setup_labels "$repo"
            ;;
        validate)
            validate_github_token
            ;;
        *)
            echo "Error: Unknown command: $command"
            echo "Available commands: process, create-issue, setup-labels, validate"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi