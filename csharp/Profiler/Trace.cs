using System;
using System.Collections.Generic;

namespace Profiler
{
    /// <summary>
    /// Trace-Script output type.
    /// </summary>
    public class Trace
    {
        public DurationView[] Top50Duration { get; set; }
        public HitCountView[] Top50HitCount { get; set; }
        public SelfDurationView[] Top50SelfDuration { get; set; }

        public FunctionDurationView[] Top50FunctionDuration { get; set; }
        public FunctionHitCountView[] Top50FunctionHitCount { get; set; }
        public FunctionSelfDurationView[] Top50FunctionSelfDuration { get; set; }

        public TimeSpan TotalDuration { get; set; }
        public TimeSpan StopwatchDuration { get; set; }
        public LineProfile[] AllLines { get; set; }
        public List<Hit> Events { get; set; }
    }
}
