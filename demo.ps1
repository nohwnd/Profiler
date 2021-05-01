## Profiling a script

Import-Module $PSScriptRoot/Profiler/Profiler.psm1 -Force

$trace =  Trace-Script -ScriptBlock { & "$PSScriptRoot/demo-scripts/MyScript.ps1" }

# Shows the top 50 lines that take the most percent of the run
$trace.Top50 | Format-Table

# Try it for yourself by running the commands from this demo, or by invoking this file as
# . ./demo.ps1
