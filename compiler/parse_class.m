%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 1997-2011 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: parse_class.m.
% Main authors: dgj.
%
% This module handles the parsing of typeclass declarations.
% Perhaps some of this should go into parse_util.m?
%
%---------------------------------------------------------------------------%

:- module parse_tree.parse_class.
:- interface.

:- import_module mdbcomp.sym_name.
:- import_module parse_tree.maybe_error.
:- import_module parse_tree.parse_types.
:- import_module parse_tree.prog_data.

:- import_module list.
:- import_module term.
:- import_module varset.

%---------------------------------------------------------------------------%

    % Parse a typeclass declaration.
    %
:- pred parse_typeclass_item(module_name::in, varset::in, list(term)::in,
    prog_context::in, int::in, maybe1(item_or_marker)::out) is det.

    % Parse an instance declaration.
    %
:- pred parse_instance_item(module_name::in, varset::in, list(term)::in,
    prog_context::in, int::in, maybe1(item_or_marker)::out) is det.

    % Parse constraints on a pred or func declaration, or on an existentially
    % quantified type definition. Currently all such constraints must be
    % simple.
    %
:- pred parse_class_constraints(module_name::in, varset::in, term::in,
    maybe1(list(prog_constraint))::out) is det.

    % Parse a list of class and inst constraints.
    %
:- pred parse_class_and_inst_constraints(module_name::in, varset::in, term::in,
    maybe_class_and_inst_constraints::out) is det.

:- type maybe_class_and_inst_constraints ==
    maybe2(list(prog_constraint), inst_var_sub).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module mdbcomp.prim_data.
:- import_module parse_tree.error_util.
:- import_module parse_tree.parse_inst_mode_name.
:- import_module parse_tree.parse_item.
:- import_module parse_tree.parse_sym_name.
:- import_module parse_tree.parse_tree_out_term.
:- import_module parse_tree.parse_type_name.
:- import_module parse_tree.parse_util.
:- import_module parse_tree.prog_item.
:- import_module parse_tree.prog_type.
:- import_module parse_tree.prog_util.

:- import_module cord.
:- import_module map.
:- import_module maybe.
:- import_module require.

%---------------------------------------------------------------------------%

parse_typeclass_item(ModuleName, VarSet, ArgTerms, Context, SeqNum,
        MaybeIOM) :-
    ( if ArgTerms = [ArgTerm] then
        ( if
            ArgTerm = term.functor(term.atom("where"),
                [NameTerm, MethodsTerm], _)
        then
            parse_non_empty_class(ModuleName, VarSet, NameTerm, MethodsTerm,
                Context, SeqNum, MaybeItemTypeClassInfo)
        else
            parse_class_head(ModuleName, VarSet, ArgTerm, Context, SeqNum,
                MaybeItemTypeClassInfo)
        ),
        (
            MaybeItemTypeClassInfo = ok1(ItemTypeClassInfo),
            MaybeIOM = ok1(iom_item(item_typeclass(ItemTypeClassInfo)))
        ;
            MaybeItemTypeClassInfo = error1(Specs),
            MaybeIOM = error1(Specs)
        )
    else
        Pieces = [words("Error: a"), decl("typeclass"), words("declaration"),
            words("should have the form"),
            quote(":- typeclass tcname(T1, ... Tn)"),
            words("optionally followed by"),
            quote("where [method_signature_1, ... method_signature_m]"),
            suffix("."), nl],
        Spec = error_spec(severity_error, phase_term_to_parse_tree,
            [simple_msg(Context, [always(Pieces)])]),
        MaybeIOM = error1([Spec])
    ).

:- pred parse_non_empty_class(module_name::in, varset::in, term::in, term::in,
    prog_context::in, int::in, maybe1(item_typeclass_info)::out) is det.

parse_non_empty_class(ModuleName, VarSet, NameTerm, MethodsTerm,
        Context, SeqNum, MaybeItemTypeClassInfo) :-
    parse_class_head(ModuleName, VarSet, NameTerm, Context, SeqNum,
        MaybeItemTypeClassInfo0),
    parse_class_methods(ModuleName, VarSet, MethodsTerm, MaybeClassMethods),
    ( if
        MaybeItemTypeClassInfo0 = ok1(ItemTypeClassInfo0),
        MaybeClassMethods = ok1(ClassMethods)
    then
        varset.coerce(VarSet, TVarSet),
        ItemTypeClassInfo = ((ItemTypeClassInfo0
            ^ tc_class_methods := class_interface_concrete(ClassMethods))
            ^ tc_varset := TVarSet),
        MaybeItemTypeClassInfo = ok1(ItemTypeClassInfo)
    else
        Specs = get_any_errors1(MaybeItemTypeClassInfo0) ++
            get_any_errors1(MaybeClassMethods),
        MaybeItemTypeClassInfo = error1(Specs)
    ).

:- pred parse_class_head(module_name::in, varset::in, term::in,
    prog_context::in, int::in, maybe1(item_typeclass_info)::out) is det.

