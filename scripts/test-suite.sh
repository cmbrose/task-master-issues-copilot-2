#!/bin/bash
set -euo pipefail

# Basic Test Suite for Taskmaster Action
# Tests core functionality of the GitHub Action components

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_OUTPUT_DIR="/tmp/taskmaster-tests"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Test assertion functions
assert_file_exists() {
    local file="$1"
    local test_name="$2"
    
    ((TESTS_RUN++))
    
    if [[ -f "$file" ]]; then
        log_success "$test_name: File exists: $file"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "$test_name: File not found: $file"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_command_success() {
    local command="$1"
    local test_name="$2"
    
    ((TESTS_RUN++))
    
    if $command >/dev/null 2>&1; then
        log_success "$test_name: Command succeeded: $command"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "$test_name: Command failed: $command"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_json_valid() {
    local file="$1"
    local test_name="$2"
    
    ((TESTS_RUN++))
    
    if jq empty "$file" 2>/dev/null; then
        log_success "$test_name: Valid JSON: $file"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "$test_name: Invalid JSON: $file"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Setup test environment
setup_tests() {
    log_info "Setting up test environment..."
    
    mkdir -p "$TEST_OUTPUT_DIR"
    cd "$REPO_ROOT"
    
    # Set test environment variables
    export DRY_RUN=true
    export GITHUB_TOKEN=test-token
    export GITHUB_REPOSITORY=test/repo
    
    log_info "Test environment ready: $TEST_OUTPUT_DIR"
}

# Test 1: Repository structure
test_repository_structure() {
    log_info "Testing repository structure..."
    
    # Test critical files exist
    assert_file_exists "$REPO_ROOT/action.yml" "Repository Structure"
    assert_file_exists "$REPO_ROOT/README.md" "Repository Structure"
    assert_file_exists "$REPO_ROOT/CONTRIBUTING.md" "Repository Structure"
    
    # Test script files exist and are executable
    assert_file_exists "$REPO_ROOT/scripts/taskmaster-cli.sh" "Scripts"
    assert_file_exists "$REPO_ROOT/scripts/github-issues.sh" "Scripts"
    assert_file_exists "$REPO_ROOT/scripts/config-manager.sh" "Scripts"
    assert_file_exists "$REPO_ROOT/scripts/output-processor.sh" "Scripts"
    assert_file_exists "$REPO_ROOT/scripts/artifact-manager.sh" "Scripts"
    assert_file_exists "$REPO_ROOT/scripts/hierarchy-manager.sh" "Scripts"
    
    # Test workflow files exist
    assert_file_exists "$REPO_ROOT/.github/workflows/taskmaster-generate.yml" "Workflows"
    assert_file_exists "$REPO_ROOT/.github/workflows/taskmaster-breakdown.yml" "Workflows"
    assert_file_exists "$REPO_ROOT/.github/workflows/taskmaster-watcher.yml" "Workflows"
    assert_file_exists "$REPO_ROOT/.github/workflows/taskmaster-replay.yml" "Workflows"
    assert_file_exists "$REPO_ROOT/.github/workflows/taskmaster-dry-run.yml" "Workflows"
    assert_file_exists "$REPO_ROOT/.github/workflows/artifact-cleanup.yml" "Workflows"
}

# Test 2: Configuration management
test_configuration() {
    log_info "Testing configuration management..."
    
    # Test config initialization
    assert_command_success "$REPO_ROOT/scripts/config-manager.sh init" "Config Init"
    
    # Test config validation
    assert_command_success "$REPO_ROOT/scripts/config-manager.sh validate" "Config Validation"
    
    # Test setting and getting values
    assert_command_success "$REPO_ROOT/scripts/config-manager.sh set complexity_threshold 50" "Config Set"
    
    local value
    value=$("$REPO_ROOT/scripts/config-manager.sh" get complexity_threshold)
    if [[ "$value" == "50" ]]; then
        log_success "Config Get: Retrieved correct value: $value"
        ((TESTS_PASSED++))
    else
        log_error "Config Get: Expected 50, got: $value"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test 3: Taskmaster CLI wrapper
test_taskmaster_cli() {
    log_info "Testing Taskmaster CLI wrapper..."
    
    # Test CLI setup
    assert_command_success "$REPO_ROOT/scripts/taskmaster-cli.sh setup" "CLI Setup"
    
    # Test CLI version
    assert_command_success "$REPO_ROOT/scripts/taskmaster-cli.sh version" "CLI Version"
    
    # Test PRD parsing (dry run)
    local output_file="$TEST_OUTPUT_DIR/test-graph.json"
    if "$REPO_ROOT/scripts/taskmaster-cli.sh" parse-prd "$REPO_ROOT/docs/initial-release.prd.md" "$output_file"; then
        log_success "CLI Parse: PRD parsing succeeded"
        ((TESTS_PASSED++))
        
        # Validate generated JSON
        assert_json_valid "$output_file" "CLI Parse JSON"
    else
        log_error "CLI Parse: PRD parsing failed"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Test 4: Output processing
test_output_processing() {
    log_info "Testing output processing..."
    
    local test_json="$TEST_OUTPUT_DIR/test.json"
    
    # Create test JSON
    cat > "$test_json" << 'EOF'
{
  "version": "0.19.0",
  "metadata": {
    "prd_path": "test.prd.md",
    "generated_at": "2025-07-08T01:45:00Z",
    "complexity_threshold": 40,
    "max_depth": 3
  },
  "tasks": [
    {
      "id": "1",
      "title": "Test Task",
      "description": "Test task description",
      "complexity": 35,
      "priority": "high",
      "dependencies": [],
      "subtasks": []
    }
  ]
}
EOF
    
    # Test validation
    assert_command_success "$REPO_ROOT/scripts/output-processor.sh validate $test_json taskgraph" "Output Validation"
    
    # Test processing
    assert_command_success "$REPO_ROOT/scripts/output-processor.sh process $test_json json taskgraph $TEST_OUTPUT_DIR" "Output Processing"
}

# Test 5: GitHub Issues (dry run)
test_github_issues() {
    log_info "Testing GitHub Issues functionality (dry run)..."
    
    local test_json="$TEST_OUTPUT_DIR/test.json"
    
    # Test GitHub Issues creation (dry run)
    assert_command_success "$REPO_ROOT/scripts/github-issues.sh validate" "GitHub Issues Validation"
    
    if [[ -f "$test_json" ]]; then
        assert_command_success "$REPO_ROOT/scripts/github-issues.sh process $test_json test/repo" "GitHub Issues Process"
    else
        log_warn "Skipping GitHub Issues process test - no test JSON available"
    fi
}

# Test 6: Artifact management
test_artifact_management() {
    log_info "Testing artifact management..."
    
    local test_json="$TEST_OUTPUT_DIR/test.json"
    
    if [[ -f "$test_json" ]]; then
        # Test metadata generation
        local metadata_file="$TEST_OUTPUT_DIR/metadata.json"
        assert_command_success "$REPO_ROOT/scripts/artifact-manager.sh metadata $test_json $metadata_file" "Artifact Metadata"
        
        if [[ -f "$metadata_file" ]]; then
            assert_json_valid "$metadata_file" "Artifact Metadata JSON"
        fi
        
        # Test artifact upload (dry run)
        assert_command_success "$REPO_ROOT/scripts/artifact-manager.sh upload $test_json" "Artifact Upload"
    else
        log_warn "Skipping artifact tests - no test JSON available"
    fi
}

# Test 7: Action YAML validation
test_action_yaml() {
    log_info "Testing action.yml validation..."
    
    # Check if action.yml is valid YAML
    if command -v yq >/dev/null 2>&1; then
        assert_command_success "yq eval '.' $REPO_ROOT/action.yml" "Action YAML Syntax"
    elif python3 -c "import yaml" 2>/dev/null; then
        assert_command_success "python3 -c \"import yaml; yaml.safe_load(open('$REPO_ROOT/action.yml'))\"" "Action YAML Syntax"
    else
        log_warn "No YAML validator available, skipping action.yml syntax test"
    fi
    
    # Check required fields
    if grep -q "name:" "$REPO_ROOT/action.yml" && \
       grep -q "description:" "$REPO_ROOT/action.yml" && \
       grep -q "runs:" "$REPO_ROOT/action.yml"; then
        log_success "Action YAML Structure: Required fields present"
        ((TESTS_PASSED++))
    else
        log_error "Action YAML Structure: Missing required fields"
        ((TESTS_FAILED++))
    fi
    ((TESTS_RUN++))
}

# Cleanup
cleanup_tests() {
    log_info "Cleaning up test artifacts..."
    
    # Remove test configuration
    rm -f "$REPO_ROOT/.taskmaster/action-config.json"
    
    # Remove test outputs
    rm -rf "$TEST_OUTPUT_DIR"
    
    log_info "Cleanup completed"
}

# Display test results
show_results() {
    echo
    echo "=========================================="
    echo "           TEST RESULTS"
    echo "=========================================="
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo "Success rate: $(( TESTS_PASSED * 100 / TESTS_RUN ))%"
    echo "=========================================="
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

# Main test runner
main() {
    echo "=========================================="
    echo "     TASKMASTER ACTION TEST SUITE"
    echo "=========================================="
    
    setup_tests
    
    test_repository_structure
    test_configuration
    test_taskmaster_cli
    test_output_processing
    test_github_issues
    test_artifact_management
    test_action_yaml
    
    cleanup_tests
    show_results
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi