$tests = @(
    @{ Name = "Test1"; Tag = "Windows" }
    @{ Name = "Test2"; Tag = "Windows" }
    @{ Name = "Test3"; Tag = "" }
    @{ Name = "Test4"; Tag = "" }
    5..5000 | ForEach-Object { @{ Name = "Test$_"; Tag = "" } }
)

"test count: " + $tests.Count

function Filter-Test {
    param ($Test, $Tag)
    if ($Tag -eq $Test.Tag) { 
        $Test
    }
}

$sw = [Diagnostics.Stopwatch]::StartNew()
$tag = "Windows"
$filteredTests = foreach ($test in $tests) {
    Filter-Test -Test $test -Tag $tag
}
"Passing items one by one:"
"filtered count: " + $filteredTests.Count
"elapsed ms: " + $sw.ElapsedMilliseconds
 
