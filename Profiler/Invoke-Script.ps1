function Invoke-Script {
    <# 
    .DESCRIPTION
    Invoke the provided script or command and measure the time it takes to execute it.

    .PARAMETER ScriptBlock
    A ScriptBlock to be executed.

    $trace = Invoke-Script -ScriptBlock { Import-Module $PSScriptRoot\Planets.psm1; Get-Planet } -Repeat 3

    When running a script file use the same syntax, you can specify parameters if you need: 
    $trace = Invoke-Script -ScriptBlock { & $PSScriptRoot\MyScript.ps1 } -Repeat 3

    .PARAMETER Repeat
    Run the provided script or command this many times in the same session. Default is 1. 
    The first two runs are usually much slower than the subsequent runs. Using 3 or more
    is good to get the idea of overall performance, but if you are optimizing for fast single 
    run you might want to keep 1.

    .PARAMETER Preheat
    Run the provided script or command this many times without tracing it to warm up the session.
    This is good for measuring normal performance excluding startup. Default is 0.

    .PARAMETER Flag
    A hash table of feature flags to be enabled to do before/after comparisons. The script or command will run
    twice in each repetition. Once as before changes and once as after changes. 

    For this to work your code needs to cooperate:

    Each key from the hashtable will be defined as a $global: variable. Use that variable in `if` to wrap
    the new code to test it against the old code. 

    Use $true, $false as the values. The hashtable represents the after side. Each key will be 
    defined with the value for after side. Each key will be defined with $false for the before side.

    In this case example is worth 1000 words:

    Invoke-Script -ScriptBlock { & MyScript.ps1 } -Flag @{ _profiler = $true }

    Original code in MyScript.ps1 you are trying to improve:
    $values = 1..1000
    foreach ($v in $Values) {
        $newValues += $v + 10
    }

    Modified code with changes that you think are faster wrapped in if using the feature flags: 
    if ($_profiler) {
        $values =  [System.Linq.Enumerable]::Range(1,1000)
    }
    else {
        $values = 1..1000 
    }

    if ($_profiler) {
        # after side
        $newValues = foreach ($v in $Values) { $v + 10 }
    }
    else {
        # before side
        foreach ($v in $Values) {
            $newValues += $v + 10
        }
    }

    A single feature flag might be good enough for many purposes, but imagine there are multiple improvements 
    that migh contradict each other, in that case you are better of adding different flag for each one: 

    Invoke-Script -ScriptBlock { & MyScript.ps1 } -Flag @{ _iteration = $true; _enumerable = $true }

    if ($_enumerable) {
        $values =  [System.Linq.Enumerable]::Range(1,1000)
    }
    else {
        $values = 1..1000 
    }

    if ($_iteration) {
        # B side
        $newValues = foreach ($v in $Values) { $v + 10 }
    }
    else {
        # A side
        foreach ($v in $Values) {
            $newValues += $v + 10
        }
    }

    Using two or more feature flags you can test them together as shown above, or one without the other: 

    Invoke-Script -ScriptBlock { & MyScript.ps1 } -Flag @{ _iteration = $true; _enumerable = $false }
    #>

    param(
        [Parameter(Mandatory)]
        [ScriptBlock] $ScriptBlock,
        [uint32] $Repeat = 1,
        [uint32] $Preheat = 0,
        [Hashtable] $Flag
    )

    $ErrorView = "Normal"
    $ErrorActionPreference = "Stop"

    Assert-PowerShellVersion

    Write-Host -ForegroundColor Magenta "Running in PowerShell $($PSVersionTable.PSVersion) $([System.IntPtr]::Size*8)-bit."
    if ($Flag) {
        Write-Host -ForegroundColor Magenta "Flags for After runs:"
        foreach ($f in $Flag.GetEnumerator()) {
            Write-Host -ForegroundColor Magenta "    $($f.Key) = $($f.Value)"
        }
    }

    if (0 -ge $Repeat) {
        $Repeat = 1
    }

    if (0 -ge $Preheat) {
        $Preheat = 0
    }

    if (0 -lt $Preheat) { 
        foreach ($i in 1..$Preheat) {
            Write-Host -Foreground Magenta  "Warm up $i"
            if (0 -lt $Flag.Count) { 
                foreach ($p in $Flag.GetEnumerator()) {
                    $v = if ($i % 2 -eq 1) { 
                        $false
                    } 
                    else {
                        $p.Value
                    }

                    Set-Variable -Scope Global -Name $p.Key -Value $v
                }
            }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $null = & $ScriptBlock
                $sw.Stop()
            }
            catch {
                $sw.Stop()
                Write-Host "Warm up failed with $_."
            }
        }
    }

    $run = [Collections.Generic.List[object]]@()

    foreach ($i in 1..$Repeat) {
        $sides = if ($null -ne $Flag) { "Before", "After" } else { "After" }        
        
        foreach ($side in $sides) {
            Write-Host -Foreground Magenta  "Run $i$(if (1 -lt $sides.Count) { " - $side" })"
            if (0 -lt $Flag.Count) { 
                foreach ($p in $Flag.GetEnumerator()) {
                    $v = if ("Before" -eq $side) { 
                        $false
                    } 
                    else {
                        $p.Value
                    }

                    Set-Variable -Scope Global -Name $p.Key -Value $v
                }
            }
            $err = $null
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $null = & $ScriptBlock
                $sw.Stop()
                Write-Host -Foreground Magenta  "Run $i$(if (1 -lt $sides.Count) { " - $side" }) finished after $($sw.Elapsed)"
            }
            catch { 
                $sw.Stop()
                $err = $_
                Write-Host "Run $i$(if (1 -lt $sides.Count) { " - $side" }) failed after $($sw.Elapsed) with $_."
            }

            $null = $run.Add(@{ Error = $err; SelfDuration = $sw.Elapsed; Side = $side })
        }
    }

    Write-Host -Foreground Magenta  "Done."

    if ($Flag) { 
        for ($r = 0; $r -lt $run.Count; $r = $r + 2) { 
            $b = $run[$r]
            $a = $run[$r + 1]

            $diff = [int]($a.SelfDuration.TotalMilliseconds - $b.SelfDuration.TotalMilliseconds)
            if ($diff -eq 0) { 
                $beforeColor = $afterColor = "Yellow"
            }
            elseif ($diff -gt 0) { 
                $beforeColor = "Green"
                $afterColor = "Red"
            }
            else { 
                $beforeColor = "Red"
                $afterColor = "Green"
            }

            Write-Host -NoNewline "Run $(${r}/2+1): "
            Write-Host -ForegroundColor $beforeColor $b.SelfDuration -NoNewline 
            Write-Host -NoNewline " -> "
            Write-Host -ForegroundColor $afterColor $a.SelfDuration -NoNewline 
            Write-Host " ($($diff) ms)"
        }
    }
}