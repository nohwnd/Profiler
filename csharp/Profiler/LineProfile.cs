using System;
using System.Collections.Generic;

namespace Profiler
{
    /// <summary>
    /// Represents a profiled line.
    /// </summary>
    public class LineProfile
    {
        /// <summary>
        /// Percent of total duration used by line and all the code it calls.
        /// </summary>
        public double Percent { get; set; } = 0.00;

        /// <summary>
        /// Percent of total duration used by line.
        /// </summary>
        public double SelfPercent { get; set; } = 0.00;

        /// <summary>
        /// Number of hits on line.
        /// </summary>
        public uint HitCount { get; set; } = 0;

        /// <summary>
        /// Time used by line including subcalls.
        /// </summary>
        public TimeSpan Duration { get; set; } = TimeSpan.Zero;

        /// <summary>
        /// Time used exclusively by this line.
        /// </summary>
        public TimeSpan SelfDuration { get; set; } = TimeSpan.Zero;

        /// <summary>
        /// Name of file or id of scriptblock the line belongs to.
        /// </summary>
        public string Name { get; set; }

        /// <summary>
        /// Line number in the file or scriptblock.
        /// </summary>
        public uint Line { get; set; }

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
        /// Absolute path of file or id of scriptblock the line belongs to.
        /// </summary>
        public string Path { get; set; }

        /// <summary>
        /// Average of duration for all hits.
        /// </summary>
        public TimeSpan Average { get; set; } = TimeSpan.Zero;

        /// <summary>
        /// Average of SelfDuration for all hits.
        /// </summary>
        public TimeSpan SelfAverage { get; set; } = TimeSpan.Zero;

        /// <summary>
        /// Event records for all hits to the line.
        /// </summary>
        public ICollection<Hit> Hits { get; set; } = new List<Hit>();

        /// <summary>
        /// All command hits in this line using column as key.
        /// </summary>
        public IDictionary<uint, CommandHit> CommandHits { get; set; } = new Dictionary<uint, CommandHit>();
    }
}
