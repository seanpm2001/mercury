%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 1994-2011 The University of Melbourne.
% Copyright (C) 2014-2016, 2018-2021 The Mercury team.
% This file is distributed under the terms specified in COPYING.LIB.
%---------------------------------------------------------------------------%
%
% File: benchmarking.m.
% Main author: zs.
% Stability: medium.
%
% This module contains predicates that deal with the CPU time requirements
% of (various parts of) the program.
%
%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- module benchmarking.
:- interface.

:- import_module bool.
:- import_module io.
:- import_module maybe.

    % `report_stats/0' is a non-logical procedure intended for use in profiling
    % the performance of a program. It has the side-effect of reporting
    % some memory and time usage statistics about the time period since
    % the last call to report_stats to stderr.
    %
    % Note: in Java, this reports usage of the calling thread. You will get
    % nonsensical results if the previous call to `report_stats' was
    % from a different thread.
    %
:- impure pred report_stats is det.
% NOTE_TO_IMPLEMENTORS :- pragma obsolete(report_stats/0,
% NOTE_TO_IMPLEMENTORS [io.report_stats/3, io.report_stats/4]).

    % `report_full_memory_stats' is a non-logical procedure intended for use
    % in profiling the memory usage of a program. It has the side-effect
    % of reporting a full memory profile to stderr.
    %
:- impure pred report_full_memory_stats is det.
% NOTE_TO_IMPLEMENTORS :- pragma obsolete(report_full_memory_stats/0,
% NOTE_TO_IMPLEMENTORS [io.report_full_memory_stats/3, io.report_full_memory_stats/4]).

    % report_memory_attribution(Label, Collect, !IO) is a procedure intended
    % for use in profiling the memory usage by a program. It is supported in
    % `memprof.gc' grades only, in other grades it is a no-op. It reports a
    % summary of the objects on the heap to a data file. See ``Using mprof -s
    % for profiling memory retention'' in the Mercury User's Guide. The label
    % is for your reference. If Collect is yes, it has the effect of forcing a
    % garbage collection before building the report.
    %
:- pred report_memory_attribution(string::in, bool::in, io::di, io::uo) is det.
:- impure pred report_memory_attribution(string::in, bool::in) is det.

    % report_memory_attribution(Label, !IO) is the same as
    % report_memory_attribution/4 above, except that it always forces a
    % collection (in 'memprof.gc' grades).
    %
:- pred report_memory_attribution(string::in, io::di, io::uo) is det.
:- impure pred report_memory_attribution(string::in) is det.

    % benchmark_det(Pred, In, Out, Repeats, Time) is for benchmarking the det
    % predicate Pred. We call Pred with the input In and the output Out, and
    % return Out so that the caller can check the correctness of the
    % benchmarked predicate. Since most systems do not have good facilities
    % for measuring small times, the Repeats parameter allows the caller
    % to specify how many times Pred should be called inside the timed
    % interval. The number of milliseconds required to execute Pred with input
    % In this many times is returned as Time.
    %
    % benchmark_func(Func, In, Out, Repeats, Time) does for functions
    % exactly what benchmark_det does for predicates.
    %
:- pred benchmark_det(pred(T1, T2), T1, T2, int, int).
:- mode benchmark_det(pred(in, out) is det, in, out, in, out) is cc_multi.
:- mode benchmark_det(pred(in, out) is cc_multi, in, out, in, out) is cc_multi.

:- pred benchmark_func(func(T1) = T2, T1, T2, int, int).
:- mode benchmark_func(func(in) = out is det, in, out, in, out) is cc_multi.

:- pred benchmark_det_io(pred(T1, T2, T3, T3), T1, T2, T3, T3, int, int).
:- mode benchmark_det_io(pred(in, out, di, uo) is det, in, out, di, uo,
    in, out) is cc_multi.

    % benchmark_nondet(Pred, In, Count, Repeats, Time) is for benchmarking
    % the nondet predicate Pred. benchmark_nondet is similar to benchmark_det,
    % but it returns only a count of the solutions, rather than solutions
    % themselves. The number of milliseconds required to generate all
    % solutions of Pred with input In Repeats times is returned as Time.
    %
