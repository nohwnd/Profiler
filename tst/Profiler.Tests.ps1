BeforeAll { 

    function Should-Take {
        param (
            $Expected, 
            [string] $OrLessBy = "0ms",  
            [Parameter(ValueFromPipeline)]
            [TimeSpan] $Actual
        )

        if ($null -eq $Expected) { 
            throw "Expected is null, but should be timespan or ms."
        }

        if ($Expected -is [timespan]) { 
            $Expected = "$([int]$Expected.TotalMilliseconds)ms"
        }

        $null, $unit = $Expected -split "\d+", 2
        $time, $null = [int]($Expected -split "\D+", 2)[0]
        if ("ms" -ne $unit) { 
            throw "Unit $unit of Expected is not supported."
        }

        $null, $unit = $OrLessBy -split "\d+", 2
        $less, $null = [int]($OrLessBy -split "\D+", 2)[0]

        if ("ms" -ne $unit) { 
            throw "Unit $unit of OrLessBy is not supported."
        }

        $wholeMs = [int] $Actual.TotalMilliseconds
        $diff = [int]($time - $wholeMs)
        if (0 -gt $diff) { 
            throw "Expected $($Expected), but ${wholeMs}ms is longer."
        }
        if ($less -lt $diff) {
            throw "Expected $($Expected), but ${wholeMs}ms is ${diff}ms shorter, which is not in the allowed difference $OrLessBy."
        }
    }

    Get-Module Profiler | Remove-Module 
    Import-Module "$PSScriptRoot/../Profiler/Profiler.psd1"
}

Describe "Should-Take" { 
    It "Passes when time <value.TotalMilliseconds>ms is shorter than <expected> within range of <orLessBy>" -Foreach @(
        @{ Value = [timespan]::FromMilliseconds(10); Expected = "10ms"; OrLessBy = "0ms" }
        @{ Value = [timespan]::FromMilliseconds(9); Expected = "10ms"; OrLessBy = "1ms" }
        @{ Value = [timespan]::FromMilliseconds(5); Expected = "10ms"; OrLessBy = "5ms" }
    ) {
        $Value | Should-Take -Expected $Expected -OrLessBy $OrLessBy
    }

    It "Fails when time <value.TotalMilliseconds>ms is shorter than <expected> but not within range of <orLessBy>" -Foreach @(
        @{ Value = [timespan]::FromMilliseconds(9); Expected = "10ms"; OrLessBy = "0ms" }
        @{ Value = [timespan]::FromMilliseconds(8); Expected = "10ms"; OrLessBy = "1ms" }
        @{ Value = [timespan]::FromMilliseconds(4); Expected = "10ms"; OrLessBy = "5ms" }
    ) {
        { $Value | Should-Take -Expected $Expected -OrLessBy $OrLessBy } | Should -Throw "*which is not in the allowed difference*"
    }

    It "Fails when time <value.TotalMilliseconds>ms is longer than <expected>, no matter what the range is (<orLessBy>)" -Foreach @(
        @{ Value = [timespan]::FromMilliseconds(11); Expected = "10ms"; OrLessBy = "0ms" }
        @{ Value = [timespan]::FromMilliseconds(13); Expected = "10ms"; OrLessBy = "1ms" }
        @{ Value = [timespan]::FromMilliseconds(15); Expected = "10ms"; OrLessBy = "5ms" }
    ) {
        { $Value | Should-Take -Expected $Expected -OrLessBy $OrLessBy } | Should -Throw "*is longer*"
    }
}

Describe "Trace-Script" {
    It "Can profile a scriptblock" { 
        $trace = Trace-Script { Start-Sleep -Milliseconds 100 }

        # first test gets perf hit, with just 25ms it fails almost all the time 
        # on timing issues in our CI
        $trace.TotalDuration | Should-Take $trace.StopwatchDuration -OrLessBy 50ms
    }

    It "Can profile an unbound scriptblock" { 
        $scriptBlock = [ScriptBlock]::Create({ Start-Sleep -Milliseconds 100 })
        $trace = Trace-Script $scriptBlock
        $trace.TotalDuration | Should-Take $trace.StopwatchDuration -OrLessBy 25ms
    }

    It "Can profile a simple script" { 
        "Start-Sleep -Milliseconds 100" > TestDrive:\MyScript1.ps1
        $trace = Trace-Script { & TestDrive:\MyScript1.ps1 }
        $trace.TotalDuration | Should-Take $trace.StopwatchDuration -OrLessBy 25ms
    }

    It 'Returns trace for events up to and including exception' {
        $sb = {
            'Before' > $null
            throw "We're going down"
            'After' > $null
        }

        $trace = Trace-Script $sb
        $trace.AllLines.Count | Should -BeExactly 3 # first line is {
        $trace.AllLines[0].Text | Should -Match '^throw' -Because 'the last line profiled should be the line throwing the exception'
    }

    It 'Counts hits both for lines and command hits on the same line' {
        $sb = { 1..2 | Foreach-Object { 
            $i = $_*2; Write-Output $i > $null
        } }
        $trace = Trace-Script $sb

        $inner = $trace.AllLines | Where-Object Text -like '$i = $_*2; *'  | Select-Object -Last 1

        $inner.HitCount | Should -BeExactly 4
        foreach ($k in $inner.CommandHits.Keys) {
            $inner.CommandHits[$k].HitCount | Should -BeExactly 2 -Because 'command was executed twice'
        }
    }

    It 'Reported timings are within valid range' {
        $sb = { 1..2 | Foreach-Object { 
            $i = $_*2
            Start-Sleep -Milliseconds 10
        } }
        
        $trace = Trace-Script $sb

        foreach ($line in $trace.AllLines) {
            $line.SelfDuration | Should -BeLessOrEqual $line.Duration -Because 'no line can be slower than itself'
            $line.Duration | Should -BeLessOrEqual $trace.TotalDuration -Because 'no line can be slower than all'

            foreach ($command in $line.CommandHits.GetEnumerator()) {
                $command.SelfDuration | Should -BeLessOrEqual $line.SelfDuration -Because 'no command can be slower than the whole line'
            }
        }
    }
}