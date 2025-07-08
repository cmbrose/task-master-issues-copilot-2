#!/bin/bash
set -euo pipefail

# GitHub Issue Hierarchy Management
# Manages parent-child relationships using GitHub's Sub-issues API

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
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
        return 1
    fi
    return 0
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

# Find issue by title
find_issue_by_title() {
    local title="$1"
    local repo="$2"
    
    log_info "Searching for issue: $title"
    
    if check_github_cli; then
        # Use GitHub CLI
        local result
        result=$(gh issue list --repo "$repo" --search "\"$title\"" --limit 1 --json number,title 2>/dev/null || echo "[]")
        
        local issue_number
        issue_number=$(echo "$result" | jq -r '.[0].number // empty')
        
        if [[ -n "$issue_number" ]]; then
            echo "$issue_number"
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
        
        local issue_number
        issue_number=$(echo "$response" | jq -r '.items[0].number // empty')
        
        if [[ -n "$issue_number" ]]; then
            echo "$issue_number"
            return 0
        fi
    fi
    
    return 1
}

# Create sub-issue relationship
create_subissue_relationship() {
    local parent_issue="$1"
    local child_issue="$2"
    local repo="$3"
    
    log_info "Creating sub-issue relationship: $parent_issue -> $child_issue"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create sub-issue relationship $parent_issue -> $child_issue"
        return 0
    fi
    
    # Note: GitHub's Sub-issues API is not publicly documented yet
    # This is a placeholder implementation that would need to be updated
    # when the API becomes available
    
    log_warn "Sub-issues API not yet available - using issue comments as fallback"
    
    # Fallback: Add a comment to the parent issue linking the child
    local comment_body="**Sub-issue**: #$child_issue"
    
    if check_github_cli; then
        if gh issue comment "$parent_issue" --repo "$repo" --body "$comment_body"; then
            log_success "Added sub-issue comment to #$parent_issue"
        else
            log_error "Failed to add sub-issue comment"
            return 1
        fi
    else
        local payload
        payload=$(jq -n --arg body "$comment_body" '{body: $body}')
        
        local response
        response=$(curl -s -X POST \
                        -H "Authorization: token $GITHUB_TOKEN" \
                        -H "Accept: application/vnd.github.v3+json" \
                        -H "Content-Type: application/json" \
                        -d "$payload" \
                        "https://api.github.com/repos/$repo/issues/$parent_issue/comments")
        
        if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
            log_success "Added sub-issue comment to #$parent_issue"
        else
            log_error "Failed to add sub-issue comment"
            return 1
        fi
    fi
    
    # Also add a comment to the child issue
    comment_body="**Parent issue**: #$parent_issue"
    
    if check_github_cli; then
        gh issue comment "$child_issue" --repo "$repo" --body "$comment_body" >/dev/null 2>&1
    else
        payload=$(jq -n --arg body "$comment_body" '{body: $body}')
        curl -s -X POST \
             -H "Authorization: token $GITHUB_TOKEN" \
             -H "Accept: application/vnd.github.v3+json" \
             -H "Content-Type: application/json" \
             -d "$payload" \
             "https://api.github.com/repos/$repo/issues/$child_issue/comments" >/dev/null 2>&1
    fi
    
    return 0
}

# Update issue labels based on dependencies
update_dependency_labels() {
    local issue_number="$1"
    local dependencies="$2"
    local repo="$3"
    
    log_info "Updating dependency labels for issue #$issue_number"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would update labels for issue #$issue_number"
        return 0
    fi
    
    # Check if all dependencies are resolved
    local blocked=false
    
    if [[ -n "$dependencies" && "$dependencies" != "null" && "$dependencies" != "" ]]; then
        IFS=',' read -ra dep_array <<< "$dependencies"
        
        for dep in "${dep_array[@]}"; do
            dep=$(echo "$dep" | xargs)  # trim whitespace
            
            if [[ -n "$dep" ]]; then
                # Check if dependency issue is closed
                local dep_state
                if check_github_cli; then
                    dep_state=$(gh issue view "$dep" --repo "$repo" --json state --jq '.state' 2>/dev/null || echo "unknown")
                else
                    local response
                    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                                    -H "Accept: application/vnd.github.v3+json" \
                                    "https://api.github.com/repos/$repo/issues/$dep")
                    dep_state=$(echo "$response" | jq -r '.state // "unknown"')
                fi
                
                if [[ "$dep_state" != "closed" ]]; then
                    blocked=true
                    break
                fi
            fi
        done
    fi
    
    # Update blocked label
    if [[ "$blocked" == "true" ]]; then
        log_info "Adding blocked label to issue #$issue_number"
        
        if check_github_cli; then
            gh issue edit "$issue_number" --repo "$repo" --add-label "blocked" >/dev/null 2>&1 || true
        else
            local payload
            payload='["blocked"]'
            curl -s -X POST \
                 -H "Authorization: token $GITHUB_TOKEN" \
                 -H "Accept: application/vnd.github.v3+json" \
                 -H "Content-Type: application/json" \
                 -d "$payload" \
                 "https://api.github.com/repos/$repo/issues/$issue_number/labels" >/dev/null 2>&1 || true
        fi
    else
        log_info "Removing blocked label from issue #$issue_number"
        
        if check_github_cli; then
            gh issue edit "$issue_number" --repo "$repo" --remove-label "blocked" >/dev/null 2>&1 || true
        else
            curl -s -X DELETE \
                 -H "Authorization: token $GITHUB_TOKEN" \
                 -H "Accept: application/vnd.github.v3+json" \
                 "https://api.github.com/repos/$repo/issues/$issue_number/labels/blocked" >/dev/null 2>&1 || true
        fi
    fi
    
    return 0
}

