function Assert-PowerShellVersion () { 
    if ($PSVersionTable.PSVersion.Major -notin (5, 7)) { 
        throw "This module only supports PowerShell 5 and 7, but this is $($PSVersionTable.PSVersion)."
    }
}
