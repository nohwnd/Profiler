using System;
using System.Collections.Generic;

namespace Profiler;

/// <summary>
/// Represents a profiled line.
/// </summary>
public class LineProfile
{
    /// <summary>
    /// Percent of total duration used by line including all the code it calls.
    /// </summary>
    public double Percent { get; set; } = 0.00;

    /// <summary>
    /// Time used by line including subcalls.
    /// </summary>
    public TimeSpan Duration { get; set; } = TimeSpan.Zero;


    /// <summary>
    /// Percent of total duration used by line, excluding the code it calls.
    /// </summary>
    public double SelfPercent { get; set; } = 0.00;

    /// <summary>
    /// Time used exclusively by this line.
    /// </summary>
    public TimeSpan SelfDuration { get; set; } = TimeSpan.Zero;


    /// <summary>
    /// Percent of total memory used by line including all the code it calls.
    /// </summary>
    public double MemoryPercent { get; set; } = 0.00;

    /// <summary>
    /// Memory consumed by line and all subcalls.
    /// </summary>
    public long Memory { get; set; }

    /// <summary>
    /// Percent of total memory used by line, excluding the code it calls.
    /// </summary>
    public double SelfMemoryPercent { get; set; } = 0.00;

    /// <summary>
    /// Memory consumed exclusively by this line.
    /// </summary>
    public long SelfMemory { get; set; }

    /// <summary>
    /// Garbage collections happening on this line and in all subcalls (all generations).
    /// </summary>
    public int Gc { get; set; }

    /// <summary>
    /// Garbage collections happening on this line exclusively (all generations).
    /// </summary>
    public int SelfGc { get; set; }


    /// <summary>
    /// Number of hits on line.
    /// </summary>
    public uint HitCount { get; set; } = 0;

    /// <summary>
    /// Name of file or id of ScriptBlock the line belongs to.
    /// </summary>
    public string File { get; set; }

    /// <summary>
    /// Line number in the file or ScriptBlock.
    /// </summary>
    public uint? Line { get; set; }

    /// <summary>
    /// Function that called this line.
    /// </summary>
    public string Function { get; set; }

    /// <summary>
    /// Module that contains the function that called the line.
    /// </summary>
    public string Module { get; set; }

    /// <summary>
    /// Text of line.
    /// </summary>
    public string Text { get; set; }

    /// <summary>
    /// Absolute path of file or id of ScriptBlock the line belongs to.
    /// </summary>
    public string Path { get; set; }

    /// <summary>
    /// Event records for all hits to the line.
    /// </summary>
    public ICollection<Hit> Hits { get; set; } = new List<Hit>();

    /// <summary>
    /// All command hits in this line using column as key.
    /// </summary>
    public IDictionary<uint, CommandHit> CommandHits { get; set; } = new Dictionary<uint, CommandHit>();
}
