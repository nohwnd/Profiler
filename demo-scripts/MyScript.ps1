$upperLimit = 100000
if ($_profiler) {
    $values = [System.Linq.Enumerable]::Range(1, $upperLimit)
}
else {
    $values = 1..$upperLimit
}

if ($_profiler) {
    # after changes
    Write-Host "after"
    $newValues = foreach ($v in $Values) { $v + 10 }
}
else {
    # before changes
    Write-Host "before"
    $newValues = @()
    $Values | foreach {
        $newValues += $_ + 10
    }

    $Values | foreach {        $newValues += $_ + 10    }
}