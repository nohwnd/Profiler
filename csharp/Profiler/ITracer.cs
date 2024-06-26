﻿using System.Management.Automation;
using System.Management.Automation.Language;

# if PESTER
namespace Pester.Tracing;
#else
namespace Profiler;
#endif

public interface ITracer
{
    void Trace(string message, IScriptExtent extent, ScriptBlock scriptBlock, int level, string functionName, string moduleName);
}
