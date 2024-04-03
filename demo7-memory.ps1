
cd $PSScriptRoot
get-module profiler | remove-module

import-module .\Profiler\Profiler.psd1

$sb = {  
    function Invoke-GC ($generation) { [gc]::Collect($generation, [System.GCCollectionMode]::Forced)  }
    
    Invoke-GC 0
    Invoke-GC 1
    Invoke-GC 2

    $a = "abc" 

    function f ($Level) { 
        if ($Level -gt 10) { 
            return
        }

        Invoke-GC 0 # rec

        $p = Get-Process # rec

        Start-Sleep -Milliseconds 10
        $Level
        f -Level ($Level + 1)
    }

    f 0; f 0

    $b = [System.Collections.Generic.List[int]]::new(1000)
    
    $d = @()
    foreach ($i in 1..1000) {
        $d += $i
        $b.Add($i)
    }

    $b.Add($i)

    $p = Get-Process
    $p = Get-Process
    $p = Get-Process
    $p = Get-Process
}

$trace = Trace-Script $sb
$trace.Top50SelfMemory