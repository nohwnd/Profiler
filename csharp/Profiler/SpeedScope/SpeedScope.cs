using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.CompilerServices;
using System.Text;

namespace Profiler.SpeedScope
{
    public class SpeedScope
    {
        private static Flow[] _justCall = new[] { Flow.Call };
        private static Flow[] _callAndReturn = new[] { Flow.Call, Flow.Return };
        private static JsonSerializer _jsonSerializer = new JsonSerializer
        {
            Formatting = Formatting.Indented,
            ContractResolver = new DefaultContractResolver
            {
                NamingStrategy = new CamelCaseNamingStrategy()
            }
        };

        public static string Export(string exporter, Trace trace, string directory, string name)
        {
            var report = Convert(exporter, trace, name);
            var path = Path.Combine(directory, name);
            using (StreamWriter fileStream = new StreamWriter(path)) {
                using (JsonWriter writer = new JsonTextWriter(fileStream))
                {
                    _jsonSerializer.Serialize(writer, report);
                }
            }

            return path;
        }


        public static SpeedScopeReport Convert(string exporter, Trace trace, string name)
        {
            var process = Process.GetCurrentProcess();

            ConvertEvents(trace, name, out List<SpeedScopeFrame> frames, out List<SpeedScopeEvent> events);

            var profile = new SpeedScopeProfile
            {
                Type = "evented",
                Name = $"{process.ProcessName} ({process.Id}) Time={Math.Round(trace.TotalDuration.TotalMilliseconds, 5)}ms",
                Unit = "milliseconds",
                StartValue = 0,
                EndValue = Math.Round(trace.Events[trace.Events.Count - 2].StartTime.TotalMilliseconds - trace.Events[2].StartTime.TotalMilliseconds, 5),
                Events = events
            };

            return new SpeedScopeReport
            {
                Exporter = exporter,
                Name = name,
                ActiveProfileIndex = 0,
                Schema = "https://www.speedscope.app/file-format-schema.json",
                Shared = new SpeedScopeShared
                {
                    Frames = frames
                },
                Profiles = new[]
                {
                    profile
                }
            };
        }

        private static void ConvertEvents(Trace trace, string name, out List<SpeedScopeFrame> frames, out List<SpeedScopeEvent> convertedEvents)
        {
            var events = trace.Events;

            // frame names are saved into shared section in the report re-used by events to make the file smaller
            // here we just hold onto the reference to the string so we can later render a list of frames into the report
            frames = new List<SpeedScopeFrame>(10000);

            // This helps us lookup the string faster, and stores the index in the frameStrings list
            // so the event knows on which index in the shared section the frame is
            var frameDictionary = new Dictionary<string, int>();
            convertedEvents = new List<SpeedScopeEvent>(events.Count);

            // the first 2 events are Profiler internals, third event is where the report really starts
            var start = events[2].StartTime;
            var callStack = new Stack<int>();

            // last 2 events are also Profiler internals.
            var lastValidIndex = events.Count - 3;

            foreach (var @event in events)
            {
                if (@event.Level == 0)
                {
                    // skip events that we produce directly from Profiler
                    continue;
                }

                // we mark the first event as Process, but the last one as Return, which tries to pop the call from the 
                // stack which is not there. Instead the last event should also be considered Process, because 
                // we ignore the next events.
                var patchedFlow = @event.Index != lastValidIndex ? @event.Flow : Flow.Process;

                var index = -1;

                // Add a pair of events for every Process and Return event so we can see them on the screen, and then 
                // and for Return additionaly record event for returning from the call
                var flows = patchedFlow == Flow.Call ? _justCall : _callAndReturn;

                foreach (var flow in flows)
                {
                    // when we Return, but we don't go just 1 level above (most often because of trow), we might have more calls on the
                    // call stack and need to emit all of them until we reach the current level.
                    // if the event is not Return we just record 1 event
                    var iterations = flow != Flow.Return ? 1 : callStack.Count - @event.Level +1;

                    for (var iteration = 0; iteration < iterations; iteration++)
                    {
                        if (flow == Flow.Call)
                        {
                            callStack.Push(@event.Index);
                        }

                        int callerIndex = 0;
                        if (flow == Flow.Return)
                        {
                            callerIndex = callStack.Pop();
                        }

                        // when we return we need to use the Text of who called us, because otherwise the event points to a different frame name
                        // and sppeed scope complains that we are leaving different frame than the one we intered
                        var keyEvent = flow == Flow.Call ? @event : events[callerIndex];
                        // This shows every line, with path, but we should probably rather fold into functions
                        // var fileMarker = keyEvent.IsInFile ? $"|{keyEvent.Path}:{keyEvent.Line}" : null;
                        // var key = $"{keyEvent.Text}{fileMarker}";
                        var key = keyEvent.FunctionName != "<ScriptBlock>" ? keyEvent.FunctionName : keyEvent.Text;

                        if (!frameDictionary.TryGetValue(key, out index))
                        {
                            // check the count first because indexing starts from 0
                            index = frames.Count;
                            frameDictionary.Add(key, index);
                            frames.Add(new SpeedScopeFrame
                            {
                                Name = key
                            });
                        }

                        // calls report start of the event relative to the start event, returns report start of the event + the self-duration of the event
                        var at = flow == Flow.Call ? @event.StartTime - start : @event.StartTime + @event.SelfDuration - start;
                        // O for open, that we call Call, and C for close that we call Return. Don't confuse with C for Call.
                        convertedEvents.Add(new SpeedScopeEvent
                        {
                            Type = flow == Flow.Call ? "O" : "C",
                            Frame = index,
                            At = Math.Round(at.TotalMilliseconds, 5),
                        });
                    }
                }
            }
        }
    }
}