parse_class_head(ModuleName, VarSet, ArgTerm, Context, SeqNum,
        MaybeItemTypeClassInfo) :-
    ( if
        ArgTerm = term.functor(term.atom("<="), [NameTerm, ConstraintsTerm], _)
    then
        parse_constrained_class(ModuleName, VarSet, NameTerm, ConstraintsTerm,
            Context, SeqNum, MaybeItemTypeClassInfo)
    else
        varset.coerce(VarSet, TVarSet),
        parse_unconstrained_class(ModuleName, TVarSet, ArgTerm,
            Context, SeqNum, MaybeItemTypeClassInfo)
    ).

:- pred parse_constrained_class(module_name::in, varset::in,
    term::in, term::in, prog_context::in, int::in,
    maybe1(item_typeclass_info)::out) is det.

parse_constrained_class(ModuleName, VarSet, NameTerm, ConstraintsTerm,
        Context, SeqNum, MaybeItemTypeClass) :-
    varset.coerce(VarSet, TVarSet),
    parse_superclass_constraints(ModuleName, VarSet, ConstraintsTerm,
        MaybeParsedConstraints),
    (
        MaybeParsedConstraints = ok2(ConstraintList, FunDeps),
        parse_unconstrained_class(ModuleName, TVarSet, NameTerm,
            Context, SeqNum, MaybeItemTypeClass0),
        (
            MaybeItemTypeClass0 = error1(_),
            MaybeItemTypeClass = MaybeItemTypeClass0
        ;
            MaybeItemTypeClass0 = ok1(ItemTypeClass0),
            % Check for type variables in the constraints which do not
            % occur in the type class parameters.

            constraint_list_get_tvars(ConstraintList, ConstraintVars),
            list.sort_and_remove_dups(ConstraintVars, SortedConstraintVars),
            FunDepVars = tvars_in_fundeps(FunDeps),
            list.sort_and_remove_dups(FunDepVars, SortedFunDepVars),

            Params = ItemTypeClass0 ^ tc_class_params,
            list.filter(is_in_list(Params), SortedConstraintVars,
                _ConstraintInParams, ConstraintNotInParams),
            list.filter(is_in_list(Params), SortedFunDepVars,
                _FunDepInParams, FunDepNotInParams),
            (
                ConstraintNotInParams = [_ | _],
                ( if list.length(ConstraintList) = 1 then
                    ConstraintErrorContext =
                        [words("in the superclass constraint")]
                else
                    ConstraintErrorContext =
                        [words("in superclass constraints")]
                )
            ;
                ConstraintNotInParams = [],
                ConstraintErrorContext = []
            ),
            (
                FunDepNotInParams = [_ | _],
                ( if list.length(FunDeps) = 1 then
                    FunDepErrorContext =
                        [words("in the functional dependency")]
                else
                    FunDepErrorContext =
                        [words("in functional dependencies")]
                )
            ;
                FunDepNotInParams = [],
                FunDepErrorContext = []
            ),
            NotInParams = ConstraintNotInParams ++ FunDepNotInParams,
            (
                NotInParams = [],
                ItemTypeClass = ((ItemTypeClass0
                    ^ tc_constraints := ConstraintList)
                    ^ tc_fundeps := FunDeps),
                MaybeItemTypeClass = ok1(ItemTypeClass)
            ;
                NotInParams = [_ | _],
                ClassTVarSet = ItemTypeClass0 ^ tc_varset,
                ConstraintNotInParamsStrs = list.map(
                    mercury_var_to_name_only(ClassTVarSet),
                    ConstraintNotInParams),
                FunDepNotInParamsStrs = list.map(
                    mercury_var_to_name_only(ClassTVarSet),
                    FunDepNotInParams),
                ConstraintNotInParamsPieces =
                    list_to_pieces(ConstraintNotInParamsStrs),
                FunDepNotInParamsPieces =
                    list_to_pieces(FunDepNotInParamsStrs),
                ( if list.length(NotInParams) = 1 then
                    Prefix = [words("Error: type variable")],
                    Suffix = [words("is not a parameter of this type class.")]
                else
                    Prefix = [words("Error: type variables")],
                    Suffix = [words("are not parameters of this type class.")]
                ),
                (
                    ConstraintNotInParams = [],
                    FunDepNotInParams = [],
                    unexpected($module, $pred, "no NotInParams")
                ;
                    ConstraintNotInParams = [],
                    FunDepNotInParams = [_ | _],
                    Middle =
                        FunDepNotInParamsPieces ++ FunDepErrorContext
                ;
                    ConstraintNotInParams = [_ | _],
                    FunDepNotInParams = [],
                    Middle =
                        ConstraintNotInParamsPieces ++ ConstraintErrorContext
                ;
                    ConstraintNotInParams = [_ | _],
                    FunDepNotInParams = [_ | _],
                    Middle =
                        ConstraintNotInParamsPieces ++ ConstraintErrorContext
                        ++ [words("and")] ++
                        FunDepNotInParamsPieces ++ FunDepErrorContext
                ),
                Pieces = Prefix ++ Middle ++ Suffix ++ [nl],
                Spec = error_spec(severity_error, phase_term_to_parse_tree,
                    [simple_msg(Context, [always(Pieces)])]),
                MaybeItemTypeClass = error1([Spec])
            )
        )
    ;
        MaybeParsedConstraints = error2(Specs),
        MaybeItemTypeClass = error1(Specs)
    ).

