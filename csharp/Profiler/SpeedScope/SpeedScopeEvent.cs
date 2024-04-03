namespace Profiler.SpeedScope;

public class SpeedScopeEvent
{
    public double At { get; internal set; }
    public int Frame { get; internal set; }
    public string Type { get; internal set; }
}
