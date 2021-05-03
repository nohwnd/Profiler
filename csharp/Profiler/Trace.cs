using System;
using System.Collections.Generic;

namespace Profiler
{
    /// <summary>
    /// Trace-Script output type.
    /// </summary>
    public class Trace
    {
        public Profiler.LineProfile[] Top50Duration { get; set; }
        public Profiler.LineProfile[] Top50Average { get; set; }
        public Profiler.LineProfile[] Top50HitCount { get; set; }
        public Profiler.LineProfile[] Top50SelfDuration { get; set; }
        public Profiler.LineProfile[] Top50SelfAverage { get; set; }
        public TimeSpan TotalDuration { get; set; }
        public TimeSpan StopwatchDuration { get; set; }
        public Profiler.LineProfile[] AllLines { get; set; }
        public List<ProfileEventRecord> Events { get; set; }
    }
}
