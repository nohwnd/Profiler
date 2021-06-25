$sb = {
    if (-not $profiler_Array) {
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

Invoke-Script -ScriptBlock $sb -Flag @{ profiler_array = $true } -Repeat 3