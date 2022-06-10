function Get-CallStack {

    param (
        [Parameter(Mandatory)]
        [Profiler.Hit] $hit
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