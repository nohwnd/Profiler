namespace Profiler
{
    /// <summary>
    /// Represents a span of text in a script.
    /// </summary>
    public struct ScriptExtent
    {
        /// <summary>
        /// The filename the extent includes, or null if the extent is not included in any file.
        /// </summary>
        public string File;

        /// <summary>
        /// The line number at the beginning of the extent, with the value 1 being the first line.
        /// </summary>
        public int StartLineNumber;

        /// <summary>
        /// The column number at the beginning of the extent, with the value 1 being the first column.
        /// </summary>
        public int StartColumnNumber;

        /// <summary>
        /// The line number at the end of the extent, with the value 1 being the first line.
        /// </summary>
        public int EndLineNumber;

        /// <summary>
        /// The column number at the end of the extent, with the value 1 being the first column.
        /// </summary>
        public int EndColumnNumber;

        /// <summary>
        /// The script text that the extent includes.
        /// </summary>
        public string Text;

        /// <summary>
        /// The starting offset of the extent.
        /// </summary>
        public int StartOffset;

        /// <summary>
        /// The ending offset of the extent.
        /// </summary>
        public int EndOffset;
    }
}
