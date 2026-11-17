<#
.SYNOPSIS
    Portable Coding Assistant (pca) - Zero-Dependency LLM Coding Agent for Windows AVD & Corporate VMs.
.DESCRIPTION
    Runs natively on stock Windows PowerShell 5.1+ (.NET Framework 4.8+) with ZERO external libraries,
    ZERO installed runtimes (no Python, no Node.js), and automatic Windows corporate proxy / Certificate Store integration.
    Supports Free ($0) and Ultra-Cheap LLM tiers:
      - github-models (models.github.ai - FREE with GitHub PAT)
      - gemini        (Google AI Studio Free Tier - gemini-3.8-flash / gemini-3.5-flash-lite)
      - openrouter    (Free coding models: qwen/qwen3-coder:free, deepseek/deepseek-chat-v3-0324:free)
      - groq          (Free developer tier: llama-3.3-70b-versatile)
      - deepseek      (Ultra-cheap with automatic disk prompt caching: $0.07/1M cached input)
      - openai        (gpt-4.1-nano / gpt-4.1-mini)
      - azure-openai  (Corporate internal Azure OpenAI endpoint)
      - ollama        (Local air-gapped models)
.EXAMPLE
    .\pca.ps1 "Find where database retries are configured and increase max_attempts to 5"
    git diff | .\pca.ps1 "Review this diff for bugs and security issues"
    .\pca.ps1 -Provider github-models -Tier cheap
    .\pca.ps1 -CompileExe
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$PromptArgs,

    [Parameter(ValueFromPipeline = $true)]
    [string]$PipelineInput,

    [string]$Provider = "",
    [string]$Model = "",
    [ValidateSet("", "cheap", "smart", "opus", "haiku", "sonnet")]
    [string]$Tier = "",
    [string]$ApiKey = "",
    [string]$BaseUrl = "",
    [string]$ConfigPath = "",
    [string[]]$AddFile = @(),
    [string[]]$Skill = @(),
    [switch]$AutoApprove,
    [switch]$NoTools,
    [switch]$SkipCertCheck,
    [switch]$CompileExe,
    [switch]$InitConfig,
    [switch]$ListProviders,
    [switch]$TestEndpoints,
    [switch]$Uip,
    [switch]$Help
)

begin {
    $ErrorActionPreference = "Stop"
    $Script:Version = "1.2.0"
    $Script:StartTime = Get-Date
    $Script:WorkspaceRoot = (Get-Location).Path
    $Script:ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $Script:PipeBuffer = New-Object System.Collections.Generic.List[string]

    # Enable TLS 1.2 and TLS 1.3 (3072) for modern HTTPS endpoints on Windows PowerShell 5.1
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor 3072
    } catch {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    }

    if ($SkipCertCheck) {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }

    # Built-in Provider Catalog (Free & Ultra-Cheap First)
    $Script:ProviderCatalog = @{
        "gemini" = @{
            Name        = "Google Gemini AI Studio (Gemini 3.8 Flash / 3.5 Flash-Lite)"
            BaseUrl     = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
            EnvKey      = "GEMINI_API_KEY"
            CheapModel  = "gemini-3.5-flash-lite"
            SmartModel  = "gemini-3.8-flash"
            OpusModel   = "gemini-3.8-flash"
            InputCostPer1M  = 0.00
            CachedCostPer1M = 0.00
            OutputCostPer1M = 0.00
            Notes       = "DEFAULT: Supports gemini-3.8-flash & gemini-3.5-flash-lite via Google AI Studio (Free Tier or $0.75/1M intro rate)."
        }
        "claude" = @{
            Name        = "Anthropic Claude (Haiku 5.5 / Sonnet 5.5 / Opus 5.5)"
            BaseUrl     = "https://api.anthropic.com/v1/messages"
            EnvKey      = "ANTHROPIC_API_KEY"
            CheapModel  = "claude-haiku-5-5"
            SmartModel  = "claude-sonnet-5-5"
            OpusModel   = "claude-opus-5-5"
            InputCostPer1M  = 0.10
            CachedCostPer1M = 0.01
            OutputCostPer1M = 0.50
            Notes       = "Claude Tiers: cheap=claude-haiku-5-5 ($0.10/1M, $0.01 cached), smart=claude-sonnet-5-5 ($2/1M), opus=claude-opus-5-5 ($4/1M)."
        }
        "openrouter" = @{
            Name        = "OpenRouter (Free Coding Models)"
            BaseUrl     = "https://openrouter.ai/api/v1/chat/completions"
            EnvKey      = "OPENROUTER_API_KEY"
            CheapModel  = "qwen/qwen3-coder:free"
            SmartModel  = "deepseek/deepseek-chat-v3-0324:free"
            OpusModel   = "anthropic/claude-sonnet-4.5"
            InputCostPer1M  = 0.00
            CachedCostPer1M = 0.00
            OutputCostPer1M = 0.00
            Notes       = "FREE ($0) using ':free' model variants on OpenRouter."
        }
        "groq" = @{
            Name        = "Groq Cloud (Free Developer Tier)"
            BaseUrl     = "https://api.groq.com/openai/v1/chat/completions"
            EnvKey      = "GROQ_API_KEY"
            CheapModel  = "llama-3.1-8b-instant"
            SmartModel  = "llama-3.3-70b-versatile"
            OpusModel   = "llama-3.3-70b-versatile"
            InputCostPer1M  = 0.00
            CachedCostPer1M = 0.00
            OutputCostPer1M = 0.00
            Notes       = "FREE ($0) developer tier with ultra-fast token streaming."
        }
        "deepseek" = @{
            Name        = "DeepSeek API (Ultra-Cheap + Auto Cache)"
            BaseUrl     = "https://api.deepseek.com/chat/completions"
            EnvKey      = "DEEPSEEK_API_KEY"
            CheapModel  = "deepseek-chat"
            SmartModel  = "deepseek-reasoner"
            OpusModel   = "deepseek-reasoner"
            InputCostPer1M  = 0.27
            CachedCostPer1M = 0.07
            OutputCostPer1M = 1.10
            Notes       = "Automatic disk prompt caching ($0.07/1M cached input tokens)."
        }
        "openai" = @{
            Name        = "OpenAI (Nano / Mini)"
            BaseUrl     = "https://api.openai.com/v1/chat/completions"
            EnvKey      = "OPENAI_API_KEY"
            CheapModel  = "gpt-4.1-nano"
            SmartModel  = "gpt-4.1-mini"
            OpusModel   = "gpt-4.1"
            InputCostPer1M  = 0.10
            CachedCostPer1M = 0.025
            OutputCostPer1M = 0.40
            Notes       = "GPT-4.1-nano costs $0.10/1M input ($0.025 cached)."
        }
        "azure-openai" = @{
            Name        = "Corporate Azure OpenAI Gateway"
            BaseUrl     = ""
            EnvKey      = "AZURE_OPENAI_API_KEY"
            CheapModel  = "gpt-4o-mini"
            SmartModel  = "gpt-4o"
            OpusModel   = "gpt-4o"
            InputCostPer1M  = 0.15
            CachedCostPer1M = 0.075
            OutputCostPer1M = 0.60
            Notes       = "Set base_url in config.json to your corporate Azure OpenAI deployment URL."
        }
        "ollama" = @{
            Name        = "Local Ollama / vLLM / llama.cpp"
            BaseUrl     = "http://localhost:11434/v1/chat/completions"
            EnvKey      = "OLLAMA_API_KEY"
            CheapModel  = "qwen2.5-coder:7b"
            SmartModel  = "qwen2.5-coder:14b"
            OpusModel   = "qwen2.5-coder:32b"
            InputCostPer1M  = 0.00
            CachedCostPer1M = 0.00
            OutputCostPer1M = 0.00
            Notes       = "100% offline/local inference."
        }
        "github-models" = @{
            Name        = "GitHub Models (RETIRED by GitHub on July 30, 2026)"
            BaseUrl     = "https://models.github.ai/inference/chat/completions"
            EnvKey      = "GITHUB_TOKEN"
            CheapModel  = "openai/gpt-4o-mini"
            SmartModel  = "openai/gpt-4o"
            OpusModel   = "openai/gpt-4o"
            InputCostPer1M  = 0.00
            CachedCostPer1M = 0.00
            OutputCostPer1M = 0.00
            Notes       = "RETIRED: GitHub shut down GitHub Models API on July 30, 2026 (returns plain 'OK'). Use gemini, claude, openrouter, or groq instead."
        }
    }

    # Session State
    $Script:Session = @{
        Provider          = "gemini"
        Tier              = "cheap"
        Model             = ""
        ApiKey            = ""
        BaseUrl           = ""
        MaxSessionCostUsd = 0.50
        MaxToolSteps      = 12
        MaxReadLines      = 200
        KeepRecentTurns   = 10
        AutoApprove       = [bool]$AutoApprove
        NoTools           = [bool]$NoTools
        PinnedFiles       = New-Object System.Collections.Generic.List[string]
        ActiveSkills      = New-Object System.Collections.Generic.List[string]
        History           = New-Object System.Collections.Generic.List[object]
        UndoStack         = New-Object System.Collections.Generic.List[object]
        PromptTokens      = 0
        CachedTokens      = 0
        CompletionTokens  = 0
        TotalCostUsd      = 0.0
        TurnCount         = 0
    }
}

process {
    if ($null -ne $PipelineInput -and $PipelineInput -ne "") {
        $Script:PipeBuffer.Add($PipelineInput)
    }
}

