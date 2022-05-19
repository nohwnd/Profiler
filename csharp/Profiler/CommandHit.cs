using System;

namespace Profiler
{
    /// <summary>
    /// Represents a command hit on a line
    /// </summary>
    public class CommandHit
    {
        /// <summary>
        /// Line number of the command in the file or scriptblock.
        /// </summary>
        public uint Line { get; set; }

        /// <summary>
        /// Column of the command in the file or scriptblock.
        /// </summary>
        public uint Column { get; set; }

        /// <summary>
        /// Number of hits on command.
        /// </summary>
        public uint HitCount { get; set; } = 1;

        /// <summary>
        /// Time used exclusively by this command
        /// </summary>
        public TimeSpan SelfDuration { get; set; }

        /// <summary>
        /// Command text.
        /// </summary>
        public string Text { get; set; }

        public CommandHit(Hit hit)
        {
            Line         = (uint)hit.Line;
            Column       = (uint)hit.Column;
            SelfDuration = hit.SelfDuration;
            Text         = hit.Text;
        }

        public override string ToString() {
            return $"Profiler.CommandHit: Line={this.Line}; Column={this.Column}; HitCount={this.HitCount}; SelfDuration={this.SelfDuration}; Text='{this.Text}'";
        }
    }
}
