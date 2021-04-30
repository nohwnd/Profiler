### SleepyScript.ps1
function a () { 
    Start-Sleep -Milliseconds 100
 }
 
 function b () { 
     a
 }
 
 function c () {
     a
     b
 }
 
c

## Duration per-line and per itself, and finding what was slow
Import-Module $PSScriptRoot/Profiler/Profiler.psm1 -Force

# Runs the script 1 time, with 1 warm up run (this is needed in PowerShell 7)
$trace = Trace-Script { & "demo-scripts/SleepyScript.ps1" } -Preheat 1

$trace.Top50 | Format-Table

# oooh call to function 'c' is slow
$slowLine = $trace.Top50 | Where-Object text -eq 'c'
$slowLine | Format-Table

# it was called just once (hit), and by itself (SelfDuration) takes < 1ms, but the code it calls 
# takes over 200 ms (Duration), let's see what happens in the meantime
$hit = $slowLine.Hits[0]
$trace.Events[$hit.Index..$hit.ReturnIndex] | Format-Table

# and if that is too many calls, let's see the top 50 from that that themselves take the most
$trace.Events[$hit.Index..$hit.ReturnIndex] | 
    Sort-Object -Descending SelfDuration | 
    Select-Object -First 50 | 
    Format-Table