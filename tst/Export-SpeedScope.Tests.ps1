BeforeAll { 
    Get-Module Profiler | Remove-Module
    $module = Import-Module "$PSScriptRoot/../Profiler/Profiler.psd1" -PassThru
    ${function:Export-SpeedScope} = & ($module) { Get-Command Export-SpeedScope }
    ${function:Convert-SpeedScope} = & ($module) { Get-Command Convert-SpeedScope }
}

Describe "Convert-SpeedScope" { 
    It "Can convert MyScript.ps1" {
        . $PSScriptRoot/../demo.ps1

        $trace | Should -Not -BeNullOrEmpty
        $report = $report = [Profiler.SpeedScope.SpeedScope]::Convert("exporter", $trace, "file1")
        $report.shared.frames.Count | Should -BeGreaterThan 0
        $report.profiles.Count | Should -Be 1
        $report.profiles[0].events.Count | Should -BeGreaterThan $trace.Events.Count
    }

    It "Can convert MyScript.ps1 with flag" {
        $trace = Trace-Script { & "$PSScriptRoot/../demo-scripts/MyScript.ps1" } -Flag @{ _profiler = $true }
        $trace | Should -Not -BeNullOrEmpty
        $report = [Profiler.SpeedScope.SpeedScope]::Convert("exporter", $trace, "file1")
        $report.shared.frames.Count | Should -BeGreaterThan 0
        $report.profiles.Count | Should -Be 1
        $report.profiles[0].events.Count | Should -BeGreaterThan $trace.Events.Count
    }

    It "Can convert SleepyScript.ps1" {
        $trace = Trace-Script { & "$PSScriptRoot/../demo-scripts/SleepyScript.ps1" } -Flag @{ _profiler = $true }
        $trace | Should -Not -BeNullOrEmpty
        $report = $report = [Profiler.SpeedScope.SpeedScope]::Convert("exporter", $trace, "file1")
        $report.shared.frames.Count | Should -BeGreaterThan 0
        $report.profiles.Count | Should -Be 1
        $report.profiles[0].events.Count | Should -BeGreaterThan $trace.Events.Count
    }
}