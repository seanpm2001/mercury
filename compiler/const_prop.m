%---------------------------------------------------------------------------%
% Copyright (C) 1997-1998 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% file: const_prop.m
% main author: conway.
%
% This module provides the facility to evaluate calls at compile time -
% transforming them to simpler goals such as construction unifications.
%
%------------------------------------------------------------------------------%

:- module const_prop.

:- interface.

:- import_module hlds_module, hlds_goal, hlds_pred, prog_data, instmap.
:- import_module list.

:- pred evaluate_builtin(pred_id, proc_id, list(prog_var), hlds_goal_info,
		hlds_goal_expr, hlds_goal_info, instmap,
		module_info, module_info).
:- mode evaluate_builtin(in, in, in, in, out, out, in, in, out) is semidet.

%------------------------------------------------------------------------------%

:- implementation.

:- import_module code_aux, det_analysis, follow_code, goal_util.
:- import_module hlds_goal, hlds_data, instmap, inst_match.
:- import_module globals, options, passes_aux, prog_data, mode_util, type_util.
:- import_module code_util, quantification, modes.
:- import_module bool, list, int, float, map, require.
:- import_module (inst), hlds_out, std_util.

%------------------------------------------------------------------------------%

evaluate_builtin(PredId, ProcId, Args, GoalInfo0, Goal, GoalInfo,
		InstMap, ModuleInfo0, ModuleInfo) :-
	predicate_module(ModuleInfo0, PredId, ModuleName),
	predicate_name(ModuleInfo0, PredId, PredName),
	proc_id_to_int(ProcId, ProcInt),
	LookupVarInsts = lambda([V::in, J::out] is det, (
		instmap__lookup_var(InstMap, V, VInst),
		J = V - VInst
	)),
	list__map(LookupVarInsts, Args, ArgInsts),
	evaluate_builtin_2(ModuleName, PredName, ProcInt, ArgInsts, GoalInfo0,
		Goal, GoalInfo, ModuleInfo0, ModuleInfo).

:- pred evaluate_builtin_2(module_name, string, int,
		list(pair(prog_var, (inst))), hlds_goal_info, hlds_goal_expr,
		hlds_goal_info, module_info, module_info).
:- mode evaluate_builtin_2(in, in, in, in, in, out, out, in, out) is semidet.

	% Module_info is not actually used at the moment.

evaluate_builtin_2(Module, Pred, ModeNum, Args, GoalInfo0, Goal, GoalInfo,
		ModuleInfo, ModuleInfo) :-
	% -- not yet:
	% Module = qualified(unqualified("std"), Mod),
	Module = unqualified(Mod),
	(
		Args = [X, Y],
		evaluate_builtin_bi(Mod, Pred, ModeNum, X, Y, W, Cons)
	->
		make_construction(W, Cons, Goal),
		goal_info_get_instmap_delta(GoalInfo0, Delta0),
		W = Var - _WInst,
		instmap_delta_set(Delta0, Var,
			bound(unique, [functor(Cons, [])]), Delta),
		goal_info_set_instmap_delta(GoalInfo0, Delta, GoalInfo)
	;
		Args = [X, Y, Z],
		evaluate_builtin_tri(Mod, Pred, ModeNum, X, Y, Z, W, Cons)
	->
		make_construction(W, Cons, Goal),
		goal_info_get_instmap_delta(GoalInfo0, Delta0),
		W = Var - _WInst,
		instmap_delta_set(Delta0, Var,
			bound(unique, [functor(Cons, [])]), Delta),
		goal_info_set_instmap_delta(GoalInfo0, Delta, GoalInfo)
	;
		evaluate_builtin_test(Mod, Pred, ModeNum, Args, Result)
	->
		make_true_or_fail(Result, GoalInfo0, Goal, GoalInfo)
	;
		fail
	).

%------------------------------------------------------------------------------%

:- pred evaluate_builtin_bi(string, string, int,
		pair(prog_var, (inst)), pair(prog_var, (inst)), 
		pair(prog_var, (inst)), cons_id).
:- mode evaluate_builtin_bi(in, in, in, in, in, out, out) is semidet.

	% Integer arithmetic

