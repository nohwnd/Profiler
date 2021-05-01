$script:totals = [System.Collections.Queue]::new()
function Trace-Script {
    <# 
    .DESCRIPTION
    Invoke the provided script or command and profile its execution.

    .PARAMETER ScriptBlock
    A ScriptBlock to be profiled.

    $trace = Trace-Script -ScriptBlock { Import-Module $PSScriptRoot\Planets.psm1; Get-Planet } -Preheat 1

    When running a script file use the same syntax, you can specify parameters if you need: 
    $trace = Invoke-Script -ScriptBlock { & $PSScriptRoot\MyScript.ps1 } -Preheat 1

    -Preheat 1 is recommended on PowerShell 7 because the profiler does not work fully on the first run.
    See below.

    .PARAMETER Preheat
    Run the provided script or command this many times without tracing it to warm up the session.
    This is good for measuring normal performance excluding startup. Default is 0.

    -Preheat 1 is recommended on PowerShell 7 because the profiler does not work fully on the first run.

    This is unfortunate for testing code that imports modules. Modules import much faster on second run
    when they are still in scope. In such cases, it is recommended to add code at the end of the scriptblock 
    that will remove modules and forces them to import again. But don't remove Profiler. This will still miss
    assembly loading and similar static stuff, but it is better than nothing.

    $trace = Trace-Script -ScriptBlock {
        & $Profile

        Get-Module | Where-Object Name -NE Profiler | Remove-Module
    } -Preheat 1

    This is a current limitation that will be removed if come up with a better hack to hook the profiler.
    Or when the native profiler is released. 

    The current profiler also cannot profile code running in other runspaces.

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
        [string[]] $FilterPath,
        [uint32] $Preheat = 0,
        [Switch] $DisableWarning,
        [Hashtable] $Flag,
        [Switch] $Before,
        [Switch] $After
        # [Switch] $UseNativePowerShell7Profiler
    )

    if ($Before -and $After) { 
        Write-Warning "You should not use -Before and -After together, using -After."
    }

    if ($After) { 
        $Before = $false
    }

    $invokedAs = $MyInvocation.Line

    $trace = Trace-ScriptInternal -ScriptBlock $ScriptBlock -Preheat $Preheat -DisableWarning:$DisableWarning -Flag $Flag -UseNativePowerShell7Profiler:$UseNativePowerShell7Profiler -Before:$Before

    $traceCount = $trace.Count
    Write-Host -ForegroundColor Magenta "Processing $($traceCount) trace events. $(if (1000000 -lt $traceCount) { "This might take a while..."})"
    if ($null -ne $FilterPath -and 0 -lt @($FilterPath).Count) {
        $files = $Path | ForEach-Object { (Resolve-Path $_).Path }
    }
    else {
        $unique = [Collections.Generic.HashSet[string]]::new()
        # skip first event and the last because they come from the measure script
        # they are the lines where we enable and disable tracing. # don't remove them
        # from the trace just yet. We need the timestamp to calculate correct time
        # for the last real event
        $null = foreach ($f in $Trace[1..($Trace.Length - 2)]) { $unique.Add($f.Path) }
        $files = foreach ($v in $unique.GetEnumerator()) { $v }
    }

    Write-Host -ForegroundColor Magenta "Loading sources for $($files.Count) files."

    $fileMap = @{}
    foreach ($file in $files) {
        if ($file -and -not $fileMap.ContainsKey($file)) {
            if (-not (Test-Path $file)) { 
                Write-Host "$file no longer exists, skipping."
                continue
            }
            $name = [IO.Path]::GetFileName($file)
            $lines = Get-Content $file
            # each line in this file will gets its own object
            $lineProfiles = [Collections.Generic.List[object]]::new($lines.Length)
            $index = 0
            foreach ($line in $lines) {
                $lineProfile = [PSCustomObject] @{
                    Percent      = 0
                    HitCount     = 0 
                    Duration     = [TimeSpan]::Zero
                    Average      = [TimeSpan]::Zero
                    SelfDuration = [TimeSpan]::Zero
                    SelfAverage  = [TimeSpan]::Zero

                    Name         = $name
                    Line         = ++$index # start from 1 as in file
                    Text         = $line
                    Path         = $file
                    Hits         = [Collections.Generic.List[object]]::new()
                    CommandHits  = @{}
                }

                $lineProfiles.Add($lineProfile)
            }

            $fileMap.Add($file, $lineProfiles)
        }
        else { 
            # skip the file, because we already processed it, this is an alternative to sorting the list 
            # of files and getting unique, but that would be slower
        }
    }

    Write-Host -ForegroundColor Magenta "Figuring out flow."
    $stack = [System.Collections.Generic.Stack[int]]::new()

    $caller = $null
    foreach ($hit in $trace) {
        # there is next event in the trace, 
        # we can use it to see if we remained in the 
        # function or returned

        if ($hit.Index -lt $traceCount - 2) {
            $nextEvent = $trace[$hit.Index + 1]
            # the next event has higher number on the callstack
            # we are going down into a function, meaning this is a call
            if ($nextEvent.Level -gt $hit.Level) {
                $hit.Flow = [Profiler.CallReturnProcess]::Call
                # save where we entered 
                $stack.Push($hit.Index)
                $hit.CallerIndex = $caller
                $caller = $hit.Index
            }
            elseif ($nextEvent.Level -lt $hit.Level) {
                $hit.Flow = [Profiler.CallReturnProcess]::Return
                # we go up, back from a function and we might jump up
                # for example when throw happens and we end up in try catch
                # that is x levels up
                # get all the calls that happened up until this level
                # and diff them against this to set their durations
                while ($stack.Count -ge $hit.Level) {
                    $callIndex = $stack.Pop()
                    $call = $trace[$callIndex]
                    # events are timestamped at the start, so start of when we called until 
                    # the next one after we returned is the duration of the whole call
                    $call.Duration = [TimeSpan]::FromTicks($nextEvent.Timestamp - $call.Timestamp)
                    # save into the call where it returned so we can see the events in the
                    # meantime and see what was actually slow
                    $call.ReturnIndex = $hit.Index
                    # those are structs and we can't grab it by ref from the list
                    # so we just overwrite
                    $trace[$callIndex] = $call
                }

                # return from a function is not calling anything 
                # so the duration and self duration are the same
                $hit.Duration = $hit.SelfDuration
                $hit.ReturnIndex = $hit.Index
                # who called us
                $hit.CallerIndex = $caller
            }
            else { 
                # we stay in the function in the next step, so we did 
                # not call anyone or did not return, we are just processing
                # the duration is the selfduration
                $hit.Flow = [Profiler.CallReturnProcess]::Process
                $hit.Duration = $hit.SelfDuration
                $hit.ReturnIndex = $hit.Index

                # who called us
                $hit.CallerIndex = $caller
            }

            # those are structs and we can't grab it by ref from the list
            # so we just overwrite
            $trace[$hit.Index] = $hit
        }
    }

    Write-Host -ForegroundColor Magenta "Sorting trace events to file lines."
    foreach ($hit in $trace) {
        if (-not $hit.Path -or -not ($fileMap.Contains($hit.Path))) {
            continue
        }

        # get the object that describes this particular file
        $lineProfiles = $fileMap[$hit.Path]

        $lineProfile = $lineProfiles[$hit.Line - 1] # array indexes from 0, but lines from 1
        $lineProfile.SelfDuration += $hit.SelfDuration
        # $lineProfile.Duration += $hit.Duration
        $lineProfile.HitCount++
        $lineProfile.Hits.Add($hit)

        # add distinct entries per column when there are more commands
        # on the same line so we can see which commands contributed to the line duration
        # if we need to count duration we can do it by moving this to the next part of the code
        # where we process each hit on the line
        if ($lineProfile.CommandHits.ContainsKey($hit.Column)) { 
            $commandHit = $lineProfile.CommandHits[$hit.Column] 
            $commandHit.SelfDuration += $hit.SelfDuration
            # do not track duration for now, we are not listing each call to the command
            # so we cannot add the durations correctly, because we need to exclude recursive calls
            # it is also not very useful I think, might reconsider later
            # $commandHit.Duration += $hit.Duration
            $commandHit.HitCount++
        }
        else { 
            $commandHit = [PSCustomObject] @{
                Line         = $hit.Line # start from 1 as in file
                Column       = $hit.Column
                SelfDuration = $hit.SelfDuration
                # Duration     = 0
                HitCount     = 1
                Text         = $hit.Text
            }
            $lineProfile.CommandHits.Add($hit.Column, $commandHit)
        }
    }

    Write-Host -ForegroundColor Magenta "Figuring out durations per line."
    foreach ($k in $fileMap.Keys) { 
        $file = $fileMap[$k]
        foreach ($line in $file) {
            # we can have calls that call into the same line
            # simply adding durations together gives us times
            # that can be way more than the execution time of the 
            # whole script because the line is accounted for multiple
            # times. This is best visible when calling recursive function
            # each subsequent call would add up to the previous ones
            # https://twitter.com/nohwnd/status/1388418452130603008?s=20
            # so we need to check if we are not in the current function
            # by keeping the highest return index and only adding the time
            # when we have index that is higher than it, meaning we are 
            # now running after we returned from the function
            $returnIndex = 0
            $duration = [timespan]::Zero
            foreach ($hit in $line.Hits) {
                if ($hit.Index -gt $returnIndex) { 
                    $duration += $hit.Duration
                    $returnIndex = $hit.ReturnIndex
                }
            }
            $line.Duration = $duration
        }
    }

    # trace starts with event from the measurement script where we enable tracing and ends with event where we disable it
    # events are timestamped at the start so user code duration is from the second event (index 1), till the last event (index -1) where we disable tracing
    $total = if ($null -ne $trace -and 0 -lt @($trace).Count) { [TimeSpan]::FromTicks($trace[-1].Timestamp - $trace[1].Timestamp) } else { [TimeSpan]::Zero }

    Write-Host -ForegroundColor Magenta "Counting averages and percentages."
    # this is like SelectMany, it joins the arrays of arrays
    # into a single array
    $all = $fileMap.Values | Foreach-Object { $_ } | ForEach-Object {
        $_.SelfAverage = if ($_.HitCount -eq 0) { [TimeSpan]::Zero } else { [TimeSpan]::FromTicks($_.SelfDuration.Ticks / $_.HitCount) }
        $_.Average = if ($_.HitCount -eq 0) { [TimeSpan]::Zero } else { [TimeSpan]::FromTicks($_.Duration.Ticks / $_.HitCount) }
        $_.Percent = [Math]::Round($_.Duration.Ticks / $total.Ticks, 5, [System.MidpointRounding]::AwayFromZero) * 100
        $_
    }

    Write-Host -ForegroundColor Magenta "Getting Top50 that take most percent of the run."

    $top50Percent = $all | 
    Where-Object Percent -gt 0 | 
    Sort-Object -Property Percent -Descending | 
    Select-Object -First 50

    Write-Host -ForegroundColor Magenta "Getting Top50 with the longest average Duration."

    $top50Average = $all | 
    Where-Object Average -gt 0 | 
    Sort-Object -Property Average -Descending | 
    Select-Object -First 50
        
    Write-Host -ForegroundColor Magenta "Getting Top50 with the longest Duration."

    $top50Duration = $all |
    Where-Object Duration -gt 0 | 
    Sort-Object -Property Duration -Descending | 
    Select-Object -First 50

    Write-Host -ForegroundColor Magenta "Getting Top50 with the longest average SelfDuration."

    $top50SelfAverage = $all | 
    Where-Object SelfAverage -gt 0 | 
    Sort-Object -Property SelfAverage -Descending | 
    Select-Object -First 50
        
    Write-Host -ForegroundColor Magenta "Getting Top50 with the longest SelfDuration."

    $top50SelfDuration = $all |
    Where-Object SelfDuration -gt 0 | 
    Sort-Object -Property SelfDuration -Descending | 
    Select-Object -First 50
    
    Write-Host -ForegroundColor Magenta "Getting Top50 with the most hits."

    $top50HitCount = $all | 
    Where-Object HitCount -gt 0 |
    Sort-Object -Property HitCount -Descending | 
    Select-Object -First 50

    $script:processedTrace = [PSCustomObject] @{ 
        Top50             = $top50Percent
        Top50Average      = $top50Average
        Top50Duration     = $top50Duration
        Top50HitCount     = $top50HitCount
        Top50SelfDuration = $top50SelfDuration
        Top50SelfAverage  = $top50SelfAverage
        TotalDuration     = $total
        AllLines          = $allLines
        Events            = $trace
        Files             = foreach ($pair in $fileMap.GetEnumerator()) {
            [PSCustomObject]@{
                Path    = $pair.Key
                Profile = $pair.Value
            }
        }
    }

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
    
    Write-Host -ForegroundColor Magenta "Done. Try $(if ($variable) { "$($variable)" } else { '$yourVariable' }).Top50 | Format-Table to get the report. There are also Top50Duration, Top50Average, Top50SelfDuration, Top50SelfAverage, Top50HitCount, All, Events and Files."
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
        $text = $e.Extent.Text.Trim()
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
        [Profiler.ProfileEventRecord] $hit
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