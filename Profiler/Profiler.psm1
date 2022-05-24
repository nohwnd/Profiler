# for BP to attach
if ($PSVersionTable.PSVersion.Major -ge 7) {
    [Reflection.Assembly]::LoadFrom("$PSScriptRoot/bin/netstandard2.0/Profiler.dll")
}
elseif ($PSVersionTable.PSVersion.Major -ge 5) {
    [Reflection.Assembly]::LoadFrom("$PSScriptRoot/bin/net452/Profiler.dll")
}
else {
    [Reflection.Assembly]::LoadFrom("$PSScriptRoot/bin/net451/Profiler.dll")
}

. "$PSScriptRoot/Assert-PowerShellVersion.ps1"
. "$PSScriptRoot/Invoke-Script.ps1"
. "$PSScriptRoot/Trace-ScriptInternal.ps1"
. "$PSScriptRoot/Trace-Script.ps1"
. "$PSScriptRoot/Export-SpeedScope.ps1"
. "$PSScriptRoot/Get-CallStack.ps1"
. "$PSScriptRoot/Show-ScriptExecution.ps1"

Export-ModuleMember -Function 'Invoke-Script', 'Trace-Script', 'Get-LatestTrace', 'Show-ScriptExecution', 'Get-CallStack'
