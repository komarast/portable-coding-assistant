# Usage & Practical Workflows Guide

This manual covers all command-line flags, interactive REPL commands, and day-to-day workflows for using `pca` on Windows (`pca.cmd` / `pca.ps1`) and Linux/macOS (`pca.sh`).

---

## 1. Three Ways to Run `pca`

### Mode 1: Interactive Agentic REPL (Multi-Turn Coding Session)
Start `pca` without a prompt to enter the interactive loop:
```powershell
.\pca.cmd
```
Example interactive session:
```text
  +----------------------------------------------------------------------+
  |  PCA v1.0.0 - Portable Coding Assistant (Windows AVD Zero-Dep Edition) |
  +----------------------------------------------------------------------+
  Provider : github-models | Model: gpt-4o-mini (cheap tier)
  Workspace: C:\Projects\InventoryService

pca (github-models:cheap)> Find where the SQL connection timeout is set and increase it to 60 seconds
  -> [Tool: search_text]
  -> [Tool: read_file]

  [Action Confirmation] Patch 'src/Database.cs'
    -     public const int CommandTimeoutSeconds = 15;
    +     public const int CommandTimeoutSeconds = 60;
  Allow this action? [y = yes / n = no / a = always in session]: y
  -> [Tool: edit_file]

Updated `CommandTimeoutSeconds` from 15 to 60 in `src/Database.cs`.
  [Tokens: 612 in (480 cached) / 48 out | Turn: $0.00000 | Session: $0.00000 / $0.50 cap]
```

### Mode 2: One-Shot Command Line Task
Pass your instruction directly as arguments. `pca` will run the agentic loop, execute any needed tools, print the answer, and exit:
```powershell
# Ask a question or perform a task in one command
.\pca.cmd "List all PowerShell scripts in this repo and explain what each does"

# Auto-approve file edits for automated refactoring
.\pca.cmd -AutoApprove "Add error handling to scripts/deploy.ps1"

# Pure Q&A without workspace tools (fastest & lowest token usage)
.\pca.cmd -NoTools "Write a PowerShell one-liner to find processes using port 8080"
```

### Mode 3: Pipe Mode (`stdin` -> `pca`)
Pipe the output of any command (`git diff`, compiler logs, Windows Event Logs, CSV files) directly into `pca`:
```powershell
# Code review a staged git diff
git diff --cached | .\pca.cmd "Review this diff for bugs, edge cases, and security issues"

# Diagnose an application error log
Get-Content .\logs\app-error.log -Tail 80 | .\pca.cmd "What caused this exception and how do I fix it?"

# Analyze Windows Event Viewer errors on AVD
Get-EventLog -LogName Application -EntryType Error -Newest 10 | Format-List | Out-String | .\pca.cmd "Summarize these errors"
```

---

## 2. Command-Line Flags Reference

| Windows Flag (`pca.ps1` / `pca.cmd`) | Linux/macOS Flag (`pca.sh`) | Description |
| :--- | :--- | :--- |
| `-Provider <name>` | `--provider <name>` | Select LLM provider (`github-models`, `gemini`, `openrouter`, `groq`, `deepseek`, `openai`, `azure-openai`, `ollama`) |
| `-Tier <cheap\|smart>` | `--tier <cheap\|smart>` | Use the provider's `cheap` (fast/low-cost) or `smart` (reasoning/frontier) default model |
| `-Model <id>` | `--model <id>` | Override the exact model name (e.g. `-Model DeepSeek-R1`) |
| `-ApiKey <key>` | `--api-key <key>` | Pass API key directly (overrides environment variable and `.pca.json`) |
| `-BaseUrl <url>` | `--base-url <url>` | Override the OpenAI-compatible chat completions endpoint URL |
| `-AddFile <path>` | `--add <path>` | Pin one or more files into the system prompt context |
| `-AutoApprove` | `--auto-approve` / `-y` | Automatically approve file edits and shell commands without prompting |
| `-NoTools` | `--no-tools` | Disable agentic tool execution (pure chat/Q&A mode) |
| `-SkipCertCheck` | *(via env)* | Ignore self-signed SSL certificate errors on internal corporate gateways |
| `-CompileExe` | *(Windows only)* | Compile a standalone `pca.exe` binary using built-in `.NET` `csc.exe` |
| `-InitConfig` | *(REPL `/init`)* | Generate a starter `.pca.json` configuration file in the current directory |
| `-ListProviders` | `--list-providers` | Print table of all built-in free and ultra-cheap providers |
| `-Help` | `--help` / `-h` | Show help message and provider catalog |

---

## 3. Interactive Slash Commands Reference

While inside the interactive `pca>` prompt, use these slash commands to control context, models, and costs:

- **`/provider`** — Display all configured providers and which one is active.
- **`/provider <name>`** — Switch provider immediately (e.g. `/provider gemini` or `/provider deepseek`).
- **`/tier cheap` / `/tier smart`** — Start with `cheap` for exploration and file search; switch to `/tier smart` right before asking for a complex multi-file refactor, then switch back to `/tier cheap`.
- **`/model <name>`** — Switch to any specific model supported by your current provider (e.g. `/model Codestral-2501`).
- **`/add <relative/path>`** — Pin an important file (like an interface or config schema) so it stays in the cached system prompt prefix.
- **`/drop [file|all]`** — Unpin a file when you no longer need it in every turn's context.
- **`/files`** — Inspect the workspace directory tree (automatically ignores `.git`, `node_modules`, `bin`, `obj`, etc.).
- **`/undo`** — Immediately revert the last file edit or file creation performed by `pca`. You can run `/undo` multiple times to unwind a sequence of edits.
- **`/compact`** — Compress older tool outputs and conversation turns in memory to reduce input token usage by 60%–80% during long sessions.
- **`/cost`** — Display exact prompt tokens, cached hit tokens, completion tokens, and estimated USD cost for the session.
- **`/clear`** — Reset conversation history while keeping your provider/model settings.
- **`/exit`** or **`/quit`** — Exit the assistant.

---

## 4. Best Practices for Maximum Quality at Minimum Cost

1. **Use the Cheap-Then-Smart Workflow**:
   - Keep `pca` on `-Tier cheap` (e.g. `gpt-4o-mini` or `gemini-2.5-flash-lite`) while locating files and understanding the codebase.
   - Type `/tier smart` only for the turn that designs or applies a complex algorithm, then type `/tier cheap` again.
2. **Run `/compact` After Large Searches**:
   - Once the assistant has found the right file and applied a fix, run `/compact` (or `/clear` when starting an unrelated task) so old search results aren't resent on future turns.
3. **Use `/undo` Fearlessly**:
   - Every time `edit_file` modifies or creates a file, `pca` pushes the previous file snapshot onto an in-memory undo stack. If an edit isn't what you wanted, type `/undo` to restore the exact original bytes and line endings (`CRLF`/`LF`).
