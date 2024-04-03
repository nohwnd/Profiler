using System.Collections.Generic;

namespace Profiler;

public class File
{
    public string Path { get; internal set; }
    public string Name { get; internal set; }
    public Dictionary<int, LineProfile> Lines { get; internal set; }
}
