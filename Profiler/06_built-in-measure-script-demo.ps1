
if ($PSVersionTable.PSVersion.Major -notin (5,7)) { 
    throw "This module only supports PowerShell 5 and 7, but this is $($PSVersionTable.PSVersion)."
}

if (5 -eq $PSVersionTable.PSVersion.Major) { 
    throw "will get to 5 later"
}


[string] $psVersion = $PSVersionTable.PSVersion
$isCustomBuild = '7.2.0-nohwnd' -eq $psVersion
if ($isCustomBuild) { 
    Write-Host "We are in custom PowerShell 7 build. Running in process."
}
else {
    Write-Host "We are in standard PowerShell 7. The script will run in a new process, using the current user profile."
}

if (-not $isCustomBuild) {
    throw "Can't run in new process yet. Start '$PSScriptRoot/pwsh7-nohwnd/pwsh.exe'."
}

$ErrorActionPreference = 'Stop'
Get-Module PSProfiler2 | Remove-Module

# PSProfiler PR from Ilya - https://github.com/PowerShell/PowerShell/pull/13673
# will be in some 7.1.x, version hopefully, but only from that forward

Import-Module $PSScriptRoot/PSProfiler2.psm1


#$traceCore = Measure-Script { & "$psscriptroot/scripts/hello.ps1"}
#Write-Host $traceCore[0].GetType()
$traceCore = Measure-Script { & "C:\p\pester\test.ps1" -skipp } 
Write-Host -ForegroundColor Blue "Got $($traceCore.Count) trace events. Normalizing."

Import-Module C:\p\profiler\src\csharp\Profiler\bin\Debug\net452\Profiler.dll

$index = 0
$trace = $(foreach ($t in $traceCore) { 
    $r = [Profiler.ProfileEventRecord]::new()
    $e = [Profiler.ScriptExtentEventData]::new()
    $e.File =  $t.Extent.File
    $e.StartLineNumber = $t.Extent.StartLineNumber
    $e.StartColumnNumber = $t.Extent.StartColumnNumber
    $e.EndLineNumber = $t.Extent.EndLineNumber
    $e.EndColumnNumber = $t.Extent.EndColumnNumber
    $e.Text = $t.Extent.Text
    $e.StartOffset = $t.Extent.StartOffset
    $e.EndOffset = $t.Extent.EndOffset
    $r.Extent = $e
    $r.StartTime = $t.StartTime
    $r.SelfDuration = $t.SelfDuration
    $r.Index = $index

    $r

    $index++
})

$traceCore = $null


if (-not $trace) { 
    throw "Trace is null something is wrong."
}

Write-Host -ForegroundColor Blue "Trace is done. Processing it via Get-Profile"
$profiles = Get-Profile -Trace $trace # -Path $hello
Write-Host -ForegroundColor Blue "Get-Profile is done."

# but how do we know what is slow? Well it's simple: 
$profiles.Top10 |
    Format-Table -Property Percent, HitCount, SelfDuration, Average, Name, Line, Text
# exit
break 


$profiles.Files | Select-Object -Property Path
# hello.ps1
$profiles.Files[2].Profile | Format-Table -Property Line, SelfDuration, HitCount, Text


break 

# but how do we know what is slow? Well it's simple: 
$profiles.Top10 |
    Format-Table -Property Percent, HitCount, SelfDuration, Average, Line, Text, CommandHits