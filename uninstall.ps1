# Arrête et supprime le service, puis désenregistre le runner de GitHub.
. "$PSScriptRoot\common.ps1"
Assert-Admin

if (-not (Test-Path $RunnerDir)) { Die "$RunnerDir introuvable" }
Set-Location $RunnerDir

if (Test-Path .\.runner) {
    Log "Désenregistrement auprès de $GithubUrl (supprime aussi le service)"
    & .\config.cmd remove --token (Get-RemoveToken)
    if ($LASTEXITCODE -ne 0) { Die "config.cmd remove a échoué ($LASTEXITCODE)" }
}

Log "Runner retiré. Supprimer les fichiers : Remove-Item -Recurse -Force '$RunnerDir'"
