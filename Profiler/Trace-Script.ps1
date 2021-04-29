$script:totals = [System.Collections.Queue]::new()
function Trace-Script {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock] $ScriptBlock,
        [string[]] $FilterPath,
        [uint32] $Preheat = 0,
        [Switch] $DisableWarning,
        [Hashtable] $Feature,
        [Switch] $Before,
        [Switch] $After,
        [Switch] $UseNativePowerShell7Profiler
    )

    if ($Before -and $After) { 
        Write-Warning "You cannot use -Before and -After together, using -After."
    }

    if ($After) { 
        $Before = $false
    }

    $invokedAs = $MyInvocation.Line

    $trace = Trace-ScriptInternal -ScriptBlock $ScriptBlock -Preheat $Preheat -DisableWarning:$DisableWarning -Feature $Feature -UseNativePowerShell7Profiler:$UseNativePowerShell7Profiler -Before:$Before

    $traceCount = $trace.Count
    Write-Host -ForegroundColor Magenta "Processing $($traceCount) trace events. $(if (1000000 -lt $traceCount) { " This might take a while..."})"
    if ($null -ne $FilterPath -and 0 -lt @($FilterPath).Count) {
        $files = $Path | ForEach-Object { (Resolve-Path $_).Path }
    }
    else {
        $unique = [Collections.Generic.HashSet[string]]::new()
        $null = foreach ($f in $Trace) { $unique.Add($f.Path) }
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
                    Percent     = 0
                    HitCount    = 0 
                    Duration    = [TimeSpan]::Zero
                    Average     = [TimeSpan]::Zero
                    CallDuration =  [TimeSpan]::Zero
                    AverageCall =  [TimeSpan]::Zero

                    Name        = $name
                    Line        = ++$index # start from 1 as in file
                    Text        = $line
                    Path        = $file
                    Hits        = [Collections.Generic.List[object]]::new()
                    CommandHits = @{}
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

    Write-Host -ForegroundColor Magenta "Calculating duration per line."
    $stack = [System.Collections.Generic.Stack[int]]::new()
    foreach ($hit in $trace) {
        # there is next item in the trace
        if ($hit.Index -lt $traceCount - 2) { 
            $nextHit = $trace[$hit.Index+1]            
            if ($nextHit.Level -gt $hit.Level) {
                $hit.Flow = 1 # call
                # we go down, save where we diverged
                $stack.Push($hit.Index)
                # Write-Host -nonewline "call $l -> $($hit.Extent.Text)"
            }
            elseif ($nextHit.Level -lt $hit.Level) {
                # return
                $hit.Flow = 2
                # we go up, and we might jump up
                # get all the calls down and diff them against
                # this
                while ($stack.Count -ge $hit.Level) {
                    $callIndex = $stack.Pop()
                    $call = $trace[$callIndex]
                    # own duration + duration of all called
                    $call.CallDuration = [TimeSpan]::FromTicks($hit.Duration.Ticks + ($hit.Timestamp - $call.Timestamp))
                    # save where we returned from this function so we can query the log and see what is slow
                    $call.ReturnIndex = $hit.Index
                    # those are structs and we can't grab it by ref from the list
                    # so we just overwrite
                    $trace[$callIndex] = $call
                    # Write-Host "    call to $($trace[$callIndex].Extent.Text) took $($trace[$callIndex].CallDuration)" 
                }
                # Write-Host "return $l -> $($hit.Extent.Text)"
            }
            else { 
                $hit.Flow = 1
                $hit.CallDuration = $hit.Duration
                # Write-Host "process $l -> $($hit.Extent.Text)"
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
        $lineProfile.Duration += $hit.Duration
        $lineProfile.CallDuration += $hit.CallDuration
        $lineProfile.HitCount++
        $lineProfile.Hits.Add($hit)

        # add distinct entries per column when there are more commands
        # on the same line (like we did it with the Group-Object on foreach ($i in 1...1000))
        if ($lineProfile.CommandHits.ContainsKey($hit.Column)) { 
            $commandHit = $lineProfile.CommandHits[$hit.Column] 
            $commandHit.Duration += $hit.Duration
            $commandHit.CallDuration += $hit.CallDuration
            $commandHit.HitCount++
        }
        else { 
            $commandHit = [PSCustomObject] @{
                Line     = $hit.Line # start from 1 as in file
                Column   = $hit.Column
                Duration = $hit.Duration
                CallDuration = $hit.CallDuration
                HitCount = 1
                Text     = $hit.Text
            }
            $lineProfile.CommandHits.Add($hit.Column, $commandHit)
        }
    }

    $total = if ($null -ne $trace -and 0 -lt @($trace).Count) { [TimeSpan]::FromTicks($trace[-1].Timestamp - $trace[0].Timestamp) } else { [TimeSpan]::Zero }

    Write-Host -ForegroundColor Magenta "Counting averages and percentages."
    # this is like SelectMany, it joins the arrays of arrays
    # into a single array
    $all = $fileMap.Values | Foreach-Object { $_ } | ForEach-Object {
        $_.Average = if ($_.HitCount -eq 0) { [TimeSpan]::Zero } else { [TimeSpan]::FromTicks($_.Duration.Ticks / $_.HitCount) }
        $_.AverageCall = if ($_.HitCount -eq 0) { [TimeSpan]::Zero } else { [TimeSpan]::FromTicks($_.CallDuration.Ticks / $_.HitCount) }
        $_.Percent = [Math]::Round($_.Duration.Ticks / $total.Ticks, 5, [System.MidpointRounding]::AwayFromZero) * 100
        $_
    }

    Write-Host -ForegroundColor Magenta "Getting Top50 that take most percent of the run."

    $top50Percent = $all | 
    Where-Object Percent -gt 0 | 
    Sort-Object -Property Percent -Descending | 
    Select-Object -First 50

    Write-Host -ForegroundColor Magenta "Getting Top50 with the longest average duration."

    $top50Average = $all | 
    Where-Object Average -gt 0 | 
    Sort-Object -Property Average -Descending | 
    Select-Object -First 50
        
    Write-Host -ForegroundColor Magenta "Getting Top50 with the longest duration."

    $top50Duration = $all |
    Where-Object Duration -gt 0 | 
    Sort-Object -Property Duration -Descending | 
    Select-Object -First 50

    Write-Host -ForegroundColor Magenta "Getting Top50 with the longest average duration for the whole line."

    $top50Average = $all | 
    Where-Object AverageCall -gt 0 | 
    Sort-Object -Property AverageCall -Descending | 
    Select-Object -First 50
        
    Write-Host -ForegroundColor Magenta "Getting Top50 with the longest duration for the whole line.."

    $top50Duration = $all |
    Where-Object CallDuration -gt 0 | 
    Sort-Object -Property CallDuration -Descending | 
    Select-Object -First 50
    
    Write-Host -ForegroundColor Magenta "Getting Top50 with the most hits."

    $top50HitCount = $all | 
    Where-Object HitCount -gt 0 |
    Sort-Object -Property HitCount -Descending | 
    Select-Object -First 50

    $script:processedTrace = [PSCustomObject] @{ 
        Top50         = $top50Percent
        Top50Average  = $top50Average
        Top50Duration = $top50Duration
        Top50HitCount = $top50HitCount
        Top50CallDuration = $top50CallDuration
        Top50CallDurationAverage = $top50CallDurationAverage
        TotalDuration = $total
        All           = $all
        Events        = $trace
        Files         = foreach ($pair in $fileMap.GetEnumerator()) {
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
    
    Write-Host -ForegroundColor Magenta "Done. Try $(if ($variable) { "$($variable)" } else { '$yourVariable' }).Top50 | Format-Table to get the report. There are also Top50Average, Top50Duration, Top50HitCount, and Files."
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
            [System.Threading.Thread]::Sleep($e.Duration * $x)
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