:- pred benchmark_nondet(pred(T1, T2), T1, int, int, int).
:- mode benchmark_nondet(pred(in, out) is nondet, in, out, in, out)
    is cc_multi.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

    % Turn off or on the collection of all profiling statistics.
    %
:- pred turn_off_profiling(io::di, io::uo) is det.
:- pred turn_on_profiling(io::di, io::uo) is det.

:- impure pred turn_off_profiling is det.
:- impure pred turn_on_profiling is det.

    % Turn off or on the collection of call graph profiling statistics.
    %
:- pred turn_off_call_profiling(io::di, io::uo) is det.
:- pred turn_on_call_profiling(io::di, io::uo) is det.

:- impure pred turn_off_call_profiling is det.
:- impure pred turn_on_call_profiling is det.

    % Turn off or on the collection of time spent in each procedure
    % profiling statistics.
    %
:- pred turn_off_time_profiling(io::di, io::uo) is det.
:- pred turn_on_time_profiling(io::di, io::uo) is det.

:- impure pred turn_off_time_profiling is det.
:- impure pred turn_on_time_profiling is det.

    % Turn off or on the collection of memory allocated in each procedure
    % profiling statistics.
    %
:- pred turn_off_heap_profiling(io::di, io::uo) is det.
:- pred turn_on_heap_profiling(io::di, io::uo) is det.

:- impure pred turn_off_heap_profiling is det.
:- impure pred turn_on_heap_profiling is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

    % write_out_trace_counts(FileName, MaybeErrorMsg, !IO):
    %
    % Write out the trace counts accumulated so far in this program's execution
    % to FileName. If successful, set MaybeErrorMsg to "no". If unsuccessful,
    % e.g. because the program wasn't compiled with debugging enabled or
    % because trace counting isn't turned on, then set MaybeErrorMsg to a "yes"
    % wrapper around an error message.
    %
:- pred write_out_trace_counts(string::in, maybe(string)::out,
    io::di, io::uo) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

    % Place a log message in the threadscope event stream. The event will be
    % logged as being generated by the current Mercury Engine. This is a no-op
    % when threadscope is not available.
    %
:- pred log_threadscope_message(string::in, io::di, io::uo) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module int.
:- import_module mutvar.
:- import_module string.

%---------------------------------------------------------------------------%

