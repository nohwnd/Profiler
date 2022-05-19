$sb = { 
    $a = foreach ($i in 1..10000) { 
        $i
    }
}

$trace = Trace-Script -ScriptBlock $sb
$trace.Top50Duration | Format-Table Percent, HitCount, Duration, SelfDuration, Name, Line, Text