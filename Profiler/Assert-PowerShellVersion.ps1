function Assert-PowerShellVersion ($UseNativePowerShell7Profiler) { 
    if ($PSVersionTable.PSVersion.Major -notin (5, 7)) { 
        throw "This module only supports PowerShell 5 and 7, but this is $($PSVersionTable.PSVersion)."
    }

    if (7 -eq $PSVersionTable.PSVersion.Major -and $UseNativePowerShell7Profiler) {
        if (-not (Get-Command -Name  Measure-Script -Module  Microsoft.PowerShell.Core)) {
            throw "PowerShell profiler is not released yet. You need a special build of PowerShell to be able to profile scripts on PowerShell 7 using the native profiler. You have four options:`n    - Use the profiler this module comes with, and ensure you specify -Preheat 1 or higher. Do not specify -UseNativePowerShell7Profiler `n    - Use this module in PowerShell 5 if your module supports it. And if you need to measure startup performance.`n    - Download the build from https://github.com/nohwnd/profiler, this is unofficial build or PowerShell, but feel free to run virus scan on it. I just built this PR so you don't have to: https://github.com/PowerShell/PowerShell/pull/13673`n    - Clone this PR https://github.com/PowerShell/PowerShell/pull/13673 from the official PowerShell repo, and build it using the official instructions: https://github.com/PowerShell/PowerShell#building-the-repository. Then run this module in the build pwsh.exe.`n"
        }
    }    
}
