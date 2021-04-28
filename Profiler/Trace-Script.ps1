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

    Write-Host -ForegroundColor Magenta "Processing $($trace.Count) trace events. $(if (1000000 -lt $trace.Count) { " This might take a while..."})"
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

    Write-Host -ForegroundColor Magenta "Sorting trace events to file lines."
    foreach ($hit in $trace) {
        if (-not $hit.Path -or -not ($fileMap.Contains($hit.Path))) {
            continue
        }

        # get the object that describes this particular file
        $lineProfiles = $fileMap[$hit.Path]

        $lineProfile = $lineProfiles[$hit.Line - 1] # array indexes from 0, but lines from 1
        $lineProfile.Duration += $hit.Duration
        $lineProfile.HitCount++
        $lineProfile.Hits.Add($hit)

        # add distinct entries per column when there are more commands
        # on the same line (like we did it with the Group-Object on foreach ($i in 1...1000))
        if ($lineProfile.CommandHits.ContainsKey($hit.Column)) { 
            $commandHit = $lineProfile.CommandHits[$hit.Column] 
            $commandHit.Duration += $hit.Duration
            $commandHit.HitCount++
        }
        else { 
            $commandHit = [PSCustomObject] @{
                Line     = $hit.Line # start from 1 as in file
                Column   = $hit.Column
                Duration = $hit.Duration
                HitCount = 1
                Text     = $hit.Text
            }
            $lineProfile.CommandHits.Add($hit.Column, $commandHit)
        }
    }

    $total = [TimeSpan]::FromTicks($trace[-1].Timestamp - $trace[0].Timestamp)

    Write-Host -ForegroundColor Magenta "Counting averages and percentages."
    # this is like SelectMany, it joins the arrays of arrays
    # into a single array
    $all = $fileMap.Values | Foreach-Object { $_ } | ForEach-Object { 
        $_.Average = if ($_.HitCount -eq 0) { [TimeSpan]::Zero } else { [TimeSpan]::FromTicks($_.Duration.Ticks / $_.HitCount) }
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
        Write-Warning "But there is no trace yet. This command is here to get the trace when you forgot to output it to variable. Run Trace-Script, ideally $trace = Trace-Script -ScriptBlock { & yourfile.ps1 }, and you won't need this cmdlet at all."
    }
}
