using System;
using System.Collections.Generic;

namespace Profiler;

/// <summary>
/// PowerShell formatting files distinguish the type of data by the real type, and they don't consider 
/// interfaces. I need multiple different views of the same data, without duplicating it too much,
/// e.g. when showing Top50SelfDuration I want SelfPercent and SelfDuration to be the first items,
/// but for Top50Duration I want Percent and Duration to be the first items. And I also don't want to remove
/// any of the properties from the object (e.g. by copying it to a new object type that has the correct order of 
/// properties.). Instead this class wraps LineProfile and delegates to all it's properties.
/// </summary>
/// <typeparam name="T"></typeparam>
public abstract class LineProfileView
{
    private LineProfile _line;

    public LineProfileView(LineProfile line)
    {
        _line = line;
    }

    /// <summary>
    /// Percent of total duration used by line including all the code it calls.
    /// </summary>
    public double Percent => _line.Percent;

    /// <summary>
    /// Time used by line including subcalls.
    /// </summary>
    public TimeSpan Duration => _line.Duration;


    /// <summary>
    /// Percent of total duration used by line, excluding the code it calls.
    /// </summary>
    public double SelfPercent => _line.SelfPercent;

    /// <summary>
    /// Time used exclusively by this line.
    /// </summary>
    public TimeSpan SelfDuration => _line.SelfDuration;

    /// <summary>
    /// Percent of total memory used by line including all the code it calls.
    /// </summary>
    public double MemoryPercent => _line.MemoryPercent;

    /// <summary>
    /// Memory used by this line.
    /// </summary>
    public long Memory => _line.Memory;

    /// <summary>
    /// Percent of total memory used by line.
    /// </summary>
    public double SelfMemoryPercent => _line.SelfMemoryPercent;

    /// <summary>
    /// Memory used exclusively by this line.
    /// </summary>
    public long SelfMemory => _line.SelfMemory;

    /// <summary>
    /// Garbage collection count that happened on this line.
    /// </summary>
    public long Gc => _line.Gc;

    /// <summary>
    /// Garbage collection count that happened exclusively on this line.
    /// </summary>
    public long SelfGc => _line.SelfGc;



    /// <summary>
    /// Number of hits on line.
    /// </summary>
    public uint HitCount => _line.HitCount;

    /// <summary>
    /// Name of file or id of ScriptBlock the line belongs to.
    /// </summary>
    public string File => _line.File;

    /// <summary>
    /// Line number in the file or ScriptBlock.
    /// </summary>
    public uint? Line => _line.Line;

    /// <summary>
    /// Function that called this line.
    /// </summary>
    public string Function => _line.Function;

    /// <summary>
    /// Module that contains the function that called the line.
    /// </summary>
    public string Module => _line.Module;

    /// <summary>
    /// Text of line.
    /// </summary>
    public string Text => _line.Text;

    /// <summary>
    /// Absolute path of file or id of ScriptBlock the line belongs to.
    /// </summary>
    public string Path => _line.Path;

    /// <summary>
    /// Event records for all hits to the line.
    /// </summary>
    public ICollection<Hit> Hits => _line.Hits;

    /// <summary>
    /// All command hits in this line using column as key.
    /// </summary>
    public IDictionary<uint, CommandHit> CommandHits => _line.CommandHits;
}
