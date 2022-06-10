function Show-ScriptExecution {
    # .DESCRIPTION Show how the script executed with margin to show how deep the call was, this is just for fun.
    # You can slow down the excution x times to reflect the mimic the real execution delays.
    [CmdletBinding()]
    param(
        $Trace,
        [switch] $x1,
        [switch] $x10,
        [switch] $x100,
        [switch] $x1000 # ,
        # [switch] $Color
    )

    $trace = if ($Trace) { $Trace } else { Get-LatestTrace }

    $x = if ($x1000) {
        1000
    }
    elseif ($x100) {
        100
    }
    elseif ($x10) {
        10
    }
    elseif ($x1) {
        1
    }
    else {
        0
    }

    $blueToGreen = $false
    
    if ($blueToGreen) {
        # Blue to green
        $colors = @(51, 50, 49, 48, 47, 46, 82, 118, 154, 190, 226, 227, 228, 229, 230, 231)
    }
    else {
        # heat
        $colors = @(226, 220, 214, 124, 196)
    }
    
    foreach ($e in $trace.Events) {
        $text = $e.Extent.Text.ToString().Trim()
        if ($blueToGreen) {
            # just index into the color array
            $c = $colors[$e.Level - 1]
        }
        else { 
            $p = $e.SelfDuration.TotalMilliseconds / $trace.TotalDuration.TotalMilliseconds * 100
            # get color when higher than x percent (e.g. red for more than 20%)
            $c = if ($p -gt 20) {
                $colors[4]
            } 
            elseif ($p -gt 10) {
                $colors[3]
            }
            elseif ($p -gt 5) {
                $colors[2]
            }
            elseif ($p -gt 3) {
                $colors[1]
            }
            elseif ($p -gt 1) {
                $colors[0]
            }
            else {
                0
            }

            $col = if ($c -gt 0) { 
                "`e[38;5;$($c)m"
            }
            else {
                $null
            }
        }

        $o = "$col$text`e[38;5;250m ($([math]::Round($e.SelfDuration.TotalMilliseconds,1))ms, $([int]$p)%)`e[0m"
        $margin = ' ' * ($e.Level)
        Write-Host "$margin$o"
        if (0 -lt $x) {
            # this is fun, but hardly accurate, as the resolution is <15ms
            # and many lines take <0.001ms
            [System.Threading.Thread]::Sleep($e.SelfDuration * $x)
        }
    }
}