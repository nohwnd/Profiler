﻿using System;

namespace Profiler;

/// <summary>
/// Measure-ScriptBlock output type.
/// </summary>
public struct Hit
{
    /// <summary>
    /// StartTime of event.
    /// </summary>
    public TimeSpan StartTime;

    /// <summary>
    /// SelfDuration of event.
    /// </summary>
    public TimeSpan SelfDuration;
    public TimeSpan Duration;

    /// <summary>
    /// Script text.
    /// </summary>
    public string Source;

    /// <summary>
    /// Script Extent.
    /// </summary>
    public ScriptExtent Extent;

    /// <summary>
    /// Unique identifier of the runspace.
    /// </summary>
    public Guid RunspaceId;

    /// <summary>
    /// Unique identifier of the parent script block.
    /// </summary>
    public Guid ParentScriptBlockId;

    /// <summary>
    /// Unique identifier of the script block.
    /// </summary>
    public Guid ScriptBlockId;

    // profiler specific fields
    public int Index;
    public TimeSpan Overhead;

    // extent file might be empty when we are in unsaved ScriptBlock
    // this is set when creating the struct
    public bool IsInFile;


    // adapting to unified format
    public string Path => Extent.File;
    public int Line => Extent.StartLineNumber;
    public int Column => Extent.StartColumnNumber;
    public string Text => Extent.Text;
    public long Timestamp => StartTime.Ticks;

    public string Group;

    /// <summary>
    /// The function name that is on top of stack.
    /// </summary>
    public string Function;

    /// <summary>
    /// The module name where that function is coming from.
    /// </summary>
    public string Module;

    /// <summary>
    /// How deep we are in the call stack.
    /// </summary>
    public int Level;

    public Flow Flow;

    // where we returned if we are a call, otherwise our own index
    public int ReturnIndex;
    // who called us
    public int CallerIndex;

    public bool Folded;

    // HeapSize at the start of the hit in MB.
    public decimal HeapSize;

    // WorkingSet at the start of the hit in MB.
    public decimal WorkingSet;

    // HeapSize heapSize consumed by the hit (endHeapSize - startHeapSize) in MB.
    public decimal SelfHeapSize;

    // Working set consumed by the hit in MB.
    public decimal SelfWorkingSet;

    // Working set consumed by the hit in MB.
    public decimal AllocatedBytes;

    // Bytes allocated by this hit in MB.
    public decimal SelfAllocatedBytes;

    public int Gc0;
    public int SelfGc0;

    public int Gc1;
    public int SelfGc1;

    public int Gc2;
    public int SelfGc2;


    public decimal TotalBytes;
    public int  TotalGc;
}