:- pragma foreign_decl("C", "
#include ""mercury_report_stats.h""
").

%---------------------%

report_stats :-
    trace [io(!IO)] (
        io.report_standard_stats(!IO)
    ),
    impure impure_true.

%---------------------%

report_full_memory_stats :-
    trace [io(!IO)] (
        io.report_full_memory_stats(!IO)
    ),
    impure impure_true.

%---------------------------------------------------------------------------%

:- pragma foreign_proc("C",
    report_memory_attribution(Label::in, Collect::in, _IO0::di, _IO::uo),
    [will_not_call_mercury, promise_pure],
"
    MR_bool run_collect = (Collect) ? MR_TRUE : MR_FALSE;

#ifdef  MR_MPROF_PROFILE_MEMORY_ATTRIBUTION
    MR_report_memory_attribution(Label, run_collect);
#else
    (void) Label;
#endif
").

report_memory_attribution(_, _, !IO).

report_memory_attribution(Label, Collect) :-
    trace [io(!IO)] (
        report_memory_attribution(Label, Collect, !IO)
    ),
    impure impure_true.

report_memory_attribution(Label, !IO) :-
    report_memory_attribution(Label, yes, !IO).

report_memory_attribution(Label) :-
    impure report_memory_attribution(Label, yes).

%---------------------------------------------------------------------------%

:- pragma foreign_code("C#",
"
private static double user_time_at_start
    = System.Diagnostics.Process.GetCurrentProcess().UserProcessorTime
        .TotalSeconds;
private static double user_time_at_last_stat;

private static long real_time_at_start
    = real_time_at_last_stat = System.DateTime.Now.Ticks;
private static long real_time_at_last_stat;

public static void
ML_report_standard_stats(io.MR_MercuryFileStruct stream)
{
    double user_time_at_prev_stat = user_time_at_last_stat;
    user_time_at_last_stat = System.Diagnostics.Process.GetCurrentProcess()
        .UserProcessorTime.TotalSeconds;

    long real_time_at_prev_stat = real_time_at_last_stat;
    real_time_at_last_stat = System.DateTime.Now.Ticks;

    io.mercury_print_string(stream, System.String.Format(
        ""[User time: +{0:F2}s, {1:F2}s Real time: +{2:F2}s, {3:F2}s]\\n"",
        (user_time_at_last_stat - user_time_at_prev_stat),
        (user_time_at_last_stat - user_time_at_start),
        ((real_time_at_last_stat - real_time_at_prev_stat)
            / (double) System.TimeSpan.TicksPerSecond),
        ((real_time_at_last_stat - real_time_at_start)
           / (double) System.TimeSpan.TicksPerSecond)
    ));
    // XXX At this point there should be a whole bunch of memory usage
    // statistics.
}

public static void
ML_report_full_memory_stats(io.MR_MercuryFileStruct stream)
{
    // XXX The support for this predicate is even worse. Since we don't have
    // access to memory usage statistics, all you get here is an apology.
    // But at least it doesn't just crash with an error.
    io.mercury_print_string(stream,
        ""Sorry, report_full_memory_stats is not yet "" +
            ""implemented for the C# back-end.\\n"");
}
").

:- pragma foreign_code("Java",
"
private static int user_time_at_start = 0;
private static int user_time_at_last_stat = 0;
private static long real_time_at_start;
private static long real_time_at_last_stat;

public static void
ML_initialise()
{
    // Class initialisation may be delayed so main() must explicitly initialise
    // these variables at startup, otherwise the first call to `report_stats'
    // will show the wrong elapsed time.
    real_time_at_start = System.currentTimeMillis();
    real_time_at_last_stat = real_time_at_start;
}

public static void
ML_report_standard_stats(jmercury.io.MR_TextOutputFile stream)
    throws java.io.IOException
{
    int user_time_at_prev_stat = user_time_at_last_stat;
    user_time_at_last_stat = ML_get_user_cpu_milliseconds();

    long real_time_at_prev_stat = real_time_at_last_stat;
    real_time_at_last_stat = System.currentTimeMillis();

    stream.write(
        ""[User time: +"" +
        ((user_time_at_last_stat - user_time_at_prev_stat) / 1000.0) +
        ""s, "" +
        ((user_time_at_last_stat - user_time_at_start) / 1000.0) +
        ""s"");

    stream.write(
        "" Real time: +"" +
        ((real_time_at_last_stat - real_time_at_prev_stat) / 1000.0) +
        ""s, "" +
        ((real_time_at_last_stat - real_time_at_start) / 1000.0) +
        ""s"");

    // XXX At this point there should be a whole bunch of memory usage
    // statistics. Unfortunately the Java back-end does not yet support
    // this amount of profiling, so cpu time is all you get.
}

public static void
ML_report_full_memory_stats(jmercury.io.MR_TextOutputFile stream)
    throws java.io.IOException
{
    // XXX The support for this predicate is even worse. Since we don't have
    // access to memory usage statistics, all you get here is an apology.
    // But at least it doesn't just crash with an error.

    stream.write(""Sorry, report_full_memory_stats is not yet "" +
        ""implemented for the Java back-end."");
}
").

%---------------------------------------------------------------------------%

benchmark_det(Pred, In, Out, Repeats, Time) :-
    promise_pure (
        impure get_user_cpu_milliseconds(StartTime),
        impure benchmark_det_loop(Pred, In, Out, Repeats),
        impure get_user_cpu_milliseconds(EndTime),
        Time0 = EndTime - StartTime,
        cc_multi_equal(Time0, Time)
    ).

:- impure pred benchmark_det_loop(pred(T1, T2), T1, T2, int).
:- mode benchmark_det_loop(pred(in, out) is det, in, out, in) is det.
:- mode benchmark_det_loop(pred(in, out) is cc_multi, in, out, in) is cc_multi.

benchmark_det_loop(Pred, In, Out, Repeats) :-
    % The call to do_nothing/1 here is to make sure the compiler
    % doesn't optimize away the call to `Pred'.
    Pred(In, Out0),
    impure do_nothing(Out0),
    ( if Repeats > 1 then
        impure benchmark_det_loop(Pred, In, Out, Repeats - 1)
    else
        Out = Out0
    ).

benchmark_func(Func, In, Out, Repeats, Time) :-
    promise_pure (
        impure get_user_cpu_milliseconds(StartTime),
        impure benchmark_func_loop(Func, In, Out, Repeats),
        impure get_user_cpu_milliseconds(EndTime),
        Time0 = EndTime - StartTime,
        cc_multi_equal(Time0, Time)
    ).

:- impure pred benchmark_func_loop(func(T1) = T2, T1, T2, int).
:- mode benchmark_func_loop(func(in) = out is det, in, out, in) is det.

benchmark_func_loop(Func, In, Out, Repeats) :-
    % The call to do_nothing/1 here is to make sure the compiler
    % doesn't optimize away the call to `Func'.
    Out0 = Func(In),
    impure do_nothing(Out0),
    ( if Repeats > 1 then
        impure benchmark_func_loop(Func, In, Out, Repeats - 1)
    else
        Out = Out0
    ).

:- pragma promise_pure(benchmark_det_io/7).

benchmark_det_io(Pred, InA, OutA, InB, OutB, Repeats, Time) :-
    impure get_user_cpu_milliseconds(StartTime),
    impure benchmark_det_loop_io(Pred, InA, OutA, InB, OutB, Repeats),
    impure get_user_cpu_milliseconds(EndTime),
    Time = EndTime - StartTime.
    % XXX cc_multi_equal(Time0, Time).

:- impure pred benchmark_det_loop_io(pred(T1, T2, T3, T3), T1, T2,
    T3, T3, int).
:- mode benchmark_det_loop_io(pred(in, out, di, uo) is det, in, out,
    di, uo, in) is cc_multi.

benchmark_det_loop_io(Pred, InA, OutA, InB, OutB, Repeats) :-
    % The call to do_nothing/1 here is to make sure the compiler
    % doesn't optimize away the call to `Pred'.
    Pred(InA, OutA0, InB, OutB0),
    impure do_nothing(OutA0),
    ( if Repeats > 1 then
        impure benchmark_det_loop_io(Pred, InA, OutA, OutB0, OutB, Repeats - 1)
    else
        OutA = OutA0,
        OutB = OutB0
    ).

:- pragma promise_pure(benchmark_nondet/5).

benchmark_nondet(Pred, In, Count, Repeats, Time) :-
    impure get_user_cpu_milliseconds(StartTime),
    impure benchmark_nondet_loop(Pred, In, Count, Repeats),
    impure get_user_cpu_milliseconds(EndTime),
    Time0 = EndTime - StartTime,
    cc_multi_equal(Time0, Time).

:- impure pred benchmark_nondet_loop(pred(T1, T2), T1, int, int).
:- mode benchmark_nondet_loop(pred(in, out) is nondet, in, out, in) is det.

benchmark_nondet_loop(Pred, In, Count, Repeats) :-
    impure new_mutvar(0, SolutionCounter),
    (
        impure repeat(Repeats),
        impure set_mutvar(SolutionCounter, 0),
        Pred(In, Out0),
        impure do_nothing(Out0),
        impure get_mutvar(SolutionCounter, Count),
        impure set_mutvar(SolutionCounter, Count + 1),
        fail
    ;
        true
    ),
    impure get_mutvar(SolutionCounter, Count).

:- impure pred repeat(int::in) is nondet.

repeat(N) :-
    N > 0,
    (
        true
    ;
        impure repeat(N - 1)
    ).

:- impure pred get_user_cpu_milliseconds(int::out) is det.

:- pragma foreign_export("C#", get_user_cpu_milliseconds(out),
    "ML_get_user_cpu_milliseconds").
:- pragma foreign_export("Java", get_user_cpu_milliseconds(out),
    "ML_get_user_cpu_milliseconds").

:- pragma foreign_proc("C",
    get_user_cpu_milliseconds(Time::out),
    [will_not_call_mercury, thread_safe],
"
    Time = MR_get_user_cpu_milliseconds();
").

:- pragma foreign_proc("C#",
    get_user_cpu_milliseconds(Time::out),
    [will_not_call_mercury, thread_safe],
"
    // This won't return the elapsed time since program start,
    // as it begins timing after the first call.
    // For computing time differences it should be fine.
    Time = (int) System.Diagnostics.Process.GetCurrentProcess()
        .UserProcessorTime.TotalMilliseconds;
").

:- pragma foreign_proc("Java",
    get_user_cpu_milliseconds(Time::out),
    [will_not_call_mercury, thread_safe, may_not_duplicate],
"
    try {
        java.lang.management.ThreadMXBean bean =
            java.lang.management.ManagementFactory.getThreadMXBean();
        long nsecs = bean.getCurrentThreadUserTime();
        if (nsecs == -1) {
            Time = -1;
        } else {
            Time = (int) (nsecs / 1000000L);
        }
    } catch (java.lang.UnsupportedOperationException e) {
        Time = -1;
    }
").

% To prevent the C compiler from optimizing the benchmark code away,
% we assign the benchmark output to a volatile global variable.

:- pragma foreign_decl("C", "
    extern volatile MR_Word ML_benchmarking_dummy_word;
").
:- pragma foreign_code("C", "
    volatile        MR_Word ML_benchmarking_dummy_word;
").
:- pragma foreign_code("Java", "
    static volatile Object ML_benchmarking_dummy_word;
").

:- impure pred do_nothing(T::in) is det.

:- pragma foreign_proc("C",
    do_nothing(X::in),
    [will_not_call_mercury, thread_safe],
"
    ML_benchmarking_dummy_word = (MR_Word) X;
").

:- pragma foreign_proc("C#",
    do_nothing(_X::in),
    [will_not_call_mercury, thread_safe],
"
").

:- pragma foreign_proc("Java",
    do_nothing(X::in),
    [will_not_call_mercury, thread_safe],
"
    ML_benchmarking_dummy_word = X;
").

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- pragma promise_pure(turn_off_profiling/2).

turn_off_profiling(!IO) :-
    impure turn_off_profiling.

:- pragma promise_pure(turn_on_profiling/2).

turn_on_profiling(!IO) :-
    impure turn_on_profiling.

turn_off_profiling :-
    impure turn_off_call_profiling,
    impure turn_off_time_profiling,
    impure turn_off_heap_profiling.

turn_on_profiling :-
    impure turn_on_call_profiling,
    impure turn_on_time_profiling,
    impure turn_on_heap_profiling.

%---------------------------------------------------------------------------%

:- pragma promise_pure(turn_off_call_profiling/2).

turn_off_call_profiling(!IO) :-
    impure turn_off_call_profiling.

:- pragma promise_pure(turn_on_call_profiling/2).

turn_on_call_profiling(!IO) :-
    impure turn_on_call_profiling.

:- pragma promise_pure(turn_off_time_profiling/2).

turn_off_time_profiling(!IO) :-
    impure turn_off_time_profiling.

:- pragma promise_pure(turn_on_time_profiling/2).

turn_on_time_profiling(!IO) :-
    impure turn_on_time_profiling.

:- pragma promise_pure(turn_off_heap_profiling/2).

turn_off_heap_profiling(!IO) :-
    impure turn_off_heap_profiling.

:- pragma promise_pure(turn_on_heap_profiling/2).

turn_on_heap_profiling(!IO) :-
    impure turn_on_heap_profiling.

%---------------------------------------------------------------------------%

:- pragma foreign_decl(c, local, "
#include ""mercury_prof.h""
#include ""mercury_heap_profile.h""
").

:- pragma foreign_proc(c, turn_off_call_profiling,
    [will_not_call_mercury, thread_safe, tabled_for_io],
"
#ifdef MR_MPROF_PROFILE_CALLS
    MR_prof_turn_off_call_profiling();
#endif
").

:- pragma foreign_proc(c, turn_on_call_profiling,
    [will_not_call_mercury, thread_safe, tabled_for_io],
"
#ifdef MR_MPROF_PROFILE_CALLS
    MR_prof_turn_on_call_profiling();
#endif
").

:- pragma foreign_proc(c, turn_off_time_profiling,
    [will_not_call_mercury, thread_safe, tabled_for_io],
"
#ifdef MR_MPROF_PROFILE_TIME
    MR_prof_turn_off_time_profiling();
#endif
").

:- pragma foreign_proc(c, turn_on_time_profiling,
    [will_not_call_mercury, thread_safe, tabled_for_io],
"
#ifdef MR_MPROF_PROFILE_TIME
    MR_prof_turn_on_time_profiling();
#endif
").

:- pragma foreign_proc(c, turn_off_heap_profiling,
    [will_not_call_mercury, thread_safe, tabled_for_io],
"
    MR_prof_turn_off_heap_profiling();
").

:- pragma foreign_proc(c, turn_on_heap_profiling,
    [will_not_call_mercury, thread_safe, tabled_for_io],
"
    MR_prof_turn_on_heap_profiling();
").

%---------------------------------------------------------------------------%

write_out_trace_counts(DumpFileName, MaybeErrorMsg, !IO) :-
    dump_trace_counts_to(DumpFileName, Result, !IO),
    ( if Result = 0 then
        MaybeErrorMsg = no
    else if Result = 1 then
        MaybeErrorMsg = yes("Couldn't dump trace counts to `" ++
            DumpFileName ++ "': no compiled with debugging")
    else if Result = 2 then
        MaybeErrorMsg = yes("Couldn't dump trace counts to `" ++
            DumpFileName ++ "': trace counting not turned on")
    else if Result = 3 then
        MaybeErrorMsg = yes("Couldn't dump trace counts to `" ++
            DumpFileName ++ "': couldn't open file")
    else
        MaybeErrorMsg = yes("Couldn't dump trace counts to `" ++
            DumpFileName ++ "'")
    ).

:- pred dump_trace_counts_to(string::in, int::out, io::di, io::uo) is det.

:- pragma foreign_proc("C",
    dump_trace_counts_to(FileName::in, Result::out, _IO0::di, _IO::uo),
    [will_not_call_mercury, promise_pure],
"
#ifdef  MR_EXEC_TRACE
    FILE    *fp;

    if (MR_trace_count_enabled && MR_trace_func_enabled) {
        fp = fopen(FileName, ""w"");
        if (fp != NULL) {
            MR_trace_write_label_exec_counts(fp, MR_progname, MR_FALSE);
            Result = 0;
            (void) fclose(fp);
        } else {
            Result = 3;
        }
    } else {
        Result = 2;
    }
#else
    Result = 1;
#endif
").

% Default definition for non-C backends.
dump_trace_counts_to(_, 1, !IO).

%---------------------------------------------------------------------------%

:- pragma foreign_proc("C",
    log_threadscope_message(Message::in, _IO0::di, _IO::uo),
    [will_not_call_mercury, will_not_throw_exception, thread_safe,
        promise_pure, tabled_for_io],
"
#if MR_THREADSCOPE
    MR_threadscope_post_log_msg(Message);
#endif
").

%---------------------------------------------------------------------------%
