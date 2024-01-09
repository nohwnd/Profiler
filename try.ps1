
cd $PSScriptRoot
get-module profiler | remove-module

.\build.ps1
import-module .\Profiler\Profiler.psd1
$l = Trace-Script { 
    function a {  
        1..10 | % { 
            $ps = get-service

            if ($_ -eq 4) { 
                [gc]::Collect($true)
            }
        } 
    }
    a
}

$l.AllLines | select gc, mem, selfgc, selfmem, text | ft

#  $l.Events | select index, @{ n="txt"; e = { ($_.text[0..20] -join "" ) }}, heapsize, workingset, selfheapsize, selfworkingset, AllocatedBytes, SelfAllocatedBytes, gc0, gc1, gc2, selfgc0, selfgc1, selfgc2 | ft