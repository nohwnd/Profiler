using System;
using System.Collections.Generic;

namespace Profiler;

/// <summary>
/// Profiler processes the trace to sort it in lines with hit counts and durations.
/// </summary>
public static partial class Profiler
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
}
