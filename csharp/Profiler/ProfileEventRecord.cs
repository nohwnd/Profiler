using System;

namespace Profiler
{

    /// <summary>
    /// Measure-ScriptBlock output type.
    /// </summary>
    public struct ProfileEventRecord
    {
        /// <summary>
        /// StartTime of event.
        /// </summary>
        public TimeSpan StartTime;

        /// <summary>
        /// Duration of event.
        /// </summary>
        public TimeSpan Duration;
        public TimeSpan CallDuration;

        /// <summary>
        /// Script text.
        /// </summary>
        public string Source;

        /// <summary>
        /// Script Extent.
        /// </summary>
        public ScriptExtentEventData Extent;

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

        // adapting to unified format
        public string Path => Extent.File;
        public int Line => Extent.StartLineNumber;
        public int Column => Extent.StartColumnNumber;
        public string Text => Extent.Text;
        public long Timestamp => StartTime.Ticks;

        public int Level;

        public CallReturnProcess Flow;

        public int ReturnIndex;
    }

    public enum CallReturnProcess
    {
        Process = 0,
        Call,
        Return,
    }
}
