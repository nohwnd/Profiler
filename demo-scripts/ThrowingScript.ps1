
function a () {
    throw "aaa"
}

function b () {
    a
}

function c () { 
    b
}

try { 
    c
}
catch {
    "failed"
}