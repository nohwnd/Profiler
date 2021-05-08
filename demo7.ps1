
Get-Module Profiler, Pester | Remove-Module 

Import-Module $PSScriptRoot/Profiler/Profiler.psd1

$container = @{ Trace = $null }
$traceOfProfiler = Trace-Script { 

    $container.Trace = Trace-Script { 
        Start-Sleep -Second 1
    }

} -Preheat 0

$trace = $container.Trace
$trace.Top50Duration | Format-Table

$traceOfProfiler.Top50Duration | Format-Table
