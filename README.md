# Portable Coding Assistant (`pca`)

A **zero-dependency, single-file agentic CLI coding assistant** designed specifically for **locked-down corporate environments** such as **Windows Azure Virtual Desktop (AVD)**, Citrix VDI, or minimal Linux VMs where **no Python, no Node.js, and no third-party libraries are installed**.

---

## Why `pca` Works on Locked-Down Windows AVD

1. **Zero Installed Languages Required**: Runs directly on stock **Windows PowerShell 5.1** and **.NET Framework 4.8**, which are pre-installed on 100% of Windows 10, Windows 11, and Windows Server AVD images.
2. **No `.exe` Download Required (AppLocker / SmartScreen Safe)**: Because [`pca.ps1`](pca.ps1) is plain text, you can even **copy-paste it over your RDP clipboard** into Notepad if file transfers or binary downloads are blocked.
3. **Optional Self-Compiling `pca.exe`**: If you want a native `.exe` binary on Windows, run `.\pca.ps1 -CompileExe` — it uses Windows' built-in `.NET` compiler (`csc.exe`) to compile `pca.exe` locally on the VM without Visual Studio or any SDK.
4. **Automatic Corporate Proxy & SSL Inspection Support**: Uses `.NET`'s `System.Net.WebRequest.GetSystemWebProxy()` with `DefaultCredentials` and the **Windows Certificate Store**, so corporate proxies (Zscaler, Netskope, Azure Firewall) and enterprise Root CAs work out of the box.

---

## Detailed Documentation Guides

- **[Windows AVD & Corporate VM Deployment Guide](docs/WINDOWS_AVD_GUIDE.md)** — How to transfer `pca` onto a restricted AVD via RDP Clipboard or Base64, bypass `ExecutionPolicy` without admin rights, compile `pca.exe` locally, and handle corporate proxies/firewalls.
- **[Cheapest & Free ($0.00) LLM Providers Guide](docs/CHEAPEST_LLM_PROVIDERS.md)** — Step-by-step instructions to get free API keys (`github-models` on `*.azure.com`, `gemini`, `openrouter`, `groq`) and ultra-cheap cached models (`deepseek`, `openai`).
- **[UiPath Skills & Automation Guide](docs/UIPATH_SKILLS_GUIDE.md)** — How to use `pca` with UiPath Studio `.xaml` workflows, `project.json`, `inspect_xaml` (90%+ token savings on large `.xaml` files), Selectors, VB.NET/C# LINQ, and Coded Workflows.
- **[Usage & Practical Workflows Guide](docs/USAGE_AND_WORKFLOWS.md)** — Full command-line flags reference, interactive REPL slash commands, one-shot tasks, piping `git diff`/logs, and token-saving habits.
- **[Architecture & Agentic Tool Protocol](docs/ARCHITECTURE_AND_TOOLS.md)** — How the built-in tools (`list_files`, `search_text`, `read_file`, `inspect_xaml`, `edit_file`, `run_command`), `SEARCH/REPLACE` patching, and prompt cache alignment work under the hood.

---

## Cheapest & Free ($0.00) LLM Providers

`pca` includes built-in profiles for **4 completely free ($0.00/month)** tiers and ultra-cheap paid tiers:

| Provider (`-Provider`) | Default Cheap Model | Smart Model (`-Tier smart`) | Cost / 1M Tokens | Why Use It on Corporate AVD? |
| :--- | :--- | :--- | :--- | :--- |
| **`github-models`** *(Default)* | `gpt-4o-mini` | `gpt-4o` | **$0.00 (FREE)** | Uses any GitHub Personal Access Token (`GITHUB_TOKEN`). Hosted on **`models.inference.ai.azure.com`** (`*.azure.com`), which is almost always whitelisted on Azure AVD firewalls! |
| **`gemini`** | `gemini-3.5-flash-lite` | `gemini-3.8-flash` | **$0.00 (FREE)** / $0.75 intro | Free tier via Google AI Studio (`GEMINI_API_KEY`) with 1M context window and `gemini-3.8-flash` agentic coding model. |
| **`openrouter`** | `qwen/qwen3-coder:free` | `deepseek/deepseek-chat-v3-0324:free` | **$0.00 (FREE)** | Free coding models via `OPENROUTER_API_KEY`. |
| **`groq`** | `llama-3.1-8b-instant` | `llama-3.3-70b-versatile` | **$0.00 (FREE)** | Free developer tier (`GROQ_API_KEY`) with ~500 tok/s speed. |
| **`deepseek`** | `deepseek-chat` (V3) | `deepseek-reasoner` (R1) | **$0.07** cached in | Automatic disk prompt caching cuts multi-turn coding costs by 75%. |
| **`openai`** | `gpt-4.1-nano` | `gpt-4.1-mini` | **$0.10** in (`$0.025` cached) | Ultra-low-cost OpenAI nano/mini models. |
| **`azure-openai`** | `gpt-4o-mini` | `gpt-4o` | Corporate Gateway | Connect to your company's internal Azure OpenAI endpoint. |
| **`ollama`** | `qwen2.5-coder:7b` | `qwen2.5-coder:14b` | **$0.00 (Local)** | 100% air-gapped local inference. |

