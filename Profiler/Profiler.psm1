# for BP to attach
Import-Module "$PSScriptRoot/bin/net452/Profiler.dll"

# last 10 runs, show times to see how it went

. "$PSScriptRoot/Assert-PowerShellVersion.ps1"
. "$PSScriptRoot/Invoke-Script.ps1"
. "$PSScriptRoot/Trace-ScriptInternal.ps1"
. "$PSScriptRoot/Trace-Script.ps1"


Export-ModuleMember -Function 'Invoke-Script', 'Trace-Script', 'Get-LatestTrace'