:- func tvars_in_fundeps(list(prog_fundep)) = list(tvar).

tvars_in_fundeps(FunDeps) = list.condense(list.map(tvars_in_fundep, FunDeps)).

:- func tvars_in_fundep(prog_fundep) = list(tvar).

tvars_in_fundep(fundep(Domain, Range)) = Domain ++ Range.

:- pred parse_superclass_constraints(module_name::in, varset::in, term::in,
    maybe2(list(prog_constraint), list(prog_fundep))::out) is det.

parse_superclass_constraints(_ModuleName, VarSet, ConstraintsTerm, Result) :-
    parse_arbitrary_constraints(VarSet, ConstraintsTerm, Result0),
    (
        Result0 = ok1(one_or_more(HeadArbConstraint, TailArbConstraints)),
        ArbitraryConstraints = [HeadArbConstraint | TailArbConstraints],
        ( if
            collect_simple_and_fundep_constraints(ArbitraryConstraints,
                Constraints, FunDeps)
        then
            Result = ok2(Constraints, FunDeps)
        else
            Pieces = [words("Error: constraints on class declarations"),
                words("may only constrain type variables and ground types."),
                nl],
            Spec = error_spec(severity_error, phase_term_to_parse_tree,
                [simple_msg(get_term_context(ConstraintsTerm),
                    [always(Pieces)])]),
            Result = error2([Spec])
        )
    ;
        Result0 = error1(Specs),
        Result = error2(Specs)
    ).

:- pred collect_simple_and_fundep_constraints(list(arbitrary_constraint)::in,
    list(prog_constraint)::out, list(prog_fundep)::out) is semidet.

collect_simple_and_fundep_constraints([], [], []).
collect_simple_and_fundep_constraints([Constraint | Constraints],
        SimpleConstraints, FunDeps) :-
    collect_simple_and_fundep_constraints(Constraints, SimpleConstraints0,
        FunDeps0),
    (
        Constraint = simple(SimpleConstraint),
        SimpleConstraints = [SimpleConstraint | SimpleConstraints0],
        FunDeps = FunDeps0
    ;
        Constraint = fundep(FunDep),
        FunDeps = [FunDep | FunDeps0],
        SimpleConstraints = SimpleConstraints0
    ).

:- pred parse_unconstrained_class(module_name::in, tvarset::in, term::in,
    prog_context::in, int::in, maybe1(item_typeclass_info)::out) is det.

parse_unconstrained_class(ModuleName, TVarSet, NameTerm, Context, SeqNum,
        MaybeTypeClassInfo) :-
    ContextPieces = cord.singleton(words("In typeclass declaration:")),
    varset.coerce(TVarSet, VarSet),
    parse_implicitly_qualified_sym_name_and_args(ModuleName, NameTerm,
        VarSet, ContextPieces, MaybeClassName),
    (
        MaybeClassName = ok2(ClassName, TermVars0),
        list.map(term.coerce, TermVars0, TermVars),
        (
            TermVars = [],
            Pieces = [words("Error: typeclass declarations require"),
                words("at least one class parameter."), nl],
            Spec = error_spec(severity_error, phase_term_to_parse_tree,
                [simple_msg(get_term_context(NameTerm), [always(Pieces)])]),
            MaybeTypeClassInfo = error1([Spec])
        ;
            TermVars = [_ | _],
            ( if
                term.term_list_to_var_list(TermVars, Vars),
                list.sort_and_remove_dups(TermVars, SortedTermVars),
                list.length(SortedTermVars, NumSortedTermVars),
                list.length(TermVars, NumTermVars),
                NumSortedTermVars = NumTermVars
            then
                % XXX Would this be a better context?
                % Context = get_term_context(NameTerm),
                TypeClassInfo = item_typeclass_info(ClassName, Vars, [], [],
                    class_interface_abstract, TVarSet, Context, SeqNum),
                MaybeTypeClassInfo = ok1(TypeClassInfo)
            else
                Pieces = [words("Error: expected distinct variables"),
                    words("as class parameters."), nl],
                % XXX Would Context be better than get_term_context(NameTerm)?
                Spec = error_spec(severity_error, phase_term_to_parse_tree,
                    [simple_msg(get_term_context(NameTerm),
                        [always(Pieces)])]),
                MaybeTypeClassInfo = error1([Spec])
            )
        )
    ;
        MaybeClassName = error2(Specs),
        MaybeTypeClassInfo = error1(Specs)
    ).

:- pred parse_class_methods(module_name::in, varset::in, term::in,
    maybe1(class_methods)::out) is det.