---

## Quick Start on Windows AVD (3 Transfer Methods)

### Method A: RDP Clipboard Copy-Paste (Works Even When Downloads Are Blocked)
1. On your local machine, open [`pca.ps1`](pca.ps1) and copy its contents (`Ctrl+A`, `Ctrl+C`).
2. Inside your Windows AVD session, open **PowerShell** and paste the clipboard directly into a file:
   ```powershell
   Get-Clipboard | Set-Content -Path .\pca.ps1 -Encoding UTF8
   ```
3. Set your free API key (e.g. GitHub PAT or Gemini key) and run:
   ```powershell
   $env:GITHUB_TOKEN = "ghp_your_token_here"
   powershell -ExecutionPolicy Bypass -File .\pca.ps1
   ```

### Method B: Single-Line PowerShell Download (If GitHub is Accessible)
```powershell
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/komarast/portable-coding-assistant/main/pca.ps1" -OutFile pca.ps1
```

### Method C: Compile a Native `pca.exe` on the AVD (No SDK Needed)
```powershell
powershell -ExecutionPolicy Bypass -File .\pca.ps1 -CompileExe
.\pca.exe "Explain this repository"
```

---

## Usage Examples

### 0. Test Which AI Endpoints Pass Your Corporate Firewall (`-TestEndpoints`)
Run this first on a corporate AVD (even before creating an API key) to see which AI endpoints are allowed through Zscaler/Netskope/corporate proxy:
```powershell
.\pca.cmd -TestEndpoints
```

### 1. Interactive Agentic REPL
```powershell
.\pca.cmd
```
Inside the REPL, the agent can inspect your workspace, search code, read specific line ranges, apply surgical `SEARCH/REPLACE` patches (with diff preview and confirmation), and run commands:
```text
pca (github-models:cheap)> Find where SQL connection strings are built and add retry logic
```

### 2. One-Shot Command Line Mode
```powershell
.\pca.cmd "Find all TODO comments and summarize them"
.\pca.cmd -Provider gemini -Tier smart "Refactor utils.ps1 to handle null inputs safely"
```

### 3. Pipe Mode (Code Review / Log Analysis)
```powershell
git diff | .\pca.cmd "Review this diff for bugs or security issues"
Get-Content error.log -Tail 100 | .\pca.cmd "Diagnose this crash"
```

### 4. Linux / macOS VMs ([`pca.sh`](pca.sh))
```bash
chmod +x pca.sh
export GITHUB_TOKEN="ghp_your_token_here"
./pca.sh "Inspect the project structure and run tests"
```

---

## Interactive Slash Commands

| Command | Description |
| :--- | :--- |
| `/test [prov\|url]` | Test which AI endpoints are allowed or blocked by your corporate firewall/proxy |
| `/provider [name]` | List all free/cheap providers or switch active provider on the fly |
| `/model [name]` | View or switch the active model ID (e.g. `/model gemini-3.8-flash`) |
| `/tier <cheap\|smart>` | Switch between `cheap` (fast/free) and `smart` (reasoning/frontier) models |
| `/skill [name\|off]` | Activate a domain skill (e.g. `/skill uipath`) or turn skills off |
| `/add <file>` | Pin a file to the cached system prompt context |
| `/drop [file\|all]` | Unpin a file or clear all pinned files |
| `/files` | Display workspace directory tree |
| `/undo` | Revert the last file edit or file creation made by the assistant |
| `/compact` | Compress older conversation turns to save input tokens |
| `/cost` | Show session prompt tokens, cached hit tokens, output tokens, and USD spent |
| `/init` | Generate a `.pca.json` configuration file in the current directory |
| `/clear` | Clear conversation history |
| `/exit` | Quit `pca` |

---

## How `pca` Minimizes Token Costs

1. **Compact `SEARCH / REPLACE` File Patching**: Output tokens cost 3x–4x more than input tokens. Instead of regenerating entire files, `pca` instructs the LLM to emit minimal `search`/`replace` blocks and applies them transactionally with `/undo` backup.
2. **Surgical Line-Range Reads**: `read_file` caps reads at 200 lines per call so large files never flood your context window.
3. **Prompt Cache Prefix Alignment**: System instructions, tool schemas, and pinned files are ordered deterministically at the start of the request so DeepSeek, OpenAI, and Gemini apply **50%–90% cached input discounts** automatically.
4. **Automatic History Compaction**: Older tool outputs and long messages are automatically summarized after 10 turns (or on demand with `/compact`).
5. **Hard Session Cost Cap**: Enforces `max_session_cost_usd` (default `$0.50`) so a runaway loop can never surprise you with a bill.
