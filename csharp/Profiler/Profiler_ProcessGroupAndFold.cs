using System;
using System.Collections.Generic;

namespace Profiler;

public static partial class Profiler
{
    public static List<Hit> ProcessGroupAndFold(List<Hit> trace)
    {
        var traceCount = trace.Count;

        for (var i = 0; i < traceCount - 1; i++)
        {
            var hit = trace[i];

            //// Group Pester entries, to have the same identifier, we need to check also path because we often take ScriptBlocks from Pester and invoke them 
            //// in another session state, where they won't tie to Pester module.
            if (hit.Module == "Pester" || (hit.Path != null && (hit.Path.EndsWith("Pester.psm1") || hit.Path.EndsWith("Pester.ps1") || hit.Path.EndsWith("Pester.psd1"))))
            {
                hit.Group = "Pester";

                // This shows more details about pester, but there are few problems, and unnecessary detail if you use 
                // Profiler to find why is your code slow, but don't really care about why your tests are slow.
                //if (hit.FunctionName != null)
                //{
                //    if (hit.FunctionName.StartsWith("Should<Begin>") || hit.FunctionName == "Assert-MockCalled")
                //    {
                //        // show when we call should
                //        hit.Group = "Should";
                //    }
                //    else if (hit.FunctionName.StartsWith("Before") || hit.FunctionName.StartsWith("After"))
                //    {
                //        // show when we call setup blocks
                //        hit.Group = hit.FunctionName;
                //    }
                //    else if (hit.FunctionName == "Discover-Test" || hit.FunctionName == "Run-Test")
                //    {
                //        // Show discovery and run as separates steps
                //        hit.Group = hit.FunctionName;
                //    }
                //    else if (hit.FunctionName == "Describe" || hit.FunctionName == "Context" || hit.FunctionName == "It")
                //    {
                //        // Show blocks and tests
                //        hit.Group = hit.FunctionName;
                //    }
                //    else if (hit.FunctionName == "Mock" || hit.FunctionName == "Invoke-Mock")
                //    {
                //        // show mocking and mock calls
                //        hit.Group = "Mock";
                //    }
                //}
            }


            // those are structs and we can't grab it by ref from the list
            // so we just overwrite
            trace[hit.Index] = hit;
        }

        var foldStart = 0;
        string foldGroup = null;
        TimeSpan selfDurationAccumulator = TimeSpan.Zero;

        for (var i = 0; i < traceCount - 1; i++)
        {
            var hit = trace[i];

            var nextHit = trace[i + 1];

            // we are entering a fold, keep note of where it started
            // and which group we are folding so we can find the end.
            // if next item is different group, this is single item group and we don't need to update anything.
            if (hit.Group != null && hit.Group != foldGroup && nextHit.Group == hit.Group)
            {
                foldStart = hit.Index;
                foldGroup = hit.Group;

                hit.Folded = true;
                trace[i] = hit;
            }
            // We are already in a fold, and the next event is different group, meaning the current
            // event is the end of the fold. Aggregate the data from where the fold started to the current event.
            else if (foldGroup != null && hit.Group == foldGroup && foldGroup != nextHit.Group)
            {
                var foldStartHit = trace[foldStart];
                hit.StartTime = foldStartHit.StartTime;
                hit.SelfDuration = foldStartHit.SelfDuration + selfDurationAccumulator;
                hit.CallerIndex = foldStartHit.CallerIndex;

                trace[i] = hit;

                foldGroup = null;
                foldStart = 0;
                selfDurationAccumulator = TimeSpan.Zero;
            }
            else if (hit.Group != null && hit.Group == foldGroup && hit.Index != foldStart)
            {
                // we are in the middle of a fold, mark the event as folded
                hit.Folded = true;
                trace[i] = hit;
            }
            else
            {
                // we are not in a fold
            }
        }

        return trace;
    }
}
