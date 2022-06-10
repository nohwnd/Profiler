## Profiling a script

Import-Module $PSScriptRoot/Profiler/Profiler.psd1 -Force

$trace =  Trace-Script -ScriptBlock { 
    
    start-sleep -Seconds 4
    & "$PSScriptRoot/demo-scripts/Get-Icons.ps1" } -ExportPath emojis.speedscope.json

# Shows the top 50 lines that take the most percent of the run by themselves
$trace.Top50SelfDuration | Format-Table

# Try it for yourself by running the commands from this demo, or by invoking this file as
# . ./demo.ps1
