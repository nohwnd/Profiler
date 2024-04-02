using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace Profiler
{
    /// <summary>
    /// Profiler processes the trace to sort it in lines with hit counts and durations.
    /// </summary>
    public static class Profiler
    {
        public static List<Hit> ProcessFlow(List<Hit> trace)
        {
            var traceCount = trace.Count;
            var stack = new Stack<int>();
            int caller = -1;

            for (var i = 0; i < traceCount; i++)
            {
                var hit = trace[i];
                // there is next event in the trace,
                // we can use it to see if we remained in the
                // function or returned

                if (hit.Index < traceCount - 2)
                {
                    var nextEvent = trace[hit.Index + 1];
                    // the next event has higher number on the callstack
                    // we are going down into a function, meaning this is a call
                    if (nextEvent.Level > hit.Level)
                    {
                        hit.Flow = Flow.Call;
                        // save where we entered
                        stack.Push(hit.Index);
                        hit.CallerIndex = caller;
                        caller = hit.Index;
                    }
                    else if (nextEvent.Level < hit.Level)
                    {
                        hit.Flow = Flow.Return;
                        // we go up, back from a function and we might jump up
                        // for example when throw happens and we end up in try catch
                        // that is x levels up
                        // get all the calls that happened up until this level
                        // and diff them against this to set their durations
                        while (stack.Count >= hit.Level)
                        {
                            var callIndex = stack.Pop();
                            var call = trace[callIndex];
                            // events are timestamped at the start, so start of when we called until
                            // the next one after we returned is the duration of the whole call
                            call.Duration = TimeSpan.FromTicks(nextEvent.Timestamp - call.Timestamp);
                            call.TotalBytes = nextEvent.AllocatedBytes - call.AllocatedBytes;
                            call.TotalGc = (nextEvent.Gc0 + nextEvent.Gc1 + nextEvent.Gc2) - (call.Gc0 + call.Gc1 + call.Gc2);
                            // save into the call where it returned so we can see the events in the
                            // meantime and see what was actually slow
                            call.ReturnIndex = hit.Index;
                            // those are structs and we can't grab it by ref from the list
                            // so we just overwrite
                            trace[callIndex] = call;
                        }

                        // return from a function is not calling anything
                        // so the duration and self duration are the same
                        hit.Duration = hit.SelfDuration;
                        hit.TotalBytes = hit.SelfAllocatedBytes;
                        hit.TotalGc = hit.SelfGc0 + hit.SelfGc1 + hit.SelfGc2;
                        hit.ReturnIndex = hit.Index;
                        // who called us
                        hit.CallerIndex = caller;
                    }
                    else
                    {
                        // we stay in the function in the next step, so we did
                        // not call anyone or did not return, we are just processing
                        // the duration is the selfduration
                        hit.Flow = Flow.Process;
                        hit.Duration = hit.SelfDuration;
                        hit.TotalBytes = hit.SelfAllocatedBytes;
                        hit.TotalGc = hit.SelfGc0 + hit.SelfGc1 + hit.SelfGc2;
                        hit.ReturnIndex = hit.Index;

                        // who called us
                        hit.CallerIndex = caller;
                    }

                    // those are structs and we can't grab it by ref from the list
                    // so we just overwrite
                    trace[hit.Index] = hit;
                }
            }

            return trace;
        }

        public static List<Hit> ProcessGroupAndFold(List<Hit> trace)
        {
            var traceCount = trace.Count;

            for (var i = 0; i < traceCount - 1; i++)
            {
                var hit = trace[i];

                //// Group Pester entries, to have the same identifier, we need to check also path because we often take scriptblocks from Pester and invoke them 
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

        public static Dictionary<string, LineProfile> ProcessFunctions(List<Hit> trace)
        {
            // map of scriptblocks/files and lines
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

                lineProfile.SelfMem = lineProfile.SelfMem + hit.TotalBytes;
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

                lineProfile.Mem = lineProfile.Mem + hit.TotalBytes;
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
                if (!lineProfile.CommandHits.TryGetValue((uint)hit.Column, out var commandHit))
                {
                    commandHit = new CommandHit(hit);
                    lineProfile.CommandHits.Add((uint)hit.Column, commandHit);
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

        public static Dictionary<Guid, File> ProcessLines(List<Hit> trace, Dictionary<Guid, ScriptBlock> scriptBlocks, bool collectAllHits)
        {
            // map of scriptblocks/files and lines
            var fileMap = new Dictionary<Guid, File>();
            var contentMap = new Dictionary<Guid, string[]>();
            var returnIndexPerLineMap = new Dictionary<Guid, Dictionary<int, int>>();
            var traceCount = trace.Count;
            var newLineArray = new string[] { Environment.NewLine };

            ScriptBlock lastScriptBlock = null;
            // excluding start and stop internal events
            for (var i = 2; i <= traceCount - 3; i++)
            {
                var hit = trace[i];

                var key = hit.ScriptBlockId;

                if (!contentMap.TryGetValue(key, out var lines))
                {
                    lastScriptBlock = scriptBlocks[key];
                    // there is an edge case when using classes that will fail to convert to string
                    try { lines = lastScriptBlock?.Ast.ToString().Split(newLineArray, StringSplitOptions.None); } catch { lines = null; }
                    contentMap.Add(key, lines);
                }

                if (null == lines)
                {
                    // this failed to cast to string above skip it
                    continue;
                }

                // get the scriptblock quicker if we stay in the same one,
                // and also if we are avoid second lookup if we added the value above
                ScriptBlock scriptBlock;
# if !POWERSHELL3
                if (lastScriptBlock?.Id != key)
                {
                    lastScriptBlock = scriptBlocks[key];
                }
#endif
                scriptBlock = lastScriptBlock;


                if (!fileMap.TryGetValue(key, out var file))
                {
                    file = new File
                    {
                        Path = hit.IsInFile ? hit.Path : key.ToString(),
                        Name = hit.IsInFile ? System.IO.Path.GetFileName(hit.Path) : key.ToString(),
                        Lines = new Dictionary<int, LineProfile>(),
                    };

                    fileMap.Add(key, file);
                }

                var lineNumber = hit.Line;
                if (!file.Lines.TryGetValue(lineNumber, out var lineProfile))
                {
                    var lineIndex = hit.Line - scriptBlock.StartPosition.StartLine;
                    // entering or leaving scriptblock we get { and } which might be on the next line (outside of the array)
                    // in that case we will take the text from the extent
                    var text = lineIndex < lines.Length ? lines[lineIndex]?.Trim() : hit.Text?.Trim();

                    lineProfile = new LineProfile
                    {
                        File = file.Name,
                        Line = (uint)lineNumber,
                        Text = text,
                        Function = hit.Function,
                        Module = hit.Module,
                        Path = file.Path,
                    };
                    file.Lines.Add(lineNumber, lineProfile);
                }

                lineProfile.SelfDuration = lineProfile.SelfDuration.Add(hit.SelfDuration);
                lineProfile.SelfMem = lineProfile.SelfMem + hit.SelfAllocatedBytes;
                lineProfile.SelfGc = lineProfile.SelfGc + hit.SelfGc0 + hit.SelfGc1 + hit.SelfGc2;

                // keep the highest return index per line so we only add up durations that are not 
                // within each other
                int returnIndex = 0;
                if (!returnIndexPerLineMap.TryGetValue(key, out var lineReturns))
                {
                    // we did not have the key in the dictionary yet, add the current returnIndex
                    // which will be the last hit on this line for the future
                    returnIndexPerLineMap.Add(key, new Dictionary<int, int> { [lineNumber] = hit.ReturnIndex });
                }
                else
                {
                    if (!lineReturns.TryGetValue(lineNumber, out returnIndex))
                    {
                        // we found the key, but not the line add the current return index 
                        // which will be the last return index on this line for the future
                        lineReturns.Add(lineNumber, hit.ReturnIndex);
                    }
                    else
                    {
                        if (hit.Index > returnIndex)
                        {
                            // we found the key and the line number, if the current index is higher than the return index
                            // overwrite the last return index. The last return index is now in the returnIndex variable
                            lineReturns[lineNumber] = hit.ReturnIndex;
                        }
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

                lineProfile.Mem = lineProfile.Mem + hit.TotalBytes;
                lineProfile.Gc = lineProfile.Gc + hit.TotalGc;

                lineProfile.HitCount++;

                if (collectAllHits || lineProfile.Hits.Count < 100)
                {
                    lineProfile.Hits.Add(hit);
                }

                // add distinct entries per column when there are more commands
                // on the same line so we can see which commands contributed to the line duration
                // if we need to count duration we can do it by moving this to the next part of the code
                // where we process each hit on the line
                if (!lineProfile.CommandHits.TryGetValue((uint)hit.Column, out var commandHit))
                {
                    commandHit = new CommandHit(hit);
                    lineProfile.CommandHits.Add((uint)hit.Column, commandHit);
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

            return fileMap;
        }
    }
}
