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
        //
        // cast the frequency to double to avoid whole number division. On systems where frequency 
        // is smaller than ticks per second this otherwise results in 0, and all timestamps then
        // become positive infininty becaue of timestamp / 0 = ∞ or when cast to long: -9223372036854775808
        private static double _tickDivider = ((double)Stopwatch.Frequency) / TimeSpan.TicksPerSecond;
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
            var timestampRaw = Stopwatch.GetTimestamp();
            // usually 1 on Windows Desktop, 100 on *nix, but can be anything on some server systems like some Windows Server 2016
            long timestamp = _tickDivider == 1
                ? timestampRaw
                : _tickDivider == 100
                    ? timestampRaw / 100
                    : (long)(timestampRaw / _tickDivider);
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

    public class CodeCoverageTracer : ITracer
    {
        public CodeCoverageTracer(List<CodeCoveragePoint> points)
        {
            foreach (var point in points)
            {
                var key = $"{point.Line}:{point.Column}";
                if (!Hits.ContainsKey(point.Path))
                {
                    var lineColumn = new Dictionary<string, CodeCoveragePoint> { [key] = point };
                    Hits.Add(point.Path, lineColumn);
                    continue;
                }

                var hits = Hits[point.Path];
                if (!hits.ContainsKey(key))
                {
                    hits.Add(key, point);
                    continue;
                }
                
                // if the key is there do nothing, we already set it to false
            }
        }

        // list of what Pester figures out from the AST that we care about for CC
        // keyed as path -> line:column -> bool
        public Dictionary<string, Dictionary<string, CodeCoveragePoint>> Hits { get; } = new Dictionary<string, Dictionary<string, CodeCoveragePoint>>();

        public void Trace(TraceLineInfo traceLineInfo)
        {
            // ignore unbound scriptblocks
            if (traceLineInfo.Extent?.File == null)
                return;

               // Console.WriteLine($"{traceLineInfo.Extent.File}:{traceLineInfo.Extent.StartLineNumber}:{traceLineInfo.Extent.StartColumnNumber}:{traceLineInfo.Extent.Text}");
            if (!Hits.TryGetValue(traceLineInfo.Extent.File, out var lineColumn))
                return;

            var key2 = $"{traceLineInfo.Extent.StartLineNumber}:{traceLineInfo.Extent.StartColumnNumber}";
            if (!lineColumn.ContainsKey(key2))
                return;

            
            var point = lineColumn[key2];
            if (point.Hit == true)
                return;

            point.Hit = true;
            point.Text = traceLineInfo.Extent.Text;
            
            lineColumn[key2] = point;
        }
    }

    public struct CodeCoveragePoint
    {
        public CodeCoveragePoint (string path, int line, int column, int bpColumn, string astText)
        {
            Path = path;
            Line = line;
            Column = column;
            BpColumn = bpColumn;
            AstText = astText;

            // those are not for users to set,
            // we use them to make CC output easier to debug
            // because this will show in list of hits what we think
            // should or should not hit, for performance just bool 
            // would be enough
            Text = default;
            Hit = false;
        }

        public int Line;
        public int Column;
        public int BpColumn;
        public string Path;
        public string AstText;

        // those are not for users to set,
        // we use them to make CC output easier to debug
        // because this will show in list of hits what we think
        // should or should not hit, for performance just bool 
        // would be enough
        public string Text;
        public bool Hit;

        public override string ToString()
        {
            return $"{Hit}:'{AstText}':{Line}:{Column}:{Path}";
        }
    }
}
