## Improving performance

Import-Module $PSScriptRoot/Profiler/Profiler.psm1 -Force

# This is the script to be profiled. Provide a path to script, and provide
# parameters if you need them. You can also profile any other code. Like 
# importing a module and running a function from it.
$scriptBlock = { & "$PSScriptRoot/demo-scripts/MyScript.ps1" }

# When making changes to your code, use `if` to wrap the new 
# improved code and keep the old code in `else`. Profiler defines
# global variables based on the hashtable below, and can automatically
# switch between the code before and after changes to compare it.
$flag = @{ _profiler = $true }

## Comparing performance
# Runs the script mulitiple times, switching between the code before
# and after changes:
Invoke-Script -ScriptBlock $scriptBlock -Preheat 0 -Repeat 3 -Flag $flag

# At this point you probably improved your performance a bit. Run the profiler again, 
# this time providing the -Flag to enable running the new code. 

# Runs the script 1 time, with 1 warm up run (this is needed in PowerShell 7) using the 
# code After the changes. You can switch back to before changes by adding `-Before`.
$trace = Trace-Script -ScriptBlock $scriptBlock -Preheat 1 -Flag $flag

# Shows the top 50 lines that take the most percent of the run
$trace.Top50 | Format-Table


# Try it for yourself by running the commands from this demo, or by invoking this file as
# . ./demo2.ps1