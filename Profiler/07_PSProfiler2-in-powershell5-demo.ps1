$ErrorActionPreference = 'Stop'

# .\build.ps1

Get-Module Tracer, Profiler | Remove-Module

Import-Module $PSScriptRoot/Profiler.psm1
 
$trace2 = Trace-Script { & "$PSScriptRoot/scripts/hello.ps1" } -old

$trace = Trace-Script { & "$PSScriptRoot/scripts/hello.ps1" } -old

if (-not $trace) { 
    throw "Trace is null something is wrong."
}

Write-Host -ForegroundColor Blue "Trace is done. Processing the it via Get-Profile"
$profiles = Get-Profile -Trace $trace # -Path $hello
Write-Host -ForegroundColor Blue "Get-Profile is done."

Write-Host -ForegroundColor Magenta Trace events $trace.Count 
$profiles.Top10 | ft

break 

$profiles.Files | Select-Object -Property Path
# hello.ps1
$profiles.Files[2].Profile | Format-Table -Property Line, Duration, HitCount, Text


break 

# but how do we know what is slow? Well it's simple: 
$profiles.Top10 |
    Format-Table -Property Percent, HitCount, Duration, Average, Line, Text, CommandHits