# Profiler

Script, ScriptBlock and module performance profiler for PowerShell 5, and PowerShell 7 that works in Windows, Linux and MacOS. 

## Quick start

Install the module from PowerShell gallery: 

```powershell
Install-Module Profiler
```

```powershell
$trace =  Trace-Script -ScriptBlock { & "demo-scripts/MyScript.ps1" }
$trace.Top50Duration | Format-Table
```

![](images/Profile.jpg)

## More Features 

- Profile module functions, or any scriptblock.
```powershell
$scriptBlock = { 
    Import-Module Pester
    Invoke-Pester
}
Trace-Script -ScriptBlock $scriptBlock
```

(Excluding files, e.g. Pester internals from the profiling is coming later.)


- Run code multiple times, comparing performance before and after your changes. 

```powershell
$flag = @{ _profiler = $true }
Invoke-Script -ScriptBlock $scriptBlock -Preheat 0 -Repeat 3 -Flag $flag
```

![](images/Compare.jpg)

- Look at a file or portion of a file

```powershell
# to see the whole file 
$trace.Files[0].Profile | Format-Table

# or to get first 10 lines 
$trace.Files[0].Profile[0..9] | Format-Table
```

![](images/Profile.jpg)

- Retrieve the last profile when you did not assign it to a variable 

```powershell 
Invoke-Script -ScriptBlock $scriptBlock -Preheat 0 -Repeat 3 -Flag $flag

# Output:
# Looks like you did not assign the output to a variable. Use Get-LatestTrace to retrieve the trace, e.g.: $trace = Get-LatestTrace

$trace = Get-LatestTrace
$trace.Top50Duration | Format-Table
```

- Progress of your changes

Running profiling multiple times in a row keeps the previous times to show you your progress. Indicating Before and After with B and A.

![](images/Progress.jpg)

- And more, like breakdown of a given line (.CommandHits), seeing who called given line (.Hits) and seeing the call stack that lead to the current call. All of them just need to be documented first. 


## DEMO:

Original prototype of this module is demoed [here on Youtube](https://www.youtube.com/watch?v=qLjDjm-nvLQ) The commands were renamed, but the way you can work with the resulting trace remained the same.


## Knows limitations:

This module is under heavy development. Here are some limitations of my current desing that I know how to fix, I just did not have time to do it yet:

- Using Set-PSDebug -Off, or Set-PSDebug -Trace 0 stops the tracing, because that is what we internally use to enable and disable it. If this is a must for you let me know in issues.

- Removing all breakpoints from the current session stops tracing. We add a synthetic breakpoint to prevent this, but if your code needs to remove all breakpoints, including the ones that are not "your own" let me know in issues.










