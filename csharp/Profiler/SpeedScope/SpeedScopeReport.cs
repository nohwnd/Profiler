namespace Profiler.SpeedScope;

public class SpeedScopeReport
{
    public string Exporter { get; set; }
    public string Name { get; set; }
    public int ActiveProfileIndex { get; set; }
    public string Schema { get; set; }
    public SpeedScopeShared Shared { get; set; }
    public SpeedScopeProfile[] Profiles { get; set; }
}