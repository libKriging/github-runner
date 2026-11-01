# Pilotage du service : start | stop | restart | status | logs
param([ValidateSet('start', 'stop', 'restart', 'status', 'logs')] [string]$Action = 'status')
. "$PSScriptRoot\common.ps1"

$svc = Get-RunnerServiceName
switch ($Action) {
    'start'   { Assert-Admin; Start-Service $svc }
    'stop'    { Assert-Admin; Stop-Service $svc }
    'restart' { Assert-Admin; Restart-Service $svc }
    'status'  { Get-Service $svc | Format-Table -AutoSize }
    'logs'    {
        $log = Get-ChildItem (Join-Path $RunnerDir '_diag') -Filter 'Runner_*.log' |
               Sort-Object LastWriteTime | Select-Object -Last 1
        if (-not $log) { Die "aucun journal dans $RunnerDir\_diag" }
        Get-Content $log.FullName -Tail 50 -Wait
    }
}
