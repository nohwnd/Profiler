function Export-SpeedScope {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ExportTrace")]
        $Trace,
        [Alias("ExportPath")]
        [string] $Path = '.'
    )

    process {
        Write-Host -ForegroundColor Magenta "Exporting report into speedscope format." -NoNewline
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        $finalPath, $finalName = if (Test-Path $fullPath) {
            $item = Get-Item $fullPath -Force
            if ($item.PSIsContainer) {
                # we are given an existing directory, grab the next available default name
                Get-NextName -Path $item.FullName
            }
            else {
                # we are given an existing file, grab the name so we can check if it has template
                Get-NextName -Path $item.Directory -Name $item.Name
            }
        }
        else {
            if ([IO.Path]::EndsInDirectorySeparator($fullPath)) {
                # the path ends in \ or / which means we are given a directory, get the next name
                Get-NextName -Path $fullPath
            }
            else {
                # we are given a file, it might have an extension or not
                Get-NextName -Path (Split-Path $fullPath) -Name (Split-Path -Leaf $fullPath)
            }
        }

        $report = Convert-SpeedScope -Name $finalName -Events $trace.Events

        $destination = (Join-Path $finalPath $finalName)
        Write-Host "converted in $($sw.ElapsedMilliseconds) ms"
        Set-Content -Value (ConvertTo-Json $report -Depth 5) -Encoding UTF8 -Path $destination
        Write-TimeAndRestart $sw
        Write-Host -ForegroundColor Cyan "Exported for https://speedscope.app/, to: $destination"
    }
}

function Get-NextName {
    param(
        [Parameter(Mandatory)]
        [string] $Path,
        [string] $Name = 'profiler_<id>.speedscope.json'
    )

    $Name = $Name -like "*.speedscope.json" ? $Name : "$Name.speedscope.json"
    $idTemplate = '<id>'
    $hasIdTemplate = $Name -like "*$idTemplate*"

    if (-not $hasIdTemplate) {
        return $Path, $Name
    }

    for ($id = 0; $id -le 9999; $id++) {
        $candidate = $Name -replace $idTemplate, $id.ToString("d4")
        if (-not (Test-Path -Path (Join-Path $Path $candidate))) {
            return $Path, $candidate
        }
    }

    throw "Could not find next name for $Name, last name candidate: '$candidate'"
}

function Convert-SpeedScope {
    param(
        [Parameter(Mandatory)]
        $Name,
        $Events
    )

    # schema: https://github.com/jlfwong/speedscope/blob/main/src/lib/file-format-spec.ts
    $process = Get-Process -Id $pid
    $frames, $convertedEvents = @(Convert-EventsAndFrames $Events)
    $aProfile = [PSCustomObject][Ordered] @{
        type       = 'evented' # or sampled
        name       = "$($process.Name) ($($process.Id)) Time=$([Math]::Round($trace.TotalDuration.TotalMilliseconds, 5))ms"
        unit       = 'milliseconds'
        startValue = 0
        # we start from the third event, and the next to last start event is the end time
        endValue   = [Math]::Round($Events[-2].StartTime.TotalMilliseconds - $Events[2].StartTime.TotalMilliseconds, 5)
        events     = @($convertedEvents)
    }

    $profiles = @($aProfile)

    $report = [PSCustomObject][Ordered] @{
        exporter           = "$($ExecutionContext.SessionState.Module.Name)@$($ExecutionContext.SessionState.Module.Version)"
        name               = $fileName
        activeProfileIndex = 0
        '$schema'          = 'https://www.speedscope.app/file-format-schema.json'
        shared             = [PSCustomObject][Ordered]@{
            frames = @($frames)
        }
        profiles           = @($profiles)
    }

    $report
}

function Convert-EventsAndFrames {
    param ($Events)

    # this will go into the report, frame names are saved once and re-used by events
    # to make the file smaller
    $frames = [System.Collections.Generic.List[object]]::new(1000)
    # this stores the index to which we added the value to frames list so we can quickly look it up
    $frameDictionary = [System.Collections.Generic.Dictionary[string, int]]::new()
    $convertedEvents = [System.Collections.Generic.List[object]]::new(1000)
    $start = $Events[2].StartTime
    $callStack = [Collections.Generic.Stack[int]]::new()

    $lastValidEventIndex = $Events.Count - 3
    $c = 0
    foreach ($event in $Events) {

        
        if ($Event.index % 100000 -eq 0) { 
            Write-Host "$($Event.index) in $($sw.ElapsedMilliseconds) ms"
        }
        # skip events that we produce directly from Profiler
        if (0 -eq $event.Level) {
            continue
        }

        # we mark the first event as Process, but the last one as return, which tries to pop the call from the 
        # stack which will end up in error. Instead the last event should also be considered Process, because 
        # we ignore the next events
        $flow = $event.Index -ne $lastValidEventIndex ? $event.Flow : [Profiler.Flow]::Process

        $index = -1

        # Add a pair of events for every Process and Return event so we can see them on the screen, and then 
        # and for Return additionaly record event for returning from the call
        $flows = @([Profiler.Flow]::Process -eq $flow -or [Profiler.Flow]::Return -eq $flow ? [Profiler.Flow]::Call, [Profiler.Flow]::Return : $flow)
        foreach ($flow in $flows) {

            # when we Return, but we don't go just 1 level above (most often because of trow), we might have more calls on the
            # call stack and need to emit all of them until we reach the current level.
            # if the event is not Return we just record 1 event
            $pops =  [Profiler.Flow]::Return -ne $flow ? @(1) : @(0..($event.Level - $callStack.Count))
            foreach ($pop in $pops) {
                if ([Profiler.Flow]::Call -eq $flow) {
                    $callStack.Push($event.Index)
                }

                if ([Profiler.Flow]::Return -eq $flow) {
                    $callerIndex = $callStack.Pop()
                }

                # when we return we need to use the Text of who called us, because otherwise the event points to a different frame name
                # and sppeed scope complains that we are leaving different frame than the one we intered
                $key = [Profiler.Flow]::Call -eq $flow ? $event.Text : $Events[$callerIndex].Text

                if (-not $frameDictionary.TryGetValue($key, [ref] $index)) {
                    # check the count first because indexing starts from 0
                    $index = $frames.Count
                    $frameDictionary.Add($key, $index)
                    $frames.Add([PSCustomObject]@{
                            name = $key

                            # # for debugging
                            # index = $index
                        })
                }

                # calls report start of the event relative to the start event, returns report start of the event + the self-duration of the event
                $at = [Profiler.Flow]::Call -eq $flow ? $event.StartTime - $start : $event.StartTime + $event.SelfDuration - $start
                $convertedEvents.Add([PSCustomObject]@{
                    # O for open, that we call Call, and C for close that we call Return. Don't confuse with C for Call.
                    type  = [Profiler.Flow]::Call -eq $flow ? "O" : "C"
                    frame = $index
                    at    = [Math]::Round($at.TotalMilliseconds, 5)

                    # # for debugging 
                    # stack = $frames[$index].name
                    level = $event.Level
                    # event = ($event | Select-Object Index, Flow, Level, CallerIndex, ReturnIndex, Text | Format-Table -HideTableHeaders | Out-String).Trim()
                })
            }
        }
    }

    $frames, ($convertedEvents)
}
