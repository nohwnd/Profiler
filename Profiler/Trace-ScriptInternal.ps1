function Trace-ScriptInternal { 
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock] $ScriptBlock,
        [uint32] $Preheat = 0,
        [Switch] $DisableWarning,
        [Hashtable] $Flag,
        [Switch] $Before,
        [Switch] $UseNativePowerShell7Profiler,
        # Putting the collection into object will make it modified when returned for some reason
        # outputting time through this
        $Out
    )

    $ErrorView = "Normal"
    $ErrorActionPreference = "Stop"

    Assert-PowerShellVersion

    Write-Host -ForegroundColor Magenta "Running in PowerShell $($PSVersionTable.PSVersion)."

    if (0 -ge $Preheat) {
        $Preheat = 0
    }

    if ($Flag) { 
        Write-Host -ForegroundColor Magenta "Flags for $(if (-not $Before) { "After" } else { "Before"}) run:"
        foreach ($p in $Flag.GetEnumerator()) {
            $v = if ($Before) { $false } else { $p.Value }
            Write-Host -ForegroundColor Magenta "    $($p.Key) = $($v)"
            Set-Variable -Scope Global -Name $p.Key -Value $v
        }
    }

    if (0 -lt $Preheat) { 
        foreach ($i in 1..$Preheat) {
            Write-Host -Foreground Magenta  "Warm up $i"

            if ($UseNativePowerShell7Profiler) {
                $null = Measure-Script $ScriptBlock
            }
            else {
                $result = Measure-ScriptHarmony $ScriptBlock
                if ($null -ne $result.Error) { 
                    Write-Host -ForegroundColor Red "Warm up failed with $($result.Error)."
                }
            }
            
        }
    }

    if (0 -lt $Flag.Count) { 
        foreach ($p in $Flag.GetEnumerator()) {
            $v = if ($Before) { $false } else { $p.Value }
            Set-Variable -Scope Global -Name $p.Key -Value $v
        }
    }

    Write-Host -Foreground Magenta  "Tracing..."

    if ($UseNativePowerShell7Profiler) {
        $result = Measure-Script $ScriptBlock
    }
    else {
        $result = Measure-ScriptHarmony $ScriptBlock
    }
    if ($null -eq $result.Error) {
        Write-Host -Foreground Magenta  "Run$(if (1 -lt $sides.Count) { " - $side" }) finished after $($result.Stopwatch)"
    }
    else {
        Write-Host -ForegroundColor Red "Run$(if (1 -lt $sides.Count) { " - $side" }) failed after $($result.Stopwatch) with the following error:`n$($result.Error)."
    }

    $out.Stopwatch = $result.Stopwatch
    $trace = $result.Trace
    Write-Host -Foreground Magenta "Tracing done. Got $($trace.Count) trace events."
    if ($UseNativePowerShell7Profiler) {
        $normalizedTrace = [Collections.Generic.List[Profiler.ProfileEventRecord]]::new($trace.Count)
        Write-Host "Used native tracer from PowerShell 7. Normalizing trace."
        foreach ($t in $trace) { 
            $r = [Profiler.ProfileEventRecord]::new()
            $e = [Profiler.ScriptExtentEventData]::new()
            $e.File = $t.Extent.File
            $e.StartLineNumber = $t.Extent.StartLineNumber
            $e.StartColumnNumber = $t.Extent.StartColumnNumber
            $e.EndLineNumber = $t.Extent.EndLineNumber
            $e.EndColumnNumber = $t.Extent.EndColumnNumber
            $e.StartOffset = $t.Extent.StartOffset
            $e.EndOffset = $t.Extent.EndOffset
            $r.Extent = $e
            $r.StartTime = $t.StartTime
            $r.SelfDuration = $t.SelfDuration
            $r.Index = $index

            $index++

            $normalizedTrace.Add($r)
        }
        
        $trace = $null
        $normalizedTrace
    }
    else { 
       $trace
    }
}

function Measure-ScriptHarmony ($ScriptBlock) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        # ensure all output to pipeline is dumped
        $null = & {
            try {
                [Profiler.Tracer]::Patch($PSVersionTable.PSVersion.Major, $ExecutionContext, $host.UI)
                Set-PSDebug -Trace 1
                & $ScriptBlock
            } 
            finally {
                Set-PSDebug -Trace 0
                [Profiler.Tracer]::Unpatch()
            }
        }
    }
    catch {
        $err = $_
    }
    $sw.Stop()

    $result = @{
        Trace = [Profiler.Tracer]::Hits
        Error = $err
        Stopwatch = $sw.Elapsed
    }

    if ($null -eq $result.Trace -or 0 -eq @($result.Trace).Count) { 
        throw "Trace is null or empty."
    }

    $lastLine = $result.Trace[-1]

    $disableCommand = "[Profiler.Tracer]::Unpatch()"
    if ($PSCommandPath -ne $lastLine.Path -or $disableCommand -ne $lastLine.Text) { 
        Write-Warning "Event list is incomplete, it should end with '$disableCommand' from within Profiler module, but instead ends with entry '$($lastLine.Text)', from '$($lastLine.Path)'. Are you disabling trace mode in your code using Set-PSDebug -Trace 0 or using Remove-PSBreakpoint?"
    }

    $result
}