evaluate_builtin_bi("int", "+", 0, X, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	ZVal is XVal.

evaluate_builtin_bi("int", "-", 0, X, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	ZVal is -XVal.

evaluate_builtin_bi("int", "\\", 0, X, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	ZVal is \ XVal.

	% Floating point arithmetic

evaluate_builtin_bi("float", "+", 0, X, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	ZVal is XVal.

evaluate_builtin_bi("float", "-", 0, X, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	ZVal is -XVal.

%------------------------------------------------------------------------------%

:- pred evaluate_builtin_tri(string, string, int,
		pair(prog_var, (inst)), pair(prog_var, (inst)),
		pair(prog_var, (inst)), pair(prog_var, (inst)), cons_id).
:- mode evaluate_builtin_tri(in, in, in, in, in, in, out, out) is semidet.

	%
	% Integer arithmetic
	%
evaluate_builtin_tri("int", "+", 0, X, Y, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	ZVal is XVal + YVal.
evaluate_builtin_tri("int", "+", 1, X, Y, Z, X, int_const(XVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(int_const(ZVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	XVal is ZVal - YVal.
evaluate_builtin_tri("int", "+", 2, X, Y, Z, Y, int_const(YVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(int_const(ZVal), [])]),
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	YVal is ZVal - XVal.

evaluate_builtin_tri("int", "-", 0, X, Y, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	ZVal is XVal - YVal.
evaluate_builtin_tri("int", "-", 1, X, Y, Z, X, int_const(XVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(int_const(ZVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	XVal is YVal + ZVal.
evaluate_builtin_tri("int", "-", 2, X, Y, Z, Y, int_const(YVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(int_const(ZVal), [])]),
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	YVal is XVal - ZVal.

evaluate_builtin_tri("int", "*", 0, X, Y, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	ZVal is XVal * YVal.
/****
evaluate_builtin_tri("int", "*", 1, X, Y, Z, X, int_const(XVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(int_const(ZVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	YVal \= 0,
	XVal is ZVal // YVal.
evaluate_builtin_tri("int", "*", 2, X, Y, Z, Y, int_const(YVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(int_const(ZVal), [])]),
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	XVal \= 0,
	YVal is ZVal // XVal.
****/

evaluate_builtin_tri("int", "//", 0, X, Y, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	YVal \= 0,
	ZVal is XVal // YVal.
/****
evaluate_builtin_tri("int", "//", 1, X, Y, Z, X, int_const(XVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(int_const(ZVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	XVal is ZVal * YVal.
evaluate_builtin_tri("int", "//", 2, X, Y, Z, Y, int_const(YVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(int_const(ZVal), [])]),
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	ZVal \= 0,
	YVal is XVal // ZVal.
****/

	% This isn't actually a builtin.
evaluate_builtin_tri("int", "mod", 0, X, Y, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	ZVal is XVal mod YVal.

evaluate_builtin_tri("int", "rem", 0, X, Y, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	ZVal is XVal rem YVal.

evaluate_builtin_tri("int", "unchecked_left_shift",
		0, X, Y, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	ZVal is unchecked_left_shift(XVal, YVal).

	% This isn't actually a builtin.
evaluate_builtin_tri("int", "<<", 0, X, Y, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	ZVal is XVal << YVal.

evaluate_builtin_tri("int", "unchecked_right_shift",
		0, X, Y, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	ZVal is unchecked_right_shift(XVal, YVal).

	% This isn't actually a builtin.
evaluate_builtin_tri("int", ">>", 0, X, Y, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	ZVal is XVal >> YVal.

evaluate_builtin_tri("int", "/\\", 0, X, Y, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	ZVal is XVal /\ YVal.

evaluate_builtin_tri("int", "\\/", 0, X, Y, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	ZVal is XVal \/ YVal.

evaluate_builtin_tri("int", "^", 0, X, Y, Z, Z, int_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	ZVal is XVal ^ YVal.

	%
	% float arithmetic
	%

evaluate_builtin_tri("float", "+", 0, X, Y, Z, Z, float_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(float_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(float_const(YVal), [])]),
	ZVal is XVal + YVal.
evaluate_builtin_tri("float", "+", 1, X, Y, Z, X, float_const(XVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(float_const(ZVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(float_const(YVal), [])]),
	XVal is ZVal - YVal.
evaluate_builtin_tri("float", "+", 2, X, Y, Z, Y, float_const(YVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(float_const(ZVal), [])]),
	X = _XVar - bound(_XUniq, [functor(float_const(XVal), [])]),
	YVal is ZVal - XVal.

evaluate_builtin_tri("float", "-", 0, X, Y, Z, Z, float_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(float_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(float_const(YVal), [])]),
	ZVal is XVal - YVal.
evaluate_builtin_tri("float", "-", 1, X, Y, Z, X, float_const(XVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(float_const(ZVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(float_const(YVal), [])]),
	XVal is YVal + ZVal.
evaluate_builtin_tri("float", "-", 2, X, Y, Z, Y, float_const(YVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(float_const(ZVal), [])]),
	X = _XVar - bound(_XUniq, [functor(float_const(XVal), [])]),
	YVal is XVal - ZVal.

evaluate_builtin_tri("float", "*", 0, X, Y, Z, Z, float_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(float_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(float_const(YVal), [])]),
	ZVal is XVal * YVal.
evaluate_builtin_tri("float", "*", 1, X, Y, Z, X, float_const(XVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(float_const(ZVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(float_const(YVal), [])]),
	YVal \= 0.0,
	XVal is ZVal / YVal.
evaluate_builtin_tri("float", "*", 2, X, Y, Z, Y, float_const(YVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(float_const(ZVal), [])]),
	X = _XVar - bound(_XUniq, [functor(float_const(XVal), [])]),
	XVal \= 0.0,
	YVal is ZVal / XVal.

evaluate_builtin_tri("float", "//", 0, X, Y, Z, Z, float_const(ZVal)) :-
	X = _XVar - bound(_XUniq, [functor(float_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(float_const(YVal), [])]),
	YVal \= 0.0,
	ZVal is XVal / YVal.
evaluate_builtin_tri("float", "//", 1, X, Y, Z, X, float_const(XVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(float_const(ZVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(float_const(YVal), [])]),
	XVal is ZVal * YVal.
evaluate_builtin_tri("float", "//", 2, X, Y, Z, Y, float_const(YVal)) :-
	Z = _ZVar - bound(_ZUniq, [functor(float_const(ZVal), [])]),
	X = _XVar - bound(_XUniq, [functor(float_const(XVal), [])]),
	ZVal \= 0.0,
	YVal is XVal / ZVal.

%------------------------------------------------------------------------------%

:- pred evaluate_builtin_test(string, string, int,
		list(pair(prog_var, inst)), bool).
:- mode evaluate_builtin_test(in, in, in, in, out) is semidet.

	% Integer comparisons

evaluate_builtin_test("int", "<", 0, Args, Result) :-
	Args = [X, Y],
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	( XVal < YVal ->
		Result = yes
	;
		Result = no
	).
evaluate_builtin_test("int", "=<", 0, Args, Result) :-
	Args = [X, Y],
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	( XVal =< YVal ->
		Result = yes
	;
		Result = no
	).
evaluate_builtin_test("int", ">", 0, Args, Result) :-
	Args = [X, Y],
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	( XVal > YVal ->
		Result = yes
	;
		Result = no
	).
evaluate_builtin_test("int", ">=", 0, Args, Result) :-
	Args = [X, Y],
	X = _XVar - bound(_XUniq, [functor(int_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(int_const(YVal), [])]),
	( XVal >= YVal ->
		Result = yes
	;
		Result = no
	).

	% Float comparisons

evaluate_builtin_test("float", "<", 0, Args, Result) :-
	Args = [X, Y],
	X = _XVar - bound(_XUniq, [functor(float_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(float_const(YVal), [])]),
	( XVal < YVal ->
		Result = yes
	;
		Result = no
	).
evaluate_builtin_test("float", "=<", 0, Args, Result) :-
	Args = [X, Y],
	X = _XVar - bound(_XUniq, [functor(float_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(float_const(YVal), [])]),
	( XVal =< YVal ->
		Result = yes
	;
		Result = no
	).
evaluate_builtin_test("float", ">", 0, Args, Result) :-
	Args = [X, Y],
	X = _XVar - bound(_XUniq, [functor(float_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(float_const(YVal), [])]),
	( XVal > YVal ->
		Result = yes
	;
		Result = no
	).
evaluate_builtin_test("float", ">=", 0, Args, Result) :-
	Args = [X, Y],
	X = _XVar - bound(_XUniq, [functor(float_const(XVal), [])]),
	Y = _YVar - bound(_YUniq, [functor(float_const(YVal), [])]),
	( XVal >= YVal ->
		Result = yes
	;
		Result = no
	).

%------------------------------------------------------------------------------%

:- pred make_construction(pair(prog_var, inst), cons_id, hlds_goal_expr).
:- mode make_construction(in, in, out) is det.

make_construction(Var - VarInst, ConsId, Goal) :-
	RHS = functor(ConsId, []),
	CInst = bound(unique, [functor(ConsId, [])]),
	Mode =  (VarInst -> CInst) - (CInst -> CInst),
	Unification = construct(Var, ConsId, [], []),
	Context = unify_context(explicit, []),
	Goal = unify(Var, RHS, Mode, Unification, Context).

%------------------------------------------------------------------------------%

:- pred make_true_or_fail(bool, hlds_goal_info, hlds_goal_expr, hlds_goal_info).
:- mode make_true_or_fail(in, in, out, out) is det.

make_true_or_fail(yes, GoalInfo, conj([]), GoalInfo).
make_true_or_fail(no, GoalInfo, disj([], SM), GoalInfo) :-
	map__init(SM).

%------------------------------------------------------------------------------%
