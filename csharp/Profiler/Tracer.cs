
using HarmonyLib;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Reflection;
using System.Threading;
using Debugger = System.Diagnostics.Debugger;

namespace Profiler
{
    public static class Tracer
    {
        internal static ProfileEventRecord _previousHit;
        internal static int _index = 0;
        private static PropertyInfo _currentPositionProperty;
        private static Func<int> GetLevel;

        public static List<ProfileEventRecord> Hits { get; } = new List<ProfileEventRecord>();

        public static void PatchOrUnpatch(EngineIntrinsics context, bool patch, bool useBp)
        {
            Dbg.WaitForDebugger();

            if (patch)
            {
                _previousHit = default;
                _index = 0;
                Hits.Clear();
            }

            if (!patch)
            {
                SetSelfDurationAndAddToHits(ref _previousHit, Stopwatch.GetTimestamp());
            }

            Harmony harmony = new Harmony("fix.debugger");

            if (patch)
            {
                // getting MethodInfo of context._context.Debugger.TraceLine
                var bf = BindingFlags.NonPublic | BindingFlags.Instance;
                var contextInternal = context.GetType().GetField("_context", bf).GetValue(context);
                var debugger = contextInternal.GetType().GetProperty("Debugger", bf).GetValue(contextInternal);
                var debuggerType = debugger.GetType();

                var callStackField = debuggerType.GetField("_callStack", BindingFlags.Instance | BindingFlags.NonPublic);
                var _callStack = callStackField.GetValue(debugger);

                var callStackType = _callStack.GetType();

                var countProperty = callStackType.GetProperty("Count", BindingFlags.Instance | BindingFlags.NonPublic);
                var getCount = countProperty.GetMethod;
                var empty = new object[0];
                var stack = callStackField.GetValue(debugger);
                var initialLevel = (int)getCount.Invoke(stack, empty);
                GetLevel = () => { return (int)getCount.Invoke(callStackField.GetValue(debugger), empty) - initialLevel; };


                if (!useBp)
                {
                    BindingFlags bindingAttr = BindingFlags.Instance | BindingFlags.NonPublic;
                    object obj = context.GetType().GetField("_context", bindingAttr).GetValue((object)context);
                    MethodInfo traceLineInPowerShell = debuggerType.GetMethod("TraceLine", bindingAttr);
                    MethodInfo traceLinePatch = typeof(Tracer).GetMethod("TraceLine", BindingFlags.Static | BindingFlags.Public);

                    harmony.Patch((MethodBase)traceLineInPowerShell, new HarmonyMethod(traceLinePatch));
                }
                else
                {
                    var setPendingBreakpointsInPowerShell = debuggerType.GetMethod(nameof(SetPendingBreakpoints), bf);
                    var setPendingBreakpointsPatch = typeof(Tracer).GetMethod(nameof(SetPendingBreakpoints), BindingFlags.Static | BindingFlags.NonPublic);
                    harmony.Patch(setPendingBreakpointsInPowerShell, new HarmonyMethod(setPendingBreakpointsPatch));
                }
            }
            else
            {
                harmony.UnpatchAll();
            }
        }

        // this name needs to be the same as in powershell code don't rename it
        private static bool SetPendingBreakpoints(object functionContext)
        {

            if (_currentPositionProperty == null)
            {
                BindingFlags bindingAttr = BindingFlags.Instance | BindingFlags.NonPublic;
                _currentPositionProperty = functionContext.GetType().GetProperty("CurrentPosition", bindingAttr);
            }

            var extent = (IScriptExtent)_currentPositionProperty.GetValue(functionContext);
            Trace(extent);

            // skip
            return false;
        }

        // this name needs to be the same as in powershell code don't rename it
        public static bool TraceLine(IScriptExtent extent)
        {
            Trace(extent);

            //skip
            return false;
        }

        public static void Trace(IScriptExtent extent)
        {
            

            var timestamp = Stopwatch.GetTimestamp();
            // we are using structs so we need to insert the final struct to the 
            // list instead of inserting it to the list, and keeping reference to modify it later
            // so when we are on second event (index 1) we modify the first (index 0) with the correct
            // SelfDuration (start of index 0 until start of index 1 = SelfDuration of index 0) and then add it to 
            // the final list
            // We need to do the same when unpatching to get the last event
            if (_index > 0)
            {
                SetSelfDurationAndAddToHits(ref _previousHit, timestamp);
            }


            // overwrite the previous event because we already scraped it
            Tracer._previousHit = new ProfileEventRecord();
            Tracer._previousHit.StartTime = TimeSpan.FromTicks(timestamp);
            Tracer._previousHit.Index = _index;
            Tracer._previousHit.Extent = new ScriptExtentEventData
            {
                File = extent.File,
                StartLineNumber = extent.StartLineNumber,
                StartColumnNumber = extent.StartColumnNumber,
                EndLineNumber = extent.EndLineNumber,
                EndColumnNumber = extent.EndColumnNumber,
                Text = extent.Text,
                StartOffset = extent.StartOffset,
                EndOffset = extent.EndOffset,
            };
            Tracer._previousHit.Level = GetLevel();

            _index++;
        }

        private static void SetSelfDurationAndAddToHits(ref ProfileEventRecord eventRecord, long timestamp)
        {
            eventRecord.SelfDuration = TimeSpan.FromTicks(timestamp - eventRecord.Timestamp);
            Tracer.Hits.Add(eventRecord);
        }
    }

    internal static class Dbg
    {
        static bool _triggered = false;

        public static void WaitForDebugger()
        {
            if (_triggered)
                return;

            var debug = Environment.GetEnvironmentVariable("PROFILER_DEBUG")?.ToLowerInvariant();
            if (!new[] { "on", "yes", "true", "1" }.Contains(debug))
                return;

            while (!Debugger.IsAttached)
            {
                var process = Process.GetCurrentProcess();
                Console.WriteLine($"Waiting for debugger {process.Id} - {process.ProcessName}");
                Thread.Sleep(1000);
            }

            _triggered = true;
            Debugger.Break();
        }
    }
}
