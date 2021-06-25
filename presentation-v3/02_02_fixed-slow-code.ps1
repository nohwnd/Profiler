
$sb = { 
    $tests = @(
        # tag is now an array of items
        @{ Name = "Test1"; Tag = @("Windows") }
        @{ Name = "Test2"; Tag = @("Windows") }
        @{ Name = "Test3"; Tag = @() }
        @{ Name = "Test4"; Tag = @() }
        5..5000 | ForEach-Object { @{ Name = "Test$_"; Tag = @() } }
    )

    "test count: " + $tests.Count

    function Filter-Test {
        param ($Test, $Tag)

        if ($null -eq $Tag -or 0 -ge @($Tag).Length) {
            return
        }

        # This condition is more complex in real life so returning 
        # early for no tags significantly simplifies the logic.
        if ($Tag -in $Test.Tag) { 
            $Test
        }
    }

    $tag = "Windows"
    $filteredTests = foreach ($test in $tests) {
        Filter-Test -Test $test -Tag $tag
    }

    Write-Host "Filered tests: " $filteredTests.Count
}

$trace = Trace-Script -ScriptBlock $sb
$trace.Top50Duration | Format-Table Percent, HitCount, Duration, SelfDuration, Name, Line, Text 
