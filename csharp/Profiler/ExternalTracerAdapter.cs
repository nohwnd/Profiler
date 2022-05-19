﻿using System;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Reflection;

namespace Profiler
{
    class ExternalTracerAdapter : ITracer
    {
        private object _tracer;
        private MethodInfo _traceMethod;

        public ExternalTracerAdapter(object tracer)
        {
            _tracer = tracer ?? new NullReferenceException(nameof(tracer));
            var traceMethod = tracer.GetType().GetMethod("Trace", new Type[] { typeof(IScriptExtent), typeof(ScriptBlock), typeof(int), typeof(string) });
            _traceMethod = traceMethod ?? throw new InvalidOperationException("The provided tracer does not have Trace method with this signature: Trace(IScriptExtent extent, ScriptBlock scriptBlock, int level, string functionName)");
        }

        public void Trace(IScriptExtent extent, ScriptBlock scriptBlock, int level, string functionName, string moduleName)
        {
            _traceMethod.Invoke(_tracer, new object[] { extent, scriptBlock, level });
        }
    }
}
