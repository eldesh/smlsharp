(**
 * Utility functions to manipulate the typed pattern calculus.
 * @copyright (c) 2006, Tohoku University.
 * @author Atsushi Ohori 
 * @version $Id: TypedCalcUtils.sml,v 1.20.6.5 2010/01/29 06:41:34 hiro-en Exp $
 *)
structure TypedCalcUtils = struct
local 
  structure T = Types 
  structure TC = TypedCalc
  structure TB = TypesBasics
  structure BT = BuiltinTypes
  fun bug s = Bug.Bug ("TypedCalcUtil: " ^ s)
  val tempVarNamePrefix = "T_"
in
  fun newTCVarName loc = Symbol.generateWithPrefix tempVarNamePrefix
  fun newTCVarInfo loc (ty:T.ty) =
      let
        val newVarId = VarID.generate()
        val IdString =  VarID.toString newVarId
        val longsymbol = Symbol.mkLongsymbol [tempVarNamePrefix ^ IdString] loc
      in
        {path=longsymbol, id=newVarId, ty = ty, opaque=false}
      end
  fun newTCVarInfoWithLongsymbol (longsymbol:Symbol.longsymbol,ty:T.ty) =
      let
        val newVarId = VarID.generate()
      in
        {path=longsymbol, id=newVarId, ty = ty, opaque=false}
      end
  fun getLocOfExp exp =
      case exp of
        TC.TPERROR => Loc.noloc
      | TC.TPCONSTANT {const, ty, loc} => loc
      | TC.TPVAR {path,...} => Symbol.longsymbolToLoc path
      | TC.TPEXVAR {path,...} => Symbol.longsymbolToLoc path
      | TC.TPRECFUNVAR {var={path,...},...} => Symbol.longsymbolToLoc path
      | TC.TPFNM  {loc,...} => loc
      | TC.TPAPPM {loc,...} => loc
      | TC.TPDATACONSTRUCT {loc,...} => loc
      | TC.TPEXNCONSTRUCT {loc,...} => loc
      | TC.TPEXN_CONSTRUCTOR {loc,...} => loc
      | TC.TPEXEXN_CONSTRUCTOR {loc,...} => loc
      | TC.TPCASEM {loc,...} => loc
      | TC.TPPRIMAPPLY {loc,...} => loc
      | TC.TPOPRIMAPPLY {loc,...} => loc
      | TC.TPRECORD {loc,...} => loc
      | TC.TPSELECT {loc,...} => loc
      | TC.TPMODIFY {loc,...} => loc
      | TC.TPSEQ {loc,...} => loc
      | TC.TPMONOLET {loc,...} => loc
      | TC.TPLET {decls, body, tys, loc} => loc
      | TC.TPRAISE {exp, ty, loc} => loc
      | TC.TPHANDLE {loc,...} => loc
      | TC.TPPOLYFNM {loc,...} => loc
      | TC.TPPOLY {loc,...} => loc
      | TC.TPTAPP {loc,...} => loc
      | TC.TPCAST (toexo, ty, loc) => loc
      | TC.TPFFIIMPORT {loc,...} => loc
      | TC.TPSIZEOF (_, loc) => loc

  fun isAtom tpexp =
      case tpexp of
        TC.TPCONSTANT {const, loc, ty} => true
      | TC.TPVAR var => true
      | TC.TPEXVAR exVarInfo => true
      | TC.TPRECFUNVAR {arity, var} => true
      | _ => false

  fun expansive tpexp =
      case tpexp of
        TC.TPCONSTANT _ => false
      | TC.TPVAR _ => false
      | TC.TPEXVAR exVarInfo => false
      | TC.TPRECFUNVAR _ => false
      | TC.TPFNM {argVarList, bodyTy, bodyExp, loc} => false
      | TC.TPEXN_CONSTRUCTOR {exnInfo, loc} => false
      | TC.TPEXEXN_CONSTRUCTOR {exExnInfo, loc} => false
      | TC.TPDATACONSTRUCT {con, instTyList, argTyOpt, argExpOpt=NONE, loc} => false
      | TC.TPEXNCONSTRUCT {exn, instTyList, argTyOpt, argExpOpt=NONE, loc} => false
      | TC.TPDATACONSTRUCT {con={path, id, ty}, instTyList, argTyOpt, argExpOpt= SOME tpexp, loc} =>
        let
          val tyCon = TB.tyConFromConTy ty
        in
          TypID.eq (#id tyCon, #id BT.refTyCon)  
          orelse expansive tpexp
        end
      | TC.TPEXNCONSTRUCT {exn, instTyList, argTyOpt, argExpOpt= SOME tpexp, loc} =>
        expansive tpexp
      | TC.TPRECORD {fields, recordTy=ty, loc=loc} =>
          RecordLabel.Map.foldli
          (fn (string, tpexp1, isExpansive) =>
           isExpansive orelse expansive tpexp1)
          false
          fields
      |  (*  (re : bug 141_provide.sml)
             This deep expansive test is necessary to deal with the following
              structure S :> sig
                type 'a t
                val x : 'a t
              end =
              struct
              type 'a t = int * 'a list
              val x = (0, nil)
              end
           Since (0, nil) is compiled to (0, nil:['a. 'a list]) : int * ['a. 'a list],
           the compiler need to construct the following
             val x = (#1 x, #2 x {'x})
           For this to have the type ['a. int * 'a list], the compiler need to abstract 'x
           to form
             val x = ['a. (#1 x, #2 x {'a})]
         *)
        TC.TPSELECT {exp, expTy, label, loc, resultTy} => expansive exp
      | TC.TPMONOLET {binds=varPathInfoTpexpList, bodyExp=tpexp, loc} =>
          foldl
          (fn ((v,tpexp1), isExpansive) => isExpansive orelse expansive tpexp1)
          (expansive tpexp)
          varPathInfoTpexpList
      | TC.TPPOLY {exp=tpexp,...} => expansive tpexp
      | TC.TPTAPP {exp, ...} => expansive exp
      | TC.TPFFIIMPORT {ffiTy, loc, funExp=TC.TPFFIFUN ptrExp, stubTy} => expansive ptrExp
      | TC.TPFFIIMPORT {ffiTy, loc, funExp=TC.TPFFIEXTERN _, stubTy} => false
      | TC.TPCAST ((tpexp, expTy), ty, loc) => expansive tpexp 
      | TC.TPCASEM _ => true
      | TC.TPPRIMAPPLY _ => true
      | TC.TPOPRIMAPPLY _ => true
      | TC.TPERROR => true
      | TC.TPAPPM _ => true
      | TC.TPMODIFY _ => true
      | TC.TPSEQ _ => true
      | TC.TPLET {decls, body, tys,loc} => true
      | TC.TPRAISE _ => true
      | TC.TPHANDLE _ => true
      | TC.TPPOLYFNM _ => false
      | TC.TPSIZEOF _ => true

  (**
   * Make a fresh instance of a polytype and a term of that type.
   *)
  fun freshInst (ty,exp) =
      (* 2016-06-16 sasaki: インスタンス化した制約を返すよう変更 *)
      if TB.monoTy ty then (ty,nil,exp)
      else
        let
          val expLoc = getLocOfExp exp
        in
          case ty of
            T.POLYty{boundtvars,body,constraints} =>
            let 
              val subst = TB.freshSubst boundtvars
              val bty = TB.substBTvar subst body
              val newExp = 
                  case exp of
                    TC.TPDATACONSTRUCT {con,instTyList=nil,argTyOpt, argExpOpt=NONE,loc}
                    => TC.TPDATACONSTRUCT
                         {con=con,
                          instTyList=BoundTypeVarID.Map.listItems subst,
                          argTyOpt =NONE,
                          argExpOpt=NONE, 
                          loc=loc}
                  | _ => TC.TPTAPP
                           {exp=exp,
                            expTy=ty,
                            instTyList=BoundTypeVarID.Map.listItems subst,
                            loc=expLoc}
              val bconstraints = 
                  List.map (fn c =>
                               case c of T.JOIN {res, args = (arg1, arg2)} =>
                                 T.JOIN
                                     {res = TB.substBTvar subst res,
                                      args = (TB.substBTvar subst arg1,
                                              TB.substBTvar subst arg2)})
                           constraints
              val (freshty, freshconstraints, freshexp) =
                  freshInst (bty,newExp)
            in  
              (freshty, bconstraints @ freshconstraints, freshexp)
            end
          | T.FUNMty (tyList, bodyTy) =>
            (* 
              2015-10-31 ohori: bug 321; we must preserve evaluation order

              OLD: (fn f:ty => fn x :ty1 => inst(f x)) exp 
              NEW:  fn {x1:ty1,...,xn:tyn} => inst(exp {x1,...,xn})
            *)
              let
                val (exp, mkNewExp) = 
                    if expansive exp then 
                      let
                        val newVar = newTCVarInfo expLoc bodyTy
                      in
                        (TC.TPVAR newVar,
                         fn x => TC.TPMONOLET {binds = [(newVar, exp)],
                                               bodyExp = x,
                                               loc=expLoc}
                        )
                      end
                    else (exp, fn x => x)
                val argVarList = map (newTCVarInfo expLoc) tyList
                val argExpList = map (fn x => TC.TPVAR x) argVarList
                val (instBodyTy, instConstraints, instBody) = 
                    freshInst
                      (bodyTy,
                       TC.TPAPPM{funExp=exp,
                                 funTy=ty,
                                 argExpList=argExpList,
                                 loc=expLoc})
                val newExp = 
                  TC.TPFNM
                    {argVarList = argVarList,
                     bodyTy = instBodyTy,
                     bodyExp = instBody,
                     loc = expLoc}
              in 
                (T.FUNMty(tyList, instBodyTy), instConstraints, mkNewExp newExp)
              end
          | T.RECORDty tyFields => 
            (* 
              OLD: (fn r => {...,l=inst(x.l,ty) ...}) ex 
              NEW: let val xex = ex in {...,l=inst(x.l,ty) ...}
            *)
              (case exp of
                 TC.TPRECORD {fields, recordTy=_, loc=loc} =>
                 let
                   val (bindsRev, bindConstraints, newTyFields, newFields) =
                       RecordLabel.Map.foldli
                         (fn (l, fieldTy, (bindsRev,bindConstraints,newTyFields,newFields)) =>
                             case RecordLabel.Map.find(fields,l) of
                                SOME field =>
                                let
                                  val (ty',constraints',exp') = freshInst (fieldTy, field)
                                  val newTyFields = RecordLabel.Map.insert(newTyFields, l, ty')
                                  val (bindsRev, newFields) =
                                      if isAtom exp' then 
                                        (bindsRev, RecordLabel.Map.insert(newFields, l, exp'))
                                      else
                                        let
                                          val fieldVar = newTCVarInfo loc ty'
                                          val fieldExp = TC.TPVAR fieldVar
                                          val newFields = RecordLabel.Map.insert(newFields, l, fieldExp)
                                          val bindsRev = (fieldVar, exp') :: bindsRev
                                        in
                                          (bindsRev, newFields)
                                        end

                                in (bindsRev, constraints', newTyFields, newFields)
                                end
                              | _ => raise bug "freshInst"
                         )
                         (nil, nil, RecordLabel.Map.empty, RecordLabel.Map.empty)
                         tyFields
                   val binds = List.rev bindsRev
                   val recordExp =
                       TC.TPRECORD{fields=newFields,
                                   recordTy=T.RECORDty newTyFields,
                                   loc=loc}
                   val returnExp =
                       case binds of
                         nil => recordExp
                       | _ => 
                         TC.TPMONOLET
                           {binds = binds, bodyExp = recordExp, loc=loc}
                 in
                   (T.RECORDty newTyFields, bindConstraints, returnExp)
                 end
               | _ =>
                 if isAtom exp then
                   let 
                     val (bindsRev, bindConstraints, flty, flexp) =
                         RecordLabel.Map.foldli 
                           (fn (label, fieldTy, (bindsRev,bindConstraints,flty,flexp)) =>
                               let
                                 val (fieldTy,instConstraints,instExp) =
                                     freshInst
                                       (fieldTy,
                                        TC.TPSELECT{label=label,
                                                    exp=exp,
                                                    expTy=ty,
                                                    resultTy=fieldTy,
                                                    loc=expLoc})
                                 val fieldVar = newTCVarInfo expLoc fieldTy
                                 val fieldExp = TC.TPVAR fieldVar
                               in
                                 ((fieldVar, instExp)::bindsRev,
                                  instConstraints @ bindConstraints,
                                  RecordLabel.Map.insert(flty,label,fieldTy),
                                  RecordLabel.Map.insert(flexp,label,fieldExp)
                                 )
                               end)
                           (nil,nil,RecordLabel.Map.empty,RecordLabel.Map.empty)
                           tyFields
                     val binds = List.rev bindsRev
                     val recordExp =
                         TC.TPRECORD{fields=flexp,
                                     recordTy=T.RECORDty flty,
                                     loc=expLoc}
                     val returnExp =
                         case binds of
                           nil => recordExp
                         | _ => 
                           TC.TPMONOLET
                             {binds = binds,
                              bodyExp = recordExp,
                              loc=expLoc}
                   in 
                     (T.RECORDty flty, bindConstraints, returnExp)
                   end
                 else
                   let 
                     val var = newTCVarInfo expLoc ty
                     val varExp = TC.TPVAR var
                     val (bindsRev,bindConstraints,flty,flexp) =
                         RecordLabel.Map.foldli
                           (fn (label,fieldTy,(bindsRev,bindConstraints,flty,flexp)) =>
                               let val (fieldTy,instConstraints,instExp) =
                                       freshInst
                                         (fieldTy,
                                          TC.TPSELECT
                                            {label=label,
                                             exp=varExp,
                                             expTy=ty,
                                             resultTy=fieldTy,
                                             loc=expLoc})
                                 val fieldVar = newTCVarInfo expLoc fieldTy
                                 val fieldExp = TC.TPVAR fieldVar
                               in
                                 ((fieldVar, instExp)::bindsRev,
                                  instConstraints @ bindConstraints,
                                  RecordLabel.Map.insert(flty,label,fieldTy),
                                  RecordLabel.Map.insert(flexp,label,fieldExp)
                                 )
                               end
                           )
                           ([(var, exp)], nil, RecordLabel.Map.empty,RecordLabel.Map.empty)
                           tyFields
                   in 
                     (
                      T.RECORDty flty, 
                      bindConstraints,
                      TC.TPMONOLET
                        {binds = List.rev bindsRev,
                         bodyExp =
                         TC.TPRECORD
                           {fields=flexp,
                            recordTy=T.RECORDty flty,
                            loc=expLoc},
                         loc = expLoc
                        }
                     )
                   end
              )
          | ty => (ty,nil,exp)
        end

  (**
   * Make a fresh instance of a polytype and a term of that type.
   *)
  fun freshToplevelInst (ty,exp) =
      (* 2016-06-16 sasaki: インスタンス化した制約を返すよう変更 *)
      if TB.monoTy ty then (ty,nil,exp)
      else
        case ty of
          T.POLYty{boundtvars,body,constraints} =>
          let 
            val subst = TB.freshSubst boundtvars
            val bty = TB.substBTvar subst body
            val newExp = 
                case exp of
                  TC.TPDATACONSTRUCT {con,instTyList=nil,argTyOpt, argExpOpt=NONE,loc}
                  => TC.TPDATACONSTRUCT
                       {con=con,
                        instTyList=BoundTypeVarID.Map.listItems subst,
                        argExpOpt=NONE, 
                        argTyOpt = NONE,
                        loc=loc}
                | _ => TC.TPTAPP
                         {exp=exp,
                          expTy=ty,
                          instTyList=BoundTypeVarID.Map.listItems subst,
                          loc=getLocOfExp exp}
            val constraints = 
                List.map (fn c =>
                             case c of T.JOIN {res, args = (arg1, arg2)} =>
                               T.JOIN
                                   {res = TB.substBTvar subst res,
                                    args = (TB.substBTvar subst arg1,
                                            TB.substBTvar subst arg2)})
                         constraints
          in  
            (bty,constraints,newExp)
          end
        | ty => (ty,nil,exp)



  (**
   * Make a kind consistent ground instance.
   *)
  local
    fun instantiateTv ty =
      case ty of
        T.TYVARty (tv as ref(T.TVAR {tvarKind = T.OCONSTkind (h::_), ...})) =>
        tv := T.SUBSTITUTED h
      | T.TYVARty (tv as ref(T.TVAR {tvarKind = T.OPRIMkind
                                            {instances = (h::_),...},
                               ...}
                      ))
        => tv := T.SUBSTITUTED h
      | T.TYVARty (tv as ref(T.TVAR {tvarKind = T.REC tyFields, ...})) => 
        tv := T.SUBSTITUTED (T.RECORDty tyFields)
      | T.TYVARty(tv as ref(T.TVAR {tvarKind = T.UNIV, ...})) => 
        tv := T.SUBSTITUTED BuiltinTypes.unitTy
      | _ => ()

  in
    fun freshToplevelGtoundInst (ty,exp) =
        (* 2016-06-16 sasaki: インスタンス化した制約を返すよう変更 *)
        if TB.monoTy ty then (ty,nil,exp)
        else
          case ty of
            T.POLYty{boundtvars,body,constraints} =>
            let 
              val subst = TB.freshSubst boundtvars
              val _ = BoundTypeVarID.Map.app instantiateTv subst
              val bty = TB.substBTvar subst body
              val newExp = 
                  case exp of
                    TC.TPDATACONSTRUCT {con,instTyList=nil,argTyOpt, argExpOpt=NONE,loc}
                    => TC.TPDATACONSTRUCT
                         {con=con,
                          instTyList=BoundTypeVarID.Map.listItems subst,
                          argExpOpt=NONE, 
                          argTyOpt = NONE,
                          loc=loc}
                  | _ => TC.TPTAPP
                           {exp=exp,
                            expTy=ty,
                            instTyList=BoundTypeVarID.Map.listItems subst,
                            loc=getLocOfExp exp}
              val constraints =
                List.map (fn c =>
                             case c of T.JOIN {res, args = (arg1, arg2)} =>
                               T.JOIN 
                                   {res = TB.substBTvar subst res,
                                    args = (TB.substBTvar subst arg1,
                                            TB.substBTvar subst arg2)})
                         constraints
            in  
              (bty,constraints,newExp)
            end
          | ty => (ty,nil,exp)

    fun freshToplevelGtoundTy ty =
        let
          val (ty, _, _) = freshToplevelGtoundInst (ty,TC.TPERROR)
        in
          ty
        end

    fun groundInst (ty,exp) =
        (* 2016-06-16 sasaki: インスタンス化した制約を返すよう変更 *)
        if TB.monoTy ty then (ty,nil,exp)
        else
          let
            val expLoc = getLocOfExp exp
          in
            case ty of
              T.POLYty{boundtvars,body,constraints} =>
              let 
                val subst = TB.freshSubst boundtvars
                val _ = BoundTypeVarID.Map.app instantiateTv subst
                val bty = TB.substBTvar subst body
                val newExp = 
                    case exp of
                      TC.TPDATACONSTRUCT {con,instTyList=nil,argTyOpt, argExpOpt=NONE,loc}
                      => TC.TPDATACONSTRUCT
                           {con=con,
                            instTyList=BoundTypeVarID.Map.listItems subst,
                            argTyOpt =NONE,
                            argExpOpt=NONE, 
                            loc=loc}
                    | _ => TC.TPTAPP
                             {exp=exp,
                              expTy=ty,
                              instTyList=BoundTypeVarID.Map.listItems subst,
                              loc=expLoc}
                val instConstraints =
                List.map (fn c =>
                             case c of T.JOIN {res, args = (arg1, arg2)} =>
                               T.JOIN
                                   {res = TB.substBTvar subst res,
                                    args = (TB.substBTvar subst arg1,
                                            TB.substBTvar subst arg2)})
                         constraints
                val (gty, gconstraints, newExp) = groundInst (bty,newExp)
              in  
                (gty, instConstraints @ gconstraints, newExp)
              end
            | T.FUNMty (tyList, bodyTy) => (ty, nil, exp)
            | T.RECORDty tyFields => 
              (case exp of
                 TC.TPRECORD {fields, recordTy=_, loc=loc} =>
                 let
                   val (bindsRev, instConstraints, newTyFields, newFields) =
                       RecordLabel.Map.foldli
                         (fn (l, fieldTy, (bindsRev,instConstraints,newTyFields,newFields)) =>
                             case RecordLabel.Map.find(fields,l) of
                                SOME field =>
                                let
                                  val (ty',constraints',exp') = groundInst (fieldTy, field)
                                  val newTyFields = RecordLabel.Map.insert(newTyFields, l, ty')
                                  val (bindsRev, instConstraints, newFields) =
                                      if isAtom exp' then 
                                        (bindsRev, instConstraints, RecordLabel.Map.insert(newFields, l, exp'))
                                      else
                                        let
                                          val fieldVar = newTCVarInfo loc ty'
                                          val fieldExp = TC.TPVAR fieldVar
                                          val newFields = RecordLabel.Map.insert(newFields, l, fieldExp)
                                          val bindsRev = (fieldVar, exp') :: bindsRev
                                          val instConstraints = constraints' @ instConstraints
                                        in
                                          (bindsRev, instConstraints, newFields)
                                        end

                                in (bindsRev, instConstraints, newTyFields, newFields)
                                end
                              | _ => raise bug "groundInst"
                         )
                         (nil, nil, RecordLabel.Map.empty, RecordLabel.Map.empty)
                         tyFields
                   val binds = List.rev bindsRev
                   val recordExp =
                       TC.TPRECORD{fields=newFields,
                                   recordTy=T.RECORDty newTyFields,
                                   loc=loc}
                   val returnExp =
                       case binds of
                         nil => recordExp
                       | _ => 
                         TC.TPMONOLET
                           {binds = binds, bodyExp = recordExp, loc=loc}
                 in
                   (T.RECORDty newTyFields, instConstraints, returnExp)
                 end
               | _ =>
                 if isAtom exp then
                   let 
                     val (bindsRev, instConstraints, flty, flexp) =
                         RecordLabel.Map.foldli 
                           (fn (label, fieldTy, (bindsRev,instConstraints,flty,flexp)) =>
                               let
                                 val (fieldTy,fieldConstraints,instExp) =
                                     groundInst
                                       (fieldTy,
                                        TC.TPSELECT{label=label,
                                                    exp=exp,
                                                    expTy=ty,
                                                    resultTy=fieldTy,
                                                    loc=expLoc})
                                 val fieldVar = newTCVarInfo expLoc fieldTy
                                 val fieldExp = TC.TPVAR fieldVar
                               in
                                 ((fieldVar, instExp)::bindsRev,
                                  fieldConstraints @ instConstraints,
                                  RecordLabel.Map.insert(flty,label,fieldTy),
                                  RecordLabel.Map.insert(flexp,label,fieldExp)
                                 )
                               end)
                           (nil,nil,RecordLabel.Map.empty,RecordLabel.Map.empty)
                           tyFields
                     val binds = List.rev bindsRev
                     val recordExp =
                         TC.TPRECORD{fields=flexp,
                                     recordTy=T.RECORDty flty,
                                     loc=expLoc}
                     val returnExp =
                         case binds of
                           nil => recordExp
                         | _ => 
                           TC.TPMONOLET
                             {binds = binds,
                              bodyExp = recordExp,
                              loc=expLoc}
                   in 
                     (T.RECORDty flty, instConstraints, returnExp)
                   end
                 else
                   let 
                     val var = newTCVarInfo expLoc ty
                     val varExp = TC.TPVAR var
                     val (bindsRev,instConstraints,flty,flexp) =
                         RecordLabel.Map.foldli
                           (fn (label,fieldTy,(bindsRev,instConstraints,flty,flexp)) =>
                               let val (fieldTy,fieldConstraints,instExp) =
                                       groundInst
                                         (fieldTy,
                                          TC.TPSELECT
                                            {label=label,
                                             exp=varExp,
                                             expTy=ty,
                                             resultTy=fieldTy,
                                             loc=expLoc})
                                 val fieldVar = newTCVarInfo expLoc fieldTy
                                 val fieldExp = TC.TPVAR fieldVar
                               in
                                 ((fieldVar, instExp)::bindsRev,
                                  fieldConstraints @ instConstraints,
                                  RecordLabel.Map.insert(flty,label,fieldTy),
                                  RecordLabel.Map.insert(flexp,label,fieldExp)
                                 )
                               end
                           )
                           ([(var, exp)], nil, RecordLabel.Map.empty,RecordLabel.Map.empty)
                           tyFields
                   in 
                     (
                      T.RECORDty flty, 
                      instConstraints,
                      TC.TPMONOLET
                        {binds = List.rev bindsRev,
                         bodyExp =
                         TC.TPRECORD
                           {fields=flexp,
                            recordTy=T.RECORDty flty,
                            loc=expLoc},
                         loc = expLoc
                        }
                     )
                   end
              )
            | ty => (ty,nil,exp)
          end
    fun groundInstTy ty = 
        let
          val (ty, _, _) = groundInst (ty, TC.TPERROR)
        in
          ty
        end
  end

  fun toplevelInstWithInstTy (ty, exp, instTy) =
      (* 2016-06-16 sasaki: インスタンス化した制約を返すよう変更 *)
      if TB.monoTy ty then (ty,nil,exp)
      else
        case ty of
          T.POLYty{boundtvars,body,constraints} =>
          let 
            val subst =
                BoundTypeVarID.Map.map
                  (fn x => instTy)
                  boundtvars
            val bty = TB.substBTvar subst body
            val newExp = 
                case exp of
                  TC.TPDATACONSTRUCT {con,instTyList=nil,argTyOpt, argExpOpt=NONE,loc}
                  => TC.TPDATACONSTRUCT
                       {con=con,
                        instTyList=map (fn x => instTy) (BoundTypeVarID.Map.listItems subst),
                        argExpOpt=NONE, 
                        argTyOpt = NONE,
                        loc=loc}
                | _ => TC.TPTAPP
                         {exp=exp,
                          expTy=ty,
                          instTyList=map (fn x => instTy) (BoundTypeVarID.Map.listItems subst),
                          loc=getLocOfExp exp}
            val constraints = 
                List.map (fn c =>
                             case c of T.JOIN {res, args = (arg1, arg2)} =>
                               T.JOIN
                                   {res = TB.substBTvar subst res,
                                    args = (TB.substBTvar subst arg1,
                                            TB.substBTvar subst arg2)})
                         constraints
          in  
            (bty,constraints,newExp)
          end
        | ty => (ty,nil,exp)


end
end
