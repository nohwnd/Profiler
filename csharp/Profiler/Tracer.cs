using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Management.Automation.Language;
using System.Reflection;
using System.Security;
using System.Threading;
using Debugger = System.Diagnostics.Debugger;

namespace Profiler
{
    public static class Tracer
    {
        internal static ProfileEventRecord _previousHit;
        internal static int _index = 0;
        private static PSHostUserInterface _ui;
        private static FieldInfo _externalUIField;
        private static PSHostUserInterface _externalUI;
        public static Action TraceLine;

        public static List<ProfileEventRecord> Hits { get; } = new List<ProfileEventRecord>();
        public static Dictionary<Guid, ScriptBlock> UnboundScriptBlocks { get; } = new Dictionary<Guid, ScriptBlock>();
        public static Dictionary<string, ScriptBlock> FileScriptBlocks { get; } = new Dictionary<string, ScriptBlock>();

        public static void Patch(EngineIntrinsics context, PSHostUserInterface ui)
        {
            Clear();

            _ui = ui;
            // we get InternalHostUserInterface, grab external ui from that and replace it with ours
            _externalUIField = ui.GetType().GetField("_externalUI", BindingFlags.Instance | BindingFlags.NonPublic);
            _externalUI = (PSHostUserInterface)_externalUIField.GetValue(ui);

            // replace it with out patched up UI that writes to profiler on debug
            _externalUIField.SetValue(ui, new ProfilerUI(_externalUI));

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

            var lastFunctionContextMethod = callStackType.GetMethod("LastFunctionContext", BindingFlags.Instance | BindingFlags.NonPublic);

            object functionContext1 = lastFunctionContextMethod.Invoke(callStackField.GetValue(debugger), empty);
            var functionContextType = functionContext1.GetType();
            var scriptBlockField = functionContextType.GetField("_scriptBlock", BindingFlags.Instance | BindingFlags.NonPublic);
            var currentPositionProperty = functionContextType.GetProperty("CurrentPosition", BindingFlags.Instance | BindingFlags.NonPublic);

            var scriptBlock1 = (ScriptBlock)scriptBlockField.GetValue(functionContext1);
            var extent1 = (IScriptExtent)currentPositionProperty.GetValue(functionContext1);

            TraceLine = () =>
            {
                var callStack = callStackField.GetValue(debugger);
                var level = (int)getCount.Invoke(callStack, empty) - initialLevel;
                object functionContext = lastFunctionContextMethod.Invoke(callStack, empty);
                var scriptBlock = (ScriptBlock)scriptBlockField.GetValue(functionContext);
                var extent = (IScriptExtent)currentPositionProperty.GetValue(functionContext);

                Trace(extent, scriptBlock, level);
                // Set-PSDebug -Trace 1 is no longer automatically logged for some reason,
                // but we get the & $ScriptBlock like our first event
            };
        }

        public static void Clear()
        {
            Hits.Clear();
            UnboundScriptBlocks.Clear();
            FileScriptBlocks.Clear();
            _index = 0;
            _previousHit = default;
        }

        public static void Unpatch()
        {
            TraceLine();
            _externalUIField.SetValue(_ui, _externalUI);
        }

        public static void Trace(IScriptExtent extent, ScriptBlock scriptBlock, int level)
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

            if (string.IsNullOrEmpty(scriptBlock.File))
            {
                if (!UnboundScriptBlocks.ContainsKey(scriptBlock.Id))
                {
                    UnboundScriptBlocks.Add(scriptBlock.Id, scriptBlock);
                }
            }
            else
            {
                if (!FileScriptBlocks.ContainsKey(scriptBlock.File))
                {
                    FileScriptBlocks.Add(scriptBlock.File, scriptBlock);
                }
            }

            // overwrite the previous event because we already scraped it
            Tracer._previousHit = new ProfileEventRecord();
            Tracer._previousHit.StartTime = TimeSpan.FromTicks(timestamp);
            Tracer._previousHit.Index = _index;
            Tracer._previousHit.IsInFile = !string.IsNullOrWhiteSpace(extent.File);
            Tracer._previousHit.ScriptBlockId = scriptBlock.Id;
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
            Tracer._previousHit.Level = level;

            _index++;
        }

        private static void SetSelfDurationAndAddToHits(ref ProfileEventRecord eventRecord, long timestamp)
        {
            eventRecord.SelfDuration = TimeSpan.FromTicks(timestamp - eventRecord.Timestamp);
            Tracer.Hits.Add(eventRecord);
        }
    }

    internal class ProfilerUI : PSHostUserInterface
    {
        private PSHostUserInterface _ui;

        public ProfilerUI(PSHostUserInterface ui)
        {
            _ui = ui;
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

            // _ui.WriteDebugLine(message);
            Tracer.TraceLine();
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
