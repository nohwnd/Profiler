$tests = @(
    @{ Name = "Test1"; Tag = "Windows" }
    @{ Name = "Test2"; Tag = "Windows" }
    @{ Name = "Test3"; Tag = "" }
    @{ Name = "Test4"; Tag = "" }
    5..5000 | ForEach-Object { @{ Name = "Test$_"; Tag = "" } }
)

function Filter-Test ($Tests, $Tag) {
    foreach ($test in $tests) {
        if ($Tag -eq $Test.Tag) { 
            $Test
        }
    }
}

$sw = [Diagnostics.Stopwatch]::StartNew()
$tag = "Windows"
$filteredTests = Filter-Test -Tests $tests -Tag $tag
"Passing whole array:"
"filtered count: " + $filteredTests.Count
"elapsed ms: " + $sw.ElapsedMilliseconds