# Process task graph for hierarchy
process_hierarchy() {
    local task_graph_file="$1"
    local repo="$2"
    
    log_info "Processing task hierarchy: $task_graph_file"
    
    if [[ ! -f "$task_graph_file" ]]; then
        log_error "Task graph file not found: $task_graph_file"
        return 1
    fi
    
    # Get tasks array
    local task_count
    task_count=$(jq '.tasks | length' "$task_graph_file")
    
    log_info "Processing hierarchy for $task_count tasks"
    
    # First pass: create mapping of task ID to issue number
    declare -A task_to_issue
    
    for ((i=0; i<task_count; i++)); do
        local task_id title
        task_id=$(jq -r ".tasks[$i].id" "$task_graph_file")
        title=$(jq -r ".tasks[$i].title" "$task_graph_file")
        
        local issue_number
        if issue_number=$(find_issue_by_title "$title" "$repo"); then
            task_to_issue["$task_id"]="$issue_number"
            log_info "Mapped task $task_id to issue #$issue_number"
        else
            log_warn "Could not find issue for task $task_id: $title"
        fi
    done
    
    # Second pass: create relationships and update labels
    for ((i=0; i<task_count; i++)); do
        local task_id dependencies subtasks
        task_id=$(jq -r ".tasks[$i].id" "$task_graph_file")
        dependencies=$(jq -r ".tasks[$i].dependencies // [] | join(\",\")" "$task_graph_file")
        subtasks=$(jq -r ".tasks[$i].subtasks // [] | map(.id) | join(\",\")" "$task_graph_file")
        
        local issue_number="${task_to_issue[$task_id]:-}"
        
        if [[ -n "$issue_number" ]]; then
            # Update dependency labels
            update_dependency_labels "$issue_number" "$dependencies" "$repo"
            
            # Create sub-issue relationships
            if [[ -n "$subtasks" && "$subtasks" != "null" && "$subtasks" != "" ]]; then
                IFS=',' read -ra subtask_array <<< "$subtasks"
                
                for subtask_id in "${subtask_array[@]}"; do
                    subtask_id=$(echo "$subtask_id" | xargs)  # trim whitespace
                    
                    local subtask_issue="${task_to_issue[$subtask_id]:-}"
                    
                    if [[ -n "$subtask_issue" ]]; then
                        create_subissue_relationship "$issue_number" "$subtask_issue" "$repo"
                    else
                        log_warn "Could not find issue for subtask $subtask_id"
                    fi
                done
            fi
        fi
    done
    
    log_success "Hierarchy processing completed"
    return 0
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
            
            process_hierarchy "$task_graph_file" "$repo"
            ;;
        create-relationship)
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 create-relationship <parent-issue> <child-issue> [repo]"
                exit 1
            fi
            
            local parent="$1" child="$2"
            local repo="${3:-$(get_repo_info)}"
            
            create_subissue_relationship "$parent" "$child" "$repo"
            ;;
        update-labels)
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 update-labels <issue-number> <dependencies> [repo]"
                exit 1
            fi
            
            local issue="$1" deps="$2"
            local repo="${3:-$(get_repo_info)}"
            
            update_dependency_labels "$issue" "$deps" "$repo"
            ;;
        *)
            echo "Error: Unknown command: $command"
            echo "Available commands: process, create-relationship, update-labels"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi