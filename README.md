# Task-Planning GitHub Action

Automatically generate hierarchical task graphs from Product Requirements Document (PRD) files and create GitHub Issues with dependency management.

## Features

- 🔄 **Automated Task Generation**: Converts PRD files into structured task graphs
- 📋 **GitHub Issues Integration**: Creates Issues with proper hierarchy and dependencies
- 🔗 **Dependency Management**: Automatically manages blocked/unblocked status based on dependencies
- 🎯 **Manual Breakdown**: On-demand task breakdown via `/breakdown` slash commands
- 📦 **Artifact Storage**: Durable storage for task graphs to enable replay workflows
- 🔍 **Dry-Run Mode**: Preview task graphs in pull requests without creating Issues

## Quick Start

### Basic Usage

1. **Add the Action to your repository**:

Create `.github/workflows/taskmaster-generate.yml`:

```yaml
name: Generate Task Graph from PRD

on:
  push:
    paths:
      - 'docs/**.prd.md'
    branches:
      - main

permissions:
  issues: write
  contents: read
  actions: read

jobs:
  generate-tasks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: your-org/task-planning-action@v1
        with:
          complexity-threshold: '40'
          max-depth: '3'
```

2. **Create a PRD file**:

Add a `.prd.md` file in your `docs/` directory with your project requirements.

3. **Commit and Push**: The action will automatically generate Issues from your PRD.

## Configuration

### Inputs

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `complexity-threshold` | Complexity threshold for task breakdown | `40` | No |
| `max-depth` | Maximum recursion depth for auto breakdown | `3` | No |
| `prd-path-glob` | POSIX glob pattern for PRD files | `docs/**.prd.md` | No |
| `breakdown-max-depth` | Maximum additional depth for manual breakdown | `2` | No |
| `taskmaster-args` | Additional arguments to pass to Taskmaster CLI | `''` | No |

### Outputs

| Output | Description |
|--------|-------------|
| `task-graph-path` | Path to the generated task graph JSON file |
| `issues-created` | Number of GitHub Issues created |
| `artifact-url` | URL of the uploaded task graph artifact |

## Workflows

This action includes several workflows:

### 1. Task Generation (`taskmaster-generate.yml`)
- **Trigger**: Push to PRD files
- **Purpose**: Generate task graphs and create Issues
- **Permissions**: `issues: write`, `contents: read`

### 2. Dependency Watcher (`taskmaster-watcher.yml`)
- **Trigger**: Issue closed events + cron every 10 minutes
- **Purpose**: Remove 'blocked' labels when dependencies are resolved
- **Permissions**: `issues: write`, `contents: read`

### 3. Manual Breakdown (`taskmaster-breakdown.yml`)
- **Trigger**: Issue comments containing `/breakdown`
- **Purpose**: On-demand task breakdown
- **Permissions**: `issues: write`, `contents: read`

### 4. Task Replay (`taskmaster-replay.yml`)
- **Trigger**: Manual dispatch
- **Purpose**: Replay task generation from stored artifacts
- **Permissions**: `issues: write`, `contents: read`, `actions: read`

### 5. Dry Run Preview (`taskmaster-dry-run.yml`)
- **Trigger**: Pull requests to PRD files
- **Purpose**: Preview task graphs without creating Issues
- **Permissions**: `contents: read`, `pull-requests: write`

## Manual Task Breakdown

You can request additional breakdown of any Issue by commenting:

```
/breakdown
```

With optional parameters:

```
/breakdown --depth 2 --threshold 30
```

Parameters:
- `--depth N`: Maximum additional breakdown depth
- `--threshold X`: Complexity threshold for breakdown

## Issue Format

Created Issues include YAML front-matter with metadata:

```yaml
---
id: "task-123"
parent: "task-100"
depends_on: ["task-121", "task-122"]
complexity: 35
generated_by: "taskmaster-v1.0"
---

# Task Title

Task description here...

## Implementation Details

Detailed implementation steps...

## Test Strategy

Testing approach...
```

## Labels

The action uses these labels:

- `task`: Applied to all generated tasks
- `blocked`: Applied when dependencies are not yet resolved
- `parent-task`: Applied to tasks that have subtasks
- `leaf-task`: Applied to tasks with no subtasks

## Recovery and Replay

If a workflow fails, you can replay it using the stored artifact:

1. Go to Actions → Task Graph Replay
2. Provide the artifact URL or run ID
3. Run the workflow to recreate Issues

## Best Practices

1. **PRD Structure**: Use clear hierarchical structure in your PRD files
2. **Complexity Management**: Adjust `complexity-threshold` based on your team's capacity
3. **Dependency Tracking**: Use the dependency watcher to keep Issues up-to-date
4. **Manual Breakdown**: Use `/breakdown` for tasks that seem too large during execution

## Troubleshooting

### Common Issues

**No Issues Created**
- Check that your PRD file matches the `prd-path-glob` pattern
- Verify the workflow has `issues: write` permission
- Check action logs for Taskmaster CLI errors

**Blocked Labels Not Updating**
- Ensure the dependency watcher workflow is enabled
- Check that Issue descriptions contain proper YAML front-matter
- Verify dependency Issue numbers are correct

**Dry Run Not Working**
- Confirm the dry-run workflow has `pull-requests: write` permission
- Check that the PR modifies files matching the PRD path pattern

## Requirements

- GitHub repository with Issues enabled
- GitHub Actions enabled
- Proper permissions configured for workflows

## Support

For issues and feature requests, please use the GitHub Issues in this repository.

## License

[License information here]