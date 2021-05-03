param ($Clean) 
if ($Clean) {
    & "$PSScriptRoot/build.ps1"
}

if (-not (Get-Module Pester -List | Where-Object Version -GE 5.2.0)) {
    Install-Module Pester -MinimumVersion 5.0.0 -MaximumVersion 5.9999.9999
}

Invoke-Pester ./tst/ 