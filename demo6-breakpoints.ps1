
Get-Module Profiler, Pester | Remove-Module 

Import-Module $PSScriptRoot/Profiler/Profiler.psd1

$sb = {
    $bp1 = Set-PSBreakpoint -Script $PSCommandPath -Line 1 -Action {}
    $bp1 | Disable-PSBreakpoint
    $bp = Set-PSBreakpoint -Script $PSCommandPath -Line 1 -Action {}
    Start-Sleep -Milliseconds 500

    # Remove-PSBreakpoint removes our hook for some reason. If you are using it in your script and don't rely on the sideeffects
    # you can add an empty Remove-PSBreakPoint function for now to be able to profile your script. Working on a fix.
    # there is warning on screen when this happens and the log is incomplete.
    $bp | Remove-PSBreakpoint 
    
    Write-Host "This is not measured."
    Start-Sleep 1
}

$trace = Trace-Script { & $sb } -Preheat 0

$trace.Top50Duration | Format-Table