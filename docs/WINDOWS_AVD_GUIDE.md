# Windows AVD & Corporate VM Deployment Guide

This guide explains how to deploy, configure, and troubleshoot **Portable Coding Assistant (`pca`)** inside locked-down **Windows Azure Virtual Desktop (AVD)**, Citrix VDI, or corporate bastion VMs where **no Python, no Node.js, no admin rights, and no package managers** are available.

---

## 1. Prerequisites (Already Installed on Every Windows AVD)

You do **not** need to install anything. `pca.ps1` uses only built-in OS components present on every Windows 10, Windows 11, and Windows Server image:
- **Windows PowerShell 5.1** (`C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`)
- **.NET Framework 4.8** (`System.Net.HttpWebRequest`, `System.IO`, and `csc.exe`)

---

## 2. How to Transfer `pca` Onto a Locked-Down Windows AVD

Corporate AVDs often block browser downloads, USB drives, or file uploads. Choose whichever transfer method works in your environment:

### Method 1: RDP Clipboard Copy-Paste (Works When All Downloads Are Blocked)
If your AVD allows text copy-paste between your local PC and the remote session:
1. On your local machine, open [`pca.ps1`](../pca.ps1), select all (`Ctrl+A`), and copy (`Ctrl+C`).
2. Inside your Windows AVD, open **PowerShell** and run:
   ```powershell
   mkdir $HOME\pca -Force | Out-Null
   cd $HOME\pca
   Get-Clipboard | Set-Content -Path .\pca.ps1 -Encoding UTF8
   ```
3. Optional: Create the `pca.cmd` launcher so you can type `pca` from any prompt:
   ```powershell
   '@echo off' | Set-Content .\pca.cmd -Encoding ASCII
   'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0pca.ps1" %*' | Add-Content .\pca.cmd -Encoding ASCII
   ```

### Method 2: Base64 Chunk Copy-Paste (If Special Characters Get Mangled by Clipboard)
If your VDI clipboard strips newlines or quotes:
1. On your local machine, encode `pca.ps1` to Base64:
   - **Windows**: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("pca.ps1")) | Set-Clipboard`
   - **Linux/macOS**: `base64 -w0 pca.ps1`
2. On the Windows AVD, decode it back to `pca.ps1`:
   ```powershell
   $b64 = Get-Clipboard
   [IO.File]::WriteAllBytes("$PWD\pca.ps1", [Convert]::FromBase64String($b64))
   ```

### Method 3: Direct PowerShell Download (If GitHub Is Reachable)
```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/komarast/portable-coding-assistant/main/pca.ps1" -OutFile pca.ps1
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/komarast/portable-coding-assistant/main/pca.cmd" -OutFile pca.cmd
```

---

## 3. Bypassing PowerShell ExecutionPolicy Restrictions (Without Admin Rights)

Many corporate AVDs set PowerShell's `ExecutionPolicy` to `Restricted` or `AllSigned`, which blocks running `.ps1` scripts directly (`.\pca.ps1 cannot be loaded because running scripts is disabled on this system`).

You can run `pca` **without administrator privileges** in three ways:

### Option A: Use `pca.cmd` (Recommended)
`pca.cmd` launches PowerShell with `-ExecutionPolicy Bypass` scoped only to that process:
```cmd
.\pca.cmd "Analyze this folder"
```

### Option B: Unblock Current Process in PowerShell
Run this once per PowerShell window:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\pca.ps1
```

### Option C: Compile a Native `pca.exe` Binary On-Device
Windows includes a built-in C# compiler inside `.NET Framework`. Run:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\pca.ps1 -CompileExe
```
This produces `pca.exe` in the same folder. You can then add `$HOME\pca` to your user `PATH`:
```powershell
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
[Environment]::SetEnvironmentVariable("Path", "$userPath;$HOME\pca", "User")
```
Now you can run `pca` from **any** folder in Command Prompt or PowerShell!

---

## 4. Corporate Firewalls, Proxies, and TLS Inspection (Zscaler / Netskope)

### How `pca` Handles Corporate Proxies Automatically
Unlike Python (`requests`/`urllib`) or Node.js (`fetch`), which ignore Windows PAC files and fail on corporate SSL inspection unless you manually export `.pem` certificates, `pca.ps1` uses `.NET`'s native `HttpWebRequest`:
1. **Automatic System Proxy & PAC Support**: Calls `[System.Net.WebRequest]::GetSystemWebProxy()` and attaches `[System.Net.CredentialCache]::DefaultCredentials` (your logged-in Windows Active Directory / Entra ID session credentials).
2. **Automatic Windows Certificate Store Trust**: Any corporate Root CA pushed by Group Policy/Intune into the Windows Certificate Store is automatically trusted.

### If Your Corporate Proxy Requires Self-Signed Cert Bypass
If an internal LLM gateway uses an untrusted self-signed certificate, pass `-SkipCertCheck`:
```powershell
.\pca.cmd -SkipCertCheck "Hello"
```

### Choosing an Endpoint That Passes Corporate Firewalls
If your corporate AVD blocks consumer AI sites (`openai.com`, `openrouter.ai`, `deepseek.com`):
- **Try `github-models` first**: Its endpoint is `https://models.inference.ai.azure.com/chat/completions`. Because it lives under **`*.azure.com`**, almost all Azure Virtual Desktop environments allow outbound HTTPS traffic to it!
- **Try `gemini` second**: Its endpoint is `https://generativelanguage.googleapis.com/...` under **`*.googleapis.com`**, which is commonly allowed when Google Workspace/Chrome is permitted.
- **Try `azure-openai`**: If your company has an internal Azure OpenAI resource, set `base_url` in `.pca.json` to your internal endpoint.
