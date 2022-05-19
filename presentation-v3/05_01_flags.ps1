$sb = {
    if (-not $profiler_array) {
        $a = @()
        foreach ($i in 1..10000) { 
            $a += $i
        }
    }
    else {
        $a = foreach ($i in 1..10000) { 
            $i
        }
    } 
}

$trace = Trace-Script -ScriptBlock $sb -Flag @{ profiler_array = $true }
$trace.Top50Duration | Format-Table Percent, HitCount, Duration, SelfDuration, Name, Line, Text 