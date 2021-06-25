$trace = Trace-Script {
    Start-Sleep -Seconds 1
}

$trace.Events[2..4] | Format-Table Index, Text, Timestamp, @{ n = "Time"; e = { 
    $ticks = $trace.Events[$_.Index+1].Timestamp - $_.TimeStamp  
    "$([int][TimeSpan]::FromTicks($ticks).TotalMilliseconds) ms"
} }

