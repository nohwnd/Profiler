# Doing CC


Get-Module Profiler, Pester | Remove-Module 

Import-Module $PSScriptRoot/Profiler/Profiler.psd1

$ScriptBlock = {  
    if ($true) { 
        "yes"
    }
    else { 
        "no"
    }

}

$lines = [Collections.Generic.List[Profiler.CodeCoveragePoint]]@(
    [Profiler.CodeCoveragePoint]::new($PSCommandPath, 10, 9, "yes")
    [Profiler.CodeCoveragePoint]::new($PSCommandPath, 13, 9, "no")
)

$tracer = [Profiler.CodeCoverageTracer]::new($lines)
try {
    [Profiler.Tracer]::Patch($PSVersionTable.PSVersion.Major, $ExecutionContext, $host.UI, $tracer)
    Set-PSDebug -Trace 1
    & $ScriptBlock
} 
finally {
    Set-PSDebug -Trace 0
    [Profiler.Tracer]::Unpatch()
}

$tracer.Hits | Format-List


