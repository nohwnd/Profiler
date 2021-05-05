using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Management.Automation;

namespace Profiler
{
    public class ProfilerTracer : ITracer
    {
        // timespan ticks are 10k per millisecond, but the stopwatch can have different resolution
        // calculate the diff betwen the timestamps and convert it to 10k per ms ticks
        private static double _tickDivider = Stopwatch.Frequency / TimeSpan.TicksPerSecond;
        internal int _index = 0;
        internal Hit _previousHit;

        public List<Hit> Hits { get; } = new List<Hit>();
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
            _previousHit = new Hit();
            _previousHit.StartTime = TimeSpan.FromTicks(timestamp);
            _previousHit.Index = _index;
            _previousHit.IsInFile = !string.IsNullOrWhiteSpace(extent.File);
# if !POWERSHELL3
            _previousHit.ScriptBlockId = scriptBlock.Id;
# endif
            _previousHit.Extent = new ScriptExtent
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

        private void SetSelfDurationAndAddToHits(ref Hit eventRecord, long timestamp)
        {
            eventRecord.SelfDuration = TimeSpan.FromTicks(timestamp - eventRecord.Timestamp);
            Hits.Add(eventRecord);
        }
    }
}
