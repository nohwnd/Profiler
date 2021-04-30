## Profiling a script

Import-Module $PSScriptRoot/Profiler/Profiler.psm1 -Force

# Runs the script 1 time, with 1 warm up run (this is needed in PowerShell 7)
$trace =  Trace-Script -Preheat 1 -ScriptBlock { & "$PSScriptRoot/demo-scripts/MyScript.ps1" }

# Shows the top 50 lines that take the most percent of the run
$trace.Top50 | Format-Table

# Try it for yourself by running the commands from this demo, or by invoking this file as
# . ./demo.ps1
