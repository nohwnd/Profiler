using System;
using System.Collections.Generic;

namespace Profiler
{
    /// <summary>
    /// Trace-Script output type.
    /// </summary>
    public class Trace
    {
        public LineProfile[] Top50Duration { get; set; }
        public LineProfile[] Top50Average { get; set; }
        public LineProfile[] Top50HitCount { get; set; }
        public LineProfile[] Top50SelfDuration { get; set; }
        public LineProfile[] Top50SelfAverage { get; set; }
        public TimeSpan TotalDuration { get; set; }
        public TimeSpan StopwatchDuration { get; set; }
        public LineProfile[] AllLines { get; set; }
        public List<Hit> Events { get; set; }
    }
}
