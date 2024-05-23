function Trace-ScriptInternal { 
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock] $ScriptBlock,
        [uint32] $Preheat = 0,
        [Switch] $DisableWarning,
        [Hashtable] $Flag,
        [Switch] $Before,
        # Putting the collection into object will make it modified when returned for some reason
        # outputting time through this
        $Out
    )

    $ErrorView = "Normal"
    $ErrorActionPreference = "Stop"

    Assert-PowerShellVersion

    Write-Host -ForegroundColor Magenta "Running in PowerShell $($PSVersionTable.PSVersion) $([System.IntPtr]::Size*8)-bit."

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

            $result = Measure-ScriptHarmony $ScriptBlock
            if ($null -ne $result.Error) { 
                Write-Host -ForegroundColor Red "Warm up failed with $($result.Error)."
            }            
        }
    }

    if (0 -lt $Flag.Count) { 
        foreach ($p in $Flag.GetEnumerator()) {
            $v = if ($Before) { $false } else { $p.Value }
            Set-Variable -Scope Global -Name $p.Key -Value $v
        }
    }

    Write-Host -Foreground Magenta  "Starting trace."
    Write-Host -Foreground Magenta  "Stopwatch $(if([Diagnostics.Stopwatch]::IsHighResolution) { "is" } else { "is not" }) high resolution, max resolution of timestamps is $([int] (1e9/[Diagnostics.Stopwatch]::Frequency))ns."

    $result = Measure-ScriptHarmony $ScriptBlock

    if ($null -eq $result.Error) {
        Write-Host -Foreground Magenta  "Run$(if (1 -lt $sides.Count) { " - $side" }) finished after $($result.Stopwatch)."
    }
    else {
        Write-Host -ForegroundColor Red "Run$(if (1 -lt $sides.Count) { " - $side" }) failed after $($result.Stopwatch) with the following error:`n$($result.Error)."
    }

    $out.Stopwatch = $result.Stopwatch
    $out.ScriptBlocks = $result.ScriptBlocks
    Write-Host -Foreground Magenta "Tracing done. Got $($trace.Count) trace events."
    $result
}

function Measure-ScriptHarmony ($ScriptBlock) {
    
    $tracer = [Profiler.ProfilerTracer]::new()

    if (-not [Profiler.Tracer]::IsEnabled) {
        # use this as a marker of position, scriptblocks are aware of the current line, so we can use it to 
        # make this code not rely on exact line numbers
        $here = {}
        # add a dummy breakpoint and disable it, otherwise when someone calls Remove-PSBreakpoint and there are 
        # no breakpoints left the debugger will disable itself. This could also be solved by adding global function
        # that is generated as a proxy for Remove-PSBreakpoint and re-enables Set-PSDebug -Trace 1. That would 
        # be more resilient to users who can remove all breakpoints including ours. But we would have to generate it
        # and modify the code, and it would look weird in their code output. On the other hand we would not show up extra 
        # breakpoint in VSCode (or other editor)
        $bp = Set-PSBreakpoint -Script $PSCommandPath -Line $here.StartPosition.StartLine -Action {}
        $null = $bp | Disable-PSBreakpoint
    }

    $sw = [System.Diagnostics.Stopwatch]::new()
    try {
        try {
            if (-not [Profiler.Tracer]::IsEnabled) {
                $null = [Profiler.Tracer]::Patch($PSVersionTable.PSVersion.Major, $ExecutionContext, $host.UI, $tracer)
            }
            else { 
                # just add second tracer to the existing setup
                $null = [Profiler.Tracer]::Register($tracer)
            }

            $sw.Start();
            $null = Set-PSDebug -Trace 1
            $null = & $ScriptBlock
        }
        finally { 
            # disable tracing in any case because we don't want too many internal 
            # details to leak into the log, otherwise any change in this code will 
            # reflect into the log and we need to change counts in Profiler
            $corruptionAutodetectionVariable = Set-PSDebug -Trace 0
            $sw.Stop()
            if ([Profiler.Tracer]::HasTracer2) {
                $null = [Profiler.Tracer]::Unregister()
                # re-enable tracing because tracer 1 still needs to continue tracing
                $null = Set-PSDebug -Trace 1
            }
            else { 
                $null = [Profiler.Tracer]::Unpatch()

                if ($bp) { 
                    $null = $bp | Remove-PSBreakPoint
                }
            }
        }
    } 
    catch {
        $err = $_
    }



    $result = @{
        Trace        = $tracer.Hits
        ScriptBlocks = $tracer.ScriptBlocks
        Error        = $err
        Stopwatch    = $sw.Elapsed
    }

    if ($null -eq $result.Trace -or 0 -eq @($result.Trace).Count) { 
        throw "Trace is null or empty. $(if ($null -ne $err) { "There was an error: $err."})"
    }

    $firstLine = $result.Trace[0]
    $enableCommand = '$null = [Profiler.Tracer]::Patch($PSVersionTable.PSVersion.Major, $ExecutionContext, $host.UI, $tracer)'
    $registerCommand = '$null = [Profiler.Tracer]::Register($tracer)'
    if (-not ($PSCommandPath -eq $firstLine.Path -and ($enableCommand -eq $firstLine.Text -or $registerCommand -eq $firstLine.Text))) { 
        Write-Warning "Event list is incomplete, it should start with '$enableCommand' or '$registerCommand' from within Profiler module, but instead starts with entry '$($firstLine.Text)', from '$($firstLine.Path)'. Are you running profiler in the code you are profiling?"
    }

    $result
}