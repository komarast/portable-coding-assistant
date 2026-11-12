# First-Time Setup Guide (2 Minutes on Windows AVD)

Follow these **4 simple steps** to run the Portable Coding Assistant (`pca`) for the first time on a corporate **Windows Azure Virtual Desktop (AVD)** — with **no Python, no Node.js, and no admin rights required**.

---

## Step 1: Put `pca.ps1` on Your Windows AVD

Open **PowerShell** inside your Windows AVD and create a folder for `pca`:

```powershell
mkdir $HOME\pca -Force | Out-Null
cd $HOME\pca
```

Now choose **Option A** (if GitHub is reachable) or **Option B** (if downloads are blocked):

### Option A: Download with 1 Command
```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/komarast/portable-coding-assistant/main/pca.ps1" -OutFile pca.ps1
```

### Option B: Copy-Paste Over RDP Clipboard (Works Even When Downloads Are Blocked!)
1. On your personal computer, open [`pca.ps1`](pca.ps1) on GitHub, press `Ctrl+A`, then `Ctrl+C` to copy the text.
2. Inside your Windows AVD PowerShell window, run:
   ```powershell
   Get-Clipboard | Set-Content -Path .\pca.ps1 -Encoding UTF8
   ```

---

## Step 2: Check Which AI Providers Are Allowed by Your Corporate Firewall

Run this command in PowerShell (you do **not** need an API key yet):

```powershell
powershell -ExecutionPolicy Bypass -File .\pca.ps1 -TestEndpoints
```

You will see a table showing which AI endpoints are **`ALLOWED`** and which are **`BLOCKED`** on your corporate network:
- If **`gemini`** (`generativelanguage.googleapis.com`) says **`ALLOWED`** -> Use a free **Google AI Studio Key** (`GEMINI_API_KEY`).
- If **`claude`** (`api.anthropic.com`) says **`ALLOWED`** -> Use an **Anthropic Claude Key** (`ANTHROPIC_API_KEY`) with `cheap` (`claude-haiku-5-5`), `smart` (`claude-sonnet-5-5`), or `opus` (`claude-opus-5-5`).
- If **`openrouter`** (`openrouter.ai`) says **`ALLOWED`** -> Use a free **OpenRouter Key** (`OPENROUTER_API_KEY`).
- If **`groq`** (`api.groq.com`) says **`ALLOWED`** -> Use a free **Groq Developer Key** (`GROQ_API_KEY`).
*(Note: GitHub permanently retired the free `github-models` API on July 30, 2026.)*

---

## Step 3: Get an API Key & Save It Securely

1. Get an API key (you can generate this on your personal PC or phone if your AVD browser blocks sign-up pages):
   - **For `gemini` (Default — Free / Gemini 3.8 Flash)**: Go to [aistudio.google.com/apikey](https://aistudio.google.com/apikey) -> Click **Create API Key** (`AIzaSy...`).
   - **For `claude` (Anthropic Claude 5.5 Haiku / Sonnet / Opus)**: Go to [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys) -> Click **Create Key** (`sk-ant-...`).
   - **For `openrouter` (Free coding models)**: Go to [openrouter.ai/keys](https://openrouter.ai/keys) -> Click **Create Key** (`sk-or-v1-...`).
   - **For `groq` (Free developer tier)**: Go to [console.groq.com/keys](https://console.groq.com/keys) -> Click **Create API Key** (`gsk_...`).

2. Launch `pca` on your Windows AVD:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\pca.ps1
   ```

3. Inside the `pca>` prompt, select your allowed provider and save your API key (encrypted with Windows DPAPI so you never have to type it again):
   ```text
   pca> /provider claude
   pca> /key save
   Enter API key for 'claude' (input is hidden): ********************
   ```
   *(Or for Gemini / OpenRouter / Groq, run `/provider gemini`, `/provider openrouter`, or `/provider groq` and then `/key save`.)*

---

## Step 4: Start Using Your Coding Assistant!

Navigate to any code or **UiPath Studio** project folder and start `pca`:

```powershell
cd C:\Users\YourName\Documents\UiPath\MyProject
powershell -ExecutionPolicy Bypass -File $HOME\pca\pca.ps1
```

### Common Things You Can Ask Right Away:
- **Understand a project**:
  ```text
  pca> Explain the structure of this project and what Main.xaml does
  ```
- **Switch between Model Tiers (`cheap`, `smart`, `opus`)**:
  ```text
  pca> /tier cheap     # claude-haiku-5-5  or gemini-3.5-flash-lite
  pca> /tier smart     # claude-sonnet-5-5 or gemini-3.8-flash
  pca> /tier opus      # claude-opus-5-5   or gemini-2.5-pro
  ```
- **Edit code or fix a bug**:
  ```text
  pca> Find where the timeout is configured and change it from 15 to 60
  ```
  *(It will show you a red/green diff preview and ask `Allow this action? [y/n/a]` before changing any file!)*
- **Undo the last change if needed**:
  ```text
  pca> /undo
  ```
- **Check your token & cost usage**:
  ```text
  pca> /cost
  ```
- **Exit**:
  ```text
  pca> /exit
  ```

---

## Optional Bonus: Create a `pca.exe` Shortcut So You Can Type `pca` Anywhere

If you don't want to type `powershell -ExecutionPolicy Bypass -File ...` every time, run this once:

```powershell
cd $HOME\pca
powershell -ExecutionPolicy Bypass -File .\pca.ps1 -CompileExe
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
[Environment]::SetEnvironmentVariable("Path", "$userPath;$HOME\pca", "User")
```

Close and reopen PowerShell. Now you can just type **`pca`** from any folder!
