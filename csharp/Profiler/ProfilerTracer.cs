using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Diagnostics.Tracing;
using System.Management.Automation;
using System.Management.Automation.Language;

namespace Profiler;

[EventSource(Name = "Profiler")]
public class ProfilerEventSource : EventSource
{
    private ProfilerEventSource() { }

    public void WriteStart(int index, string functionName, string text)
    {
        WriteEvent(1, index, AsNonNull(functionName), Max100Chars(text));
    }

    public void WriteStop(int index, string functionName, string text)
    {
        WriteEvent(2, index, AsNonNull(functionName), Max100Chars(text));
    }

    public static ProfilerEventSource Log { get; } = new ProfilerEventSource();

    private static string AsNonNull(string functionName)
    {
        return functionName ?? string.Empty;
    }

    private static string Max100Chars(string text)
    {
        text = AsNonNull(text);
        if (text.Length > 100)
        {
            return text.Substring(0, 100);
        }

        return text;
    }
}

public class ProfilerTracer : ITracer
{
    // timespan ticks are 10k per millisecond, but the stopwatch can have different resolution
    // calculate the diff between the timestamps and convert it to 10k per ms ticks
    //
    // cast the frequency to double to avoid whole number division. On systems where frequency 
    // is smaller than ticks per second this otherwise results in 0, and all timestamps then
    // become positive infinity because of timestamp / 0 = ∞ or when cast to long: -9223372036854775808
    private static double _tickDivider = ((double)Stopwatch.Frequency) / TimeSpan.TicksPerSecond;
    private const string ScriptBlockName = "<ScriptBlock>";
    internal int _index = 0;
    internal Hit _previousHit;

    public List<Hit> Hits { get; } = new List<Hit>();
    public Dictionary<Guid, ScriptBlock> ScriptBlocks { get; } = new Dictionary<Guid, ScriptBlock>();
    public Dictionary<string, ScriptBlock> FileScriptBlocks { get; } = new Dictionary<string, ScriptBlock>();

    public void Trace(string _, IScriptExtent extent, ScriptBlock scriptBlock, int level, string functionName, string moduleName)
    {
        var timestampRaw = Stopwatch.GetTimestamp();
        // usually 1 on Windows Desktop, 100 on *nix, but can be anything on some server systems like some Windows Server 2016
        long timestamp = _tickDivider == 1
            ? timestampRaw
            : _tickDivider == 100
                ? timestampRaw / 100
                : (long)(timestampRaw / _tickDivider);

        var workingSet = Environment.WorkingSet;
        var heapSize = GC.GetTotalMemory(false);
        var gc0 = GC.CollectionCount(0);
        var gc1 = GC.CollectionCount(1);
        var gc2 = GC.CollectionCount(2);

#if NET5_0_OR_GREATER
        var allocatedBytes = GC.GetTotalAllocatedBytes(precise: false);
#else
        var allocatedBytes = GC.GetTotalMemory(forceFullCollection: false);
#endif

        // we are using structs so we need to insert the final struct to the 
        // list instead of inserting it to the list, and keeping reference to modify it later
        // so when we are on second event (index 1) we modify the first (index 0) with the correct
        // SelfDuration (start of index 0 until start of index 1 = SelfDuration of index 0) and then add it to 
        // the final list
        // We need to do the same when unpatching to get the last event
        if (_index > 0)
        {
            SetSelfValuesAndAddToHits(ref _previousHit, timestamp, workingSet, heapSize, allocatedBytes, gc0, gc1, gc2);
            ProfilerEventSource.Log.WriteStop(_previousHit.Index, _previousHit.Function, _previousHit.Text);
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
#if !POWERSHELL3
        _previousHit.ScriptBlockId = scriptBlock.Id;
#endif
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

        _previousHit.Module = moduleName;
        _previousHit.Function = functionName != ScriptBlockName ? functionName : null;
        _previousHit.Level = level;

        _previousHit.WorkingSet = workingSet;
        _previousHit.HeapSize = heapSize;
        _previousHit.AllocatedBytes = allocatedBytes;

        _previousHit.Gc0 = gc0;
        _previousHit.Gc1 = gc1;
        _previousHit.Gc2 = gc2;

        _index++;
        ProfilerEventSource.Log.WriteStart(_previousHit.Index, _previousHit.Function, _previousHit.Text);
    }

    private void SetSelfValuesAndAddToHits(ref Hit eventRecord, long timestamp,
        long workingSet, long heapSize, long allocatedBytes,
        int gc0, int gc1, int gc2)
    {
        eventRecord.SelfWorkingSet = workingSet - eventRecord.WorkingSet;
        eventRecord.SelfHeapSize = heapSize - eventRecord.HeapSize;
        eventRecord.SelfAllocatedBytes = allocatedBytes - eventRecord.AllocatedBytes;
        eventRecord.SelfDuration = TimeSpan.FromTicks(timestamp - eventRecord.Timestamp);
        eventRecord.SelfGc0 = gc0 - eventRecord.Gc0;
        eventRecord.SelfGc1 = gc1 - eventRecord.Gc1;
        eventRecord.SelfGc2 = gc2 - eventRecord.Gc2;
        Hits.Add(eventRecord);
    }
}
