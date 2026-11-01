# Fonctions partagées (Windows) — à dot-sourcer : . "$PSScriptRoot\common.ps1"
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Die($msg) { Write-Error "ERREUR: $msg"; exit 1 }
function Log($msg) { Write-Host "==> $msg" }

function Assert-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Die "lancer PowerShell en administrateur"
    }
}

# Lecture de runner.env (KEY=VALUE, avec $HOME, $(hostname), ${VAR} / $VAR)
function Read-RunnerEnv($path) {
    if (-not (Test-Path $path)) { Die "$path introuvable (copy runner.env.example runner.env)" }
    $vars = @{ HOME = $env:USERPROFILE }
    foreach ($line in Get-Content $path) {
        $line = $line.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { continue }
        $key = $Matches[1]
        $val = $Matches[2].Trim().Trim('"').Trim("'")
        $val = $val.Replace('$(hostname)', $env:COMPUTERNAME)
        $val = [regex]::Replace($val, '\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?', {
            param($m)
            $n = $m.Groups[1].Value
            if ($vars.ContainsKey($n)) { $vars[$n] }
            elseif (Test-Path "env:$n") { (Get-Item "env:$n").Value }
            else { '' }
        })
        $vars[$key] = $val
    }
    return $vars
}

$EnvFile = if ($env:ENV_FILE) { $env:ENV_FILE } else { Join-Path $PSScriptRoot 'runner.env' }
$Cfg = Read-RunnerEnv $EnvFile

foreach ($k in 'GITHUB_URL', 'RUNNER_NAME') {
    if (-not $Cfg[$k]) { Die "$k manquant dans $EnvFile" }
}
$GithubUrl     = $Cfg.GITHUB_URL.TrimEnd('/')
$RunnerName    = $Cfg.RUNNER_NAME
$RunnerLabels  = $Cfg.RUNNER_LABELS
$RunnerGroup   = if ($Cfg.RUNNER_GROUP) { $Cfg.RUNNER_GROUP } else { 'Default' }
$RunnerVersion = if ($Cfg.RUNNER_VERSION) { $Cfg.RUNNER_VERSION } else { 'latest' }
$RunnerDir     = if ($Cfg.RUNNER_DIR_WIN) { $Cfg.RUNNER_DIR_WIN } else { "C:\actions-runner\$RunnerName" }
$GithubPat     = if ($Cfg.GITHUB_PAT) { $Cfg.GITHUB_PAT } else { $env:GITHUB_PAT }

# Chemin d'API : repos/OWNER/REPO ou orgs/ORG
function Get-ApiScope {
    $path = $GithubUrl -replace '^https://github.com/', ''
    if ($path -like '*/*') { "repos/$path" } else { "orgs/$path" }
}

# Appel POST à l'API GitHub (PAT ou gh CLI)
function Invoke-GhPost($endpoint) {
    if ($GithubPat) {
        Invoke-RestMethod -Method Post -Uri "https://api.github.com/$endpoint" -Headers @{
            Authorization = "Bearer $GithubPat"; Accept = 'application/vnd.github+json'
        }
    } elseif (Get-Command gh -ErrorAction SilentlyContinue) {
        gh api -X POST $endpoint | ConvertFrom-Json
    } else {
        Die "ni GITHUB_PAT ni gh CLI disponibles"
    }
}

function Get-RegistrationToken { (Invoke-GhPost "$(Get-ApiScope)/actions/runners/registration-token").token }
function Get-RemoveToken       { (Invoke-GhPost "$(Get-ApiScope)/actions/runners/remove-token").token }

function Get-RunnerArch {
    switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { 'x64' }
        'ARM64' { 'arm64' }
        default { Die "architecture non supportée: $env:PROCESSOR_ARCHITECTURE" }
    }
}

# Nom du service Windows enregistré par config.cmd --runasservice
function Get-RunnerServiceName {
    $f = Join-Path $RunnerDir '.service'
    if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }
    $svc = Get-Service "actions.runner.*.$RunnerName" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($svc) { return $svc.Name }
    Die "service non installé (install.ps1)"
}
