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
        $trace.TotalDuration | Should-Take $trace.StopwatchDuration -OrLessBy 25ms
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
}