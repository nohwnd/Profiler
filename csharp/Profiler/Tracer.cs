using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Management.Automation.Language;
using System.Reflection;
using System.Security;
using NonGeneric = System.Collections;

namespace Profiler
{
    public static class Tracer
    {
        private static Func<TraceLineInfo> GetTraceLineInfo;
        private static Action ResetUI;
        private static ITracer _tracer;

        public static ProfilerTracer Patch(int version, EngineIntrinsics context, PSHostUserInterface ui)
        {
            var tracer = new ProfilerTracer();
            Patch(version, context, ui, tracer);
            return tracer;
        }

        public static void Patch(int version, EngineIntrinsics context, PSHostUserInterface ui, ITracer tracer)
        {
            _tracer = tracer;

            var uiFieldName = version >= 7 ? "_externalUI" : "externalUI";
            // we get InternalHostUserInterface, grab external ui from that and replace it with ours
            var externalUIField = ui.GetType().GetField(uiFieldName, BindingFlags.Instance | BindingFlags.NonPublic);
            var externalUI = (PSHostUserInterface)externalUIField.GetValue(ui);

            // replace it with out patched up UI that writes to profiler on debug
            externalUIField.SetValue(ui, new TracerHostUI(externalUI, TraceLine));

            ResetUI = () =>
            {
                externalUIField.SetValue(ui, externalUI);
            };

            // getting MethodInfo of context._context.Debugger.TraceLine
            var bf = BindingFlags.NonPublic | BindingFlags.Instance;
            var contextInternal = context.GetType().GetField("_context", bf).GetValue(context);
            var debugger = contextInternal.GetType().GetProperty("Debugger", bf).GetValue(contextInternal);
            var debuggerType = debugger.GetType();

            var callStackField = debuggerType.GetField("_callStack", BindingFlags.Instance | BindingFlags.NonPublic);
            var _callStack = callStackField.GetValue(debugger);

            var callStackType = _callStack.GetType();

            var countBindingFlags = BindingFlags.Instance | BindingFlags.NonPublic;
            if (version == 3)
            {
                // in PowerShell 3 callstack is List<CallStackInfo> not a struct CallStackList 
                // Count is public property
                countBindingFlags = BindingFlags.Instance | BindingFlags.Public;
            }
            var countProperty = callStackType.GetProperty("Count", countBindingFlags);
            var getCount = countProperty.GetMethod;
            var empty = new object[0];
            var stack = callStackField.GetValue(debugger);
            var initialLevel = (int)getCount.Invoke(stack, empty);

            if (version == 3 || version == 4)
            {
                // we do the same operation as in the TraceLineAction below, but here 
                // we resolve the static things like types and properties, and then in the 
                // action we just use them to get the live data without the overhead of looking 
                // up properties all the time. This might be internally done in the reflection code
                // did not measure the impact, and it is probably done for us in the reflection api itself
                // in modern verisons of runtime
                var callStack1 = callStackField.GetValue(debugger);
                var callStackList1 = (NonGeneric.IList)callStack1;
                var level1 = callStackList1.Count - initialLevel;
                var last1 = callStackList1[callStackList1.Count - 1];
                var lastType = last1.GetType();
                var functionContextProperty = lastType.GetProperty("FunctionContext", BindingFlags.NonPublic | BindingFlags.Instance);
                var functionContext1 = functionContextProperty.GetValue(last1);
                var functionContextType = functionContext1.GetType();

                var scriptBlockField = functionContextType.GetField("_scriptBlock", BindingFlags.Instance | BindingFlags.NonPublic);
                var currentPositionProperty = functionContextType.GetProperty("CurrentPosition", BindingFlags.Instance | BindingFlags.NonPublic);

                var scriptBlock1 = (ScriptBlock)scriptBlockField.GetValue(functionContext1);
                var extent1 = (IScriptExtent)currentPositionProperty.GetValue(functionContext1);

                GetTraceLineInfo = () =>
                {
                    var callStack = callStackField.GetValue(debugger);
                    var callStackList = (NonGeneric.IList)callStack;
                    var level = callStackList.Count - initialLevel;
                    var last = callStackList[callStackList.Count - 1];
                    var functionContext = functionContextProperty.GetValue(last);

                    var scriptBlock = (ScriptBlock)scriptBlockField.GetValue(functionContext);
                    var extent = (IScriptExtent)currentPositionProperty.GetValue(functionContext);

                    return new TraceLineInfo(extent, scriptBlock, level);
                };
            }
            else
            {
                var lastFunctionContextMethod = callStackType.GetMethod("LastFunctionContext", BindingFlags.Instance | BindingFlags.NonPublic);

                object functionContext1 = lastFunctionContextMethod.Invoke(callStackField.GetValue(debugger), empty);
                var functionContextType = functionContext1.GetType();
                var scriptBlockField = functionContextType.GetField("_scriptBlock", BindingFlags.Instance | BindingFlags.NonPublic);
                var currentPositionProperty = functionContextType.GetProperty("CurrentPosition", BindingFlags.Instance | BindingFlags.NonPublic);

                var scriptBlock1 = (ScriptBlock)scriptBlockField.GetValue(functionContext1);
                var extent1 = (IScriptExtent)currentPositionProperty.GetValue(functionContext1);

                GetTraceLineInfo = () =>
                {
                    var callStack = callStackField.GetValue(debugger);
                    var level = (int)getCount.Invoke(callStack, empty) - initialLevel;
                    object functionContext = lastFunctionContextMethod.Invoke(callStack, empty);
                    var scriptBlock = (ScriptBlock)scriptBlockField.GetValue(functionContext);
                    var extent = (IScriptExtent)currentPositionProperty.GetValue(functionContext);

                    return new TraceLineInfo(extent, scriptBlock, level);
                };
            }

            // Add another event to the top apart from the scriptblock invocation
            // in Trace-ScriptInternal, this makes it more consistently work on first
            // run. Without this, the triggering line sometimes does not show up as 99.9%
            TraceLine();
        }

