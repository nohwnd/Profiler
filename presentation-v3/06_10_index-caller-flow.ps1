$trace = Trace-Script {
    function a () { throw "uh oh!" }
    function b () { a }

    try { b } catch { "ERR: $_" }
}

$trace.Events | Format-Table Index, CallerIndex, ReturnIndex, Flow, Level, Text