parse_class_methods(ModuleName, VarSet, MethodsTerm, MaybeClassMethods) :-
    ( if
        % Convert the list of terms into a list of maybe1(class_method)s.
        list_term_to_term_list(MethodsTerm, MethodTerms)
    then
        list.map(parse_class_method_decl(ModuleName, VarSet),
            MethodTerms, MaybeMethods),
        find_errors(MaybeMethods, MaybeClassMethods)
    else
        Pieces = [words("Error: expected a list of class methods."), nl],
        Spec = error_spec(severity_error, phase_term_to_parse_tree,
            [simple_msg(get_term_context(MethodsTerm), [always(Pieces)])]),
        MaybeClassMethods = error1([Spec])
    ).

    % From a list of maybe1s, search through until you find an error.
    % If some errors are found, error1(their union).
    % If no error is found, return ok1(the original elements).
    %
:- pred find_errors(list(maybe1(T))::in, maybe1(list(T))::out) is det.

find_errors(Xs, Result) :-
    find_errors_2(Xs, [], Methods, [], Specs),
    (
        Specs = [],
        Result = ok1(Methods)
    ;
        Specs = [_ | _],
        Result = error1(Specs)
    ).

:- pred find_errors_2(list(maybe1(T))::in, list(T)::in, list(T)::out,
    list(error_spec)::in, list(error_spec)::out) is det.

find_errors_2([], !Methods, !Specs).
find_errors_2([X | Xs], !Methods, !Specs) :-
    find_errors_2(Xs, !Methods, !Specs),
    (
        X = ok1(CurMethod),
        !:Methods = [CurMethod | !.Methods]
    ;
        X = error1(CurSpecs),
        !:Specs = CurSpecs ++ !.Specs
    ).

%---------------------------------------------------------------------------%
%
% Predicates for parsing various kinds of constraints.
%

parse_class_constraints(ModuleName, VarSet, ConstraintsTerm, Result) :-
    Pieces = [words("Sorry, not implemented:"),
        words("constraints may only constrain type variables"),
        words("and ground types"), nl],
    parse_simple_class_constraints(ModuleName, VarSet, ConstraintsTerm, Pieces,
        Result).

:- pred parse_simple_class_constraints(module_name::in, varset::in, term::in,
    list(format_component)::in, maybe1(list(prog_constraint))::out) is det.

parse_simple_class_constraints(_ModuleName, VarSet, ConstraintsTerm, Pieces,
        Result) :-
    parse_arbitrary_constraints(VarSet, ConstraintsTerm, Result0),
    (
        Result0 = ok1(one_or_more(HeadArbConstraint, TailArbConstraints)),
        ( if
            % Fail if any of the constraints aren't simple.
            get_simple_constraint(HeadArbConstraint, HeadConstraint),
            list.map(get_simple_constraint,
                TailArbConstraints, TailConstraints)
        then
            % XXX ITEM_LIST Loosens representation; switching from one_or_more
            % to list allows an empty list.
            Result = ok1([HeadConstraint | TailConstraints])
        else
            Spec = error_spec(severity_error, phase_term_to_parse_tree,
                [simple_msg(get_term_context(ConstraintsTerm),
                    [always(Pieces)])]),
            Result = error1([Spec])
        )
    ;
        Result0 = error1(Specs),
        Result = error1(Specs)
    ).

:- pred get_simple_constraint(arbitrary_constraint::in, prog_constraint::out)
    is semidet.

get_simple_constraint(simple(Constraint), Constraint).

parse_class_and_inst_constraints(_ModuleName, VarSet, ConstraintsTerm,
        Result) :-
    parse_arbitrary_constraints(VarSet, ConstraintsTerm, Result0),
    (
        Result0 = ok1(one_or_more(HeadArbConstraint, TailArbConstraints)),
        ArbitraryConstraints = [HeadArbConstraint | TailArbConstraints],
        ( if
            collect_class_and_inst_constraints(ArbitraryConstraints,
                ProgConstraints, InstVarSub)
        then
            Result = ok2(ProgConstraints, InstVarSub)
        else
            Pieces = [words("Error: functional dependencies are only allowed"),
                words("in typeclass declarations."), nl],
            Spec = error_spec(severity_error, phase_term_to_parse_tree,
                [simple_msg(get_term_context(ConstraintsTerm),
                    [always(Pieces)])]),
            Result = error2([Spec])
        )
    ;
        Result0 = error1(Specs),
        Result = error2(Specs)
    ).

:- pred collect_class_and_inst_constraints(list(arbitrary_constraint)::in,
    list(prog_constraint)::out, inst_var_sub::out) is semidet.

collect_class_and_inst_constraints([], [], map.init).
collect_class_and_inst_constraints([Constraint | Constraints],
        ProgConstraints, InstVarSub) :-
    collect_class_and_inst_constraints(Constraints, ProgConstraints0,
        InstVarSub0),
    (
        Constraint = simple(SimpleConstraint),
        ProgConstraints = [SimpleConstraint | ProgConstraints0],
        InstVarSub = InstVarSub0
    ;
        Constraint = non_simple(ClassConstraint),
        ProgConstraints = [ClassConstraint | ProgConstraints0],
        InstVarSub = InstVarSub0
    ;
        Constraint = inst_constraint(InstVar, Inst),
        map.set(InstVar, Inst, InstVarSub0, InstVarSub),
        ProgConstraints = ProgConstraints0
    ).

