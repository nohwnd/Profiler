
cd $PSScriptRoot
get-module profiler | remove-module

# .\build.ps1
import-module .\Profiler\Profiler.psd1

$sb = {  
    function Invoke-GC ($generation) { [gc]::Collect($generation, [System.GCCollectionMode]::Forced)  }
    
    Invoke-GC 0
    Invoke-GC 1
    Invoke-GC 2

    $a = "abc" 

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
$trace.AllLines | ft *mem*,*gc*, text

# $trace.Events | select index, @{ n="txt"; e = { ($_.text[0..20] -join "" ) }}, heapsize, workingset, selfheapsize, selfworkingset, AllocatedBytes, SelfAllocatedBytes, gc0, gc1, gc2, selfgc0, selfgc1, selfgc2 | ft