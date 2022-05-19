﻿using System.Management.Automation;
using System.Management.Automation.Language;

namespace Profiler
{
    public interface ITracer
    {
        void Trace(IScriptExtent extent, ScriptBlock scriptBlock, int level, string functionName, string moduleName);
    }
}
