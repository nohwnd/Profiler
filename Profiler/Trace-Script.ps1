$script:totals = [System.Collections.Queue]::new()

function Write-TimeAndRestart ($sw) { 
    $t = $sw.Elapsed

    if ([timespan]::FromSeconds(1) -gt $t) { 
        Write-Host -ForegroundColor DarkGray " ($([int]$t.TotalMilliseconds)ms)"
    }
    else { 
        Write-Host -ForegroundColor DarkGray " ($([math]::Round($t.TotalSeconds, 2))s)"
    }

    $sw.Restart()
}

function Trace-Script {
    <#
    .DESCRIPTION
    Invoke the provided script or command and profile its execution.

    .PARAMETER ScriptBlock
    A ScriptBlock to be profiled.

    $trace = Trace-Script -ScriptBlock { Import-Module $PSScriptRoot\Planets.psm1; Get-Planet }

    When running a script file use the same syntax, you can specify parameters if you need:
    $trace = Invoke-Script -ScriptBlock { & $PSScriptRoot\MyScript.ps1 }

    .PARAMETER Preheat
    Run the provided script or command this many times without tracing it to warm up the session.
    This is good for measuring normal performance excluding startup. Default is 0.

    .PARAMETER DisableWarning
    Disable warning about Preheat on PowerShell 7.

    .PARAMETER Flag
    A hash table of feature flags to be set to profile code before or after changes. The default is After
    changes. You can toggle the behavior using -Before and also -After (which is the same as using neither).

    For this to work your code needs to cooperate:

    Each key from the hashtable will be defined as a $global: variable. Use that variable in `if` to wrap
    the new code to test it against the old code.

    Use $true, $false as the values. The hashtable represents the after side. Each key will be
    defined with the value for after side. Each key will be defined with $false for the before side.

    In this case example is worth 1000 words:

    Trace-Script -ScriptBlock { & MyScript.ps1 } -Flag @{ _profiler = $true }

    Original code in MyScript.ps1 you are trying to improve:
    $values = 1..1000
    foreach ($v in $Values) {
        $newValues += $v + 10
    }

    Modified code with changes that you think are faster wrapped in if using the feature flags:
    if ($_profiler) {
        $values =  [System.Linq.Enumerable]::Range(1,1000)
    }
    else {
        $values = 1..1000
    }

    if ($_profiler) {
        # after side
        $newValues = foreach ($v in $Values) { $v + 10 }
    }
    else {
        # before side
        foreach ($v in $Values) {
            $newValues += $v + 10
        }
    }

    A single feature flag might be good enough for many purposes, but imagine there are multiple improvements
    that migh contradict each other, in that case you are better of adding different flag for each one:

    Trace-Script -ScriptBlock { & MyScript.ps1 } -Flag @{ _iteration = $true; _enumerable = $true }

    if ($_enumerable) {
        $values =  [System.Linq.Enumerable]::Range(1,1000)
    }
    else {
        $values = 1..1000
    }

    if ($_iteration) {
        # B side
        $newValues = foreach ($v in $Values) { $v + 10 }
    }
    else {
        # A side
        foreach ($v in $Values) {
            $newValues += $v + 10
        }
    }

    Using two or more feature flags you can test them together as shown above, or one without the other:

    Trace-Script -ScriptBlock { & MyScript.ps1 } -Flag @{ _iteration = $true; _enumerable = $false }

    .PARAMETER Before
    When using -Flag. Force all flags to be set as $false to run the code before changes.

    .PARAMETER After
    When using -Flag. Force all flags to be set to the values provided in the -Flag hashtable.
    When both -Before and -After are enabled, -After is used.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock] $ScriptBlock,
        # [string[]] $FilterPath,
        [uint32] $Preheat = 0,
        [Switch] $DisableWarning,
        [Hashtable] $Flag,
        [Switch] $Before,
        [Switch] $After,
        [string] $ExportPath
        # [Switch] $UseNativePowerShell7Profiler
    )

    if ($Before -and $After) {
        Write-Warning "You should not use -Before and -After together, using -After."
    }

    if ($After) {
        $Before = $false
    }

    $invokedAs = $MyInvocation.Line

    $out = @{ Stopwatch = [TimeSpan]::Zero; ScriptBlocks = $null }
    $trace = Trace-ScriptInternal -ScriptBlock $ScriptBlock -Preheat $Preheat -DisableWarning:$DisableWarning -Flag $Flag -UseNativePowerShell7Profiler:$UseNativePowerShell7Profiler -Before:$Before -Out $out

    $scriptBlocks = $out.ScriptBlocks
    $traceCount = $trace.Count

    Write-Host -ForegroundColor Magenta "Processing $($traceCount) trace events. $(if (1000000 -lt $traceCount) { "This might take a while..."})"

    Write-Host -ForegroundColor Magenta "Figuring out flow." -NoNewline
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $trace = [Profiler.Profiler]::ProcessFlow($trace)
    Write-TimeAndRestart $sw

    Write-Host -ForegroundColor Magenta "Grouping and folding." -NoNewline
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $trace = [Profiler.Profiler]::ProcessGroupAndFold($trace)
    Write-TimeAndRestart $sw

    Write-Host -ForegroundColor Magenta "Sorting events into lines." -NoNewline
    $fileMap = [Profiler.Profiler]::ProcessLines($trace, $scriptBlocks, $false)
    Write-TimeAndRestart $sw

    # trace starts with event from the measurement script where we enable tracing and ends with event where we disable it
    # events are timestamped at the start so user code duration is from the second event (index 1), till the last real event (index -2) where we disable tracing
    $total = if ($null -ne $trace -and 0 -lt @($trace).Count) { [TimeSpan]::FromTicks($trace[-2].Timestamp - $trace[2].Timestamp) } else { [TimeSpan]::Zero }

    Write-Host -ForegroundColor Magenta "Counting averages and percentages." -NoNewline
    # this is like SelectMany, it lists all the lines in all files into a single array
    $all = foreach ($line in $fileMap.Values.Lines.Values) {
        $ticks = if (0 -ne $total.Ticks) { $total.Ticks } else { 1 }
        $line.Percent = [Math]::Round($line.Duration.Ticks / $ticks, 5, [System.MidpointRounding]::AwayFromZero) * 100
        $line.SelfPercent = [Math]::Round($line.SelfDuration.Ticks / $ticks, 5, [System.MidpointRounding]::AwayFromZero) * 100
        $line
    }
    Write-TimeAndRestart $sw

    Write-Host -ForegroundColor Magenta "Getting Top50 with the longest Duration." -NoNewline
    $top50Duration = $all |
    Where-Object Duration -gt 0 |
    Sort-Object -Property Duration -Descending |
    Select-Object -First 50
    Write-TimeAndRestart $sw

    Write-Host -ForegroundColor Magenta "Getting Top50 with the longest SelfDuration." -NoNewline
    $top50SelfDuration = $all |
    Where-Object SelfDuration -gt 0 |
    Sort-Object -Property SelfDuration -Descending |
    Select-Object -First 50
    Write-TimeAndRestart $sw

    Write-Host -ForegroundColor Magenta "Getting Top50 with the most hits." -NoNewline
    $top50HitCount = $all |
    Where-Object HitCount -gt 0 |
    Sort-Object -Property HitCount -Descending |
    Select-Object -First 50
    Write-TimeAndRestart $sw

    # do not use object initializer syntax here @{}
    # when it fails it will not create any object
    # and won't tell you on which line exactly it failed
    #
    # order properties based on what is least likely to
    # fail on casting
    #
    # this way we can get the partial object out for 
    # debugging when this fails on someones system
    $script:processedTrace = [Profiler.Trace]::new()
    $script:processedTrace.TotalDuration = $total
    $script:processedTrace.StopwatchDuration = $out.Stopwatch
    $script:processedTrace.Events = $trace
    $script:processedTrace.AllLines = $all
    $script:processedTrace.Top50Duration = $top50Duration
    $script:processedTrace.Top50HitCount = $top50HitCount
    $script:processedTrace.Top50SelfDuration = $top50SelfDuration

    $script:processedTrace

    $variable = if ($invokedAs -match "(\$\S*)\s*=\s*Trace-Script") {
        "$($matches[1])"
    }

    if ($null -eq $variable) {
        Write-Host -ForegroundColor Yellow "Looks like you did not assign the output to a variable. Use Get-LatestTrace to retrieve the trace, e.g.: `$trace = Get-LatestTrace"
    }


    $previous = if (0 -lt $totals.Count) {
        $totals.ToArray()[-1]
    }

    $diff = if ($null -eq $previous) {
        0
    }
    else {
        [int] ($total.TotalMilliseconds - $previous.Total.TotalMilliseconds)
    }

    $color = if (0 -eq $diff) {
        "Yellow"
    }
    elseif (0 -gt $diff) {
        "Green"
    }
    else {
        "Red"
    }

    $totals.Enqueue(@{ Color = $color; Diff = $diff ; Total = $total; Before = $Before } )
    while ($totals.Count -gt 5) { $null = $totals.Dequeue() }
    if (1 -lt $totals.Count) {
        Write-Host -ForegroundColor Magenta "Progress: " -NoNewline

        $i = 0
        foreach ($t in $totals) {
            $last = $i -eq ($totals.Count - 1)

            Write-Host -ForegroundColor $t.Color "$(if ($t.Before) { "B:" } else {"A:" }) $($t.Total) ($($t.Diff) ms)$(if (-not $last) {" -> "} else { "`n" })" -NoNewline
            $i++
        }
    }
    else {
        Write-Host -ForegroundColor Magenta "Duration: $(if ($Before) { "B:" } else {"A:" }) " -NoNewline
        Write-Host -ForegroundColor Yellow $total
    }

    if ($ExportPath) {
        Export-SpeedScope -Trace $script:processedTrace -Path $ExportPath
    }

    Write-Host -ForegroundColor Magenta "Done. Try $(if ($variable) { "$($variable)" } else { '$yourVariable' }).Top50Duration | Format-Table to get the report. There are also Top50Average, Top50SelfDuration, Top50SelfAverage, Top50HitCount, AllLines and Events."
}

function Get-LatestTrace {
    if ($script:processedTrace) {
        $script:processedTrace
    }
    else {
        Write-Warning "There is no trace yet. Run Trace-Script. For example Trace-Script -ScriptBlock { & yourfile.ps1 }."
    }
}


function Show-ScriptExecution {
    # .DESCRIPTION Show how the script executed with margin to show how deep the call was, this is just for fun.
    # You can slow down the excution x times to reflect the mimic the real execution delays.
    [CmdletBinding()]
    param(
        $Trace,
        [switch] $x1,
        [switch] $x10,
        [switch] $x100,
        [switch] $x1000 # ,
        # [switch] $Color
    )

    $trace = if ($Trace) { $Trace } else { Get-LatestTrace }

    $x = if ($x1000) {
        1000
    }
    elseif ($x100) {
        100
    }
    elseif ($x10) {
        10
    }
    elseif ($x1) {
        1
    }
    else {
        0
    }

    $c = [bool] $Color
    if ($c) {
        # https://www.reddit.com/r/PowerShell/comments/b06gtw/til_that_powershell_can_do_colors/
        # ANSI escape character
        $r = 0
        $g = 0
        $b = 0
        $ansi_escape = [char]27
    }

    foreach ($e in $trace.Events) {
        $text = $e.Extent.Text.ToString().Trim()
        $o = "$ansi_escape[48;2;$r;$g;${b}m$text$ansi_escape[0m"
        $margin = ' ' * ($e.Level)
        Write-Host "$margin$o"
        if (0 -lt $x) {
            # this is fun, but hardly accurate, as the resolution is <15ms
            # and many lines take <0.001ms
            [System.Threading.Thread]::Sleep($e.SelfDuration * $x)
        }


        if ($c) {

            $r++

            if (254 -eq $r) {
                $r = 0
                $g++

                if (254 -eq $g) {
                    $g = 0
                    $b++

                    if (254 -eq $b) {
                        $r = 0
                        $g = 0
                        $b = 0
                    }
                }
            }

            "$r $g $b"
        }
    }
}

# don't publish just yet till I get some time using this
function Get-CallStack {

    param (
        [Parameter(Mandatory)]
        [Profiler.Hit] $hit
    )

    $trace = (Get-LatestTrace).Events

    $hit

    if (0 -ne $hit.CallerIndex) {
        do {
            $hit = $trace[$hit.CallerIndex]
            $hit
        } while (1 -lt $hit.CallerIndex)
    }
}