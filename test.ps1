param ([Switch] $Clean) 
if ($Clean) {
    & "$PSScriptRoot/build.ps1"
}
else { 
    try { 
        & "$PSScriptRoot/build.ps1"
    }
    catch { 
        if ($_ -like "*The process cannot access the file*Profiler.dll*being used by another process*") { 
            Write-Warning "Files are locked, if you made changes to the C# code, close all processes that have the dll loaded and run with -Clean, or run ./build.ps1."
        }
        else {
            throw $_
        }
    }
}

$devPesterPath = "/p/pester/bin/Pester.psd1"
if (Test-Path $devPesterPath) { 
    Write-Host "Using Pester from: $devPesterPath"
    Get-Module Pester | Remove-Module
    Import-Module $devPesterPath
}
else {
    if (-not (Get-Module Pester -List | Where-Object Version -GE 5.2.0)) {
        Write-Host "Installing Pester"
        Install-Module Pester -MinimumVersion 5.0.0 -MaximumVersion 5.9999.9999
    }
}

Invoke-Pester ./tst/ 