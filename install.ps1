# Télécharge, enregistre et installe le runner GitHub Actions comme service Windows.
# Usage (PowerShell administrateur) : powershell -ExecutionPolicy Bypass -File install.ps1
. "$PSScriptRoot\common.ps1"
Assert-Admin

if (Test-Path (Join-Path $RunnerDir '.runner')) {
    Die "runner déjà configuré dans $RunnerDir (uninstall.ps1 d'abord)"
}

$arch = Get-RunnerArch
if ($RunnerVersion -eq 'latest') {
    $RunnerVersion = (Invoke-RestMethod https://api.github.com/repos/actions/runner/releases/latest).tag_name.TrimStart('v')
}
$zip = "actions-runner-win-$arch-$RunnerVersion.zip"
$url = "https://github.com/actions/runner/releases/download/v$RunnerVersion/$zip"

Log "Installation du runner v$RunnerVersion (win-$arch) dans $RunnerDir"
New-Item -ItemType Directory -Force -Path $RunnerDir | Out-Null
Set-Location $RunnerDir
if (-not (Test-Path .\config.cmd)) {
    $ProgressPreference = 'SilentlyContinue'   # accélère fortement Invoke-WebRequest
    Invoke-WebRequest -Uri $url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath . -Force
    Remove-Item $zip
}

Log "Enregistrement auprès de $GithubUrl"
$token = Get-RegistrationToken
if (-not $token) { Die "impossible d'obtenir un jeton d'enregistrement" }

$cfgArgs = @('--unattended', '--replace', '--runasservice',
             '--url', $GithubUrl, '--token', $token,
             '--name', $RunnerName, '--work', '_work')
if ($RunnerLabels) { $cfgArgs += @('--labels', $RunnerLabels) }
if ((Get-ApiScope) -like 'orgs/*') { $cfgArgs += @('--runnergroup', $RunnerGroup) }
& .\config.cmd @cfgArgs
if ($LASTEXITCODE -ne 0) { Die "config.cmd a échoué ($LASTEXITCODE)" }

$svc = Get-RunnerServiceName
Start-Service $svc -ErrorAction SilentlyContinue
Get-Service $svc | Format-Table -AutoSize

$labels = if ($RunnerLabels) { ", $RunnerLabels" } else { '' }
Log "OK. Dans les workflows : runs-on: [self-hosted, windows$labels]"
