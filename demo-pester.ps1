
Get-Module Profiler, Pester | Remove-Module 

Import-Module $PSScriptRoot/Profiler/Profiler.psd1 -Force

$sb = {
        ${global:function:Set-PSBreakpoint} = {}
        ${global:function:Get-PSBreakpoint} = {}
        c:\p/pester/test.ps1 -SkipPTests
}


$trace = Trace-Script $sb -Preheat 0 -ExportPath pester

  # $trace.Top50Duration | Format-Table 