:- type arbitrary_constraint
    --->    simple(prog_constraint)
            % A class constraint whose arguments are either variables
            % or ground terms.

    ;       non_simple(prog_constraint)
            % An arbitrary class constraint not matching the description
            % of "simple".

    ;       inst_constraint(inst_var, mer_inst)
            % A constraint on an inst variable (that is, one whose head
            % is '=<'/2).

    ;       fundep(prog_fundep).
            % A functional dependency (that is, one whose head is '->'/2)
            % and whose arguments are comma-separated variables.

:- type arbitrary_constraints == one_or_more(arbitrary_constraint).

:- pred parse_arbitrary_constraints(varset::in, term::in,
    maybe1(arbitrary_constraints)::out) is det.

parse_arbitrary_constraints(VarSet, ConstraintsTerm, Result) :-
    conjunction_to_one_or_more(ConstraintsTerm,
        one_or_more(HeadConstraintTerm, TailConstraintTerms)),
    parse_arbitrary_constraint_list(VarSet,
        HeadConstraintTerm, TailConstraintTerms, Result).

:- pred parse_arbitrary_constraint_list(varset::in, term::in, list(term)::in,
    maybe1(arbitrary_constraints)::out) is det.

parse_arbitrary_constraint_list(VarSet, HeadTerm, TailTerms, Result) :-
    parse_arbitrary_constraint(VarSet, HeadTerm, HeadResult),
    (
        TailTerms = [],
        (
            HeadResult = ok1(HeadConstraint),
            Result = ok1(one_or_more(HeadConstraint, []))
        ;
            HeadResult = error1(Specs),
            Result = error1(Specs)
        )
    ;
        TailTerms = [HeadTailTerm | TailTailTerms],
        parse_arbitrary_constraint_list(VarSet, HeadTailTerm, TailTailTerms,
            TailResult),
        ( if
            HeadResult = ok1(HeadConstraint),
            TailResult = ok1(TailConstraints)
        then
            Result = ok1(one_or_more_cons(HeadConstraint, TailConstraints))
        else
            Result = error1(get_any_errors1(HeadResult) ++
                get_any_errors1(TailResult))
        )
    ).

:- pred parse_arbitrary_constraint(varset::in, term::in,
    maybe1(arbitrary_constraint)::out) is det.

parse_arbitrary_constraint(VarSet, ConstraintTerm, Result) :-
    ( if
        parse_inst_constraint(ConstraintTerm, InstVar, Inst)
    then
        Result = ok1(inst_constraint(InstVar, Inst))
    else if
        parse_fundep(ConstraintTerm, Result0)
    then
        Result = Result0
    else if
        try_parse_sym_name_and_args(ConstraintTerm, ClassName, Args0)
    then
        ArgsResultContextPieces =
            cord.singleton(words("In class or inst constraint:")),
        parse_types(no_allow_ho_inst_info, Args0, VarSet,
            ArgsResultContextPieces, ArgsResult),
        (
            ArgsResult = ok1(Args),
            Constraint = constraint(ClassName, Args),
            ( if constraint_is_not_simple(Constraint) then
                Result = ok1(non_simple(Constraint))
            else
                Result = ok1(simple(Constraint))
            )
        ;
            ArgsResult = error1(Specs),
            Result = error1(Specs)
        )
    else
        Pieces = [words("Error: expected atom"),
            words("as class name or inst constraint."), nl],
        Spec = error_spec(severity_error, phase_term_to_parse_tree,
            [simple_msg(get_term_context(ConstraintTerm), [always(Pieces)])]),
        Result = error1([Spec])
    ).

:- pred parse_inst_constraint(term::in, inst_var::out, mer_inst::out)
    is semidet.

parse_inst_constraint(Term, InstVar, Inst) :-
    Term = term.functor(term.atom("=<"), [Arg1, Arg2], _),
    Arg1 = term.variable(InstVar0, _),
    term.coerce_var(InstVar0, InstVar),
    convert_inst(no_allow_constrained_inst_var, Arg2, Inst).

:- pred parse_fundep(term::in, maybe1(arbitrary_constraint)::out) is semidet.

parse_fundep(Term, Result) :-
    Term = term.functor(term.atom("->"), [DomainTerm, RangeTerm], _),
    ( if
        parse_fundep_2(DomainTerm, Domain),
        parse_fundep_2(RangeTerm, Range)
    then
        Result = ok1(fundep(fundep(Domain, Range)))
    else
        Pieces = [words("Error: the domain and range"),
            words("of a functional dependency"),
            words("must be comma-separated lists of variables."), nl],
        Spec = error_spec(severity_error, phase_term_to_parse_tree,
            [simple_msg(get_term_context(Term), [always(Pieces)])]),
        Result = error1([Spec])
    ).

    % XXX ITEM_LIST Should return one_or_more(tvar).
    %
:- pred parse_fundep_2(term::in, list(tvar)::out) is semidet.

parse_fundep_2(TypesTerm0, TypeVars) :-
    TypesTerm = term.coerce(TypesTerm0),
    conjunction_to_list(TypesTerm, TypeTerms),
    term.term_list_to_var_list(TypeTerms, TypeVars).

