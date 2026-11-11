# Cheapest & Free ($0.00) LLM Providers Guide

`pca` is architected to run at **$0.00/month** using free developer tiers, or for **pennies per month** using ultra-cheap cached models. This document shows how to set up each supported provider.

---

## 1. Free Tier Providers ($0.00 / Month)

### Option A: GitHub Models (`github-models`) — *Best for Azure AVD*
- **Cost**: **$0.00 (Free)** with any GitHub account.
- **Endpoint**: `https://models.inference.ai.azure.com/chat/completions`
- **Why it's #1 for Windows AVD**: Hosted on Microsoft's `*.azure.com` domain, which is almost universally whitelisted on corporate Azure Virtual Desktop firewalls.
- **Available Models**:
  - Cheap tier (`-Tier cheap`): `gpt-4o-mini`
  - Smart tier (`-Tier smart`): `gpt-4o`, `DeepSeek-R1`, `Codestral-2501`
- **How to get a key (60 seconds)**:
  1. Go to GitHub -> **Settings** -> **Developer settings** -> **Personal access tokens**.
  2. Generate a token (no special repo scopes are required for GitHub Models inference).
  3. Set it in PowerShell:
     ```powershell
     $env:GITHUB_TOKEN = "ghp_your_token_here"
     .\pca.cmd -Provider github-models
     ```

---

### Option B: Google Gemini AI Studio (`gemini`) — *Gemini 3.8 Flash & 3.5 Flash-Lite (1M Context)*
- **Cost**: **$0.00 (Free)** on the Google AI Studio Free Tier (or introductory $0.75/1M input on paid tier for `gemini-3.8-flash`).
- **Endpoint**: `https://generativelanguage.googleapis.com/v1beta/openai/chat/completions`
- **Available Models**:
  - Cheap tier (`-Tier cheap`): `gemini-3.5-flash-lite`
  - Smart tier (`-Tier smart`): **`gemini-3.8-flash`** (Google's flagship agentic software engineering Flash model)
  - Also supports: `gemini-3.7-flash`, `gemini-3.6-flash`, `gemini-2.5-flash` via `-Model <name>`
- **How to get a key & run `gemini-3.8-flash`**:
  1. Visit [Google AI Studio](https://aistudio.google.com/apikey) and click **Create API Key**.
  2. Set it in PowerShell and launch with `-Tier smart` or `-Model gemini-3.8-flash`:
     ```powershell
     $env:GEMINI_API_KEY = "AIzaSy..."
     .\pca.cmd -Provider gemini -Model gemini-3.8-flash
     ```

---

### Option C: OpenRouter Free Coding Models (`openrouter`)
- **Cost**: **$0.00 (Free)** for any model ending with `:free`.
- **Endpoint**: `https://openrouter.ai/api/v1/chat/completions`
- **Available Free Coding Models**:
  - Cheap tier (`-Tier cheap`): `qwen/qwen3-coder:free`
  - Smart tier (`-Tier smart`): `deepseek/deepseek-chat-v3-0324:free`
  - Other free options (`/model <name>`): `meta-llama/llama-3.3-70b-instruct:free`, `google/gemma-3-27b-it:free`
- **How to get a key**:
  1. Sign up at [OpenRouter](https://openrouter.ai/keys) and create a key (no credit purchase required to use `:free` models).
  2. Set it in PowerShell:
     ```powershell
     $env:OPENROUTER_API_KEY = "sk-or-v1-..."
     .\pca.cmd -Provider openrouter
     ```

---

### Option D: Groq Cloud Free Developer Tier (`groq`)
- **Cost**: **$0.00 (Free)** rate-limited developer tier.
- **Endpoint**: `https://api.groq.com/openai/v1/chat/completions`
- **Available Models**:
  - Cheap tier (`-Tier cheap`): `llama-3.1-8b-instant` (~800 tokens/sec)
  - Smart tier (`-Tier smart`): `llama-3.3-70b-versatile` (~300 tokens/sec)
- **Setup**:
  ```powershell
  $env:GROQ_API_KEY = "gsk_..."
  .\pca.cmd -Provider groq
  ```

---

## 2. Ultra-Cheap Paid Providers ($0.02 – $0.27 per 1M Tokens)

When you need unlimited rate limits without hitting free-tier quotas, these providers cost less than **$0.50 for an entire month** of daily coding:

| Provider | Model | Uncached Input / 1M | Cached Input / 1M | Output / 1M | Typical 20-Turn Coding Session Cost |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`deepseek`** | `deepseek-chat` (V3) | $0.27 | **$0.07** | $1.10 | **~$0.004** (less than half a cent) |
| **`gemini`** (Paid) | `gemini-2.5-flash-lite` | $0.075 | **$0.018** | $0.30 | **~$0.001** (one-tenth of a cent) |
| **`openai`** | `gpt-4.1-nano` | $0.10 | **$0.025** | $0.40 | **~$0.002** |
| **`openai`** | `gpt-4.1-mini` | $0.40 | **$0.10** | $1.60 | **~$0.008** |

### Why DeepSeek + `pca` Prompt Caching Is So Cheap
`pca` places your static system prompt, tool definitions, and pinned files (`/add`) at the very beginning of every API request. DeepSeek's automatic context caching recognizes this prefix and charges **$0.07 per 1M tokens** (a **74% discount**) automatically on every subsequent turn in your session.

---

## 3. Saving Your Provider Configuration Permanently (`.pca.json`)

Instead of exporting environment variables every time you open PowerShell, you can generate a `.pca.json` config file:

```powershell
.\pca.cmd -InitConfig
```

Or create `$HOME\.pca.json` on your Windows AVD:
```json
{
  "provider": "github-models",
  "tier": "cheap",
  "model": "gpt-4o-mini",
  "api_key": "ghp_your_token_here",
  "max_session_cost_usd": 0.50,
  "max_tool_steps": 12,
  "max_read_lines": 200,
  "auto_approve": false
}
```
*(Note: `.pca.json` is listed in `.gitignore` so your API key is never accidentally committed to git.)*
