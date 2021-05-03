$recursiveScriptBlock = {
    function f ($Level) { 
        if ($Level -gt 10) { 
            return
        }

        Start-Sleep -Milliseconds 10
        $Level
        f -Level ($Level + 1)
    }

    f 0; f 0
}


Import-Module $PSScriptRoot/Profiler/Profiler.psm1 -Force

$trace = Trace-Script $recursiveScriptBlock

$trace.Top50Duration | Format-Table