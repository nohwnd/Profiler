
Get-Module Profiler, Pester | Remove-Module 

Import-Module $PSScriptRoot/Profiler/Profiler.psd1

$sb = {
    Set-PSBreakpoint -Script $PSCommandPath -Line 1 -Action {}
    Start-Sleep -Milliseconds 500

    # Remove-PSBreakpoint removes our hook when it remove all breakpoints, because it will also turn off script tracing. 
    Get-PSBreakpoint | Remove-PSBreakpoint 
    
    Write-Host "This is not measured."
    Start-Sleep 1
}

$trace = Trace-Script { & $sb } -Preheat 0

$trace.Top50SelfDuration | Format-Table

$trace.Events | ft