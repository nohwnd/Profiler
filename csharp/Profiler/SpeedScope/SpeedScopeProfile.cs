using System.Collections.Generic;

namespace Profiler.SpeedScope;

public class SpeedScopeProfile
{
    public string Type { get; set; }
    public string Name { get; set; }
    public string Unit { get; set; }
    public int StartValue { get; set; }
    public double EndValue { get; set; }
    public List<SpeedScopeEvent> Events { get; set; }
}