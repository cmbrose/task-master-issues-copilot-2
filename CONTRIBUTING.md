# Contributing to Task Planning GitHub Action

Thank you for your interest in contributing to the Task Planning GitHub Action! This document provides guidelines for contributing to the project.

## Development Setup

### Prerequisites

- Node.js 18+ (for testing and development tools)
- Bash shell
- GitHub CLI (optional, for testing)
- Access to Taskmaster CLI

### Local Development

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-org/task-planning-action.git
   cd task-planning-action
   ```

2. **Install development dependencies**
   ```bash
   npm install
   ```

3. **Set up environment variables**
   ```bash
   export GITHUB_TOKEN="your-github-token"
   export COMPLEXITY_THRESHOLD="40"
   export MAX_DEPTH="3"
   ```

## Project Structure

```
.
├── .github/workflows/     # GitHub Actions workflows
│   ├── taskmaster-generate.yml
│   ├── taskmaster-breakdown.yml
│   ├── taskmaster-watcher.yml
│   ├── taskmaster-replay.yml
│   └── taskmaster-dry-run.yml
├── scripts/              # Shell scripts for action logic
├── src/                  # Source code (TypeScript/JavaScript)
├── action.yml            # Action metadata and configuration
├── README.md             # Main documentation
└── docs/                 # Additional documentation
```

## Testing

### Unit Tests

Run unit tests with:
```bash
npm test
```

### Integration Tests

Test with a sample PRD:
```bash
# Place a test PRD in docs/test.prd.md
./scripts/test-local.sh docs/test.prd.md
```

### Manual Testing

1. Create a test repository
2. Add PRD files to the configured path
3. Trigger workflows manually or via commits
4. Verify issue creation and dependency management

## Code Style

- Use consistent bash scripting practices
- Follow GitHub Actions best practices
- Add comments for complex logic
- Use meaningful variable names

### Bash Guidelines

- Use `set -euo pipefail` for error handling
- Quote variables to prevent word splitting
- Use `local` for function variables
- Include error messages with context

### YAML Guidelines

- Use consistent indentation (2 spaces)
- Include descriptive names and descriptions
- Group related steps logically
- Use meaningful step names

## Workflow Contributions

### Adding New Workflows

When adding new workflows:

1. Follow the naming convention: `taskmaster-<purpose>.yml`
2. Include proper permissions
3. Add comprehensive error handling
4. Document inputs and outputs
5. Test thoroughly

### Modifying Existing Workflows

- Maintain backward compatibility
- Update documentation
- Test edge cases
- Consider performance impact

## Issue and PR Guidelines

### Reporting Issues

When reporting issues:

1. Use the issue template
2. Include relevant logs
3. Describe expected vs actual behavior
4. Provide minimal reproduction steps

### Pull Requests

1. **Create feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make focused changes**
   - Keep PRs small and focused
   - Include tests for new functionality
   - Update documentation as needed

3. **Test thoroughly**
   - Run all tests locally
   - Test in a real repository if possible
   - Verify backwards compatibility

4. **Write good commit messages**
   ```
   feat: add support for custom PRD paths
   
   - Add prd-path-glob input parameter
   - Update workflow to use configurable paths
   - Add tests for path globbing functionality
   ```

5. **Update documentation**
   - Update README.md for new features
   - Add inline code comments
   - Update action.yml descriptions

## Release Process

### Versioning

We follow semantic versioning:
- **Major** (v1.0.0): Breaking changes
- **Minor** (v1.1.0): New features, backwards compatible
- **Patch** (v1.0.1): Bug fixes, backwards compatible

### Release Checklist

1. **Update version numbers**
   - Update action.yml metadata
   - Update README examples
   - Update documentation

2. **Test release candidate**
   - Deploy to test repository
   - Run full test suite
   - Verify all workflows work

3. **Create release**
   - Tag the release: `git tag v1.0.0`
   - Push tags: `git push --tags`
   - Create GitHub release with changelog

## Architecture Notes

### Core Components

1. **Action Entry Point** (`action.yml`)
   - Defines inputs, outputs, and composite steps
   - Configures environment variables

2. **Taskmaster CLI Integration**
   - Downloads and validates CLI binary
   - Executes with proper error handling
   - Parses JSON output

3. **GitHub API Integration**
   - Creates and manages issues
   - Handles rate limiting
   - Manages labels and dependencies

4. **Workflow Orchestration**
   - Coordinates multiple workflows
   - Handles cross-workflow communication
   - Manages state and artifacts

### Design Principles

- **Idempotency**: Repeated runs produce same results
- **Error Recovery**: Graceful handling of failures
- **Rate Limit Awareness**: Respect GitHub API limits
- **Modularity**: Clear separation of concerns
- **Observability**: Comprehensive logging

## Security Considerations

- Never log sensitive tokens
- Validate all external inputs
- Use minimal required permissions
- Handle untrusted PRD content safely
- Audit third-party dependencies

## Performance Guidelines

- Batch API calls when possible
- Use pagination for large result sets
- Implement exponential backoff
- Cache CLI binary downloads
- Optimize workflow trigger conditions

## Documentation Standards

- Keep README.md up to date
- Include practical examples
- Document all inputs and outputs
- Explain workflow purposes
- Provide troubleshooting guidance

## Getting Help

- Check existing issues and documentation
- Review the troubleshooting section in README
- Ask questions in issues with the "question" label
- Join community discussions

## Code of Conduct

This project follows the [GitHub Community Guidelines](https://docs.github.com/en/github/site-policy/github-community-guidelines). Please be respectful and constructive in all interactions.

Thank you for contributing!