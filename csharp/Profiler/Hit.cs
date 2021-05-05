using System;

namespace Profiler
{
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
        /// Unique identifer of the runspace.
        /// </summary>
        public Guid RunspaceId;

        /// <summary>
        /// Unique identifer of the parent script block.
        /// </summary>
        public Guid ParentScriptBlockId;

        /// <summary>
        /// Unique identifer of the script block.
        /// </summary>
        public Guid ScriptBlockId;

        // profiler specific fields
        public long Index;
        public TimeSpan Overhead;

        // extent file might be empty when we are in unsaves scriptblock
        // this is set when creating the struct
        public bool IsInFile;


        // adapting to unified format
        public string Path => Extent.File;
        public int Line => Extent.StartLineNumber;
        public int Column => Extent.StartColumnNumber;
        public string Text => Extent.Text;
        public long Timestamp => StartTime.Ticks;

        public int Level;

        public Flow Flow;

        // where we returned if we are a call, otherwise our own index
        public int ReturnIndex;
        // who called us
        public int CallerIndex;
    }
}