:- pred constraint_is_not_simple(prog_constraint::in) is semidet.

constraint_is_not_simple(constraint(_ClassName, ArgTypes)) :-
    some [Type] (
        list.member(ArgType, ArgTypes),
        type_is_nonvar(ArgType),
        type_is_nonground(ArgType)
    ).

%---------------------------------------------------------------------------%

parse_instance_item(ModuleName, VarSet, ArgTerms, Context, SeqNum,
        MaybeIOM) :-
    ( if ArgTerms = [ArgTerm] then
        varset.coerce(VarSet, TVarSet),
        ( if
            ArgTerm = term.functor(term.atom("where"),
                [NameTerm, MethodsTerm], _)
        then
            parse_non_empty_instance(ModuleName, VarSet, TVarSet,
                NameTerm, MethodsTerm, Context, SeqNum, MaybeItemInstanceInfo)
        else
            parse_instance_name(ModuleName, TVarSet, ArgTerm,
                Context, SeqNum, MaybeItemInstanceInfo)
        ),
        (
            MaybeItemInstanceInfo = ok1(ItemInstanceInfo),
            MaybeIOM = ok1(iom_item(item_instance(ItemInstanceInfo)))
        ;
            MaybeItemInstanceInfo = error1(Specs),
            MaybeIOM = error1(Specs)
        )
    else
        Pieces = [words("Error: an"), decl("instance"), words("declaration"),
            words("should have the form"),
            quote(":- instance tcname(type1, ... typen)"),
            words("optionally followed by"),
            quote("where [method_spec_1, ... method_spec_m]"),
            suffix("."), nl],
        Spec = error_spec(severity_error, phase_term_to_parse_tree,
            [simple_msg(Context, [always(Pieces)])]),
        MaybeIOM = error1([Spec])
    ).

:- pred parse_instance_name(module_name::in, tvarset::in, term::in,
    prog_context::in, int::in, maybe1(item_instance_info)::out) is det.

parse_instance_name(ModuleName, TVarSet, ArgTerm, Context, SeqNum,
        MaybeItemInstanceInfo) :-
    ( if
        ArgTerm = term.functor(term.atom("<="), [NameTerm, ConstraintsTerm], _)
    then
        parse_derived_instance(ModuleName, TVarSet, NameTerm, ConstraintsTerm,
            Context, SeqNum, MaybeItemInstanceInfo)
    else
        parse_underived_instance(ModuleName, TVarSet, ArgTerm,
            Context, SeqNum, MaybeItemInstanceInfo)
    ).

:- pred parse_derived_instance(module_name::in, tvarset::in,
    term::in, term::in, prog_context::in, int::in,
    maybe1(item_instance_info)::out) is det.

parse_derived_instance(ModuleName, TVarSet, NameTerm, ConstraintsTerm,
        Context, SeqNum, MaybeItemInstanceInfo) :-
    varset.coerce(TVarSet, VarSet),
    parse_underived_instance(ModuleName, TVarSet, NameTerm,
        Context, SeqNum, MaybeItemInstanceInfo0),
    parse_instance_constraints(ModuleName, VarSet, ConstraintsTerm,
        MaybeInstanceConstraints),
    ( if
        MaybeItemInstanceInfo0 = ok1(ItemInstanceInfo0),
        MaybeInstanceConstraints = ok1(InstanceConstraints)
    then
        ItemInstanceInfo = ItemInstanceInfo0 ^ ci_deriving_class
            := InstanceConstraints,
        MaybeItemInstanceInfo = ok1(ItemInstanceInfo)
    else
        Specs = get_any_errors1(MaybeItemInstanceInfo0) ++
            get_any_errors1(MaybeInstanceConstraints),
        MaybeItemInstanceInfo = error1(Specs)
    ).

:- pred parse_instance_constraints(module_name::in, varset::in, term::in,
    maybe1(list(prog_constraint))::out) is det.

parse_instance_constraints(ModuleName, VarSet, ConstraintsTerm, Result) :-
    Pieces = [words("Error: constraints on instance declarations"),
        words("may only constrain type variables and ground types."), nl],
    parse_simple_class_constraints(ModuleName, VarSet, ConstraintsTerm, Pieces,
        Result).

:- pred parse_underived_instance(module_name::in, tvarset::in, term::in,
    prog_context::in, int::in, maybe1(item_instance_info)::out) is det.

parse_underived_instance(ModuleName, TVarSet, NameTerm, Context, SeqNum,
        MaybeItemInstanceInfo) :-
    % We don't give a default module name here since the instance declaration
    % could well be for a typeclass defined in another module.
    NameContextPieces = cord.singleton(words("In instance declaration:")),
    varset.coerce(TVarSet, VarSet),
    parse_sym_name_and_args(NameTerm, VarSet, NameContextPieces,
        MaybeClassName),
    (
        MaybeClassName = ok2(ClassName, TypeTerms),
        TypesContextPieces = NameContextPieces,
        parse_types(no_allow_ho_inst_info, TypeTerms, VarSet,
            TypesContextPieces, MaybeTypes),
        (
            MaybeTypes = ok1(Types),
            ItemInstanceInfo = item_instance_info(ClassName, Types, Types, [],
                instance_body_abstract, TVarSet, ModuleName, Context, SeqNum),
            MaybeItemInstanceInfo = ok1(ItemInstanceInfo)
        ;
            MaybeTypes = error1(Specs),
            MaybeItemInstanceInfo = error1(Specs)
        )
    ;
        MaybeClassName = error2(Specs),
        MaybeItemInstanceInfo = error1(Specs)
    ).

