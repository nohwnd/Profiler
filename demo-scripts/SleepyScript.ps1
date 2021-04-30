function a () { 
   Start-Sleep -Milliseconds 100
}

function b () { 
    a
}

function c () {
    a
    b
}

c