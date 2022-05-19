$sb = { 
    function f () {  
        Start-Sleep -Seconds 1
    }
    f
}

$trace = Trace-Script -ScriptBlock $sb
$trace.Top50Duration | Format-Table Percent, HitCount, Duration, SelfDuration, Name, Line, Text
$trace.Top50SelfDuration | Format-Table Percent, HitCount, Duration, SelfDuration, Name, Line, Text