:- pred parse_non_empty_instance(module_name::in, varset::in, tvarset::in,
    term::in, term::in, prog_context::in, int::in,
    maybe1(item_instance_info)::out) is det.

parse_non_empty_instance(ModuleName, VarSet, TVarSet, NameTerm, MethodsTerm,
        Context, SeqNum, MaybeItemInstanceInfo) :-
    parse_instance_name(ModuleName, TVarSet, NameTerm, Context, SeqNum,
        MaybeItemInstanceInfo0),
    parse_instance_methods(ModuleName, VarSet, MethodsTerm,
        MaybeInstanceMethods),
    ( if
        MaybeItemInstanceInfo0 = ok1(ItemInstanceInfo0),
        MaybeInstanceMethods = ok1(InstanceMethods)
    then
        ItemInstanceInfo = ((ItemInstanceInfo0
            ^ ci_method_instances := instance_body_concrete(InstanceMethods))
            ^ ci_varset := TVarSet),
        check_tvars_in_instance_constraint(ItemInstanceInfo, NameTerm,
            MaybeCheckSpec),
        (
            MaybeCheckSpec = yes(Spec),
            MaybeItemInstanceInfo = error1([Spec])
        ;
            MaybeCheckSpec = no,
            MaybeItemInstanceInfo = ok1(ItemInstanceInfo)
        )
    else
        Specs = get_any_errors1(MaybeItemInstanceInfo0) ++
            get_any_errors1(MaybeInstanceMethods),
        MaybeItemInstanceInfo = error1(Specs)
    ).

:- pred check_tvars_in_instance_constraint(item_instance_info::in,
    term::in, maybe(error_spec)::out) is det.

check_tvars_in_instance_constraint(ItemInstanceInfo, NameTerm, MaybeSpec) :-
    % XXX
    ItemInstanceInfo = item_instance_info(_Name, Types, _OriginalTypes,
        Constraints, _Methods, TVarSet, _ModName, _Context, _SeqNum),
    % Check that all of the type variables in the constraints on the instance
    % declaration also occur in the type class argument types in the instance
    % declaration.
    ( if
        prog_type.constraint_list_get_tvars(Constraints, TVars),
        type_vars_list(Types, TypesVars),
        list.filter(is_in_list(TypesVars), TVars, _BoundTVars, UnboundTVars),
        UnboundTVars = [_ | _]
    then
        UnboundTVarStrs = list.map(mercury_var_to_name_only(TVarSet),
            UnboundTVars),
        UnboundTVarPieces = list_to_pieces(UnboundTVarStrs),
        ( if list.length(UnboundTVars) = 1 then
            Prefix = [words("Error: unbound type variable")]
        else
            Prefix = [words("Error: unbound type variables")]
        ),
        Pieces = Prefix ++ UnboundTVarPieces ++
            [words("in constraints on instance declaration."), nl],
        % XXX Would _Context be better than get_term_context(NameTerm)?
        Spec = error_spec(severity_error, phase_term_to_parse_tree,
            [simple_msg(get_term_context(NameTerm), [always(Pieces)])]),
        MaybeSpec = yes(Spec)
    else
        MaybeSpec = no
    ).

:- pred parse_instance_methods(module_name::in, varset::in, term::in,
    maybe1(list(instance_method))::out) is det.

parse_instance_methods(ModuleName, VarSet, MethodsTerm, Result) :-
    ( if list_term_to_term_list(MethodsTerm, MethodList) then
        % Convert the list of terms into a list of maybe1(class_method)s.
        list.map(term_to_instance_method(ModuleName, VarSet), MethodList,
            Interface),
        find_errors(Interface, Result)
    else
        Pieces = [words("Error: expected list of instance methods."), nl],
        Spec = error_spec(severity_error, phase_term_to_parse_tree,
            [simple_msg(get_term_context(MethodsTerm), [always(Pieces)])]),
        Result = error1([Spec])
    ).

    % Turn the term into a method instance.
    %
:- pred term_to_instance_method(module_name::in, varset::in, term::in,
    maybe1(instance_method)::out) is det.

