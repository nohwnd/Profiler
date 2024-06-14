namespace Profiler.SpeedScope;

public class SpeedScopeEvent
{
    public decimal At { get; internal set; }
    public int Frame { get; internal set; }
    public string Type { get; internal set; }
}