end {
    # =========================================================================
    # Helper Functions: UI & Formatting
    # =========================================================================
    function Write-Banner {
        Write-Host ""
        Write-Host "  +----------------------------------------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |  PCA v$($Script:Version) - Portable Coding Assistant (Windows AVD Zero-Dep Edition) |" -ForegroundColor Cyan
        Write-Host "  +----------------------------------------------------------------------+" -ForegroundColor Cyan
        $provInfo = $Script:ProviderCatalog[$Script:Session.Provider]
        $provLabel = if ($provInfo) { $Script:Session.Provider } else { "custom" }
        $skillsLabel = if ($Script:Session.ActiveSkills.Count -gt 0) { ($Script:Session.ActiveSkills -join ", ") } else { "none" }
        Write-Host ("  Provider : {0} | Model: {1} ({2} tier) | Skills: {3}" -f $provLabel, $Script:Session.Model, $Script:Session.Tier, $skillsLabel) -ForegroundColor Gray
        Write-Host ("  Workspace: {0}" -f $Script:WorkspaceRoot) -ForegroundColor Gray
        Write-Host "  Type '/help' for commands, '/skill uipath' for UiPath mode, or '/exit' to quit." -ForegroundColor DarkGray
        Write-Host ""
    }

    function Write-StatusFooter {
        param([int]$InTok, [int]$CachedTok, [int]$OutTok, [double]$TurnCost)
        $costStr = ("`${0:N5}" -f $TurnCost)
        $totStr  = ("`${0:N5}" -f $Script:Session.TotalCostUsd)
        Write-Host ("  [Tokens: {0} in ({1} cached) / {2} out | Turn: {3} | Session: {4} / `${5:N2} cap]" -f `
            $InTok, $CachedTok, $OutTok, $costStr, $totStr, $Script:Session.MaxSessionCostUsd) -ForegroundColor DarkGray
    }

    function Estimate-Tokens {
        param([string]$Text)
        if ([string]::IsNullOrEmpty($Text)) { return 0 }
        return [Math]::Max(1, [int][Math]::Ceiling($Text.Length / 4.0))
    }

    # =========================================================================
    # Configuration Loading & Saving
    # =========================================================================
    function Get-DpapiKeyStorePath {
        $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        return (Join-Path $userHome ".pca.keys.dpapi.json")
    }

    function Save-EncryptedApiKey {
        param([string]$ProviderName, [string]$PlainKey)
        $storePath = Get-DpapiKeyStorePath
        $store = @{}
        if (Test-Path $storePath) {
            try {
                $parsed = ([System.IO.File]::ReadAllText($storePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
                foreach ($prop in $parsed.PSObject.Properties) {
                    $store[$prop.Name] = [string]$prop.Value
                }
            } catch {}
        }
        $sec = ConvertTo-SecureString -String $PlainKey -AsPlainText -Force
        $enc = ConvertFrom-SecureString -SecureString $sec
        $store[$ProviderName.ToLower()] = $enc
        $json = $store | ConvertTo-Json -Depth 3
        [System.IO.File]::WriteAllText($storePath, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "  Saved Windows DPAPI-encrypted API key for '$ProviderName' in $storePath" -ForegroundColor Green
    }

    function Get-EncryptedApiKey {
        param([string]$ProviderName)
        $storePath = Get-DpapiKeyStorePath
        if (-not (Test-Path $storePath)) { return "" }
        try {
            $parsed = ([System.IO.File]::ReadAllText($storePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
            $prop = $parsed.PSObject.Properties[$ProviderName.ToLower()]
            if ($null -eq $prop -or [string]::IsNullOrEmpty([string]$prop.Value)) { return "" }
            $sec = ConvertTo-SecureString -String ([string]$prop.Value)
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
            try {
                return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            } finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        } catch {
            return ""
        }
    }

    function Get-DefaultConfigPath {
        if (-not [string]::IsNullOrEmpty($ConfigPath)) { return $ConfigPath }
        $localCfg = Join-Path $Script:WorkspaceRoot ".pca.json"
        if (Test-Path $localCfg) { return $localCfg }
        $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        return (Join-Path $userHome ".pca.json")
    }

    function Initialize-ConfigFile {
        $target = Join-Path $Script:WorkspaceRoot ".pca.json"
        $sample = [ordered]@{
            provider             = "github-models"
            tier                 = "cheap"
            model                = ""
            api_key              = ""
            base_url             = ""
            proxy_url            = ""
            skills               = @("uipath")
            max_session_cost_usd = 0.50
            max_tool_steps       = 12
            max_read_lines       = 200
            auto_approve         = $false
        }
        $json = $sample | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($target, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "Created configuration file at: $target" -ForegroundColor Green
    }

    function Get-ModelForTier {
        param([hashtable]$Cat, [string]$TierName)
        if ($null -eq $Cat) { return "gemini-3.5-flash-lite" }
        $t = if ($TierName) { $TierName.ToLower() } else { "cheap" }
        if ($t -eq "opus" -and $Cat.OpusModel) { return $Cat.OpusModel }
        if ($t -eq "smart" -or $t -eq "sonnet") { return $Cat.SmartModel }
        return $Cat.CheapModel
    }

    function Resolve-Configuration {
        $cfgFile = Get-DefaultConfigPath
        $fileCfg = $null
        if (Test-Path $cfgFile) {
            try {
                $raw = [System.IO.File]::ReadAllText($cfgFile, [System.Text.Encoding]::UTF8)
                $fileCfg = $raw | ConvertFrom-Json
            } catch {
                Write-Warning "Failed to parse config file $cfgFile : $($_.Exception.Message)"
            }
        }

        # 1. Provider resolution: CLI > Env > Config > Auto-detect from Env Keys or DPAPI store > Default
        if (-not [string]::IsNullOrEmpty($Provider)) {
            $Script:Session.Provider = $Provider.ToLower()
        } elseif (-not [string]::IsNullOrEmpty($env:PCA_PROVIDER)) {
            $Script:Session.Provider = $env:PCA_PROVIDER.ToLower()
        } elseif ($fileCfg -and $fileCfg.provider) {
            $Script:Session.Provider = ([string]$fileCfg.provider).ToLower()
        } else {
            # Auto-detect whichever free/cheap key exists in environment or DPAPI store
            foreach ($key in @("gemini", "claude", "openrouter", "groq", "deepseek", "openai")) {
                $envName = $Script:ProviderCatalog[$key].EnvKey
                $val = [Environment]::GetEnvironmentVariable($envName)
                if ([string]::IsNullOrEmpty($val)) { $val = Get-EncryptedApiKey -ProviderName $key }
                if (-not [string]::IsNullOrEmpty($val)) {
                    $Script:Session.Provider = $key
                    break
                }
            }
        }
        if ($Script:Session.Provider -eq "anthropic") { $Script:Session.Provider = "claude" }

        # 2. Tier resolution
        if (-not [string]::IsNullOrEmpty($Tier)) {
            $Script:Session.Tier = $Tier.ToLower()
        } elseif (-not [string]::IsNullOrEmpty($env:PCA_TIER)) {
            $Script:Session.Tier = $env:PCA_TIER.ToLower()
        } elseif ($fileCfg -and $fileCfg.tier) {
            $Script:Session.Tier = ([string]$fileCfg.tier).ToLower()
        }
        if ($Script:Session.Tier -eq "haiku")  { $Script:Session.Tier = "cheap" }
        if ($Script:Session.Tier -eq "sonnet") { $Script:Session.Tier = "smart" }

        $cat = $Script:ProviderCatalog[$Script:Session.Provider]

        # 3. Model resolution
        if (-not [string]::IsNullOrEmpty($Model)) {
            $Script:Session.Model = $Model
        } elseif (-not [string]::IsNullOrEmpty($env:PCA_MODEL)) {
            $Script:Session.Model = $env:PCA_MODEL
        } elseif ($fileCfg -and $fileCfg.model) {
            $Script:Session.Model = [string]$fileCfg.model
        } elseif ($cat) {
            $Script:Session.Model = Get-ModelForTier -Cat $cat -TierName $Script:Session.Tier
        } else {
            $Script:Session.Model = "gemini-3.5-flash-lite"
        }

        # 4. BaseUrl resolution
        if (-not [string]::IsNullOrEmpty($BaseUrl)) {
            $Script:Session.BaseUrl = $BaseUrl
        } elseif (-not [string]::IsNullOrEmpty($env:PCA_BASE_URL)) {
            $Script:Session.BaseUrl = $env:PCA_BASE_URL
        } elseif ($fileCfg -and $fileCfg.base_url) {
            $Script:Session.BaseUrl = [string]$fileCfg.base_url
        } elseif ($cat) {
            $Script:Session.BaseUrl = $cat.BaseUrl
        }
        # Auto-migrate deprecated Azure GitHub Models hostname to models.github.ai
        if ($Script:Session.BaseUrl -match "models\.inference\.ai\.azure\.com") {
            $Script:Session.BaseUrl = "https://models.github.ai/inference/chat/completions"
        }

        # 5. API Key resolution (CLI > PCA_API_KEY > Provider ENV > Windows DPAPI Store > .pca.json)
        if (-not [string]::IsNullOrEmpty($ApiKey)) {
            $Script:Session.ApiKey = $ApiKey
        } elseif (-not [string]::IsNullOrEmpty($env:PCA_API_KEY)) {
            $Script:Session.ApiKey = $env:PCA_API_KEY
        } elseif ($cat -and -not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($cat.EnvKey))) {
            $Script:Session.ApiKey = [Environment]::GetEnvironmentVariable($cat.EnvKey)
        } else {
            $dpapiKey = Get-EncryptedApiKey -ProviderName $Script:Session.Provider
            if (-not [string]::IsNullOrEmpty($dpapiKey)) {
                $Script:Session.ApiKey = $dpapiKey
            } elseif ($fileCfg -and $fileCfg.api_key) {
                $Script:Session.ApiKey = [string]$fileCfg.api_key
            }
        }

        # 6. Budget & limits
        if ($fileCfg) {
            if ($null -ne $fileCfg.max_session_cost_usd) { $Script:Session.MaxSessionCostUsd = [double]$fileCfg.max_session_cost_usd }
            if ($null -ne $fileCfg.max_tool_steps)       { $Script:Session.MaxToolSteps      = [int]$fileCfg.max_tool_steps }
            if ($null -ne $fileCfg.max_read_lines)       { $Script:Session.MaxReadLines      = [int]$fileCfg.max_read_lines }
            if ($null -ne $fileCfg.auto_approve -and -not $AutoApprove) { $Script:Session.AutoApprove = [bool]$fileCfg.auto_approve }
            if ($fileCfg.skills) {
                foreach ($sk in $fileCfg.skills) {
                    $skName = ([string]$sk).ToLower()
                    if (-not [string]::IsNullOrEmpty($skName) -and -not $Script:Session.ActiveSkills.Contains($skName)) {
                        $Script:Session.ActiveSkills.Add($skName)
                    }
                }
            }
        }

        # Pin initial files
        foreach ($f in $AddFile) {
            if (-not [string]::IsNullOrEmpty($f) -and -not $Script:Session.PinnedFiles.Contains($f)) {
                $Script:Session.PinnedFiles.Add($f)
            }
        }

        # Activate skills from CLI or auto-detect UiPath project (project.json + .xaml)
        foreach ($sk in $Skill) {
            $skName = ([string]$sk).ToLower()
            if (-not [string]::IsNullOrEmpty($skName) -and -not $Script:Session.ActiveSkills.Contains($skName)) {
                $Script:Session.ActiveSkills.Add($skName)
            }
        }
        $uipathProj = Join-Path $Script:WorkspaceRoot "project.json"
        if ((Test-Path $uipathProj) -and -not $Script:Session.ActiveSkills.Contains("uipath")) {
            try {
                $projRaw = [System.IO.File]::ReadAllText($uipathProj, [System.Text.Encoding]::UTF8)
                if ($projRaw -match "UiPath" -or $projRaw -match "expressionLanguage") {
                    $Script:Session.ActiveSkills.Add("uipath")
                }
            } catch {}
        }
    }

    # =========================================================================
    # Self-Compiling Native Windows .EXE Generator (Uses Built-in .NET csc.exe)
    # =========================================================================
    function Invoke-CompileNativeExe {
        $outExe = Join-Path $Script:WorkspaceRoot "pca.exe"
        $scriptFull = $MyInvocation.PSCommandPath
        if ([string]::IsNullOrEmpty($scriptFull)) {
            $scriptFull = Join-Path $Script:WorkspaceRoot "pca.ps1"
        }
        Write-Host "Compiling native Windows launcher '$outExe' using built-in .NET compiler..." -ForegroundColor Cyan

        $csharpSource = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

public class PcaLauncher {
    public static int Main(string[] args) {
        string exeDir = AppDomain.CurrentDomain.BaseDirectory;
        string ps1Path = Path.Combine(exeDir, "pca.ps1");
        if (!File.Exists(ps1Path)) {
            Console.Error.WriteLine("Error: pca.ps1 not found alongside pca.exe at " + ps1Path);
            return 1;
        }
        StringBuilder sb = new StringBuilder();
        sb.Append("-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"");
        sb.Append(ps1Path);
        sb.Append("\"");
        foreach (string a in args) {
            sb.Append(" \"");
            sb.Append(a.Replace("\"", "\\\""));
            sb.Append("\"");
        }
        ProcessStartInfo psi = new ProcessStartInfo("powershell.exe", sb.ToString());
        psi.UseShellExecute = false;
        Process p = Process.Start(psi);
        p.WaitForExit();
        return p.ExitCode;
    }
}
"@
        Add-Type -TypeDefinition $csharpSource -OutputAssembly $outExe -OutputType ConsoleApplication
        Write-Host "Successfully compiled zero-dependency binary: $outExe" -ForegroundColor Green
    }

    # =========================================================================
    # Workspace & Context Optimization Tools
    # =========================================================================
    $Script:IgnoredDirs = @(".git", ".hg", ".svn", "node_modules", "bin", "obj", "dist", "build", "__pycache__", ".venv", "venv", ".vs", ".idea", "packages")

    function Get-SafePath {
        param([string]$RelOrAbsPath)
        if ([string]::IsNullOrEmpty($RelOrAbsPath)) { return $Script:WorkspaceRoot }
        $cleaned = $RelOrAbsPath.Trim() -replace "^\{PROJECT_DIR\}[\\/]*", ""
        $candidate = if ([System.IO.Path]::IsPathRooted($cleaned)) {
            $cleaned
        } else {
            Join-Path $Script:WorkspaceRoot $cleaned
        }
        $fullCand = [System.IO.Path]::GetFullPath($candidate)
        if (Test-Path $fullCand) {
            return $fullCand
        }

        # Fallback 1: .local/docs/packages/<PackageId>/<rest> -> bundled skills/uipath-rpa/references/activity-docs/<PackageId>/<ver>/<rest>
        $normSlash = $cleaned.Replace('\', '/')
        if ($normSlash -match "(?:^|/)\.local/docs/packages/([^/]+)/(.+)$") {
            $pkgId = $Matches[1]
            $restRel = $Matches[2].Replace('/', [IO.Path]::DirectorySeparatorChar)
            $pkgRoot = Join-Path $Script:ScriptDir ("skills\uipath-rpa\references\activity-docs\" + $pkgId)
            if (Test-Path $pkgRoot -PathType Container) {
                $verDirs = Get-ChildItem -LiteralPath $pkgRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
                foreach ($vd in $verDirs) {
                    $bundled = Join-Path $vd.FullName $restRel
                    if (Test-Path $bundled) {
                        return [System.IO.Path]::GetFullPath($bundled)
                    }
                }
            }
        }

        # Fallback 2: relative reference path from native UiPath/skills (e.g. references/xaml/xaml-basics-and-rules.md)
        $relClean = $cleaned.TrimStart('.', '\', '/')
        foreach ($skFolder in @("uipath-rpa", "uipath-planner", "uipath-review", "uipath-troubleshoot", "uipath-activity-migrator", "uipath-desktop", "uipath")) {
            $skCand = Join-Path $Script:ScriptDir ("skills\" + $skFolder + "\" + $relClean)
            if (Test-Path $skCand) {
                return [System.IO.Path]::GetFullPath($skCand)
            }
        }

        $repoCand = Join-Path $Script:ScriptDir $relClean
        if (Test-Path $repoCand) {
            return [System.IO.Path]::GetFullPath($repoCand)
        }

        return $fullCand
    }

    function Get-RelativePath {
        param([string]$FullPath)
        if ($FullPath.StartsWith($Script:WorkspaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $sub = $FullPath.Substring($Script:WorkspaceRoot.Length).TrimStart('\', '/')
            if ([string]::IsNullOrEmpty($sub)) { return "." }
            return $sub.Replace('\', '/')
        }
        return $FullPath
    }

    function Invoke-ToolListFiles {
        param([string]$SubDir = ".", [int]$MaxDepth = 3, [int]$MaxEntries = 150)
        $targetDir = Get-SafePath $SubDir
        if (-not (Test-Path $targetDir)) {
            return "Error: Directory not found: $SubDir"
        }
        $results = New-Object System.Collections.Generic.List[string]
        $queue = New-Object System.Collections.Generic.Queue[object]
        $queue.Enqueue(@{ Path = $targetDir; Depth = 0 })

        while ($queue.Count -gt 0 -and $results.Count -lt $MaxEntries) {
            $curr = $queue.Dequeue()
            $items = Get-ChildItem -LiteralPath $curr.Path -Force -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if ($results.Count -ge $MaxEntries) { break }
                if ($item.PSIsContainer) {
                    if ($Script:IgnoredDirs -contains $item.Name) { continue }
                    $rel = Get-RelativePath $item.FullName
                    $results.Add("[DIR]  $rel/")
                    if ($curr.Depth + 1 -lt $MaxDepth) {
                        $queue.Enqueue(@{ Path = $item.FullName; Depth = ($curr.Depth + 1) })
                    }
                } else {
                    $rel = Get-RelativePath $item.FullName
                    $kb = [Math]::Round($item.Length / 1024.0, 1)
                    $results.Add(("[FILE] {0} ({1} KB)" -f $rel, $kb))
                }
            }
        }
        if ($results.Count -eq 0) { return "(empty workspace)" }
        if ($results.Count -ge $MaxEntries) {
            $results.Add("... (truncated at $MaxEntries entries; specify a subdirectory to inspect deeper)")
        }
        return ($results -join "`n")
    }

    function Invoke-ToolSearchText {
        param([string]$Pattern, [string]$SubDir = ".", [int]$MaxMatches = 40)
        if ([string]::IsNullOrEmpty($Pattern)) { return "Error: pattern is required." }
        $targetDir = Get-SafePath $SubDir
        if (-not (Test-Path $targetDir)) { return "Error: Path not found: $SubDir" }

        $matchesList = New-Object System.Collections.Generic.List[string]
        $files = Get-ChildItem -Path $targetDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $full = $_.FullName
            $skip = $false
            foreach ($ig in $Script:IgnoredDirs) {
                if ($full -match ([regex]::Escape([IO.Path]::DirectorySeparatorChar + $ig + [IO.Path]::DirectorySeparatorChar))) {
                    $skip = $true; break
                }
            }
            (-not $skip) -and ($_.Length -lt 1048576)
        }

        foreach ($f in $files) {
            if ($matchesList.Count -ge $MaxMatches) { break }
            try {
                $sel = Select-String -LiteralPath $f.FullName -Pattern $Pattern -ErrorAction SilentlyContinue
                foreach ($m in $sel) {
                    if ($matchesList.Count -ge $MaxMatches) { break }
                    $rel = Get-RelativePath $f.FullName
                    $lineText = $m.Line.Trim()
                    if ($lineText.Length -gt 160) { $lineText = $lineText.Substring(0, 160) + "..." }
                    $matchesList.Add(("{0}:{1}: {2}" -f $rel, $m.LineNumber, $lineText))
                }
            } catch {}
        }

        if ($matchesList.Count -eq 0) { return "No matches found for pattern: $Pattern" }
        return ($matchesList -join "`n")
    }

    function Invoke-ToolReadFile {
        param([string]$Path, [int]$StartLine = 1, [int]$EndLine = 0)
        if ([string]::IsNullOrEmpty($Path)) { return "Error: path is required." }
        $full = Get-SafePath $Path
        if (-not (Test-Path $full -PathType Leaf)) {
            return "Error: File does not exist: $Path"
        }
        $lines = [System.IO.File]::ReadAllLines($full, [System.Text.Encoding]::UTF8)
        $total = $lines.Count
        if ($total -eq 0) { return "(File '$Path' is empty)" }

        if ($StartLine -lt 1) { $StartLine = 1 }
        if ($EndLine -le 0) { $EndLine = [Math]::Min($total, $StartLine + $Script:Session.MaxReadLines - 1) }
        if (($EndLine - $StartLine + 1) -gt $Script:Session.MaxReadLines) {
            $EndLine = $StartLine + $Script:Session.MaxReadLines - 1
        }
        if ($EndLine -gt $total) { $EndLine = $total }

        $out = New-Object System.Collections.Generic.List[string]
        $out.Add(("--- {0} (lines {1}-{2} of {3}) ---" -f (Get-RelativePath $full), $StartLine, $EndLine, $total))
        for ($i = $StartLine; $i -le $EndLine; $i++) {
            $out.Add(("{0,4} | {1}" -f $i, $lines[$i - 1]))
        }
        if ($EndLine -lt $total) {
            $out.Add(("... ({0} more lines; call read_file with start_line={1} to continue)" -f ($total - $EndLine), ($EndLine + 1)))
        }
        return ($out -join "`n")
    }

    function Confirm-UserAction {
        param([string]$Title, [string]$PreviewText)
        if ($Script:Session.AutoApprove) { return $true }
        Write-Host ""
        Write-Host "  [Action Confirmation] $Title" -ForegroundColor Yellow
        if (-not [string]::IsNullOrEmpty($PreviewText)) {
            foreach ($ln in ($PreviewText -split "`r?`n")) {
                if ($ln.StartsWith("+")) {
                    Write-Host "    $ln" -ForegroundColor Green
                } elseif ($ln.StartsWith("-")) {
                    Write-Host "    $ln" -ForegroundColor Red
                } else {
                    Write-Host "    $ln" -ForegroundColor Gray
                }
            }
        }
        Write-Host -NoNewline "  Allow this action? [y = yes / n = no / a = always in session]: " -ForegroundColor Cyan
        $ans = [Console]::ReadLine()
        if ($null -eq $ans) { return $false }
        $ans = $ans.Trim().ToLower()
        if ($ans -eq "a" -or $ans -eq "always") {
            $Script:Session.AutoApprove = $true
            return $true
        }
        return ($ans -eq "y" -or $ans -eq "yes")
    }

    function Invoke-ToolEditFile {
        param([string]$Path, [string]$Search = "", [string]$Replace = "")
        if ([string]::IsNullOrEmpty($Path)) { return "Error: path is required." }
        $full = Get-SafePath $Path
        $rel = Get-RelativePath $full
        $exists = Test-Path $full -PathType Leaf

        $oldContent = if ($exists) { [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8) } else { "" }

        if (-not $exists) {
            if (-not [string]::IsNullOrEmpty($Search)) {
                return "Error: File '$rel' does not exist, so 'search' must be empty when creating a new file."
            }
            $preview = "+ [New File: $rel ($($Replace.Length) chars)]"
            if (-not (Confirm-UserAction -Title "Create new file '$rel'" -PreviewText $preview)) {
                return "User declined creating file '$rel'."
            }
            $parent = Split-Path -Parent $full
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            [System.IO.File]::WriteAllText($full, $Replace, (New-Object System.Text.UTF8Encoding($false)))
            $Script:Session.UndoStack.Add(@{ Path = $full; Existed = $false; OldContent = "" })
            return "Created file '$rel' ($($Replace.Length) bytes)."
        }

        # Existing file: apply SEARCH / REPLACE block
        if ([string]::IsNullOrEmpty($Search)) {
            # Full overwrite
            $preview = "- [Overwrite entire file '$rel' ($($oldContent.Length) -> $($Replace.Length) chars)]"
            if (-not (Confirm-UserAction -Title "Overwrite '$rel'" -PreviewText $preview)) {
                return "User declined overwriting '$rel'."
            }
            [System.IO.File]::WriteAllText($full, $Replace, (New-Object System.Text.UTF8Encoding($false)))
            $Script:Session.UndoStack.Add(@{ Path = $full; Existed = $true; OldContent = $oldContent })
            return "Updated file '$rel'."
        }

        # Normalize CRLF vs LF for matching
        $useCrLf = $oldContent.Contains("`r`n")
        $normOld = $oldContent.Replace("`r`n", "`n")
        $normSearch = $Search.Replace("`r`n", "`n")
        $normReplace = $Replace.Replace("`r`n", "`n")

        $idx = $normOld.IndexOf($normSearch, [System.StringComparison]::Ordinal)
        if ($idx -lt 0) {
            return "Error: Exact SEARCH block not found in '$rel'. Use read_file first to verify exact lines and indentation."
        }
        $secondIdx = $normOld.IndexOf($normSearch, $idx + $normSearch.Length, [System.StringComparison]::Ordinal)
        if ($secondIdx -ge 0) {
            return "Error: SEARCH block matched multiple locations in '$rel'. Include more surrounding context lines."
        }

        $previewLines = New-Object System.Collections.Generic.List[string]
        foreach ($l in ($normSearch -split "`n"))  { $previewLines.Add("- $l") }
        foreach ($l in ($normReplace -split "`n")) { $previewLines.Add("+ $l") }

        if (-not (Confirm-UserAction -Title "Patch '$rel'" -PreviewText ($previewLines -join "`n"))) {
            return "User declined editing '$rel'."
        }

        $newNorm = $normOld.Substring(0, $idx) + $normReplace + $normOld.Substring($idx + $normSearch.Length)
        $finalText = if ($useCrLf) { $newNorm.Replace("`n", "`r`n") } else { $newNorm }

        [System.IO.File]::WriteAllText($full, $finalText, (New-Object System.Text.UTF8Encoding($false)))
        $Script:Session.UndoStack.Add(@{ Path = $full; Existed = $true; OldContent = $oldContent })
        return "Successfully patched '$rel'."
    }

    function Get-UipFlagValue {
        param([string[]]$Tokens, [string[]]$FlagNames, [string]$DefaultValue = "")
        for ($i = 0; $i -lt $Tokens.Count; $i++) {
            $t = $Tokens[$i]
            foreach ($fn in $FlagNames) {
                if ($t -eq $fn -and ($i + 1) -lt $Tokens.Count) {
                    return $Tokens[$i + 1].Trim('"', "'")
                }
                $prefix = $fn + "="
                if ($t.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $t.Substring($prefix.Length).Trim('"', "'")
                }
            }
        }
        return $DefaultValue
    }

    function Invoke-NativeUipCommand {
        param([string]$RawCommand)
        $cleaned = $RawCommand -replace ">\s*/dev/null.*$", "" -replace ">\s*\`$null.*$", "" -replace "2>&1\s*&?\s*$", ""
        $cleaned = $cleaned.Trim()
        $tokenMatches = [regex]::Matches($cleaned, '(?:[^\s"'']+|"[^"]*"|''[^'']*'')+ ')
        $tokens = New-Object System.Collections.Generic.List[string]
        foreach ($m in [regex]::Matches($cleaned, '[^\s"'']+|"([^"]*)"|''([^'']*)''')) {
            $val = $m.Value.Trim('"', "'")
            if (-not [string]::IsNullOrEmpty($val)) {
                $tokens.Add($val)
            }
        }
        if ($tokens.Count -eq 0) {
            return (@{ Result = "Failure"; Code = "InvalidCommand"; Data = @{ message = "Empty command" } } | ConvertTo-Json -Depth 6 -Compress)
        }
        if ($tokens[0] -match "^(?i)(?:\.[\\/])?uip(?:\.exe|\.cmd|\.ps1)?$") {
            $tokens.RemoveAt(0)
        }
        if ($tokens.Count -eq 0 -or $tokens[0] -in @("--help", "-h", "help")) {
            $helpObj = @{
                Result = "Success"
                Code   = "Help"
                Data   = @{
                    emulator = "PCA Built-in Offline uip CLI Emulator"
                    commands = @(
                        "uip rpa init",
                        "uip rpa validate",
                        "uip rpa build",
                        "uip rpa activities find",
                        "uip rpa activities get-default-xaml",
                        "uip rpa packages versions",
                        "uip rpa packages install",
                        "uip rpa templates search",
                        "uip rpa get-object-repository",
                        "uip rpa analyzer-rules list",
                        "uip rpa uia",
                        "uip rpa-legacy validate",
                        "uip rpa-legacy find-activities",
                        "uip rpa-legacy type-definition"
                    )
                }
            }
            return ($helpObj | ConvertTo-Json -Depth 6 -Compress)
        }

        $tokArr = $tokens.ToArray()
        $domain = $tokArr[0].ToLower()
        $sub = if ($tokArr.Count -gt 1) { $tokArr[1..($tokArr.Count - 1)] } else { @() }

        if ($domain -eq "tools" -and $sub.Count -ge 1 -and $sub[0] -eq "list") {
            return (@{ Result = "Success"; Code = "ToolsList"; Data = @{ tools = @("rpa", "rpa-legacy", "solution", "or", "is") } } | ConvertTo-Json -Depth 6 -Compress)
        }

        if ($domain -in @("rpa", "rpa-legacy")) {
            $action = if ($sub.Count -ge 1) { $sub[0].ToLower() } else { "--help" }
            $sub2   = if ($sub.Count -ge 2) { $sub[1].ToLower() } else { "" }

            if ($action -eq "init") {
                $projName = Get-UipFlagValue -Tokens $sub -FlagNames @("--name", "-n") -DefaultValue "UiPathProject"
                $locArg   = Get-UipFlagValue -Tokens $sub -FlagNames @("--location", "-l") -DefaultValue $Script:WorkspaceRoot
                $exprLang = Get-UipFlagValue -Tokens $sub -FlagNames @("--expression-language") -DefaultValue "VisualBasic"
                $targetFw = Get-UipFlagValue -Tokens $sub -FlagNames @("--target-framework") -DefaultValue "Windows"

                $locFull = Get-SafePath $locArg
                $leafName = Split-Path -Leaf $locFull
                $projDir = if ($leafName -ieq $projName) { $locFull } else { Join-Path $locFull $projName }
                if (-not (Test-Path $projDir)) { New-Item -ItemType Directory -Path $projDir -Force | Out-Null }

                $projObj = [ordered]@{
                    name        = $projName
                    projectId   = "d9a8f1b2-4c3e-4a1b-9f0e-123456789abc"
                    description = "UiPath $targetFw automation project ($exprLang)"
                    main        = "Main.xaml"
                    dependencies = [ordered]@{
                        "UiPath.System.Activities"       = "[25.10.2]"
                        "UiPath.UIAutomation.Activities" = "[26.10.0-preview]"
                    }
                    schemaVersion      = "4.0"
                    studioVersion      = "25.10.0.0"
                    projectVersion     = "1.0.0"
                    expressionLanguage = $exprLang
                    targetFramework    = $targetFw
                    entryPoints        = @(
                        [ordered]@{
                            filePath = "Main.xaml"
                            uniqueId = "e1a2b3c4-5678-4012-9abc-def012345678"
                            input    = @()
                            output   = @()
                        }
                    )
                }
                $projJsonFile = Join-Path $projDir "project.json"
                [System.IO.File]::WriteAllText($projJsonFile, ($projObj | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

                $mainXaml = Join-Path $projDir "Main.xaml"
                if (-not (Test-Path $mainXaml -PathType Leaf)) {
                    $prevApprove = $Script:Session.AutoApprove
                    $Script:Session.AutoApprove = $true
                    try {
                        Invoke-ToolScaffoldXaml -Path $mainXaml -Template "sequence" | Out-Null
                    } finally {
                        $Script:Session.AutoApprove = $prevApprove
                    }
                }

                $bundledUia = Join-Path $Script:ScriptDir "skills\uipath-rpa\references\activity-docs\UiPath.UIAutomation.Activities\26.10\ui-automation-guide.md"
                if (Test-Path $bundledUia -PathType Leaf) {
                    $targetUia = Join-Path $projDir ".local\docs\packages\UiPath.UIAutomation.Activities\ui-automation-guide.md"
                    $targetUiaParent = Split-Path -Parent $targetUia
                    if (-not (Test-Path $targetUiaParent)) { New-Item -ItemType Directory -Path $targetUiaParent -Force | Out-Null }
                    Copy-Item -LiteralPath $bundledUia -Destination $targetUia -Force
                }

                $res = @{
                    Result = "Success"
                    Code   = "Init"
                    Data   = @{
                        projectDir         = $projDir
                        projectFile        = $projJsonFile
                        mainFile           = $mainXaml
                        targetFramework    = $targetFw
                        expressionLanguage = $exprLang
                    }
                }
                return ($res | ConvertTo-Json -Depth 6 -Compress)
            }

            if ($action -in @("validate", "analyze")) {
                $fileArg = Get-UipFlagValue -Tokens $sub -FlagNames @("--file-path", "-f") -DefaultValue ""
                $projArg = Get-UipFlagValue -Tokens $sub -FlagNames @("--project-dir", "-p") -DefaultValue $Script:WorkspaceRoot
                if ([string]::IsNullOrEmpty($fileArg) -and $sub.Count -ge 2 -and -not $sub[1].StartsWith("-")) {
                    $fileArg = $sub[1]
                }
                $targets = New-Object System.Collections.Generic.List[string]
                if (-not [string]::IsNullOrEmpty($fileArg)) {
                    $fp = Get-SafePath $fileArg
                    if (-not (Test-Path $fp -PathType Leaf) -and -not [string]::IsNullOrEmpty($projArg)) {
                        $fp = Get-SafePath (Join-Path $projArg $fileArg)
                    }
                    $targets.Add($fp)
                } else {
                    $pdir = Get-SafePath $projArg
                    $xFiles = Get-ChildItem -Path $pdir -Filter "*.xaml" -Recurse -File -ErrorAction SilentlyContinue
                    foreach ($xf in $xFiles) { $targets.Add($xf.FullName) }
                }

                $allErrs = New-Object System.Collections.Generic.List[string]
                $allWarns = New-Object System.Collections.Generic.List[string]
                foreach ($tf in $targets) {
                    $rep = Invoke-ToolValidateXaml -Path $tf
                    if ($rep.StartsWith("Error:")) {
                        $allErrs.Add($rep)
                        continue
                    }
                    $inErr = $false; $inWarn = $false
                    foreach ($ln in ($rep -split "`r?`n")) {
                        $s = $ln.Trim()
                        if ($s -match "^Errors \(") { $inErr = $true; $inWarn = $false; continue }
                        if ($s -match "^Warnings") { $inWarn = $true; $inErr = $false; continue }
                        if ($s.StartsWith("- ")) {
                            if ($inErr)  { $allErrs.Add((Split-Path -Leaf $tf) + ": " + $s.Substring(2)) }
                            if ($inWarn) { $allWarns.Add((Split-Path -Leaf $tf) + ": " + $s.Substring(2)) }
                        }
                    }
                }

                if ($allErrs.Count -gt 0) {
                    return (@{
                        Result = "Failure"
                        Code   = "ValidationErrorsFound"
                        Data   = @{
                            message  = ($allErrs -join "; ")
                            errors   = $allErrs.ToArray()
                            warnings = $allWarns.ToArray()
                        }
                    } | ConvertTo-Json -Depth 6 -Compress)
                }
                return (@{
                    Result = "Success"
                    Code   = "Validate"
                    Data   = @{
                        message  = "Validation succeeded for $($targets.Count) file(s) with 0 error(s) and $($allWarns.Count) warning(s)."
                        errors   = @()
                        warnings = $allWarns.ToArray()
                    }
                } | ConvertTo-Json -Depth 6 -Compress)
            }

            if ($action -in @("build", "pack")) {
                $projArg = Get-UipFlagValue -Tokens $sub -FlagNames @("--project-dir", "-p") -DefaultValue ""
                if ([string]::IsNullOrEmpty($projArg) -and $sub.Count -ge 2 -and -not $sub[1].StartsWith("-")) {
                    $projArg = $sub[1]
                }
                if ([string]::IsNullOrEmpty($projArg)) { $projArg = $Script:WorkspaceRoot }
                $pdir = Get-SafePath $projArg
                if (Test-Path $pdir -PathType Leaf) { $pdir = Split-Path -Parent $pdir }

                $xFiles = Get-ChildItem -Path $pdir -Filter "*.xaml" -Recurse -File -ErrorAction SilentlyContinue
                $allErrs = New-Object System.Collections.Generic.List[string]
                $allWarns = New-Object System.Collections.Generic.List[string]
                foreach ($xf in $xFiles) {
                    $rep = Invoke-ToolValidateXaml -Path $xf.FullName
                    $inErr = $false; $inWarn = $false
                    foreach ($ln in ($rep -split "`r?`n")) {
                        $s = $ln.Trim()
                        if ($s -match "^Errors \(") { $inErr = $true; $inWarn = $false; continue }
                        if ($s -match "^Warnings") { $inWarn = $true; $inErr = $false; continue }
                        if ($s.StartsWith("- ")) {
                            if ($inErr)  { $allErrs.Add($xf.Name + ": " + $s.Substring(2)) }
                            if ($inWarn) { $allWarns.Add($xf.Name + ": " + $s.Substring(2)) }
                        }
                    }
                }

                $localContent = Join-Path $pdir ".local\content"
                if (-not (Test-Path $localContent)) { New-Item -ItemType Directory -Path $localContent -Force | Out-Null }
                [System.IO.File]::WriteAllText((Join-Path $localContent "entry-points.json"), '{"entryPoints":[{"filePath":"Main.xaml"}]}', (New-Object System.Text.UTF8Encoding($false)))
                [System.IO.File]::WriteAllText((Join-Path $localContent "bindings_v2.json"), '{"version":"2.0","resources":[]}', (New-Object System.Text.UTF8Encoding($false)))

                if ($allErrs.Count -gt 0) {
                    return (@{
                        Result = "Failure"
                        Code   = "BuildFailed"
                        Data   = @{
                            projectDir = $pdir
                            message    = ($allErrs -join "; ")
                            errors     = $allErrs.ToArray()
                            warnings   = $allWarns.ToArray()
                        }
                    } | ConvertTo-Json -Depth 6 -Compress)
                }
                return (@{
                    Result = "Success"
                    Code   = "Build"
                    Data   = @{
                        projectDir     = $pdir
                        filesValidated = @($xFiles).Count
                        errors         = @()
                        warnings       = $allWarns.ToArray()
                        message        = "Build succeeded ($(@($xFiles).Count) workflow(s) validated, 0 errors)."
                    }
                } | ConvertTo-Json -Depth 6 -Compress)
            }

            if (($action -eq "activities" -and $sub2 -eq "find") -or $action -eq "find-activities") {
                $q = (Get-UipFlagValue -Tokens $sub -FlagNames @("--query", "-q") -DefaultValue "").ToLower()
                $acts = New-Object System.Collections.Generic.List[object]
                $docsRoot = Join-Path $Script:ScriptDir "skills\uipath-rpa\references\activity-docs"
                if (Test-Path $docsRoot -PathType Container) {
                    $mdFiles = Get-ChildItem -Path $docsRoot -Filter "*.md" -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -match "activities$" }
                    foreach ($mf in $mdFiles) {
                        $aName = $mf.BaseName
                        if ([string]::IsNullOrEmpty($q) -or $aName.ToLower().Contains($q)) {
                            $pkgName = $mf.Directory.Parent.Parent.Name
                            $acts.Add(@{
                                className   = $aName
                                displayName = $aName
                                packageId   = $pkgName
                                isTrigger   = $aName.Contains("Trigger")
                            })
                        }
                        if ($acts.Count -ge 30) { break }
                    }
                }
                return (@{
                    Result = "Success"
                    Code   = "ActivitiesFind"
                    Data   = @{ query = $q; count = $acts.Count; activities = $acts.ToArray() }
                } | ConvertTo-Json -Depth 6 -Compress)
            }

            if (($action -eq "activities" -and $sub2 -eq "get-default-xaml") -or $action -eq "type-definition") {
                $clsName = Get-UipFlagValue -Tokens $sub -FlagNames @("--activity-class-name", "--type", "-t") -DefaultValue "LogMessage"
                $parts = $clsName -split "[:\.]"
                $shortCls = $parts[$parts.Count - 1]
                $isUia = $shortCls.StartsWith("N")
                $xmlns = if ($isUia) { 'xmlns:uix="http://schemas.uipath.com/workflow/activities/uix"' } else { 'xmlns:ui="http://schemas.uipath.com/workflow/activities"' }
                $prefix = if ($isUia) { "uix" } else { "ui" }
                $defXaml = "<" + $prefix + ":" + $shortCls + ' DisplayName="' + $shortCls + '" sap2010:WorkflowViewState.IdRef="' + $shortCls + '_1" />'
                return (@{
                    Result = "Success"
                    Code   = "GetDefaultXaml"
                    Data   = @{
                        className   = $shortCls
                        packageId   = if ($isUia) { "UiPath.UIAutomation.Activities" } else { "UiPath.System.Activities" }
                        xmlns       = $xmlns
                        defaultXaml = $defXaml
                    }
                } | ConvertTo-Json -Depth 6 -Compress)
            }

            if ($action -eq "packages" -and $sub2 -eq "versions") {
                $pkgId = Get-UipFlagValue -Tokens $sub -FlagNames @("--package-id", "-p") -DefaultValue "UiPath.System.Activities"
                return (@{
                    Result = "Success"
                    Code   = "PackageVersions"
                    Data   = @{ packageId = $pkgId; versions = @("26.10.0-preview", "25.12.2", "25.10.2", "24.10.6") }
                } | ConvertTo-Json -Depth 6 -Compress)
            }

            if ($action -eq "packages" -and $sub2 -eq "install") {
                $pkgSpec = Get-UipFlagValue -Tokens $sub -FlagNames @("--packages") -DefaultValue ""
                $projArg = Get-UipFlagValue -Tokens $sub -FlagNames @("--project-dir") -DefaultValue $Script:WorkspaceRoot
                $pdir = Get-SafePath $projArg
                return (@{
                    Result = "Success"
                    Code   = "PackagesInstall"
                    Data   = @{ installed = @($pkgSpec); projectDir = $pdir }
                } | ConvertTo-Json -Depth 6 -Compress)
            }

            if ($action -eq "templates" -and $sub2 -eq "search") {
                $q = Get-UipFlagValue -Tokens $sub -FlagNames @("--query") -DefaultValue ""
                return (@{
                    Result = "Success"
                    Code   = "TemplatesSearch"
                    Data   = @{
                        query     = $q
                        templates = @(
                            @{ id = "blank-process"; name = "Blank Process"; source = "Official" },
                            @{ id = "reframework"; name = "Robotic Enterprise Framework (REFramework)"; source = "Official" }
                        )
                    }
                } | ConvertTo-Json -Depth 6 -Compress)
            }

            if ($action -eq "get-object-repository") {
                return (@{
                    Result = "Success"
                    Code   = "GetObjectRepository"
                    Data   = @{ applications = @(); note = "Offline PCA mode: use inline TargetAnchorable selectors or inspect_ui_tree." }
                } | ConvertTo-Json -Depth 6 -Compress)
            }

            if ($action -eq "analyzer-rules" -and $sub2 -eq "list") {
                return (@{
                    Result = "Success"
                    Code   = "AnalyzerRulesList"
                    Data   = @{
                        rules = @(
                            @{ id = "ST-NMG-002"; severity = "Warning"; description = "Prefix arguments with in_, out_, or io_" },
                            @{ id = "ST-SEC-007"; severity = "Error"; description = "Keep secrets inside scope" },
                            @{ id = "ST-USG-010"; severity = "Warning"; description = "Prefer NCheckAppState over hardcoded Delay" },
                            @{ id = "UI-ANA-001"; severity = "Warning"; description = "Avoid volatile idx >= 2 in selectors" }
                        )
                    }
                } | ConvertTo-Json -Depth 6 -Compress)
            }

            if ($action -eq "uia") {
                $winTitle = Get-UipFlagValue -Tokens $sub -FlagNames @("--window-title", "--title") -DefaultValue ""
                $treeText = Invoke-ToolInspectUiTree -WindowTitle $winTitle -MaxDepth 3
                return (@{
                    Result = "Success"
                    Code   = "UiaInspect"
                    Data   = @{ windowTitle = $winTitle; uiTree = $treeText }
                } | ConvertTo-Json -Depth 6 -Compress)
            }
        }

        return (@{
            Result = "Success"
            Code   = "EmulatedCommand"
            Data   = @{ command = $RawCommand; message = "Executed in PCA offline uip emulator." }
        } | ConvertTo-Json -Depth 6 -Compress)
    }

    function Invoke-ToolRunCommand {
        param([string]$Command)
        if ([string]::IsNullOrEmpty($Command)) { return "Error: command is required." }
        if (-not (Confirm-UserAction -Title "Execute Shell Command" -PreviewText "  > $Command")) {
            return "User declined executing command: $Command"
        }

        # Intercept uip commands when external uip CLI is not installed on this machine
        $uipBin = Get-Command "uip" -ErrorAction SilentlyContinue
        $forceBuiltin = ($env:PCA_FORCE_BUILTIN_UIP -eq "1")
        $segments = @($Command -split "&&" | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrEmpty($_) })
        $hasUipSeg = $false
        foreach ($seg in $segments) {
            if ($seg -match "^(?i)(?:\.[\\/])?uip(?:\.exe|\.cmd|\.ps1)?\b") {
                $hasUipSeg = $true
                break
            }
        }
        if ($hasUipSeg -and ($null -eq $uipBin -or $forceBuiltin)) {
            $outputs = New-Object System.Collections.Generic.List[string]
            $exitCode = 0
            foreach ($seg in $segments) {
                if ($seg -match "^(?i)(?:\.[\\/])?uip(?:\.exe|\.cmd|\.ps1)?\b") {
                    $jsonOut = Invoke-NativeUipCommand -RawCommand $seg
                    $outputs.Add($jsonOut)
                    if ($jsonOut -match '"Result"\s*:\s*"Failure"') { $exitCode = 1 }
                }
            }
            $combinedUip = ("ExitCode: {0}`n{1}" -f $exitCode, ($outputs -join "`n")).Trim()
            if ($combinedUip.Length -gt 3500) {
                $combinedUip = $combinedUip.Substring(0, 3500) + "`n... [Output truncated to save tokens]"
            }
            return $combinedUip
        }

        try {
            $escapedCmd = $Command.Replace('"', '\"')
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-NoLogo -NoProfile -NonInteractive -Command `"$escapedCmd`""
            $psi.WorkingDirectory = $Script:WorkspaceRoot
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true

            $proc = [System.Diagnostics.Process]::Start($psi)
            $stdout = $proc.StandardOutput.ReadToEnd()
            $stderr = $proc.StandardError.ReadToEnd()
            $proc.WaitForExit(30000) | Out-Null

            $combined = ("ExitCode: {0}`n{1}`n{2}" -f $proc.ExitCode, $stdout.Trim(), $stderr.Trim()).Trim()
            if ($combined.Length -gt 3500) {
                $combined = $combined.Substring(0, 3500) + "`n... [Output truncated to save tokens]"
            }
            return $combined
        } catch {
            return "Command execution failed: $($_.Exception.Message)"
        }
    }

    function Invoke-ToolInspectXaml {
        param([string]$Path)
        if ([string]::IsNullOrEmpty($Path)) { return "Error: path is required." }
        $full = Get-SafePath $Path
        if (-not (Test-Path $full -PathType Leaf)) {
            return "Error: XAML file does not exist: $Path"
        }
        $lines = [System.IO.File]::ReadAllLines($full, [System.Text.Encoding]::UTF8)
        $out = New-Object System.Collections.Generic.List[string]
        $out.Add("=== UiPath XAML Outline: $(Get-RelativePath $full) ($($lines.Count) total lines) ===")

        $argsList = New-Object System.Collections.Generic.List[string]
        $varsList = New-Object System.Collections.Generic.List[string]
        $actsList = New-Object System.Collections.Generic.List[string]
        $selsList = New-Object System.Collections.Generic.List[string]
        $inViewState = $false

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $ln = $lines[$i]
            $lineNum = $i + 1
            if ($ln -match "<sap2010:WorkflowViewState" -or $ln -match "<scg:Dictionary.*ViewState") {
                if ($ln -notmatch "/>") { $inViewState = $true }
                continue
            }
            if ($inViewState) {
                if ($ln -match "</sap2010:WorkflowViewState" -or $ln -match "</scg:Dictionary>") {
                    $inViewState = $false
                }
                continue
            }

            if ($ln -match '<x:Property\s+[^>]*Name="([^"]+)"[^>]*Type="([^"]+)"') {
                $argsList.Add(("  Line {0,4}: Argument {1} ({2})" -f $lineNum, $Matches[1], $Matches[2]))
            } elseif ($ln -match '<Variable\s+[^>]*x:TypeArguments="([^"]+)"[^>]*Name="([^"]+)"') {
                $varsList.Add(("  Line {0,4}: Variable {1} : {2}" -f $lineNum, $Matches[2], $Matches[1]))
            } elseif ($ln -match '<Variable\s+[^>]*Name="([^"]+)"[^>]*x:TypeArguments="([^"]+)"') {
                $varsList.Add(("  Line {0,4}: Variable {1} : {2}" -f $lineNum, $Matches[1], $Matches[2]))
            } elseif ($ln -match '^\s*<([A-Za-z0-9_:]+)\s+[^>]*DisplayName="([^"]+)"') {
                $tag = $Matches[1]
                $disp = $Matches[2]
                $extra = ""
                if ($ln -match 'WorkflowFileName="([^"]+)"') { $extra = " -> Calls: $($Matches[1])" }
                elseif ($ln -match 'Selector="([^"]+)"') { $extra = " [Selector]" }
                $actsList.Add(('  Line {0,4}: [{1}] `{2}`{3}' -f $lineNum, $tag, $disp, $extra))
            }

            if ($ln -match '(?:FullSelectorArgument|Selector)="([^"]+)"') {
                $rawSel = $Matches[1] -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"' -replace '&amp;', '&'
                $selsList.Add(("  Line {0,4}: {1}" -f $lineNum, $rawSel))
            }
        }

        $out.Add("Arguments ($($argsList.Count)):")
        if ($argsList.Count -gt 0) { foreach ($a in $argsList) { $out.Add($a) } } else { $out.Add("  (none)") }
        $out.Add("Variables ($($varsList.Count)):")
        if ($varsList.Count -gt 0) { foreach ($v in $varsList) { $out.Add($v) } } else { $out.Add("  (none)") }
        $out.Add("Activities ($($actsList.Count)):")
        if ($actsList.Count -gt 0) {
            $maxAct = [Math]::Min($actsList.Count, 120)
            for ($j = 0; $j -lt $maxAct; $j++) { $out.Add($actsList[$j]) }
            if ($actsList.Count -gt $maxAct) { $out.Add("  ... ($($actsList.Count - $maxAct) more activities)") }
        } else {
            $out.Add("  (none with DisplayName)")
        }
        $out.Add("UI Selectors ($($selsList.Count)):")
        if ($selsList.Count -gt 0) {
            $maxSel = [Math]::Min($selsList.Count, 40)
            for ($k = 0; $k -lt $maxSel; $k++) { $out.Add($selsList[$k]) }
        } else {
            $out.Add("  (none)")
        }
        $out.Add("Tip: Use read_file with start_line/end_line around the specific Line number above before calling edit_file, then run validate_xaml.")
        return ($out -join "`n")
    }

    function Invoke-ToolInspectUiTree {
        param(
            [string]$WindowTitle = "",
            [int]$MaxDepth = 3
        )
        try {
            Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
            Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
        } catch {
            return "Error: Windows UIAutomationClient assembly could not be loaded: $($_.Exception.Message)"
        }

        $root = [System.Windows.Automation.AutomationElement]::RootElement
        if ($null -eq $root) { return "Error: AutomationElement.RootElement is unavailable." }

        $winCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Window
        )
        $windows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $winCond)
        $out = New-Object System.Collections.Generic.List[string]

        if ([string]::IsNullOrEmpty($WindowTitle)) {
            $out.Add("=== Open Windows Desktop Applications (Live UIAutomation) ===")
            $count = 0
            foreach ($w in $windows) {
                try {
                    $wName = [string]$w.Current.Name
                    $wCls  = [string]$w.Current.ClassName
                    $pidVal = [int]$w.Current.ProcessId
                    if ([string]::IsNullOrWhiteSpace($wName)) { continue }
                    $procName = "unknown.exe"
                    try {
                        $pObj = [System.Diagnostics.Process]::GetProcessById($pidVal)
                        if ($pObj -and $pObj.ProcessName) { $procName = "$($pObj.ProcessName).exe" }
                    } catch {}
                    $count++
                    $out.Add(("  [{0}] Title: '{1}' | App: {2} | Class: {3}" -f $count, $wName, $procName, $wCls))
                    $out.Add(("      UiPath Window Selector: <wnd app='{0}' cls='{1}' title='{2}' />" -f $procName, $wCls, $wName))
                } catch {}
            }
            if ($count -eq 0) { $out.Add("  (No visible top-level desktop windows found)") }
            $out.Add("Tip: Call inspect_ui_tree with window_title='*PartOfTitle*' and max_depth=3 to inspect controls inside a window.")
            return ($out -join "`n")
        }

        $pattern = "^" + ([regex]::Escape($WindowTitle) -replace "\\\*", ".*" -replace "\\\?", ".") + "$"
        $matchedWin = $null
        foreach ($w in $windows) {
            try {
                $wName = [string]$w.Current.Name
                if (-not [string]::IsNullOrEmpty($wName) -and ($wName -match "(?i)$pattern" -or $wName.IndexOf($WindowTitle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)) {
                    $matchedWin = $w
                    break
                }
            } catch {}
        }
        if ($null -eq $matchedWin) {
            return "No open desktop window matched title '$WindowTitle'. Call inspect_ui_tree with window_title='' to list all open windows."
        }

        $wTitle = [string]$matchedWin.Current.Name
        $wClass = [string]$matchedWin.Current.ClassName
        $wPid   = [int]$matchedWin.Current.ProcessId
        $appExe = "app.exe"
        try {
            $pObj = [System.Diagnostics.Process]::GetProcessById($wPid)
            if ($pObj -and $pObj.ProcessName) { $appExe = "$($pObj.ProcessName).exe" }
        } catch {}

        $out.Add("=== Desktop UI Control Tree for '$wTitle' ($appExe) ===")
        $out.Add("TargetApp Selector: <wnd app='$appExe' cls='$wClass' title='$wTitle' />")
        $out.Add("Controls:")

        $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
        $nodeCount = 0
        $maxNodes = 120

        function Walk-UiElement {
            param($Element, [int]$Depth)
            if ($null -eq $Element -or $Depth -gt $MaxDepth -or $nodeCount -ge $maxNodes) { return }
            $child = $null
            try { $child = $walker.GetFirstChild($Element) } catch {}
            while ($null -ne $child -and $nodeCount -lt $maxNodes) {
                try {
                    $cName = [string]$child.Current.Name
                    $cId   = [string]$child.Current.AutomationId
                    $cCls  = [string]$child.Current.ClassName
                    $cType = [string]$child.Current.ControlType.ProgrammaticName -replace "^ControlType\.", ""
                    $role  = $cType.ToLower()
                    $indent = "  " * $Depth
                    $selParts = New-Object System.Collections.Generic.List[string]
                    if (-not [string]::IsNullOrEmpty($cId)) { $selParts.Add("automationid='$cId'") }
                    if (-not [string]::IsNullOrEmpty($cName)) {
                        $cleanName = $cName.Replace("'", "")
                        $selParts.Add("name='$cleanName'")
                    }
                    $selParts.Add("role='$role'")
                    $uiaSel = "<uia " + ($selParts -join " ") + " />"
                    if (-not [string]::IsNullOrEmpty($cName) -or -not [string]::IsNullOrEmpty($cId)) {
                        $script:nodeCount++
                        $out.Add(("{0}- [{1}] Name='{2}' AutomationId='{3}' Class='{4}' -> {5}" -f $indent, $cType, $cName, $cId, $cCls, $uiaSel))
                    }
                    Walk-UiElement -Element $child -Depth ($Depth + 1)
                } catch {}
                try { $child = $walker.GetNextSibling($child) } catch { $child = $null }
            }
        }

        Walk-UiElement -Element $matchedWin -Depth 1
        return ($out -join "`n")
    }

    function Invoke-ToolValidateXaml {
        param([string]$Path)
        if ([string]::IsNullOrEmpty($Path)) { return "Error: path is required." }
        $full = Get-SafePath $Path
        if (-not (Test-Path $full -PathType Leaf)) {
            return "Error: XAML file does not exist: $Path"
        }

        $raw = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
        $errors = New-Object System.Collections.Generic.List[string]
        $warnings = New-Object System.Collections.Generic.List[string]

        # 1. XML Well-formedness check
        $xmlDoc = New-Object System.Xml.XmlDocument
        try {
            $xmlDoc.LoadXml($raw)
        } catch {
            $errors.Add("[XML-001] Invalid XML structure: $($_.Exception.Message)")
            return ("=== XAML Validation FAILED: $(Get-RelativePath $full) ===`nErrors:`n  " + ($errors -join "`n  "))
        }

        $root = $xmlDoc.DocumentElement
        if ($null -eq $root -or $root.LocalName -ne "Activity") {
            $errors.Add("[XAML-001] Root element must be <Activity>, found '<$($root.Name)>'.")
        }

        # 2. Required XML Namespace checks
        if ($raw -match "<uix:" -and $raw -notmatch 'xmlns:uix=') {
            $errors.Add("[XAML-002] Uses <uix:*> Modern UIA activities but root <Activity> is missing xmlns:uix declaration.")
        }
        if ($raw -match "<ui:" -and $raw -notmatch 'xmlns:ui=') {
            $errors.Add("[XAML-003] Uses <ui:*> activities but root <Activity> is missing xmlns:ui declaration.")
        }

        if ($raw -match "<uix:NGetText\b[^>]*\bValue=") {
            $errors.Add("[XAML-PITFALL-001] <uix:NGetText> uses Text='[out_Var]', never Value='[out_Var]' (Rule 21 / common-pitfalls.md).")
        }

        if ($raw -match 'x:Class="([^"]+)"') {
            $xClsVal = $Matches[1]
            if ($xClsVal.Contains(".")) {
                $warnings.Add("[XAML-RULE25A] x:Class '$xClsVal' contains a dot. Prefer filename stem without namespace prefix.")
            }
        }

        # 3. Scope ActivityAction Body check (Rule from UiPath/skills xaml-basics-and-rules.md)
        $scopeBodies = @("NApplicationCard.Body", "WindowScope.Body", "BrowserScope.Body", "ExcelApplicationScope.Body")
        foreach ($sb in $scopeBodies) {
            $pattern = "(?s)<(?:uix|ui):$sb>\s*<(?!ActivityAction)([A-Za-z0-9_:]+)"
            if ($raw -match $pattern) {
                $errors.Add("[XAML-SCOPE-001] <$sb> must wrap child activities inside <ActivityAction x:TypeArguments='...'><ActivityAction.Argument><DelegateInArgument ... /></ActivityAction.Argument>...</ActivityAction>, found direct child <$($Matches[1])>.")
            }
        }

        # 4. Flowchart direct child check
        if ($raw -match "<Flowchart[\s>]") {
            if ($raw -match "(?s)<FlowStep[\s>].*?<FlowStep[\s>]") {
                # Check if FlowStep is nested inside another FlowStep rather than direct child of Flowchart
                $fcNodes = $xmlDoc.GetElementsByTagName("FlowStep")
                foreach ($fn in $fcNodes) {
                    if ($fn.ParentNode -and $fn.ParentNode.LocalName -ne "Flowchart" -and $fn.ParentNode.LocalName -ne "FlowStep.Next" -and $fn.ParentNode.LocalName -ne "FlowDecision.True" -and $fn.ParentNode.LocalName -ne "FlowDecision.False") {
                        $warnings.Add("[XAML-FLOW-001] Prefer placing all <FlowStep> nodes as direct children of <Flowchart> with x:Reference links.")
                        break
                    }
                }
            }
        }

        # 5. Expression Language & Selector Quality Lint
        $exprLang = "VisualBasic"
        $projPath = Join-Path $Script:WorkspaceRoot "project.json"
        if (Test-Path $projPath -PathType Leaf) {
            try {
                $projJson = [System.IO.File]::ReadAllText($projPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
                if ($projJson.expressionLanguage) { $exprLang = [string]$projJson.expressionLanguage }
            } catch {}
        }
        if ($exprLang -eq "VisualBasic" -and $raw -match '\[[^\]]*(?:&&|\|\||=>|null\b)[^\]]*\]') {
            $warnings.Add("[EXPR-001] project.json expressionLanguage is 'VisualBasic', but C#-style syntax (&&, ||, =>, null) was detected inside a [...] expression. Use AndAlso, OrElse, Function(x), Nothing.")
        } elseif ($exprLang -eq "CSharp" -and $raw -match '\[[^\]]*(?:\bAndAlso\b|\bOrElse\b|\bNothing\b|\bFunction\s*\()[^\]]*\]') {
            $warnings.Add("[EXPR-002] project.json expressionLanguage is 'CSharp', but VB.NET syntax (AndAlso, OrElse, Nothing, Function()) was detected inside a [...] expression.")
        }

        if ($raw -match "idx='[2-9]\d*'" -or $raw -match "idx=&apos;[2-9]\d*&apos;") {
            $warnings.Add("[UI-ANA-001] Volatile selector attribute idx > 1 detected. Prefer automationid, aaname, name, ctrlname, or TargetAnchorable.Anchors.")
        }
        if ($raw -match "<Delay[\s>]") {
            $warnings.Add("[ST-USG-010] Hardcoded <Delay> activity detected. Prefer <uix:NCheckAppState> or WaitForReady='COMPLETE' for resilient desktop synchronization.")
        }

        $status = if ($errors.Count -eq 0) { "PASSED" } else { "FAILED ($($errors.Count) error(s))" }
        $out = New-Object System.Collections.Generic.List[string]
        $out.Add("=== UiPath XAML Validation: $(Get-RelativePath $full) -> $status (ExpressionLanguage: $exprLang) ===")
        if ($errors.Count -gt 0) {
            $out.Add("Errors ($($errors.Count)):")
            foreach ($e in $errors) { $out.Add("  - $e") }
        }
        if ($warnings.Count -gt 0) {
            $out.Add("Warnings / Best-Practice Hints ($($warnings.Count)):")
            foreach ($w in $warnings) { $out.Add("  - $w") }
        }
        if ($errors.Count -eq 0 -and $warnings.Count -eq 0) {
            $out.Add("  All XML structure, namespace, ActivityAction scope, expression language, and selector checks passed cleanly!")
        }
        return ($out -join "`n")
    }

    function Invoke-ToolScaffoldXaml {
        param(
            [string]$Path,
            [string]$Template = "sequence",
            [string]$AppExe = "notepad.exe",
            [string]$WindowTitle = "*Notepad*"
        )
        if ([string]::IsNullOrEmpty($Path)) { return "Error: path is required." }
        $full = Get-SafePath $Path
        $rel  = Get-RelativePath $full
        $wfName = [System.IO.Path]::GetFileNameWithoutExtension($full) -replace "[^A-Za-z0-9_]", "_"
        $tLower = if ($Template) { $Template.ToLower() } else { "sequence" }

        $xamlContent = ""
        if ($tLower -eq "desktop-uia") {
            $xamlContent = @'
<Activity mc:Ignorable="sap sap2010" x:Class="__WF_NAME__"
 xmlns="http://schemas.microsoft.com/netfx/2009/xaml/activities"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:sap="http://schemas.microsoft.com/netfx/2009/xaml/activities/presentation"
 xmlns:sap2010="http://schemas.microsoft.com/netfx/2010/xaml/activities/presentation"
 xmlns:scg="clr-namespace:System.Collections.Generic;assembly=System.Private.CoreLib"
 xmlns:sco="clr-namespace:System.Collections.ObjectModel;assembly=System.Private.CoreLib"
 xmlns:ui="http://schemas.uipath.com/workflow/activities"
 xmlns:uix="http://schemas.uipath.com/workflow/activities/uiautomation/next/activities"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <x:Members>
    <x:Property Name="in_InputText" Type="InArgument(x:String)" />
    <x:Property Name="out_ResultText" Type="OutArgument(x:String)" />
  </x:Members>
  <Sequence DisplayName="__WF_NAME__" sap2010:WorkflowViewState.IdRef="Sequence_1">
    <Sequence.Variables>
      <Variable x:TypeArguments="x:String" Name="str_WindowStatus" />
    </Sequence.Variables>
    <ui:LogMessage DisplayName="Log Start __WF_NAME__" Level="Info" Message="[&quot;Starting desktop workflow: __WF_NAME__&quot;]" />
    <uix:NApplicationCard AttachMode="ByInstance" DisplayName="Use Desktop Application '__APP_EXE__'" OpenMode="IfNotOpen" ScopeGuid="d1a2b3c4-0000-4000-8000-000000000001" Version="V2">
      <uix:NApplicationCard.Body>
        <ActivityAction x:TypeArguments="x:Object">
          <ActivityAction.Argument>
            <DelegateInArgument x:TypeArguments="x:Object" Name="WSSessionData" />
          </ActivityAction.Argument>
          <Sequence DisplayName="Do Desktop UI Actions">
            <uix:NTypeInto ActivateBefore="True" ClickBeforeMode="Single" DisplayName="Type Into Main Input" EmptyFieldMode="SingleLine" InteractionMode="Simulate" ScopeIdentifier="d1a2b3c4-0000-4000-8000-000000000001" Text="[in_InputText]" Version="V3">
              <uix:NTypeInto.Target>
                <uix:TargetAnchorable DesignTimeRectangle="0, 0, 300, 100" ElementType="InputBox" FullSelectorArgument="&lt;uia role='edit' /&gt;" FuzzySelectorArgument="&lt;uia role='edit' /&gt;" Guid="a1b2c3d4-0001-4000-8000-000000000002" SearchSteps="Selector, FuzzySelector" Version="V2" Visibility="Interactive" />
              </uix:NTypeInto.Target>
            </uix:NTypeInto>
          </Sequence>
        </ActivityAction>
      </uix:NApplicationCard.Body>
      <uix:NApplicationCard.TargetApp>
        <uix:TargetApp FilePath="__APP_EXE__" Selector="&lt;wnd app='__APP_EXE__' title='__WIN_TITLE__' /&gt;" />
      </uix:NApplicationCard.TargetApp>
    </uix:NApplicationCard>
  </Sequence>
</Activity>
'@
        } elseif ($tLower -eq "try-catch-process") {
            $xamlContent = @'
<Activity mc:Ignorable="sap sap2010" x:Class="__WF_NAME__"
 xmlns="http://schemas.microsoft.com/netfx/2009/xaml/activities"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:s="clr-namespace:System;assembly=System.Private.CoreLib"
 xmlns:sap="http://schemas.microsoft.com/netfx/2009/xaml/activities/presentation"
 xmlns:sap2010="http://schemas.microsoft.com/netfx/2010/xaml/activities/presentation"
 xmlns:scg="clr-namespace:System.Collections.Generic;assembly=System.Private.CoreLib"
 xmlns:ui="http://schemas.uipath.com/workflow/activities"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <x:Members>
    <x:Property Name="in_TransactionId" Type="InArgument(x:String)" />
    <x:Property Name="out_Success" Type="OutArgument(x:Boolean)" />
  </x:Members>
  <Sequence DisplayName="__WF_NAME__" sap2010:WorkflowViewState.IdRef="Sequence_1">
    <TryCatch DisplayName="Try Catch - __WF_NAME__">
      <TryCatch.Try>
        <Sequence DisplayName="Execute Process Steps">
          <ui:LogMessage DisplayName="Log Process Start" Level="Info" Message="[&quot;Processing transaction: &quot; &amp; in_TransactionId]" />
          <Assign DisplayName="Set out_Success True">
            <Assign.To>
              <OutArgument x:TypeArguments="x:Boolean">[out_Success]</OutArgument>
            </Assign.To>
            <Assign.Value>
              <InArgument x:TypeArguments="x:Boolean">[True]</InArgument>
            </Assign.Value>
          </Assign>
        </Sequence>
      </TryCatch.Try>
      <TryCatch.Catches>
        <Catch x:TypeArguments="ui:BusinessRuleException">
          <ActivityAction x:TypeArguments="ui:BusinessRuleException">
            <ActivityAction.Argument>
              <DelegateInArgument x:TypeArguments="ui:BusinessRuleException" Name="bre" />
            </ActivityAction.Argument>
            <ui:LogMessage DisplayName="Log BusinessRuleException" Level="Warn" Message="[&quot;Business Rule Exception (No Retry): &quot; &amp; bre.Message]" />
          </ActivityAction>
        </Catch>
        <Catch x:TypeArguments="s:Exception">
          <ActivityAction x:TypeArguments="s:Exception">
            <ActivityAction.Argument>
              <DelegateInArgument x:TypeArguments="s:Exception" Name="ex" />
            </ActivityAction.Argument>
            <ui:LogMessage DisplayName="Log System Exception" Level="Error" Message="[&quot;System Exception: &quot; &amp; ex.Message]" />
          </ActivityAction>
        </Catch>
      </TryCatch.Catches>
    </TryCatch>
  </Sequence>
</Activity>
'@
        } elseif ($tLower -eq "flowchart") {
            $xamlContent = @'
<Activity mc:Ignorable="sap sap2010" x:Class="__WF_NAME__"
 xmlns="http://schemas.microsoft.com/netfx/2009/xaml/activities"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:sap="http://schemas.microsoft.com/netfx/2009/xaml/activities/presentation"
 xmlns:sap2010="http://schemas.microsoft.com/netfx/2010/xaml/activities/presentation"
 xmlns:scg="clr-namespace:System.Collections.Generic;assembly=System.Private.CoreLib"
 xmlns:ui="http://schemas.uipath.com/workflow/activities"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Flowchart DisplayName="__WF_NAME__" sap2010:WorkflowViewState.IdRef="Flowchart_1">
    <Flowchart.StartNode>
      <x:Reference>__ReferenceID0</x:Reference>
    </Flowchart.StartNode>
    <FlowStep x:Name="__ReferenceID0">
      <Sequence DisplayName="Step 1 - Initialize">
        <ui:LogMessage DisplayName="Log Flowchart Start" Level="Info" Message="[&quot;Flowchart started: __WF_NAME__&quot;]" />
      </Sequence>
    </FlowStep>
  </Flowchart>
</Activity>
'@
        } else {
            $xamlContent = @'
<Activity mc:Ignorable="sap sap2010" x:Class="__WF_NAME__"
 xmlns="http://schemas.microsoft.com/netfx/2009/xaml/activities"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:sap="http://schemas.microsoft.com/netfx/2009/xaml/activities/presentation"
 xmlns:sap2010="http://schemas.microsoft.com/netfx/2010/xaml/activities/presentation"
 xmlns:scg="clr-namespace:System.Collections.Generic;assembly=System.Private.CoreLib"
 xmlns:ui="http://schemas.uipath.com/workflow/activities"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <x:Members>
    <x:Property Name="in_Input" Type="InArgument(x:String)" />
    <x:Property Name="out_Result" Type="OutArgument(x:String)" />
  </x:Members>
  <Sequence DisplayName="__WF_NAME__" sap2010:WorkflowViewState.IdRef="Sequence_1">
    <Sequence.Variables>
      <Variable x:TypeArguments="x:String" Name="str_Status" />
    </Sequence.Variables>
    <ui:LogMessage DisplayName="Log Start __WF_NAME__" Level="Info" Message="[&quot;Starting workflow: __WF_NAME__&quot;]" />
  </Sequence>
</Activity>
'@
        }

        $xamlContent = $xamlContent.Replace("__WF_NAME__", $wfName).Replace("__APP_EXE__", $AppExe).Replace("__WIN_TITLE__", $WindowTitle)

        $existed = Test-Path $full -PathType Leaf
        $oldContent = if ($existed) { [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8) } else { "" }
        if (-not (Confirm-UserAction -Title "Scaffold UiPath XAML '$rel' ($tLower)" -PreviewText "+ [XAML Workflow: $rel ($($xamlContent.Length) chars)]")) {
            return "User declined scaffolding XAML '$rel'."
        }
        $parentDir = Split-Path -Parent $full
        if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
        [System.IO.File]::WriteAllText($full, $xamlContent, (New-Object System.Text.UTF8Encoding($false)))
        $Script:Session.UndoStack.Add(@{ Path = $full; Existed = $existed; OldContent = $oldContent })
        $valReport = Invoke-ToolValidateXaml -Path $Path
        return "Scaffolded '$rel' using template '$tLower'.`n$valReport"
    }

    function Get-SkillContent {
        param([string]$SkillName)
        $candidates = @(
            (Join-Path $Script:WorkspaceRoot "skills\$SkillName\SKILL.md"),
            (Join-Path $Script:ScriptDir "skills\$SkillName\SKILL.md")
        )
        foreach ($c in $candidates) {
            if (Test-Path $c -PathType Leaf) {
                return [System.IO.File]::ReadAllText($c, [System.Text.Encoding]::UTF8)
            }
        }
        if ($SkillName -eq "uipath") {
            return @'
# UiPath Studio & Robot Built-in Skill
- Always call `inspect_xaml` first on `.xaml` files to get Arguments, Variables, and Activity line numbers without wasting tokens on ViewState XML.
- Use `inspect_ui_tree` on Windows to inspect open desktop windows and get live `<wnd ... /><uia ... />` selectors.
- Use `scaffold_xaml` (`sequence`, `desktop-uia`, `flowchart`, `try-catch-process`) to create new `.xaml` files, and always run `validate_xaml` after editing `.xaml`.
'@
        }
        return ""
    }

    function Invoke-UndoLastEdit {
        if ($Script:Session.UndoStack.Count -eq 0) {
            Write-Host "  Nothing to undo." -ForegroundColor Yellow
            return
        }
        $last = $Script:Session.UndoStack[$Script:Session.UndoStack.Count - 1]
        $Script:Session.UndoStack.RemoveAt($Script:Session.UndoStack.Count - 1)
        $rel = Get-RelativePath $last.Path
        if ($last.Existed) {
            [System.IO.File]::WriteAllText($last.Path, $last.OldContent, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "  Reverted '$rel' to previous state." -ForegroundColor Green
        } else {
            if (Test-Path $last.Path) { Remove-Item -LiteralPath $last.Path -Force }
            Write-Host "  Removed newly created file '$rel'." -ForegroundColor Green
        }
    }

    # =========================================================================
    # Prompt Cache-Aligned System Prompt & Compact Tool Protocol
    # =========================================================================
    function Build-SystemPrompt {
        # Static instructions come first for 100% prefix cache hits on DeepSeek / OpenAI / Gemini / Claude
        $sys = @'
You are PCA (Portable Coding Assistant), an expert, token-efficient coding & UiPath XAML Desktop Automation agent running on a Windows corporate/AVD environment.
Be concise, accurate, and surgical. Minimize unnecessary prose and avoid repeating unchanged code.

When you need to inspect files, search code, inspect or scaffold UiPath XAML, inspect live Windows desktop UI trees, edit files, or run commands, emit a fenced tool block in your response using this exact JSON format:
```pca-tool
{"tool": "list_files", "sub_dir": ".", "max_depth": 2}
```
Available tools:
1. list_files: {"tool": "list_files", "sub_dir": ".", "max_depth": 2}
2. search_text: {"tool": "search_text", "pattern": "regex", "sub_dir": "."}
3. read_file: {"tool": "read_file", "path": "relative/path", "start_line": 1, "end_line": 120}
4. inspect_xaml: {"tool": "inspect_xaml", "path": "Main.xaml"} (Extracts UiPath .xaml Arguments, Variables, Activity line numbers & UI Selectors, skipping ViewState noise)
5. inspect_ui_tree: {"tool": "inspect_ui_tree", "window_title": "*Notepad*", "max_depth": 3} (Lists open Windows desktop apps when window_title is "", or inspects live UIAutomation controls and outputs ready-to-use UiPath <wnd>/<uia> selectors)
6. scaffold_xaml: {"tool": "scaffold_xaml", "path": "Workflows/Action.xaml", "template": "desktop-uia", "app_exe": "notepad.exe", "window_title": "*Notepad*"} (Templates: "sequence", "desktop-uia", "flowchart", "try-catch-process")
7. validate_xaml: {"tool": "validate_xaml", "path": "Main.xaml"} (Validates .xaml XML structure, required xmlns namespaces, ActivityAction scope bodies, expression language, and selector rules)
8. edit_file: {"tool": "edit_file", "path": "relative/path", "search": "exact existing lines", "replace": "new lines"}
   (To create a new file, set "search": "" and put full file content in "replace".)
9. run_command: {"tool": "run_command", "command": "powershell command"}

Rules for Token Efficiency & UiPath XAML Quality:
- Never dump or rewrite an entire large file when a small SEARCH/REPLACE block in edit_file suffices.
- For UiPath `.xaml` files: call `inspect_xaml` first to locate exact activity line numbers, use `scaffold_xaml` when creating a new `.xaml` file, and ALWAYS run `validate_xaml` after creating or editing any `.xaml` file.
- Emit at most ONE ```pca-tool``` block per turn when waiting for tool output, then wait for the [Tool Result] before continuing.
'@
        if ($Script:Session.ActiveSkills.Count -gt 0) {
            foreach ($sk in $Script:Session.ActiveSkills) {
                $skText = Get-SkillContent -SkillName $sk
                if (-not [string]::IsNullOrEmpty($skText)) {
                    $sys += "`n`n--- Active Skill: $sk ---`n$skText"
                }
            }
        }
        if ($Script:Session.PinnedFiles.Count -gt 0) {
            $sys += "`n`n--- Pinned Workspace Files ---"
            foreach ($pf in $Script:Session.PinnedFiles) {
                $sys += "`n" + (Invoke-ToolReadFile -Path $pf -StartLine 1 -EndLine 150)
            }
        }
        return $sys
    }

    function Compact-HistoryIfNeeded {
        param([switch]$Force)
        $count = $Script:Session.History.Count
        $limit = $Script:Session.KeepRecentTurns
        if (-not $Force -and $count -le $limit) { return }

        $Compacted = 0
        for ($i = 0; $i -lt ($count - 4); $i++) {
            $msg = $Script:Session.History[$i]
            if ($msg.content -and $msg.content.Length -gt 600) {
                $msg.content = $msg.content.Substring(0, 400) + "`n... [Older turn compacted to save tokens]"
                $Compacted++
            }
        }
        if ($Force) {
            Write-Host "  Compacted $Compacted older message(s) in conversation history." -ForegroundColor Green
        }
    }

    # =========================================================================
    # HTTP Client with Automatic Windows Corporate Proxy & Certificate Store
    # =========================================================================
    function Invoke-LlmChatCompletion {
        param([array]$Messages)

        if ($Script:Session.TotalCostUsd -ge $Script:Session.MaxSessionCostUsd -and $Script:Session.MaxSessionCostUsd -gt 0) {
            throw "Session cost cap (`$$($Script:Session.MaxSessionCostUsd)) reached! Increase max_session_cost_usd or run /clear."
        }

        $url = $Script:Session.BaseUrl
        if ([string]::IsNullOrEmpty($url)) {
            throw "No BaseUrl configured for provider '$($Script:Session.Provider)'."
        }
        if ([string]::IsNullOrEmpty($Script:Session.ApiKey) -and $Script:Session.Provider -ne "ollama") {
            $cat = $Script:ProviderCatalog[$Script:Session.Provider]
            $envHint = if ($cat) { $cat.EnvKey } else { "PCA_API_KEY" }
            throw "Missing API Key for provider '$($Script:Session.Provider)'. Run '/key save', set `$env:$($envHint), or pass -ApiKey."
        }

        $reqModel = $Script:Session.Model
        if ($url -match "models\.github\.ai" -and $reqModel -notmatch "/") {
            $reqModel = "openai/$reqModel"
        }

        $isAnthropicMessages = ($url -match "/v1/messages") -or ($Script:Session.Provider -eq "claude" -and $url -notmatch "/chat/completions")

        if ($isAnthropicMessages) {
            $sysBlocks = New-Object System.Collections.Generic.List[object]
            $chatMsgs  = New-Object System.Collections.Generic.List[object]
            foreach ($m in $Messages) {
                if ($m.role -eq "system") {
                    $sysBlocks.Add(@{
                        type          = "text"
                        text          = [string]$m.content
                        cache_control = @{ type = "ephemeral" }
                    })
                } else {
                    $chatMsgs.Add(@{
                        role    = [string]$m.role
                        content = [string]$m.content
                    })
                }
            }
            $payloadObj = @{
                model       = $reqModel
                max_tokens  = 4096
                messages    = $chatMsgs.ToArray()
                temperature = 0.1
            }
            if ($sysBlocks.Count -gt 0) {
                $payloadObj["system"] = $sysBlocks.ToArray()
            }
        } else {
            $payloadObj = @{
                model       = $reqModel
                messages    = $Messages
                temperature = 0.1
            }
        }
        $jsonBody = $payloadObj | ConvertTo-Json -Depth 10 -Compress
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.Method = "POST"
        $req.ContentType = "application/json; charset=utf-8"
        $req.Accept = "application/json"
        $req.Timeout = 120000
        $req.UserAgent = "pca-cli/$($Script:Version)"

        # Automatic Corporate Proxy & Default Windows Credentials (vital on Windows AVD)
        $sysProxy = [System.Net.WebRequest]::GetSystemWebProxy()
        if ($null -ne $sysProxy) {
            $sysProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
            $req.Proxy = $sysProxy
        }

        if (-not [string]::IsNullOrEmpty($Script:Session.ApiKey)) {
            if ($isAnthropicMessages) {
                $req.Headers.Add("x-api-key", $Script:Session.ApiKey)
                $req.Headers.Add("anthropic-version", "2023-06-01")
            } elseif ($Script:Session.Provider -eq "azure-openai" -and $url -match "openai\.azure\.com") {
                $req.Headers.Add("api-key", $Script:Session.ApiKey)
            } else {
                $req.Headers.Add("Authorization", "Bearer $($Script:Session.ApiKey)")
            }
        }

        try {
            $reqStream = $req.GetRequestStream()
            $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
            $reqStream.Close()

            $resp = $req.GetResponse()
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $respText = $reader.ReadToEnd()
            $reader.Close()
            $resp.Close()
        } catch [System.Net.WebException] {
            $errMsg = $_.Exception.Message
            if ($null -ne $_.Exception.Response) {
                try {
                    $errReader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream(), [System.Text.Encoding]::UTF8)
                    $errBody = $errReader.ReadToEnd()
                    $errReader.Close()
                    if (-not [string]::IsNullOrEmpty($errBody)) { $errMsg += " | Body: $errBody" }
                } catch {}
            } else {
                $errMsg += " (Tip: Run '/test' or '.\pca.cmd -TestEndpoints' to see which AI endpoints are reachable through your firewall, or switch provider with '/provider gemini')"
            }
            throw "LLM API HTTP Error ($url): $errMsg"
        }

        if ([string]::IsNullOrWhiteSpace($respText) -or -not $respText.Trim().StartsWith("{")) {
            if ($url -match "models\.github\.ai|models\.inference\.ai\.azure\.com") {
                throw "GitHub permanently retired the GitHub Models API on July 30, 2026 (endpoint returned plain '$($respText.Trim())'). Switch to a free active provider: '/provider gemini' (Google AI Studio Free Tier), '/provider claude', '/provider openrouter', or '/provider groq'."
            }
            throw "LLM API returned non-JSON response from ${url}: $($respText.Substring(0, [Math]::Min(200, $respText.Length)))"
        }

        $parsed = $respText | ConvertFrom-Json
        $replyText = ""
        if ($parsed.choices -and $parsed.choices.Count -gt 0) {
            $replyText = [string]$parsed.choices[0].message.content
        } elseif ($parsed.content -and $parsed.content.Count -gt 0) {
            # Anthropic /v1/messages content blocks
            $textParts = New-Object System.Collections.Generic.List[string]
            foreach ($blk in $parsed.content) {
                if ($blk.text) { $textParts.Add([string]$blk.text) }
            }
            $replyText = ($textParts -join "`n")
        }

        # Calculate token usage & cost
        $inTok = 0; $cachedTok = 0; $outTok = 0
        if ($parsed.usage) {
            if ($null -ne $parsed.usage.prompt_tokens)     { $inTok  = [int]$parsed.usage.prompt_tokens }
            if ($null -ne $parsed.usage.completion_tokens) { $outTok = [int]$parsed.usage.completion_tokens }
            if ($parsed.usage.prompt_tokens_details -and $null -ne $parsed.usage.prompt_tokens_details.cached_tokens) {
                $cachedTok = [int]$parsed.usage.prompt_tokens_details.cached_tokens
            } elseif ($null -ne $parsed.usage.prompt_cache_hit_tokens) {
                $cachedTok = [int]$parsed.usage.prompt_cache_hit_tokens
            }
            # Anthropic /v1/messages usage fields
            if ($null -ne $parsed.usage.input_tokens) {
                $rawIn = [int]$parsed.usage.input_tokens
                $cacheRead = if ($null -ne $parsed.usage.cache_read_input_tokens) { [int]$parsed.usage.cache_read_input_tokens } else { 0 }
                $cacheCreate = if ($null -ne $parsed.usage.cache_creation_input_tokens) { [int]$parsed.usage.cache_creation_input_tokens } else { 0 }
                $inTok = $rawIn + $cacheRead + $cacheCreate
                $cachedTok = $cacheRead
            }
            if ($null -ne $parsed.usage.output_tokens) {
                $outTok = [int]$parsed.usage.output_tokens
            }
        }
        if ($inTok -eq 0)  { $inTok  = Estimate-Tokens $jsonBody }
        if ($outTok -eq 0) { $outTok = Estimate-Tokens $replyText }

        $cat = $Script:ProviderCatalog[$Script:Session.Provider]
        $inRate     = if ($cat) { [double]$cat.InputCostPer1M }  else { 0.15 }
        $cachedRate = if ($cat) { [double]$cat.CachedCostPer1M } else { 0.075 }
        $outRate    = if ($cat) { [double]$cat.OutputCostPer1M } else { 0.60 }

        # Dynamic model-tier pricing for Claude Haiku 5.5 / Sonnet 5.5 / Opus 5.5
        if ($reqModel -match "(?i)claude") {
            if ($reqModel -match "(?i)opus") {
                $inRate = 4.00; $cachedRate = 0.20; $outRate = 20.00
            } elseif ($reqModel -match "(?i)sonnet") {
                $inRate = 2.00; $cachedRate = 0.10; $outRate = 10.00
            } elseif ($reqModel -match "(?i)haiku-4") {
                $inRate = 1.00; $cachedRate = 0.10; $outRate = 5.00
            } else {
                # claude-haiku-5-5 default ($0.10/1M in, $0.01/1M cached, $0.50/1M out)
                $inRate = 0.10; $cachedRate = 0.01; $outRate = 0.50
            }
        }

        $uncachedIn = [Math]::Max(0, $inTok - $cachedTok)
        $turnCost = (($uncachedIn / 1000000.0) * $inRate) + (($cachedTok / 1000000.0) * $cachedRate) + (($outTok / 1000000.0) * $outRate)

        $Script:Session.PromptTokens     += $inTok
        $Script:Session.CachedTokens     += $cachedTok
        $Script:Session.CompletionTokens += $outTok
        $Script:Session.TotalCostUsd     += $turnCost

        return @{
            Content      = $replyText
            InputTokens  = $inTok
            CachedTokens = $cachedTok
            OutputTokens = $outTok
            TurnCostUsd  = $turnCost
        }
    }

    # =========================================================================
    # Agentic Tool Execution Loop
    # =========================================================================
    function Parse-ToolBlock {
        param([string]$Text)
        if ([string]::IsNullOrEmpty($Text)) { return $null }
        $pattern = '(?s)```pca-tool\s*(\{.*?\})\s*```'
        $m = [regex]::Match($Text, $pattern)
        if (-not $m.Success) { return $null }
        try {
            return ($m.Groups[1].Value | ConvertFrom-Json)
        } catch {
            return $null
        }
    }

    function Invoke-DispatchTool {
        param($ToolCall)
        $name = ([string]$ToolCall.tool).ToLower()
        Write-Host ("  -> [Tool: {0}]" -f $name) -ForegroundColor Cyan
        switch ($name) {
            "list_files" {
                $sd = if ($ToolCall.sub_dir) { [string]$ToolCall.sub_dir } else { "." }
                $md = if ($ToolCall.max_depth) { [int]$ToolCall.max_depth } else { 2 }
                return Invoke-ToolListFiles -SubDir $sd -MaxDepth $md
            }
            "search_text" {
                $pat = [string]$ToolCall.pattern
                $sd  = if ($ToolCall.sub_dir) { [string]$ToolCall.sub_dir } else { "." }
                return Invoke-ToolSearchText -Pattern $pat -SubDir $sd
            }
            "read_file" {
                $p  = [string]$ToolCall.path
                $sl = if ($ToolCall.start_line) { [int]$ToolCall.start_line } else { 1 }
                $el = if ($ToolCall.end_line)   { [int]$ToolCall.end_line }   else { 0 }
                return Invoke-ToolReadFile -Path $p -StartLine $sl -EndLine $el
            }
            "inspect_xaml" {
                $p = [string]$ToolCall.path
                return Invoke-ToolInspectXaml -Path $p
            }
            "inspect_ui_tree" {
                $wt = if ($null -ne $ToolCall.window_title) { [string]$ToolCall.window_title } else { "" }
                $md = if ($ToolCall.max_depth) { [int]$ToolCall.max_depth } else { 3 }
                return Invoke-ToolInspectUiTree -WindowTitle $wt -MaxDepth $md
            }
            "validate_xaml" {
                $p = [string]$ToolCall.path
                return Invoke-ToolValidateXaml -Path $p
            }
            "scaffold_xaml" {
                $p   = [string]$ToolCall.path
                $tpl = if ($ToolCall.template)     { [string]$ToolCall.template }     else { "sequence" }
                $exe = if ($ToolCall.app_exe)      { [string]$ToolCall.app_exe }      else { "notepad.exe" }
                $wt  = if ($ToolCall.window_title) { [string]$ToolCall.window_title } else { "*Notepad*" }
                return Invoke-ToolScaffoldXaml -Path $p -Template $tpl -AppExe $exe -WindowTitle $wt
            }
            "edit_file" {
                $p   = [string]$ToolCall.path
                $s   = if ($null -ne $ToolCall.search)  { [string]$ToolCall.search }  else { "" }
                $rep = if ($null -ne $ToolCall.replace) { [string]$ToolCall.replace } else { "" }
                return Invoke-ToolEditFile -Path $p -Search $s -Replace $rep
            }
            "run_command" {
                $cmd = [string]$ToolCall.command
                return Invoke-ToolRunCommand -Command $cmd
            }
            default {
                return "Error: Unknown tool '$name'."
            }
        }
    }

    function Invoke-AgentTurn {
        param([string]$UserMessage)
        $Script:Session.TurnCount++
        Compact-HistoryIfNeeded

        $Script:Session.History.Add(@{
            role    = "user"
            content = $UserMessage
        })

        $step = 0
        while ($step -lt $Script:Session.MaxToolSteps) {
            $step++
            $messages = New-Object System.Collections.Generic.List[object]
            $messages.Add(@{
                role    = "system"
                content = (Build-SystemPrompt)
            })
            foreach ($h in $Script:Session.History) {
                $messages.Add($h)
            }

            $res = Invoke-LlmChatCompletion -Messages $messages.ToArray()
            $reply = $res.Content

            $Script:Session.History.Add(@{
                role    = "assistant"
                content = $reply
            })

            Write-Host ""
            Write-Host $reply -ForegroundColor White
            Write-StatusFooter -InTok $res.InputTokens -CachedTok $res.CachedTokens -OutTok $res.OutputTokens -TurnCost $res.TurnCostUsd

            if ($Script:Session.NoTools) { break }

            $toolObj = Parse-ToolBlock -Text $reply
            if ($null -eq $toolObj) { break }

            $toolOut = Invoke-DispatchTool -ToolCall $toolObj
            $Script:Session.History.Add(@{
                role    = "user"
                content = "[Tool Result for $($toolObj.tool)]`n$toolOut"
            })
        }
    }

    function Test-SingleEndpoint {
        param(
            [string]$Name,
            [string]$Url,
            [string]$ModelName,
            [string]$EnvKeyName
        )
        if ([string]::IsNullOrEmpty($Url)) {
            return @{
                Provider = $Name
                Host     = "(not configured)"
                Status   = "SKIPPED (No URL)"
                Allowed  = $false
                Ready    = $false
                Ms       = 0
                Proxy    = "-"
                Detail   = "Set base_url in .pca.json"
            }
        }

        $uriObj = [System.Uri]$Url
        $hostName = $uriObj.Host
        $proxyLabel = "Direct"
        $sysProxy = [System.Net.WebRequest]::GetSystemWebProxy()
        if ($null -ne $sysProxy) {
            try {
                $mappedProxy = $sysProxy.GetProxy($uriObj)
                if ($null -ne $mappedProxy -and $mappedProxy.Host -ne $uriObj.Host) {
                    $proxyLabel = "$($mappedProxy.Host):$($mappedProxy.Port)"
                }
            } catch {}
        }

        $keyVal = ""
        if (-not [string]::IsNullOrEmpty($EnvKeyName)) {
            $keyVal = [Environment]::GetEnvironmentVariable($EnvKeyName)
        }
        if ([string]::IsNullOrEmpty($keyVal)) {
            $keyVal = Get-EncryptedApiKey -ProviderName $Name
        }
        if ([string]::IsNullOrEmpty($keyVal) -and $Script:Session.Provider -eq $Name) {
            $keyVal = $Script:Session.ApiKey
        }
        $hasKey = -not [string]::IsNullOrEmpty($keyVal)
        $probeKey = if ($hasKey) { $keyVal } else { "pca-firewall-probe" }

        $payload = (@{
            model      = if ($ModelName) { $ModelName } else { "gpt-4o-mini" }
            messages   = @(@{ role = "user"; content = "ping" })
            max_tokens = 1
        } | ConvertTo-Json -Depth 4 -Compress)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $req = [System.Net.HttpWebRequest]::Create($Url)
            $req.Method = "POST"
            $req.ContentType = "application/json"
            $req.Accept = "application/json"
            $req.Timeout = 8000
            $req.ReadWriteTimeout = 8000
            $req.UserAgent = "pca-cli/$($Script:Version)"
            if ($null -ne $sysProxy) {
                $sysProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
                $req.Proxy = $sysProxy
            }
            if ($Url -match "/v1/messages$" -or $Name -eq "claude" -or $Name -eq "anthropic") {
                $req.Headers.Add("x-api-key", $probeKey)
                $req.Headers.Add("anthropic-version", "2023-06-01")
            } else {
                $req.Headers.Add("Authorization", "Bearer $probeKey")
            }

            $st = $req.GetRequestStream()
            $st.Write($bytes, 0, $bytes.Length)
            $st.Close()

            $resp = $req.GetResponse()
            $sw.Stop()
            $ct = [string]$resp.ContentType
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $resp.Close()

            if ($ct -match "text/html" -or $body -match "(?i)<html|<!doctype|zscaler|netskope|fortiguard|access denied") {
                return @{
                    Provider = $Name; Host = $hostName; Status = "BLOCKED (HTML Block Page)"
                    Allowed = $false; Ready = $false; Ms = $sw.ElapsedMilliseconds; Proxy = $proxyLabel
                    Detail = "Corporate proxy returned HTML block page instead of JSON"
                }
            }
            if ($ct -notmatch "json" -and -not $body.Trim().StartsWith("{")) {
                $st = if ($hostName -match "models\.github\.ai|models\.inference\.ai\.azure\.com") { "RETIRED (Shut down Jul 2026)" } else { "BLOCKED (Non-JSON HTTP 200)" }
                return @{
                    Provider = $Name; Host = $hostName; Status = $st
                    Allowed = $false; Ready = $false; Ms = $sw.ElapsedMilliseconds; Proxy = $proxyLabel
                    Detail = "Returned non-JSON body ('$($body.Trim())')"
                }
            }
            return @{
                Provider = $Name; Host = $hostName; Status = "ALLOWED (Key Valid & Ready)"
                Allowed = $true; Ready = $true; Ms = $sw.ElapsedMilliseconds; Proxy = $proxyLabel
                Detail = "HTTP 200 JSON received"
            }
        } catch [System.Net.WebException] {
            $sw.Stop()
            $wex = $_.Exception
            $statusEnum = $wex.Status.ToString()

            if ($statusEnum -match "TrustFailure|SecureChannelFailure" -or $wex.Message -match "(?i)SSL|TLS|certificate") {
                return @{
                    Provider = $Name; Host = $hostName; Status = "BLOCKED (SSL/TLS Cert)"
                    Allowed = $false; Ready = $false; Ms = $sw.ElapsedMilliseconds; Proxy = $proxyLabel
                    Detail = "Corporate TLS inspection cert error (try -SkipCertCheck)"
                }
            }

            if ($null -ne $wex.Response) {
                $httpResp = [System.Net.HttpWebResponse]$wex.Response
                $code = [int]$httpResp.StatusCode
                $ct = [string]$httpResp.ContentType
                $errBody = ""
                try {
                    $er = New-Object System.IO.StreamReader($httpResp.GetResponseStream(), [System.Text.Encoding]::UTF8)
                    $errBody = $er.ReadToEnd()
                    $er.Close()
                } catch {}

                if ($code -eq 407) {
                    return @{
                        Provider = $Name; Host = $hostName; Status = "BLOCKED (407 Proxy Auth)"
                        Allowed = $false; Ready = $false; Ms = $sw.ElapsedMilliseconds; Proxy = $proxyLabel
                        Detail = "Corporate proxy requires authentication"
                    }
                }
                if ($ct -match "text/html" -or $errBody -match "(?i)<html|<!doctype|zscaler|netskope|fortiguard|palo alto|blocked|access denied") {
                    return @{
                        Provider = $Name; Host = $hostName; Status = "BLOCKED (Firewall HTTP $code)"
                        Allowed = $false; Ready = $false; Ms = $sw.ElapsedMilliseconds; Proxy = $proxyLabel
                        Detail = "Blocked by enterprise web filter (HTML response)"
                    }
                }
                if ($ct -match "json" -or $errBody.Trim().StartsWith("{") -or $code -eq 401 -or $code -eq 400 -or $code -eq 429) {
                    $keyNote = if ($hasKey) { "HTTP $code (Check API Key / Model)" } else { "ALLOWED (Set `$$EnvKeyName to use)" }
                    return @{
                        Provider = $Name; Host = $hostName; Status = $keyNote
                        Allowed = $true; Ready = $false; Ms = $sw.ElapsedMilliseconds; Proxy = $proxyLabel
                        Detail = "Firewall open! Reached real AI API (HTTP $code JSON)"
                    }
                }
                return @{
                    Provider = $Name; Host = $hostName; Status = "BLOCKED (HTTP $code)"
                    Allowed = $false; Ready = $false; Ms = $sw.ElapsedMilliseconds; Proxy = $proxyLabel
                    Detail = "Unexpected HTTP $code"
                }
            }

            return @{
                Provider = $Name; Host = $hostName; Status = "BLOCKED ($statusEnum)"
                Allowed = $false; Ready = $false; Ms = $sw.ElapsedMilliseconds; Proxy = $proxyLabel
                Detail = $wex.Message
            }
        } catch {
            $sw.Stop()
            return @{
                Provider = $Name; Host = $hostName; Status = "BLOCKED (Error)"
                Allowed = $false; Ready = $false; Ms = $sw.ElapsedMilliseconds; Proxy = $proxyLabel
                Detail = $_.Exception.Message
            }
        }
    }

    function Invoke-TestEndpoints {
        param([string]$Target = "")
        Write-Host ""
        Write-Host "  Testing Enterprise Firewall & Proxy Connectivity to AI Endpoints..." -ForegroundColor Cyan
        Write-Host "  ----------------------------------------------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host ("  {0,-14} | {1,-34} | {2,-30} | {3,6} | {4}" -f "Provider", "Endpoint Host", "Firewall / Status", "Time", "Proxy") -ForegroundColor White
        Write-Host "  ----------------------------------------------------------------------------------------------------" -ForegroundColor DarkGray

        $targets = New-Object System.Collections.Generic.List[object]
        if (-not [string]::IsNullOrEmpty($Target)) {
            $tLower = $Target.ToLower()
            if ($tLower -eq "anthropic") { $tLower = "claude" }
            if ($Script:ProviderCatalog.ContainsKey($tLower)) {
                $p = $Script:ProviderCatalog[$tLower]
                $targets.Add(@{ Name = $tLower; Url = $p.BaseUrl; Model = $p.CheapModel; Env = $p.EnvKey })
            } elseif ($Target -match "^https?://") {
                $targets.Add(@{ Name = "custom-url"; Url = $Target; Model = $Script:Session.Model; Env = "PCA_API_KEY" })
            } else {
                Write-Host "  Unknown provider or URL '$Target'." -ForegroundColor Red
                return
            }
        } else {
            foreach ($k in @("gemini", "claude", "openrouter", "groq", "deepseek", "openai", "github-models")) {
                $p = $Script:ProviderCatalog[$k]
                $targets.Add(@{ Name = $k; Url = $p.BaseUrl; Model = $p.CheapModel; Env = $p.EnvKey })
            }
            if (-not [string]::IsNullOrEmpty($Script:Session.BaseUrl) -and $Script:Session.Provider -eq "azure-openai") {
                $targets.Add(@{ Name = "azure-openai"; Url = $Script:Session.BaseUrl; Model = $Script:Session.Model; Env = "AZURE_OPENAI_API_KEY" })
            }
        }

        $allowedList = New-Object System.Collections.Generic.List[string]
        foreach ($t in $targets) {
            $res = Test-SingleEndpoint -Name $t.Name -Url $t.Url -ModelName $t.Model -EnvKeyName $t.Env
            $color = if ($res.Ready) { "Green" } elseif ($res.Allowed) { "Yellow" } else { "Red" }
            if ($res.Allowed) { $allowedList.Add($res.Provider) }
            Write-Host ("  {0,-14} | {1,-34} | {2,-30} | {3,4}ms | {4}" -f `
                $res.Provider, $res.Host, $res.Status, $res.Ms, $res.Proxy) -ForegroundColor $color
        }
        Write-Host "  ----------------------------------------------------------------------------------------------------" -ForegroundColor DarkGray
        if ($allowedList.Count -gt 0) {
            Write-Host ("  Recommended Allowed Providers on this machine: {0}" -f ($allowedList -join ", ")) -ForegroundColor Green
        } else {
            Write-Host "  All external AI endpoints were blocked. Configure an internal corporate gateway via -BaseUrl or azure-openai." -ForegroundColor Yellow
        }
        Write-Host ""
    }

    # =========================================================================
    # Interactive Slash Commands
    # =========================================================================
    function Show-ProvidersTable {
        Write-Host ""
        Write-Host "  Available Free & Ultra-Cheap LLM Providers (Tiers: cheap | smart | opus):" -ForegroundColor Cyan
        Write-Host "  ------------------------------------------------------------------------------------------------------" -ForegroundColor DarkGray
        foreach ($k in @("gemini", "claude", "openrouter", "groq", "deepseek", "openai", "azure-openai", "ollama", "github-models")) {
            $p = $Script:ProviderCatalog[$k]
            $active = if ($Script:Session.Provider -eq $k) { "*" } else { " " }
            Write-Host ("  [{0}] {1,-14} | Cheap: {2,-22} | Smart: {3,-22} | Opus: {4}" -f $active, $k, $p.CheapModel, $p.SmartModel, $p.OpusModel) -ForegroundColor White
            Write-Host ("      Env: {0,-21} | {1}" -f $p.EnvKey, $p.Notes) -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    function Handle-SlashCommand {
        param([string]$InputLine)
        $parts = $InputLine.Trim() -split "\s+", 2
        $cmd = $parts[0].ToLower()
        $arg = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }

        switch ($cmd) {
            "/help" {
                Write-Host @"

  Slash Commands:
    /test [prov|url]        Test which AI endpoints are allowed through corporate firewall/proxy
    /key [save]             Enter API key securely (masked) and optionally save encrypted via Windows DPAPI
    /provider [name]        List providers or switch active provider (e.g. /provider claude, /provider gemini)
    /model [name]           Switch active model name (e.g. /model claude-sonnet-5-5)
    /tier [cheap|smart|opus] Switch between cheap (Haiku/Flash), smart (Sonnet/Pro), and opus tiers
    /uipath                 Activate UiPath XAML & Desktop Automation Agent mode (uipath + uipath-desktop)
    /skill [name|off]       Activate a domain skill (uipath, uipath-desktop, uipath-planner, uipath-review)
    /add <file>             Pin a file to system context
    /drop [file|all]        Unpin a file or clear all pinned files
    /files                  List workspace files
    /undo                   Revert the most recent file edit or creation
    /compact                Compress older conversation history to save tokens
    /cost                   Show session token and USD cost breakdown
    /init                   Create a default .pca.json config file in current workspace
    /clear                  Clear conversation history
    /exit                   Exit PCA
"@ -ForegroundColor Gray
            }
            "/test" {
                Invoke-TestEndpoints -Target $arg
            }
            "/key" {
                $secInput = Read-Host -Prompt "  Enter API key for '$($Script:Session.Provider)' (input is hidden)" -AsSecureString
                $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secInput)
                $plain = ""
                try {
                    $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                } finally {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                }
                if (-not [string]::IsNullOrEmpty($plain)) {
                    $Script:Session.ApiKey = $plain
                    Write-Host "  API key set in memory for current session." -ForegroundColor Green
                    if ($arg.ToLower() -eq "save") {
                        Save-EncryptedApiKey -ProviderName $Script:Session.Provider -PlainKey $plain
                    } else {
                        Write-Host "  (Tip: Run '/key save' to store encrypted on disk using Windows DPAPI so you never retype it.)" -ForegroundColor DarkGray
                    }
                }
            }
            "/uipath" {
                $sub = $arg.ToLower()
                if ($sub -in @("off", "none", "clear")) {
                    $Script:Session.ActiveSkills.Clear()
                    Write-Host "  Cleared all active skills." -ForegroundColor Green
                } else {
                    $toAdd = @("uipath", "uipath-rpa", "uipath-desktop")
                    if ($sub -eq "plan")         { $toAdd = @("uipath", "uipath-rpa", "uipath-desktop", "uipath-planner") }
                    if ($sub -eq "review")       { $toAdd = @("uipath", "uipath-rpa", "uipath-desktop", "uipath-review") }
                    if ($sub -eq "troubleshoot") { $toAdd = @("uipath", "uipath-rpa", "uipath-desktop", "uipath-troubleshoot") }
                    if ($sub -eq "migrate")      { $toAdd = @("uipath", "uipath-rpa", "uipath-desktop", "uipath-activity-migrator") }
                    if ($sub -in @("full", "all")) { $toAdd = @("uipath", "uipath-rpa", "uipath-desktop", "uipath-planner", "uipath-review", "uipath-troubleshoot", "uipath-activity-migrator") }
                    foreach ($sk in $toAdd) {
                        if (-not $Script:Session.ActiveSkills.Contains($sk)) {
                            $Script:Session.ActiveSkills.Add($sk)
                        }
                    }
                    $activeStr = $Script:Session.ActiveSkills -join ", "
                    Write-Host "  Activated UiPath XAML & Desktop Automation Agent skills: $activeStr" -ForegroundColor Green
                    Write-Host "  Sub-modes: /uipath | /uipath plan | /uipath review | /uipath troubleshoot | /uipath migrate | /uipath full | /uipath off" -ForegroundColor DarkGray
                }
            }
            "/skill" {
                if ([string]::IsNullOrEmpty($arg)) {
                    $activeStr = if ($Script:Session.ActiveSkills.Count -gt 0) { ($Script:Session.ActiveSkills -join ", ") } else { "none" }
                    Write-Host "  Active skills: $activeStr" -ForegroundColor Cyan
                    Write-Host "  Available skills: uipath, uipath-rpa, uipath-desktop, uipath-planner, uipath-review, uipath-troubleshoot, uipath-activity-migrator (or '/skill off' to clear)" -ForegroundColor DarkGray
                } elseif ($arg.ToLower() -eq "off" -or $arg.ToLower() -eq "none" -or $arg.ToLower() -eq "clear") {
                    $Script:Session.ActiveSkills.Clear()
                    Write-Host "  Cleared all active skills." -ForegroundColor Green
                } else {
                    $skName = $arg.ToLower()
                    if (-not $Script:Session.ActiveSkills.Contains($skName)) {
                        $Script:Session.ActiveSkills.Add($skName)
                    }
                    Write-Host "  Activated skill '$skName'." -ForegroundColor Green
                }
            }
            "/provider" {
                $pArg = $arg.ToLower()
                if ($pArg -eq "anthropic") { $pArg = "claude" }
                if ([string]::IsNullOrEmpty($pArg)) {
                    Show-ProvidersTable
                } elseif ($Script:ProviderCatalog.ContainsKey($pArg)) {
                    $Script:Session.Provider = $pArg
                    $cat = $Script:ProviderCatalog[$Script:Session.Provider]
                    $Script:Session.BaseUrl = $cat.BaseUrl
                    $Script:Session.Model = Get-ModelForTier -Cat $cat -TierName $Script:Session.Tier
                    $envKeyVal = [Environment]::GetEnvironmentVariable($cat.EnvKey)
                    if ([string]::IsNullOrEmpty($envKeyVal)) { $envKeyVal = Get-EncryptedApiKey -ProviderName $Script:Session.Provider }
                    if (-not [string]::IsNullOrEmpty($envKeyVal)) { $Script:Session.ApiKey = $envKeyVal }
                    Write-Host "  Switched provider to '$($Script:Session.Provider)' (model: $($Script:Session.Model))." -ForegroundColor Green
                } else {
                    Write-Host "  Unknown provider '$arg'. Run /provider to see valid options." -ForegroundColor Red
                }
            }
            "/model" {
                if ([string]::IsNullOrEmpty($arg)) {
                    Write-Host "  Current model: $($Script:Session.Model)" -ForegroundColor Cyan
                } else {
                    $Script:Session.Model = $arg
                    Write-Host "  Switched model to '$arg'." -ForegroundColor Green
                }
            }
            "/tier" {
                $tArg = $arg.ToLower()
                if ($tArg -in @("cheap", "smart", "opus", "haiku", "sonnet")) {
                    $Script:Session.Tier = if ($tArg -eq "haiku") { "cheap" } elseif ($tArg -eq "sonnet") { "smart" } else { $tArg }
                    $cat = $Script:ProviderCatalog[$Script:Session.Provider]
                    if ($cat) {
                        $Script:Session.Model = Get-ModelForTier -Cat $cat -TierName $Script:Session.Tier
                    }
                    Write-Host "  Switched tier to '$($Script:Session.Tier)' (model: $($Script:Session.Model))." -ForegroundColor Green
                } else {
                    Write-Host "  Usage: /tier cheap (haiku)  |  /tier smart (sonnet)  |  /tier opus" -ForegroundColor Yellow
                }
            }
            "/add" {
                if ([string]::IsNullOrEmpty($arg)) {
                    $pinnedStr = $Script:Session.PinnedFiles -join ", "
                    Write-Host "  Pinned files: $pinnedStr" -ForegroundColor Cyan
                } else {
                    $Script:Session.PinnedFiles.Add($arg)
                    Write-Host "  Pinned '$arg' to context." -ForegroundColor Green
                }
            }
            "/drop" {
                if ($arg -eq "all" -or [string]::IsNullOrEmpty($arg)) {
                    $Script:Session.PinnedFiles.Clear()
                    Write-Host "  Cleared all pinned files." -ForegroundColor Green
                } else {
                    $Script:Session.PinnedFiles.Remove($arg) | Out-Null
                    Write-Host "  Unpinned '$arg'." -ForegroundColor Green
                }
            }
            "/files" {
                Write-Host (Invoke-ToolListFiles -SubDir "." -MaxDepth 2) -ForegroundColor Gray
            }
            "/undo" {
                Invoke-UndoLastEdit
            }
            "/compact" {
                Compact-HistoryIfNeeded -Force
            }
            "/cost" {
                Write-Host ""
                Write-Host ("  Session Token & Cost Summary:") -ForegroundColor Cyan
                Write-Host ("    Prompt Tokens     : {0}" -f $Script:Session.PromptTokens)
                Write-Host ("    Cached Hit Tokens : {0}" -f $Script:Session.CachedTokens)
                Write-Host ("    Completion Tokens : {0}" -f $Script:Session.CompletionTokens)
                Write-Host ("    Estimated USD     : `${0:N5} (Cap: `${1:N2})" -f $Script:Session.TotalCostUsd, $Script:Session.MaxSessionCostUsd)
                Write-Host ""
            }
            "/init" {
                Initialize-ConfigFile
            }
            "/clear" {
                $Script:Session.History.Clear()
                Write-Host "  Cleared conversation history." -ForegroundColor Green
            }
            "/exit" { return "EXIT" }
            "/quit" { return "EXIT" }
            default {
                Write-Host "  Unknown command '$cmd'. Type /help for available commands." -ForegroundColor Yellow
            }
        }
        return "CONTINUE"
    }

    # =========================================================================
    # Entrypoint Execution
    # =========================================================================
    Resolve-Configuration

    if ($Uip) {
        $Script:Session.AutoApprove = $true
        $rawUipCmd = "uip " + ($PromptArgs -join " ")
        $uipJson = Invoke-NativeUipCommand -RawCommand $rawUipCmd
        Write-Output $uipJson
        return
    }

    if ($Help) {
        Write-Banner
        Handle-SlashCommand "/help" | Out-Null
        Show-ProvidersTable
        return
    }

    if ($ListProviders) {
        Show-ProvidersTable
        return
    }

    if ($TestEndpoints) {
        $targetArg = if ($PromptArgs -and $PromptArgs.Count -gt 0) { $PromptArgs[0] } else { "" }
        Invoke-TestEndpoints -Target $targetArg
        return
    }

    if ($InitConfig) {
        Initialize-ConfigFile
        return
    }

    if ($CompileExe) {
        Invoke-CompileNativeExe
        return
    }

    $initialPrompt = if ($PromptArgs -and $PromptArgs.Count -gt 0) { ($PromptArgs -join " ").Trim() } else { "" }
    $pipedText = if ($Script:PipeBuffer.Count -gt 0) { ($Script:PipeBuffer -join "`n").Trim() } else { "" }

    # One-Shot Mode (if prompt or piped stdin was supplied)
    if (-not [string]::IsNullOrEmpty($initialPrompt) -or -not [string]::IsNullOrEmpty($pipedText)) {
        $combinedPrompt = $initialPrompt
        if (-not [string]::IsNullOrEmpty($pipedText)) {
            if ($pipedText.Length -gt 12000) {
                $pipedText = $pipedText.Substring(0, 12000) + "`n... [Piped input truncated to 12,000 chars to save tokens]"
            }
            $fence = '```'
            $combinedPrompt = "$initialPrompt`n`n--- Piped Input ---`n$($fence)text`n$pipedText`n$fence"
        }
        Invoke-AgentTurn -UserMessage $combinedPrompt.Trim()
        return
    }

    # Interactive REPL Mode
    Write-Banner
    while ($true) {
        Write-Host -NoNewline "pca ($($Script:Session.Provider):$($Script:Session.Tier))> " -ForegroundColor Green
        $line = [Console]::ReadLine()
        if ($null -eq $line) { break }
        $trimmed = $line.Trim()
        if ([string]::IsNullOrEmpty($trimmed)) { continue }

        if ($trimmed.StartsWith("/")) {
            $status = Handle-SlashCommand -InputLine $trimmed
            if ($status -eq "EXIT") { break }
            continue
        }

        try {
            Invoke-AgentTurn -UserMessage $trimmed
        } catch {
            Write-Host "  [Error] $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