        public static void Unpatch()
        {
            // Add Set-PSDebug -Trace 0 event and also another one for the internal disable
            // this make first run more consistent for some reason
            TraceLine();
            TraceLine();
            ResetUI();
            _tracer = null;
        }

        // keeping this public so I can write easier repros when something goes wrong, 
        // in that case we just need to patch, trace and unpatch and if that works then 
        // maybe the UI host does not work
        public static void TraceLine()
        {
            var traceLineInfo = GetTraceLineInfo();
            _tracer.Trace(traceLineInfo);
        }
    }

    public interface ITracer
    {
        void Trace(TraceLineInfo traceLineInfo);
    }

    internal class TracerHostUI : PSHostUserInterface
    {
        private PSHostUserInterface _ui;
        private Action _trace;

        public TracerHostUI(PSHostUserInterface ui, Action trace)
        {
            _ui = ui;
            _trace = trace;
        }

        public override PSHostRawUserInterface RawUI => _ui.RawUI;

        public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> descriptions)
        {
            return _ui.Prompt(caption, message, descriptions);
        }

        public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice)
        {
            return _ui.PromptForChoice(caption, message, choices, defaultChoice);
        }

        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName)
        {
            return _ui.PromptForCredential(caption, message, userName, targetName);
        }

        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes allowedCredentialTypes, PSCredentialUIOptions options)
        {
            return _ui.PromptForCredential(caption, message, userName, targetName, allowedCredentialTypes, options);
        }

        public override string ReadLine()
        {
            return _ui.ReadLine();
        }

        public override SecureString ReadLineAsSecureString()
        {
            return _ui.ReadLineAsSecureString();
        }

        public override void Write(string value)
        {
            _ui.Write(value);
        }

        public override void Write(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value)
        {
            _ui.Write(foregroundColor, backgroundColor, value);
        }

        public override void WriteDebugLine(string message)
        {
            if (_trace == null)
                _ui.WriteDebugLine(message);

            _trace();
        }

        public override void WriteErrorLine(string value)
        {
            _ui.WriteErrorLine(value);
        }

        public override void WriteLine(string value)
        {
            _ui.WriteLine(value);
        }

        public override void WriteProgress(long sourceId, ProgressRecord record)
        {
            _ui.WriteProgress(sourceId, record);
        }

        public override void WriteVerboseLine(string message)
        {
            _ui.WriteVerboseLine(message);
        }

        public override void WriteWarningLine(string message)
        {
            _ui.WriteWarningLine(message);
        }
    }

    public struct TraceLineInfo
    {
        public IScriptExtent Extent;
        public ScriptBlock ScriptBlock;
        public int Level;

        public TraceLineInfo(IScriptExtent extent, ScriptBlock scriptBlock, int level)
        {
            Extent = extent;
            ScriptBlock = scriptBlock;
            Level = level;
        }
    }

    public class ProfilerTracer : ITracer
    {
        // timespan ticks are 10k per millisecond, but the stopwatch can have different resolution
        // calculate the diff betwen the timestamps and convert it to 10k per ms ticks
        private static double _tickDivider = Stopwatch.Frequency / TimeSpan.TicksPerSecond;
        internal int _index = 0;
        internal ProfileEventRecord _previousHit;

        public List<ProfileEventRecord> Hits { get; } = new List<ProfileEventRecord>();
        public Dictionary<Guid, ScriptBlock> ScriptBlocks { get; } = new Dictionary<Guid, ScriptBlock>();
        public Dictionary<string, ScriptBlock> FileScriptBlocks { get; } = new Dictionary<string, ScriptBlock>();

        public void Trace(TraceLineInfo traceLineInfo)
        {
            var scriptBlock = traceLineInfo.ScriptBlock;
            var extent = traceLineInfo.Extent;
            var level = traceLineInfo.Level;

            var timestamp = (long)(Stopwatch.GetTimestamp() / _tickDivider);
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


#if !POWERSHELL3
            if (!ScriptBlocks.ContainsKey(scriptBlock.Id))
            {
                ScriptBlocks.Add(scriptBlock.Id, scriptBlock);
            }
#else
            if (!string.IsNullOrEmpty(scriptBlock.File))
            {
                var key = $"{scriptBlock.File}:{scriptBlock.StartPosition.StartLine}:{scriptBlock.StartPosition.StartColumn}";
                if (!FileScriptBlocks.ContainsKey(scriptBlock.File))
                {
                    FileScriptBlocks.Add(scriptBlock.File, scriptBlock);
                }
      }          
#endif

            // overwrite the previous event because we already scraped it
            _previousHit = new ProfileEventRecord();
            _previousHit.StartTime = TimeSpan.FromTicks(timestamp);
            _previousHit.Index = _index;
            _previousHit.IsInFile = !string.IsNullOrWhiteSpace(extent.File);
# if !POWERSHELL3
            _previousHit.ScriptBlockId = scriptBlock.Id;
# endif
            _previousHit.Extent = new ScriptExtentEventData
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
            _previousHit.Level = level;

            _index++;
        }

        private void SetSelfDurationAndAddToHits(ref ProfileEventRecord eventRecord, long timestamp)
        {
            eventRecord.SelfDuration = TimeSpan.FromTicks(timestamp - eventRecord.Timestamp);
            Hits.Add(eventRecord);
        }
    }
}
