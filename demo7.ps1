
Get-Module Profiler, Pester | Remove-Module 

Import-Module $PSScriptRoot/Profiler/Profiler.psd1

$sb = {
    Get-Factorial 100000
}

$trace = Trace-Script { & $sb } -Preheat 0

$trace.Top50Duration | Format-Table