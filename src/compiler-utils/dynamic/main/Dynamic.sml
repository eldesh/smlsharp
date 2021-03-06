(**
 * Dynamic
 * @copyright (c) 2015 Tohoku University.
 * @author UENO Katsuhiro
 *)

structure Dynamic =
struct

  structure T = Types
  structure B = BuiltinTypeNames
  structure D = DatatypeLayout
  structure Dynamic = SMLSharp_Builtin.Dynamic
  structure Pointer = SMLSharp_Builtin.Pointer

  (* along with the data structure constructed by Dynamic primitive.
   * See also PrimitiveTypedLambda.sml. *)
  type dynamic = boxed * word * Types.ty

  datatype value =
      WORD8 of Word8.word
    | CHAR of char
    | INT32 of Int32.int
    | INT64 of Int64.int
    | WORD32 of Word32.word
    | WORD64 of Word64.word
    | REAL of real
    | REAL32 of Real32.real
    | PTR of unit ptr
    | RECORD of (RecordLabel.label * dynamic) list
    | VARIANT of Types.typId * Symbol.symbol * value option
    | LIST of dynamic_list
    | ARRAY of dynamic_array
    | VECTOR of dynamic_array
    | REF of value  (*TODO: use value instead of dynamic to avoid compiler's bug*)
    | INTINF of IntInf.int
    | STRING of string
    | EXN of exn
    | FUN
    | UNIT
    | OPAQUE of value
    | OTHER
  and dynamic_list =
      NIL
    | CONS of dynamic * dynamic
  withtype dynamic_array =
      {length : int, sub : int -> dynamic}

  exception Undetermined

  fun consL h (t, x) = (h::t, x)

  fun isListTy ({id,...}:Types.tyCon, [argTy]) =
      if TypID.eq (id, #id BuiltinTypes.listTyCon) then SOME argTy else NONE
    | isListTy _ = NONE

  fun constTag' ty =
      case SingletonTyEnv2.constTag SingletonTyEnv2.emptyEnv ty of
        NONE => raise Undetermined
      | SOME x => x

  fun constTag ty =
      SingletonTyEnv2.TAG (ty, constTag' ty)

  fun constTagWord ty =
      case constTag' ty of
        RuntimeTypes.TAG_BOXED => 0w1
      | RuntimeTypes.TAG_UNBOXED => 0w0

  fun constSize' ty =
      case SingletonTyEnv2.constSize SingletonTyEnv2.emptyEnv ty of
        NONE => raise Undetermined
      | SOME x => x

  fun constSize ty =
      SingletonTyEnv2.SIZE (ty, constSize' ty)

  fun wordValue v =
      case v of
        SingletonTyEnv2.VAR _ => raise Undetermined
      | SingletonTyEnv2.TAG (_, RuntimeTypes.TAG_UNBOXED) => 0w0
      | SingletonTyEnv2.TAG (_, RuntimeTypes.TAG_BOXED) => 0w1
      | SingletonTyEnv2.SIZE (_, n) => Word.fromInt n
      | SingletonTyEnv2.CONST n => n
      | SingletonTyEnv2.CAST (v, _) => wordValue v

  fun checkNoExtraComputation accum =
      case RecordLayout2.extractDecls accum of
        nil => ()
      | _::_ => raise Undetermined

  fun computeRecord fields =
      let
        val accum = RecordLayout2.newComputationAccum ()
        val {fieldIndexes, ...} = RecordLayout2.computeRecord accum fields
        val _ = checkNoExtraComputation accum
      in
        map (fn SingletonTyEnv2.CONST w => w | _ => raise Undetermined)
            fieldIndexes
      end

  fun readRecord (p, i, fields) =
      let
        val fieldSizes =
            map (fn (label:RecordLabel.label, ty) =>
                    {tag = constTag ty, size = constSize ty})
                fields
        val accum = RecordLayout2.newComputationAccum ()
        val {fieldIndexes, ...} = RecordLayout2.computeRecord accum fieldSizes
        val _ = checkNoExtraComputation accum
        val fieldIndexes =
            map (fn SingletonTyEnv2.CONST w => w | _ => raise Undetermined)
                fieldIndexes
        val r = Dynamic.readBoxed (p, i)
      in
        ListPair.mapEq
          (fn ((label, ty), i) => (label, (r, i, ty)))
          (fields, fieldIndexes)
      end

  fun readArray con (p, i, [elemTy]) =
      (let
         val ap = Dynamic.readBoxed (p, i)
         val arraySize = Dynamic.objectSize ap
         val elemSize = Word.fromInt (constSize' elemTy)
         val arrayLength = arraySize div elemSize
         fun sub i =
             if i < 0 orelse Word.fromInt i >= arrayLength
             then raise Subscript
             else (ap, elemSize * Word.fromInt i, elemTy)
       in
         con {length = Word.toInt arrayLength, sub = sub}
       end
       handle Undetermined => OTHER)
    | readArray _ _ = OTHER

  fun invertTagMap tagMap =
      SymbolEnv.foldli
        (fn (conName, (tag, ty), z) => IEnv.insert (z, tag, (conName, ty)))
        IEnv.empty
        tagMap

  fun mergeSymbolEnv (map1, map2) =
      SymbolEnv.mergeWith
        (fn (SOME x1, SOME x2) => SOME (x1, x2)
          | _ => raise Bug.Bug "mergeSymbolEnv")
        (map1, map2)

  fun makeConMap (tagMap, conSet) =
      invertTagMap (mergeSymbolEnv (tagMap, conSet))

  fun readTag conMap (p, i) =
      let
        val tag = Dynamic.readInt (Dynamic.readBoxed (p, i), 0w0)
      in
        case IEnv.find (conMap, tag) of
          SOME (conName, NONE) => (conName, NONE)
        | SOME (conName, SOME ty) => (conName, SOME (ty ()))
        | NONE => raise Bug.Bug ("readTag " ^ Int.toString tag)
      end

  fun isNull (p, i) =
      Pointer.identityEqual (Dynamic.readBoxed (p, i), _NULL)

  fun needPack conArgTy =
      DatatypeLayout.needPack
        (case TypesBasics.derefTy conArgTy of
           T.POLYty {body, ...} => body
         | ty => ty)

  fun inlinedConArgTy conArgTy =
      case TypesBasics.derefTy conArgTy of
        T.POLYty {boundtvars, constraints, body} =>
        (case TypesBasics.derefTy body of
           T.RECORDty fieldTys =>
           T.RECORDty (RecordLabel.Map.map
                         (fn ty => T.POLYty {boundtvars=boundtvars, constraints=constraints, body=ty})
                         fieldTys)
         | _ => conArgTy)
      | _ => conArgTy

  fun readTaggedValue conMap (p, i, instTys) =
      case readTag conMap (p, i) of
        (conName, NONE) => (conName, NONE)
      | (conName, SOME ty) =>
        case inlinedConArgTy ty of
          T.RECORDty fieldTys =>
          let
            val dummyLabel = RecordLabel.fromString ""
            val fields =
                (dummyLabel, BuiltinTypes.contagTy)
                :: map (fn (k, ty) => (k, TypesBasics.tpappTy (ty, instTys)))
                       (RecordLabel.Map.listItemsi fieldTys)
            val record = readRecord (p, i, fields)
          in
            (conName, SOME (RECORD (tl record)))
          end
        | ty =>
          let
            val dummyLabel = RecordLabel.fromString ""
            val fields =
                [(dummyLabel, BuiltinTypes.contagTy),
                 (dummyLabel, TypesBasics.tpappTy (ty, instTys))]
          in
            case readRecord (p, i, fields) of
              [_, (_, dynamic)] => (conName, SOME (read dynamic))
            | _ => raise Bug.Bug "readTaggedValue: non-inlined"
          end

  and readTaggedLayout tagMap (tyCon as {id, conSet, ...}:T.tyCon) src =
      let
        val (conName, arg) = readTaggedValue (makeConMap (tagMap, conSet)) src
      in
        VARIANT (id, conName, arg)
      end

  (* See also DatatypeCompilation.sml *)
  and readDty (p, i, tyCon as {id, conSet, ...}, instTys) =
      if SymbolEnv.isEmpty conSet then OTHER else
      case DatatypeLayout.datatypeLayout tyCon of
        D.LAYOUT_TAGGED (D.TAGGED_RECORD {tagMap}) =>
        readTaggedLayout tagMap tyCon (p, i, instTys)
      | D.LAYOUT_TAGGED (D.TAGGED_OR_NULL {tagMap, nullName}) =>
        if isNull (p, i)
        then VARIANT (id, nullName, NONE)
        else readTaggedLayout tagMap tyCon (p, i, instTys)
      | D.LAYOUT_TAGGED (D.TAGGED_TAGONLY {tagMap}) =>
        let
          val tag = Dynamic.readInt (p, i)
        in
          case IEnv.find (makeConMap (tagMap, conSet), tag) of
            SOME (conName, NONE) => VARIANT (id, conName, NONE)
          | _ => raise Bug.Bug "readDty: TAGGED_TAGONLY"
        end
      | D.LAYOUT_BOOL {falseName} =>
        let
          val trueName =
              case SymbolEnv.listItemsi conSet of
                [(c1, NONE), (c2, NONE)] =>
                if Symbol.eqSymbol (c1, falseName) then c2 else c1
              | _ => raise Bug.Bug "readDty: LAYOUT_BOOL"
        in
          if Dynamic.readInt (p, i) = 0
          then VARIANT (id, falseName, NONE)
          else VARIANT (id, trueName, NONE)
        end
      | D.LAYOUT_UNIT =>
        (case SymbolEnv.listItemsi conSet of
           [(conName, NONE)] => VARIANT (id, conName, NONE)
         | _ => raise Bug.Bug "readDty: LAYOUT_UNIT")
      | D.LAYOUT_ARGONLY =>
        (case SymbolEnv.listItemsi conSet of
           [(con, SOME tyFn)] =>
           let
             val ty = tyFn ()
             val instTy = TypesBasics.tpappTy (ty, instTys)
             val arg =
                 if needPack ty
                 then (Dynamic.readBoxed (p, i), 0w0, instTy)
                 else (p, i, instTy)
           in
             VARIANT (id, con, SOME (read arg))
           end
         | _ => raise Bug.Bug "readDty: LAYOUT_ARGONLY")
      | D.LAYOUT_ARG_OR_NULL =>
        let
          val (argCon, argTy, nullCon) =
              case SymbolEnv.listItemsi conSet of
                [(c1, SOME ty), (c2, NONE)] => (c1, ty (), c2)
              | [(c1, NONE), (c2, SOME ty)] => (c2, ty (), c1)
              | _ => raise Bug.Bug "readDty: LAYOUT_ARG_OR_NULL"
          val instTy = TypesBasics.tpappTy (argTy, instTys)
        in
          if isNull (p, i)
          then VARIANT (id, nullCon, NONE)
          else VARIANT (id, argCon,
                        SOME (read (Dynamic.readBoxed (p, i), 0w0, instTy)))
        end
      | D.LAYOUT_REF => raise Bug.Bug "readDty: LAYOUT_REF"

  (* FIXME: workaround for standalone user programs.
   * A standalone program cannot access to the conSet of a tyCon since
   * conSet includes function closures whose code pointers are available
   * only in the compiler.  To avoid the access to the closures, we assume
   * the low-level representation of lists here.
   *)
  and readCons (p, i, listTy, argTy) =
      if isNull (p, i)
      then LIST NIL
      else case readRecord (Dynamic.readBoxed (p, i), 0w0,
                            RecordLabel.tupleList [argTy, listTy]) of
             [(_,car),(_,cdr)] => LIST (CONS (car, cdr))
           | _ => raise Bug.Bug "readCons"
(*
  and readCons (p, i, tyCon, instTys) =
      case readDty (p, i, tyCon, instTys) of
        VARIANT (_, symbol, argTy) =>
        (case (Symbol.symbolToString symbol, argTy) of
           ("nil", NONE) => LIST NIL
         | ("::", SOME (RECORD [(_, car), (_, cdr)])) => LIST (CONS (car, cdr))
         | _ => raise Bug.Bug "readCons")
      | _ => raise Bug.Bug "readCons"
*)

  and readPrim (p, i, bty, argTys) =
      case bty of
        B.INTty => INT32 (Dynamic.readInt (p, i))
      | B.INT64ty => INT64 (Dynamic.readInt64 (p, i))
      | B.INTINFty => INTINF (Dynamic.readIntInf (p, i))
      | B.WORDty => WORD32 (Dynamic.readWord (p, i))
      | B.WORD64ty => WORD64 (Dynamic.readWord64 (p, i))
      | B.WORD8ty => WORD8 (Dynamic.readWord8 (p, i))
      | B.CHARty => CHAR (Dynamic.readChar (p, i))
      | B.STRINGty => STRING (Dynamic.readString (p, i))
      | B.REALty => REAL (Dynamic.readReal (p, i))
      | B.REAL32ty => REAL32 (Dynamic.readReal32 (p, i))
      | B.UNITty => UNIT
      | B.PTRty => PTR (Dynamic.readPtr (p, i))
      | B.CODEPTRty => PTR (Dynamic.readPtr (p, i))
      | B.ARRAYty => readArray ARRAY (p, i, argTys)
      | B.VECTORty => readArray VECTOR (p, i, argTys)
      | B.EXNty => EXN (Dynamic.readExn (p, i))
      | B.BOXEDty => OTHER
      | B.EXNTAGty => OTHER
      | B.CONTAGty => OTHER
      | B.REFty =>
        (case argTys of
           [elemTy] => REF (read (Dynamic.readBoxed (p, i), 0w0, elemTy))
         | _ => OTHER)

  and read ((p, i, ty):dynamic) =
      case ty of
        T.SINGLETONty _ => OTHER
      | T.BACKENDty _ => OTHER
      | T.ERRORty => OTHER
      | T.DUMMYty _ => OTHER
      | T.DUMMY_RECORDty _ => OTHER
      | T.TYVARty (ref (T.TVAR {tvarKind,...})) => OTHER
      | T.TYVARty (ref (T.SUBSTITUTED ty)) => read (p, i, ty)
      | T.BOUNDVARty _ => OTHER
      | T.FUNMty _ => FUN
      | T.POLYty {boundtvars, constraints, body} =>
        (
          case TypesBasics.derefTy body of
            T.FUNMty _ => FUN
          | _ => OTHER  (* FIXME: cannot print NONE *)
        )
      | T.CONSTRUCTty {tyCon, args} =>
        (
          case #dtyKind tyCon of
            T.BUILTIN bty => readPrim (p, i, bty, args)
          | T.DTY =>
            (case isListTy (tyCon, args) of
               SOME argTy => readCons (p, i, ty, argTy)
             | NONE => readDty (p, i, tyCon, args))
          | T.OPAQUE {opaqueRep, revealKey} =>
            (
              case opaqueRep of
                T.TYCON tyCon =>
                OPAQUE (read (p, i, T.CONSTRUCTty {tyCon=tyCon, args=args}))
              | T.TFUNDEF {iseq, arity, polyTy} =>
                OPAQUE (read (p, i, TypesBasics.tpappTy (polyTy, args)))
            )
        )
      | T.RECORDty fields =>
        (RECORD (readRecord (p, i, RecordLabel.Map.listItemsi fields))
         handle Undetermined => OTHER)

  fun readList NIL = nil
    | readList (CONS (car, cdr)) =
      case read cdr of
        LIST cdr => car :: readList cdr
      | _ => raise Bug.Bug "readList"

  fun readArray ({length, sub}:dynamic_array) =
      Vector.tabulate (length, sub)

  fun load (p, ty) =
      (Dynamic.dup (p, constTagWord ty, constSize' ty), 0w0, ty) : dynamic
      handle Undetermined => (Dynamic.dup (p, 0w0, 0), 0w0, ty)

end
