function Trace-ScriptInternal { 
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock] $ScriptBlock,
        [uint32] $Preheat = 0,
        [Switch] $DisableWarning,
        [Hashtable] $Feature,
        [Switch] $Before,
        [Switch] $UseNativePowerShell7Profiler
    )

    $ErrorView = "Normal"
    $ErrorActionPreference = "Stop"

    Assert-PowerShellVersion

    Write-Host -ForegroundColor Magenta "Running in PowerShell $($PSVersionTable.PSVersion)."

    if (0 -ge $Preheat) {
        $Preheat = 0
    }

    if (7 -eq $PSVersionTable.PSVersion.Major -and -not $UseNativePowerShell7Profiler -and 0 -eq $Preheat) { 
        Write-Warning "Using the tracer on PowerShell 7 does not work fully on the first run. You will get only partial results for your first run. Use -Preheat 1 to warm up the environment for the first run. On subsequent runs in the same session you might not need to use it if you did not change much code. You can use -DisableWarning to disable this warning."
    }

    if ($Feature) { 
        Write-Host -ForegroundColor Magenta "Features for $(if (-not $Before) { "After" } else { "Before"}) run:"
        foreach ($p in $Feature.GetEnumerator()) {
            $v = if ($Before) { $false } else { $p.Value }
            Write-Host -ForegroundColor Magenta "    $($p.Key) = $($v)"
            Set-Variable -Scope Global -Name $p.Key -Value $v
        }
    }

    if (0 -lt $Preheat) { 
        foreach ($i in 1..$Preheat) {
            Write-Host -Foreground Magenta  "Warm up $i"

            try {
                if ($UseNativePowerShell7Profiler) {
                    $null = Measure-Script $ScriptBlock
                }
                else {
                    $isPS7 = 7 -eq $PSVersionTable.PSVersion.Major
                    if (1 -eq $i -and $isPS7) {
                        Write-Host -ForegroundColor Magenta "In PowerShell 7 all output is disabled for the first warmup. Just wait..."
                        $externalUiField = $host.UI.GetType().GetField("_externalUI", [System.Reflection.BindingFlags]"Instance, NonPublic")
                        $externalUi = $externalUiField.GetValue($host.UI)
                    }
                    try {
                        # remove the UI to prevent all the debug output to be dumped on the screen
                        # when we are not able to replace tha calls to TraceLine in pwsh7 with harmony
                        # because it is noisy and really slow
                        # might replace with a delegating wrapper to only ignore debug messages later
                        if (1 -eq $i -and $isPS7) {
                            $externalUiField.SetValue($host.UI, $null)
                        }

                        $null = Measure-ScriptHarmony $ScriptBlock
                    } 
                    finally { 
                        if (1 -eq $i -and $isPS7) {
                            # revert
                            $externalUiField.SetValue($host.UI, $externalUi)
                        }
                    }
                }
            }
            catch {
                Write-Host "Warm up failed with $_."
            }
        }
    }

    if (0 -lt $Feature.Count) { 
        foreach ($p in $Feature.GetEnumerator()) {
            $v = if ($Before) { $false } else { $p.Value }
            Set-Variable -Scope Global -Name $p.Key -Value $v
        }
    }

    Write-Host -Foreground Magenta  "Tracing..."
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if ($UseNativePowerShell7Profiler) {
            $trace = Measure-Script $ScriptBlock
        }
        else {
            $trace = Measure-ScriptHarmony $ScriptBlock
        }
        $sw.Stop()
        Write-Host -Foreground Magenta  "Run $i$(if (1 -lt $sides.Count) { " - $side" }) finished after $($sw.Elapsed)"
    }
    catch { 
        $sw.Stop()
        Write-Host "Run $i$(if (1 -lt $sides.Count) { " - $side" }) failed after $($sw.Elapsed) with $_."
    }


    $normalizedTrace = [Collections.Generic.List[object]]::new()
    Write-Host -Foreground Magenta "Tracing done. Got $($trace.Count) trace events."
    if ($UseNativePowerShell7Profiler) {
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
            $r.Duration = $t.Duration
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
    # ensure all output to pipeline is dumped
    $null = & {
        try {
            [Profiler.Tracer]::PatchOrUnpatch($ExecutionContext, $true, $false)
            Set-PSDebug -Trace 1
            & $ScriptBlock
        } 
        finally {
            Set-PSDebug -Trace 0
            [Profiler.Tracer]::PatchOrUnpatch($ExecutionContext, $false, $false)
        }
    }

    [Profiler.Tracer]::Hits
}