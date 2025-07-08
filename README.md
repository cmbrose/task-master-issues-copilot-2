# Task Planning GitHub Action

A GitHub Action that automatically generates GitHub Issues from Product Requirements Documents (PRDs) using the Taskmaster CLI. This action creates hierarchical task graphs, manages dependencies, and provides automated workflow management for project planning.

## Features

- **Automated Task Generation**: Parse PRD files and create GitHub Issues automatically
- **Hierarchical Dependencies**: Manage task relationships with automatic blocking/unblocking
- **Manual Breakdown**: Use `/breakdown` commands to further decompose complex tasks
- **Dry-Run Support**: Preview task graphs before creating issues
- **Artifact Storage**: Durable task graph storage for replay and recovery
- **Dependency Watching**: Automatic monitoring and status updates for dependent tasks

## Usage

### Basic Setup

Add this action to your repository workflow:

```yaml
name: Generate Tasks from PRD
on:
  push:
    paths:
      - 'docs/**.prd.md'

jobs:
  generate-tasks:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write
    steps:
      - uses: actions/checkout@v4
      - uses: your-org/task-planning-action@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Manual Breakdown

Comment on any open issue with:
```
/breakdown --depth 2 --threshold 30
```

This will create sub-issues for the task with custom depth and complexity thresholds.

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `github-token` | GitHub token for API access | Yes | `${{ github.token }}` |
| `complexity-threshold` | Complexity score threshold for task breakdown | No | `40` |
| `max-depth` | Maximum depth for automatic task recursion | No | `3` |
| `prd-path-glob` | POSIX glob pattern for PRD file paths | No | `docs/**.prd.md` |
| `breakdown-max-depth` | Maximum additional depth for manual breakdown | No | `2` |
| `taskmaster-args` | Additional arguments to pass to Taskmaster CLI | No | `''` |
| `dry-run` | Run in dry-run mode (preview only) | No | `false` |

## Outputs

| Output | Description |
|--------|-------------|
| `task-count` | Number of tasks generated |
| `issues-created` | Number of GitHub issues created |
| `artifact-url` | URL of the uploaded task graph artifact |

## Workflows

This action includes several pre-configured workflows:

### 1. Taskmaster Generate (`taskmaster-generate.yml`)
- **Trigger**: Push to PRD files in `docs/**.prd.md`
- **Function**: Generates task graphs and creates GitHub Issues
- **Manual**: Supports manual dispatch with custom parameters

### 2. Taskmaster Breakdown (`taskmaster-breakdown.yml`)
- **Trigger**: Issue comments containing `/breakdown`
- **Function**: Creates sub-issues for manual task decomposition
- **Parameters**: Supports `--depth N` and `--threshold X` arguments

### 3. Taskmaster Watcher (`taskmaster-watcher.yml`)
- **Trigger**: Issue closure or 10-minute cron schedule
- **Function**: Monitors dependencies and updates blocked status
- **Automation**: Removes `blocked` labels when dependencies are resolved

### 4. Taskmaster Replay (`taskmaster-replay.yml`)
- **Trigger**: Manual dispatch with artifact URL
- **Function**: Replays task generation from stored artifacts
- **Recovery**: Handles failed runs and API rate limit recovery

### 5. Taskmaster Dry Run (`taskmaster-dry-run.yml`)
- **Trigger**: Pull requests modifying PRD files
- **Function**: Generates preview comments without creating issues
- **Preview**: Shows what tasks would be created

## Configuration

### Repository Setup

1. **Required Permissions**: Ensure your repository has the following permissions enabled:
   - Issues: Write
   - Contents: Read
   - Pull Requests: Write (for dry-run comments)

2. **Required Labels**: The action automatically creates and manages these labels:
   - `task`: Applied to all generated issues
   - `blocked`: Applied to issues with unresolved dependencies

3. **Sub-issues API**: This action requires GitHub's Sub-issues REST API to be available.

### PRD File Format

PRD files should be placed in the configured path (default: `docs/**.prd.md`) and follow the Taskmaster CLI expected format. See the [Taskmaster CLI documentation](https://github.com/cmbrose/taskmaster) for details.

## Examples

### Basic PRD Processing
```yaml
name: Process PRDs
on:
  push:
    paths: ['docs/**.prd.md']

jobs:
  generate:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write
    steps:
      - uses: actions/checkout@v4
      - uses: ./
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          complexity-threshold: '30'
          max-depth: '2'
```

### Custom Configuration
```yaml
- uses: ./
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    complexity-threshold: '50'
    max-depth: '4'
    prd-path-glob: 'planning/**.prd.md'
    breakdown-max-depth: '3'
    taskmaster-args: '--verbose --format json'
```

### Dry Run for Pull Requests
```yaml
name: Preview Tasks
on:
  pull_request:
    paths: ['docs/**.prd.md']

jobs:
  preview:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
      - uses: ./
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          dry-run: 'true'
```

## Troubleshooting

### Common Issues

1. **Rate Limit Errors**: Use the replay workflow with artifacts to recover from rate limit failures
2. **Sub-issues API Unavailable**: Ensure your repository has access to GitHub's Sub-issues REST API
3. **Invalid PRD Format**: Check PRD files against Taskmaster CLI documentation
4. **Permission Errors**: Verify the GitHub token has required permissions

### Recovery

If a workflow fails due to rate limits or API issues:

1. Check the uploaded artifacts in the failed run
2. Use the "Taskmaster Replay" workflow with the artifact URL
3. The replay will continue from where the original run failed

## Development

### Local Testing

To test this action locally:

1. Set up required environment variables
2. Install Taskmaster CLI
3. Run the action scripts directly

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## License

[MIT License](LICENSE)

## Support

For issues and questions:
- Check the [troubleshooting section](#troubleshooting)
- Review [Taskmaster CLI documentation](https://github.com/cmbrose/taskmaster)
- Open an issue in this repository