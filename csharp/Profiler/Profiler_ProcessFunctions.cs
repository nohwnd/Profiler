using System.Collections.Generic;

namespace Profiler;

public static partial class Profiler {

    public static Dictionary<string, LineProfile> ProcessFunctions(List<Hit> trace)
    {
        // map of ScriptBlocks/files and lines
        var functionMap = new Dictionary<string, LineProfile>();
        var returnIndexPerFunctionMap = new Dictionary<string, int>();
        var traceCount = trace.Count;
        var collectAllHits = false;

        // excluding start and stop internal events
        for (var i = 2; i <= traceCount - 3; i++)
        {
            var hit = trace[i];

            var key = hit.Module + "|" + hit.Function + "|" + (hit.IsInFile ? hit.Path : hit.ScriptBlockId);

            if (!functionMap.TryGetValue(key, out var lineProfile))
            {
                lineProfile = new LineProfile
                {
                    File = hit.Path,
                    Text = hit.Function ?? "<body>",
                    Function = hit.Function ?? "<body>",
                    Module = hit.Module,
                    Path = hit.Path,
                };

                functionMap.Add(key, lineProfile);
            }

            lineProfile.SelfDuration = lineProfile.SelfDuration.Add(hit.SelfDuration);

            lineProfile.SelfMemory = lineProfile.SelfMemory + hit.TotalBytes;
            lineProfile.SelfGc = lineProfile.SelfGc + hit.TotalGc;

            // keep the highest return index per line so we only add up durations that are not 
            // within each other
            if (!returnIndexPerFunctionMap.TryGetValue(key, out int returnIndex))
            {
                // we did not have the key in the dictionary yet, add the current returnIndex
                // which will be the last hit on this line for the future
                returnIndexPerFunctionMap.Add(key, hit.ReturnIndex);
            }
            else
            {

                if (hit.Index > returnIndex)
                {
                    // we found the key and the line number, if the current index is higher than the return index
                    // overwrite the last return index. The last return index is now in the returnIndex variable
                    returnIndexPerFunctionMap[key] = hit.ReturnIndex;
                }
            }

            if (hit.Index > returnIndex)
            {
                // we can have calls that call into the same line
                // simply adding durations together gives us times
                // that can be way more than the execution time of the
                // whole script because the line is accounted for multiple
                // times. This is best visible when calling recursive function
                // each subsequent call would add up to the previous ones
                // https://twitter.com/nohwnd/status/1388418452130603008?s=20
                // so we need to check if we are not in the current function
                // by keeping the highest return index and only adding the time
                // when we have index that is higher than it, meaning we are
                // now running after we returned from the function
                lineProfile.Duration = lineProfile.Duration.Add(hit.Duration);
            }

            lineProfile.Memory = lineProfile.Memory + hit.TotalBytes;
            lineProfile.Gc = lineProfile.Gc + hit.TotalGc;

            lineProfile.HitCount++;

            if (collectAllHits || lineProfile.Hits.Count < 100)
            {
                lineProfile.Hits.Add(hit);
            }

            // add distinct entries per column when there are more commands
            // on the same line so we can see which commands contributed to the line duration
            //if we need to count duration we can do it by moving this to the next part of the code
            // where we process each hit on the line
            if (!lineProfile.CommandHits.TryGetValue((int)hit.Column, out var commandHit))
            {
                commandHit = new CommandHit(hit);
                lineProfile.CommandHits.Add((int)hit.Column, commandHit);
            }
            else
            {
                commandHit.SelfDuration = commandHit.SelfDuration.Add(hit.SelfDuration);
                // do not track duration for now, we are not listing each call to the command
                // so we cannot add the durations correctly, because we need to exclude recursive calls
                // it is also not very useful I think, might reconsider later
                // commandHit.Duration += hit.Duration
                commandHit.HitCount++;
            }
        }

        return functionMap;
    }

}
