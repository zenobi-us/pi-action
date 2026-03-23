# Gitclaw

A personal AI assistant that runs entirely through GitHub Issues and Actions. Like [OpenClaw](https://github.com/openclaw/openclaw), but no servers or extra infrastructure.

Powered by the [pi coding agent](https://github.com/badlogic/pi-mono). Every issue becomes a chat thread with an AI agent. Conversation history is committed to git, giving the agent long-term memory across sessions. It can search prior context, edit or summarize past conversations, and all changes are versioned.

Since the agent can read and write files, you can build an evolving software project that updates itself as you open issues. Try asking it to set up a GitHub Pages site, then iterate on it issue by issue.

## How it works

1. **Create an issue** → the agent processes your request and replies as a comment.
2. **Comment on the issue** → the agent resumes the same session with full prior context.
3. **Everything is committed** → sessions and changes are pushed to the repo after every turn.

The agent reacts with 👀 while working and removes it when done.

Gitclaw is a pair of reusable [composite actions](https://docs.github.com/en/actions/sharing-automations/creating-actions/creating-a-composite-action) (`authorise` and `agent`) triggered by issue and comment events. Your repo consumes them via `uses: zenobi-us/pi-action/agent@main` — you don't fork this repo.

### Repo as storage

All state lives in your repo:

```
state/
  issues/
    1.json          # maps issue #1 → its session file
  sessions/
    2026-02-04T..._abc123.jsonl    # full conversation for issue #1
```

Since sessions are in git, the agent can grep its own history and edit or summarize past conversations.

### Agent identity

The first time you open a 🥚 Hatch issue, the agent bootstraps its own identity — picking a name, personality, and communication style through conversation with you. This identity persists across sessions via `AGENTS.md` and shapes how the agent behaves in your repo.

## Prerequisites

- A GitHub repository (public or private)
- A [pi coding agent](https://github.com/badlogic/pi-mono) auth configuration (`auth.json`) with your LLM provider credentials
- GitHub Actions enabled on your repo

> **Cost note:** Each agent turn consumes LLM API tokens via GitHub Actions. Monitor your provider usage.

## Setup

1. **Scaffold your repo** — run from your repo root:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/zenobi-us/pi-action/main/setup.sh | sh
   ```
   This adds the workflow, issue templates, and agent config without overwriting existing files.

2. **Add your auth secret** — go to **Settings → Secrets and variables → Actions** and create a secret named `PI_AUTH_JSON`.

   This should contain your pi `auth.json` as a single-line JSON string. The format is provider-keyed:
   ```json
   {
     "anthropic": {
       "type": "oauth",
       "access": "sk-ant-...",
       "refresh": "...",
       "expires": "2026-12-31T00:00:00Z"
     }
   }
   ```
   The easiest way to get this is to run `pi` locally, authenticate, then copy `~/.pi/auth.json` collapsed to one line:
   ```bash
   jq -c . ~/.pi/auth.json | pbcopy   # macOS
   jq -c . ~/.pi/auth.json | xclip    # Linux
   ```

3. **Commit and push** the scaffolded files:
   ```bash
   git add -A
   git commit -m "chore: add gitclaw agent template"
   git push
   ```

4. **Open an issue** — the agent processes your request and replies as a comment.

5. **Comment on the issue** — the agent resumes the same session with full prior context.

## Security

The workflow only responds to repository **owners, members, and collaborators**. Random users cannot trigger the agent on public repos. The `github-actions[bot]` user is explicitly rejected to prevent loops.

If you plan to use gitclaw for anything private, **make the repo private**. Public repos mean your conversation history is visible to everyone, but get generous GitHub Actions usage.

## Configuration

Edit `.github/workflows/agent.yml` to customize agent behavior:

| Option | How | Example |
|--------|-----|---------|
| Model | Add `--provider` and `--model` flags to the `bunx pi` command in `agent.sh` | `--provider anthropic --model claude-sonnet-4-20250514` |
| Tools | Restrict available tools | `--tools read,grep,find,ls` (read-only) |
| Thinking | Enable extended thinking for complex tasks | `--thinking high` |
| Trigger | Adjust the `on:` block in the workflow | Filter by labels, assignees, etc. |

## Action Reference

### `zenobi-us/pi-action/authorise`

Checks whether the triggering actor is an authorized owner, member, or collaborator. Rejects `github-actions[bot]` to prevent recursive triggers.

| Output | Type | Description |
|--------|------|-------------|
| `authorized` | `string` | `"true"` if actor is authorized, `"false"` otherwise |

### `zenobi-us/pi-action/agent`

Sets up the runtime environment (mise, bun, pi auth), builds a prompt from the issue or comment, and runs the pi agent.

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `PiAuthJson` | yes | — | Pi `auth.json` contents as a single-line JSON string |
| `GitHubToken` | yes | — | GitHub token with `contents`, `issues`, `actions` write permissions |
| `BunVersion` | no | `latest` | Bun version to install via mise |

| Output | Type | Description |
|--------|------|-------------|
| `response` | `string` | The agent's response text |

### Example workflow

```yaml
name: Gitclaw Agent

on:
  issues:
    types: [opened]
  issue_comment:
    types: [created]

permissions:
  contents: write
  issues: write
  actions: read

jobs:
  agent:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: zenobi-us/pi-action/authorise@main
        id: auth

      - uses: zenobi-us/pi-action/agent@main
        if: steps.auth.outputs.authorized == 'true'
        id: agent
        with:
          PiAuthJson: ${{ secrets.PI_AUTH_JSON }}
          GitHubToken: ${{ secrets.GITHUB_TOKEN }}

      - name: Comment on issue
        if: steps.auth.outputs.authorized == 'true'
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          response="${{ steps.agent.outputs.response }}"
          gh issue comment "${{ github.event.issue.number }}" --body "${response:0:60000}"
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Workflow doesn't trigger | Issue events not enabled | Check the `on:` block includes `issues` and `issue_comment` |
| Agent fails with auth error | Wrong secret name or format | Ensure `PI_AUTH_JSON` contains valid pi auth JSON (see [Setup](#setup)) |
| No comment posted | Authorization check failed | Verify actor is repo owner, member, or collaborator |
| Push conflicts on concurrent issues | Simultaneous agent runs | Agent retries 3 times with rebase; stagger issue activity or serialize via concurrency groups |
| Broken session resumption | Session file deleted or moved | Check `state/issues/<N>.json` points to a valid `.jsonl` file |

## Acknowledgments

Built on top of [pi-mono](https://github.com/badlogic/pi-mono) by [Mario Zechner](https://github.com/badlogic).

Thanks to [ymichael](https://github.com/ymichael) for nerdsniping me with the idea of an agent that runs in GitHub Actions.

## License

[Apache 2.0](LICENSE)