term_to_instance_method(_ModuleName, VarSet, MethodTerm,
        MaybeInstanceMethod) :-
    ( if
        MethodTerm = term.functor(term.atom("is"),
            [ClassMethodTerm, InstanceMethodTerm], TermContext)
    then
        % Note that the codes for 'pred(...)' and 'func(...)' are very similar.
        % Unfortunately, factoring out the common code would not really
        % simplify things.
        ( if
            ClassMethodTerm = term.functor(term.atom("pred"), [SlashTerm], _),
            SlashTerm = term.functor(term.atom("/"),
                [PredNameTerm, ArityTerm], _)
        then
            ( if
                try_parse_sym_name_and_no_args(PredNameTerm, PredName),
                ArityTerm = term.functor(term.integer(ArityInt), [], _),
                try_parse_sym_name_and_no_args(InstanceMethodTerm,
                    InstanceMethodName)
            then
                InstanceMethod = instance_method(pf_predicate, PredName,
                    instance_proc_def_name(InstanceMethodName), ArityInt,
                    TermContext),
                MaybeInstanceMethod = ok1(InstanceMethod)
            else
                MethodTermStr = describe_error_term(VarSet, MethodTerm),
                Pieces = [words("Error: expected"),
                    quote("pred(<Name> / <Arity>) is <InstanceMethod>"),
                    suffix(","),
                    words("not"), words(MethodTermStr), suffix("."), nl],
                Spec = error_spec(severity_error, phase_term_to_parse_tree,
                    [simple_msg(get_term_context(MethodTerm),
                        [always(Pieces)])]),
                MaybeInstanceMethod = error1([Spec])
            )
        else if
            ClassMethodTerm = term.functor(term.atom("func"), [SlashTerm], _),
            SlashTerm = term.functor(term.atom("/"),
                [FuncNameTerm, ArityTerm], _)
        then
            ( if
                try_parse_sym_name_and_no_args(FuncNameTerm, FuncName),
                ArityTerm = term.functor(term.integer(ArityInt), [], _),
                try_parse_sym_name_and_no_args(InstanceMethodTerm,
                    InstanceMethodName)
            then
                InstanceMethod = instance_method(pf_function, FuncName,
                    instance_proc_def_name(InstanceMethodName), ArityInt,
                    TermContext),
                MaybeInstanceMethod = ok1(InstanceMethod)
            else
                MethodTermStr = describe_error_term(VarSet, MethodTerm),
                Pieces = [words("Error: expected"),
                    quote("func(<Name> / <Arity>) is <InstanceMethod>"),
                    suffix(","),
                    words("not"), words(MethodTermStr), suffix("."), nl],
                Spec = error_spec(severity_error, phase_term_to_parse_tree,
                    [simple_msg(get_term_context(MethodTerm),
                        [always(Pieces)])]),
                MaybeInstanceMethod = error1([Spec])
            )
        else
            MethodTermStr = describe_error_term(VarSet, MethodTerm),
            Pieces = [words("Error: expected"),
                quote("pred(<Name> / <Arity>) is <InstanceName>"),
                words("or"),
                quote("func(<Name> / <Arity>) is <InstanceName>"),
                suffix(","),
                words("not"), words(MethodTermStr), suffix("."), nl],
            Spec = error_spec(severity_error, phase_term_to_parse_tree,
                [simple_msg(get_term_context(MethodTerm), [always(Pieces)])]),
            MaybeInstanceMethod = error1([Spec])
        )
    else
        % For the clauses in an instance declaration, the default module name
        % for the clause heads is the module name of the class that this is an
        % instance declaration for, but we don't necessarily know what module
        % that is at this point, since the class name hasn't been fully
        % qualified yet. So here we give the special module name "" as the
        % default, which means that there is no default. (If the module
        % qualifiers in the clauses don't match the module name of the class,
        % we will pick that up later, in check_typeclass.m.)

        DefaultModuleName = unqualified(""),
        parse_item_or_marker(DefaultModuleName, VarSet, MethodTerm, -1,
            MaybeIOM),
        (
            MaybeIOM = error1(Specs),
            MaybeInstanceMethod = error1(Specs)
        ;
            MaybeIOM = ok1(IOM),
            ( if
                IOM = iom_item(Item),
                Item = item_clause(ItemClause)
            then
                ItemClause = item_clause_info(ClassMethodName, PredOrFunc,
                    HeadArgs, _Origin, _VarSet, _ClauseBody, Context, _SeqNum),
                adjust_func_arity(PredOrFunc, ArityInt, list.length(HeadArgs)),
                InstanceMethod = instance_method(PredOrFunc, ClassMethodName,
                    instance_proc_def_clauses([ItemClause]), ArityInt,
                    Context),
                MaybeInstanceMethod = ok1(InstanceMethod)
            else
                MethodTermStr = describe_error_term(VarSet, MethodTerm),
                Pieces = [words("Error: expected clause or"),
                    quote("pred(<Name> / <Arity>) is <InstanceName>"),
                    words("or"),
                    quote("func(<Name> / <Arity>) is <InstanceName>"),
                    suffix(","),
                    words("not"), words(MethodTermStr), suffix("."), nl],
                Spec = error_spec(severity_error, phase_term_to_parse_tree,
                    [simple_msg(get_term_context(MethodTerm),
                        [always(Pieces)])]),
                MaybeInstanceMethod = error1([Spec])
            )
        )
    ).

%---------------------------------------------------------------------------%

:- pred is_in_list(list(T)::in, T::in) is semidet.

is_in_list(List, Element) :-
    list.member(Element, List).

%---------------------------------------------------------------------------%
:- end_module parse_tree.parse_class.
%---------------------------------------------------------------------------%