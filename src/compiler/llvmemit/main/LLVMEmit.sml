(**
 * emit llvm module
 *
 * @copyright (c) 2013, Tohoku University.
 * @author UENO Katsuhiro
 *)
structure LLVMEmit : sig

  val emit : LLVMIR.program -> LLVM.LLVMModuleRef

  (* dispose module generated by emit *)
  val disposeModule : LLVM.LLVMModuleRef -> unit

end =
struct

  structure L = LLVMIR

  fun appi f l =
      let
        fun loop i nil = ()
          | loop i (h::t) = (f (i, h) : unit; loop (i + 0w1) t)
      in
        loop 0w1 l
      end

  fun word32ToWord w =
      Word.fromLarge (Word32.toLarge w)

  fun hex x = Word32.fmt StringCvt.HEX x
  fun hex8 x = StringCvt.padLeft #"0" 8 (hex x)

  fun emitVar varId =
      "v" ^ VarID.toString varId

  fun emitLabel label =
      FunLocalLabel.toString label

  fun emitLandingPadLabel label =
      "H" ^ HandlerLabel.toString label

  fun emitCallConv cconv =
      case cconv of
        L.CCC => LLVM.LLVMCCallConv
      | L.FASTCC => LLVM.LLVMFastCallConv
      | L.COLDCC => LLVM.LLVMColdCallConv
      | L.X86STDCALLCC => LLVM.LLVMX86StdcallCallConv

  fun emitLinkage linkage =
      case linkage of
        L.INTERNAL => LLVM.LLVMInternalLinkage
      | L.LINKER_PRIVATE => LLVM.LLVMPrivateLinkage
      | L.EXTERNAL => LLVM.LLVMExternalLinkage

  fun emitParamAttr attr =
      case attr of
        L.ZEROEXT => LLVM.LLVMZExtAttribute
      | L.SIGNEXT => LLVM.LLVMSExtAttribute
      | L.INREG => LLVM.LLVMInRegAttribute
      | L.BYVAL => LLVM.LLVMByValAttribute
      | L.SRET => LLVM.LLVMStructRetAttribute
      | L.NOALIAS => LLVM.LLVMNoAliasAttribute
      | L.NOCAPTURE => LLVM.LLVMNoCaptureAttribute
      | L.NEST => LLVM.LLVMNestAttribute

  fun emitFnAttr attr =
      case attr of
        L.ALWAYSINLINE => LLVM.LLVMAlwaysInlineAttribute
      | L.NONLAZYBIND => LLVM.LLVMNonLazyBind
      | L.INLINEHINT => LLVM.LLVMInlineHintAttribute
      | L.NAKED => LLVM.LLVMNakedAttribute
      | L.NOIMPLICITFLOAT => LLVM.LLVMNoImplicitFloatAttribute
      | L.NOINLINE => LLVM.LLVMNoInlineAttribute
      | L.NOREDZONE => LLVM.LLVMNoRedZoneAttribute
      | L.NORETURN => LLVM.LLVMNoReturnAttribute
      | L.NOUNWIND => LLVM.LLVMNoUnwindAttribute
      | L.OPTSIZE => LLVM.LLVMOptimizeForSizeAttribute
      | L.READNONE => LLVM.LLVMReadNoneAttribute
      | L.READONLY => LLVM.LLVMReadOnlyAttribute
      | L.RETURNS_TWICE => LLVM.LLVMReturnsTwice
      | L.SSP => LLVM.LLVMStackProtectAttribute
      | L.SSPREQ => LLVM.LLVMStackProtectReqAttribute
      | L.UWTABLE => LLVM.LLVMUWTable

  fun emitInstrAttr (call, index, nil) = ()
    | emitInstrAttr (call, index, attrs) =
      LLVM.LLVMAddInstrAttribute (call, index, attrs)

  fun emitFuncAttr (func, index, nil) = ()
    | emitFuncAttr (func, index, attrs) =
      LLVM.addFunctionAttribute (func, index, attrs)

  fun emitICmp cmp =
      case cmp of
        L.EQ => LLVM.LLVMIntEQ
      | L.NE => LLVM.LLVMIntNE
      | L.UGT => LLVM.LLVMIntUGT
      | L.UGE => LLVM.LLVMIntUGE
      | L.ULT => LLVM.LLVMIntULT
      | L.ULE => LLVM.LLVMIntULE
      | L.SGT => LLVM.LLVMIntSGT
      | L.SGE => LLVM.LLVMIntSGE
      | L.SLT => LLVM.LLVMIntSLT
      | L.SLE => LLVM.LLVMIntSLE

  fun emitFCmp cmp =
      case cmp of
        L.F_FALSE => LLVM.LLVMRealPredicateFalse
      | L.F_OEQ => LLVM.LLVMRealOEQ
      | L.F_OGT => LLVM.LLVMRealOGT
      | L.F_OGE => LLVM.LLVMRealOGE
      | L.F_OLT => LLVM.LLVMRealOLT
      | L.F_OLE => LLVM.LLVMRealOLE
      | L.F_ONE => LLVM.LLVMRealONE
      | L.F_ORD => LLVM.LLVMRealORD
      | L.F_UEQ => LLVM.LLVMRealUEQ
      | L.F_UGT => LLVM.LLVMRealUGT
      | L.F_UGE => LLVM.LLVMRealUGE
      | L.F_ULT => LLVM.LLVMRealULT
      | L.F_ULE => LLVM.LLVMRealULE
      | L.F_UNE => LLVM.LLVMRealUNE
      | L.F_UNO => LLVM.LLVMRealUNO
      | L.F_TRUE => LLVM.LLVMRealPredicateTrue

  fun emitTy context ty =
      case ty of
        L.I1 => LLVM.LLVMInt1TypeInContext context
      | L.I8 => LLVM.LLVMInt8TypeInContext context
      | L.I32 => LLVM.LLVMInt32TypeInContext context
      | L.I64 => LLVM.LLVMInt64TypeInContext context
      | L.FLOAT => LLVM.LLVMFloatTypeInContext context
      | L.DOUBLE => LLVM.LLVMDoubleTypeInContext context
      | L.VOID => LLVM.LLVMVoidTypeInContext context
      | L.PTR ty => LLVM.LLVMPointerType (emitTy context ty, 0w0)
      | L.FPTR (retTy, argTys, varargs) =>
        let
          val retTy = emitTy context retTy
          val argTys = Vector.fromList (map (emitTy context) argTys)
          val numArgs = Word.fromInt (Vector.length argTys)
          val varargs = if varargs then 1 else 0
          val funTy = LLVM.LLVMFunctionType (retTy, argTys, numArgs, varargs)
        in
          LLVM.LLVMPointerType (funTy, 0w0)
        end
      | L.ARRAY (len, ty) =>
        LLVM.LLVMArrayType (emitTy context ty, word32ToWord len)
      | L.STRUCT (tys, {packed}) =>
        let
          val tys = Vector.fromList (map (emitTy context) tys)
          val numTys = Word.fromInt (Vector.length tys)
          val packed = if packed then 1 else 0
        in
          LLVM.LLVMStructTypeInContext (context, tys, numTys, packed)
        end

  datatype top =
      FUNC of LLVM.LLVMValueRef_Function
    | GVAR of LLVM.LLVMValueRef_GlobalVariable

  type env =
      {context : LLVM.LLVMContextRef,
       builder : LLVM.LLVMBuilderRef,
       topMap : top SEnv.map}

  type bind =
      {blockMap : {bb : LLVM.LLVMBasicBlockRef,
                   phis : LLVM.LLVMValueRef_Phi list,
                   refCount : int ref}
                    FunLocalLabel.Map.map,
       handlerMap : {bb : LLVM.LLVMBasicBlockRef,
                     refCount : int ref}
                      HandlerLabel.Map.map,
       varMap : LLVM.LLVMValueRef VarID.Map.map}

  fun bindBlock ({blockMap, handlerMap, varMap}:bind) (id, bb, phis, refCount) =
      let
        val entry = {bb = bb, phis = phis, refCount = refCount}
      in
        {blockMap = FunLocalLabel.Map.insert (blockMap, id, entry),
         handlerMap = handlerMap,
         varMap = varMap} : bind
      end

  fun bindHandler ({blockMap, handlerMap, varMap}:bind) (id, bb, refCount) =
      let
        val entry = {bb = bb, refCount = refCount}
      in
        {blockMap = blockMap,
         handlerMap = HandlerLabel.Map.insert (handlerMap, id, entry),
         varMap = varMap} : bind
      end

  fun bindVar ({blockMap, handlerMap, varMap}:bind) (id, value) =
      {blockMap = blockMap,
       handlerMap = handlerMap,
       varMap = VarID.Map.insert (varMap, id, value)} : bind

  fun bindVars bind nil = bind
    | bindVars bind (pair::pairs) = bindVars (bindVar bind pair) pairs

  fun emitConst (env as {context, topMap, ...}:env) (ty, const) =
      case const of
        L.INTCONST x =>
        LLVM.LLVMConstIntOfString (emitTy context ty, hex x, 0w16)
      | L.FLOATCONST x =>
        LLVM.LLVMConstReal (emitTy context ty, x)
      | L.NULL =>
        LLVM.LLVMConstNull (emitTy context ty)
      | L.SYMBOL symbol =>
        (
          case SEnv.find (topMap, symbol) of
            NONE => raise Bug.Bug "emitConst: SYMBOL"
          | SOME (FUNC func) => LLVM.castFunc func
          | SOME (GVAR gvar) => LLVM.castGlobalVar gvar
        )
      | L.CONST_BITCAST (const, ty) =>
        LLVM.LLVMConstBitCast (emitConst env const, emitTy context ty)
      | L.CONST_INTTOPTR (const, ty) =>
        LLVM.LLVMConstIntToPtr (emitConst env const, emitTy context ty)
      | L.CONST_PTRTOINT (const, ty) =>
        LLVM.LLVMConstPtrToInt (emitConst env const, emitTy context ty)
      | L.CONST_SUB (c1, c2) =>
        LLVM.LLVMConstSub (emitConst env c1, emitConst env c2)
      | L.CONST_GETELEMENTPTR {inbounds, ptr, indices} =>
        let
          val ptr = emitConst env ptr
          val indices = Vector.fromList (map (emitConst env) indices)
          val count = Word.fromInt (Vector.length indices)
        in
          if inbounds
          then LLVM.LLVMConstInBoundsGEP (ptr, indices, count)
          else LLVM.LLVMConstGEP (ptr, indices, count)
        end

  fun emitInitializer (env as {context, ...}:env) (ty, initializer) =
      case initializer of
        L.ZEROINITIALIZER =>
        LLVM.LLVMConstNull (emitTy context ty)
      | L.INIT_STRING s =>
        LLVM.LLVMConstStringInContext (context, s, Word.fromInt (size s), 1)
      | L.INIT_CONST const =>
        emitConst env (ty, const)
      | L.INIT_STRUCT (fields, {packed}) =>
        let
          val fields = Vector.fromList (map (emitInitializer env) fields)
          val count = Word.fromInt (Vector.length fields)
          val packed = if packed then 1 else 0
        in
          LLVM.LLVMConstStructInContext (context, fields, count, packed)
        end
      | L.INIT_ARRAY fields =>
        let
          val elemTy =
              case ty of
                L.ARRAY (_, ty) => emitTy context ty
              | _ => raise Bug.Bug "emitInitializer: INIT_ARRAY"
          val fields = Vector.fromList (map (emitInitializer env) fields)
          val count = Word.fromInt (Vector.length fields)
        in
          LLVM.LLVMConstArray (elemTy, fields, count)
        end

  fun emitOperand (env2 as (env, {varMap, ...}:bind)) (ty, value) =
      case value of
        L.CONST const => emitConst env (ty, const)
      | L.VAR var =>
        case VarID.Map.find (varMap, var) of
          NONE => raise Bug.Bug ("emitOperand " ^ VarID.toString var)
        | SOME value => value

  fun emitCallAttrs (call, args, cconv, retAttrs, fnAttrs) =
      (
        emitInstrAttr (call, 0w0, map emitParamAttr retAttrs);
        appi (fn (i, (attrs, _:L.operand)) =>
                 emitInstrAttr (call, i, map emitParamAttr attrs))
             args;
        emitInstrAttr (call, Word.notb 0w0, map emitFnAttr fnAttrs);
        case cconv of
          NONE => ()
        | SOME cconv =>
          LLVM.LLVMSetInstructionCallConv (call, emitCallConv cconv)
      )

  fun emitInsn (env2 as ({context, builder, ...}, bind)) insn =
      case insn of
        L.LOAD (var, operand) =>
        let
          val operand = emitOperand env2 operand
          val v = LLVM.LLVMBuildLoad (builder, operand, emitVar var)
        in
          bindVar bind (var, v)
        end
      | L.STORE {value, dst} =>
        let
          val value = emitOperand env2 value
          val dst = emitOperand env2 dst
        in
          LLVM.LLVMBuildStore (builder, value, dst);
          bind
        end
      | L.ALLOCA (var, ty) =>
        let
          val ty = emitTy context ty
          val v = LLVM.LLVMBuildAlloca (builder, ty, emitVar var)
        in
          bindVar bind (var, v)
        end
      | L.CALL {result, tail, cconv, retAttrs, fnPtr, args, fnAttrs} =>
        let
          val argValues =
              Vector.fromList (map (fn (_,x) => emitOperand env2 x) args)
          val call = LLVM.LLVMBuildCall
                       (builder,
                        emitOperand env2 fnPtr,
                        argValues,
                        Word.fromInt (Vector.length argValues),
                        case result of NONE => "" | SOME x => emitVar x)
        in
          emitCallAttrs (call, args, cconv, retAttrs, fnAttrs);
          if tail then LLVM.LLVMSetTailCall (call, 1) else ();
          case result of
            NONE => bind
          | SOME var => bindVar bind (var, LLVM.castCall call)
        end
      | L.GETELEMENTPTR {result, inbounds, ptr, indices} =>
        let
          val ptr = emitOperand env2 ptr
          val indices = Vector.fromList (map (emitOperand env2) indices)
          val numIndices = Word.fromInt (Vector.length indices)
          val v = (if inbounds
                   then LLVM.LLVMBuildInBoundsGEP
                   else LLVM.LLVMBuildGEP)
                    (builder, ptr, indices, numIndices, emitVar result)
        in
          bindVar bind (result, v)
        end
      | L.EXTRACTVALUE (var, value, index) =>
        let
          val value = emitOperand env2 value
          val v = LLVM.LLVMBuildExtractValue
                    (builder, value, Word.fromInt index, emitVar var)
        in
          bindVar bind (var, v)
        end
      | L.OP2 (var, op2, value1, value2) =>
        let
          val buildFn =
              case op2 of
                L.OR => LLVM.LLVMBuildOr
              | L.ADD L.WRAP => LLVM.LLVMBuildAdd
              | L.ADD L.NSW => LLVM.LLVMBuildNSWAdd
              | L.ADD L.NUW => LLVM.LLVMBuildNUWAdd
              | L.FADD => LLVM.LLVMBuildFAdd
              | L.SUB L.WRAP => LLVM.LLVMBuildSub
              | L.SUB L.NSW => LLVM.LLVMBuildNSWSub
              | L.SUB L.NUW => LLVM.LLVMBuildNUWSub
              | L.FSUB => LLVM.LLVMBuildFSub
              | L.MUL L.WRAP => LLVM.LLVMBuildMul
              | L.MUL L.NSW => LLVM.LLVMBuildNSWMul
              | L.MUL L.NUW => LLVM.LLVMBuildNUWMul
              | L.FMUL => LLVM.LLVMBuildFMul
              | L.UDIV => LLVM.LLVMBuildUDiv
              | L.SDIV => LLVM.LLVMBuildSDiv
              | L.FDIV => LLVM.LLVMBuildFDiv
              | L.UREM => LLVM.LLVMBuildURem
              | L.SREM => LLVM.LLVMBuildSRem
              | L.FREM => LLVM.LLVMBuildFRem
              | L.SHL => LLVM.LLVMBuildShl
              | L.LSHR => LLVM.LLVMBuildLShr
              | L.ASHR => LLVM.LLVMBuildAShr
              | L.AND => LLVM.LLVMBuildAnd
              | L.XOR => LLVM.LLVMBuildXor
          val value1 = emitOperand env2 value1
          val value2 = emitOperand env2 value2
          val v = buildFn (builder, value1, value2, emitVar var)
        in
          bindVar bind (var, v)
        end
      | L.ICMP (var, cmp, value1, value2) =>
        let
          val cmp = emitICmp cmp
          val value1 = emitOperand env2 value1
          val value2 = emitOperand env2 value2
          val v = LLVM.LLVMBuildICmp (builder, cmp, value1, value2, emitVar var)
        in
          bindVar bind (var, v)
        end
      | L.FCMP (var, cmp, value1, value2) =>
        let
          val cmp = emitFCmp cmp
          val value1 = emitOperand env2 value1
          val value2 = emitOperand env2 value2
          val v = LLVM.LLVMBuildFCmp (builder, cmp, value1, value2, emitVar var)
        in
          bindVar bind (var, v)
        end
      | L.CONV (var, conv, operand, ty) =>
        let
          val buildFn =
              case conv of
                L.BITCAST => LLVM.LLVMBuildBitCast
              | L.TRUNC => LLVM.LLVMBuildTrunc
              | L.SITOFP => LLVM.LLVMBuildSIToFP
              | L.FPTOSI => LLVM.LLVMBuildFPToSI
              | L.FPTRUNC => LLVM.LLVMBuildFPTrunc
              | L.FPEXT => LLVM.LLVMBuildFPExt
              | L.ZEXT => LLVM.LLVMBuildZExt
              | L.SEXT => LLVM.LLVMBuildSExt
          val operand = emitOperand env2 operand
          val ty = emitTy context ty
          val v = buildFn (builder, operand, ty, emitVar var)
        in
          bindVar bind (var, v)
        end

  fun emitInsnList (_, bind) nil = bind
    | emitInsnList (env2 as (env, bind)) (insn::insns) =
      emitInsnList (env, emitInsn env2 insn) insns

  fun findLabel ({blockMap, ...}:bind) label =
      case FunLocalLabel.Map.find (blockMap, label) of
        NONE => raise Bug.Bug "findLabel"
      | SOME {bb, phis, refCount} => (refCount := !refCount + 1; (bb, phis))

  fun addIncoming fromBlock (phi, arg) =
      LLVM.LLVMAddIncoming
        (phi, Vector.fromList [arg], Vector.fromList [fromBlock], 0w1)

  fun emitDestination (env2 as (_, env), fromBlock) (label, args) =
      let
        val (toBlock, phis) = findLabel env label
      in
        ListPair.app
          (fn (phi, arg) => addIncoming fromBlock (phi, emitOperand env2 arg))
          (phis, args);
        toBlock
      end

  fun emitUnwind ({handlerMap, ...}:bind, fromBlock) label =
      case HandlerLabel.Map.find (handlerMap, label) of
        NONE => raise Bug.Bug "emitUnwind"
      | SOME {bb, refCount} => (refCount := !refCount + 1; bb)

  fun emitPhis (env2 as (env as {context, builder, ...}, bind)) phis =
      case phis of
        nil => {phiVars = nil, binds = nil}
      | _::_ =>
        let
          val phis = map (fn L.PHI (ty, var) =>
                             (var, LLVM.LLVMBuildPhi (builder,
                                                      emitTy context ty,
                                                      emitVar var)))
                         phis
        in
          {phiVars = map #2 phis,
           binds = map (fn (var, phi) => (var, LLVM.castPhi phi)) phis}
        end

  fun emitLast (env3 as (env2 as (env as {context, builder, ...}, bind),
                         block), func)
               last =
      case last of
        L.RET operand =>
        (LLVM.LLVMBuildRet (builder, emitOperand env2 operand); ())
      | L.RET_VOID =>
        (LLVM.LLVMBuildRetVoid builder; ())
      | L.RESUME operand =>
        (LLVM.LLVMBuildResume (builder, emitOperand env2 operand); ())
      | L.BR dest =>
        (LLVM.LLVMBuildBr (builder, emitDestination env3 dest); ())
      | L.BR_C (operand, dest1, dest2) =>
        (LLVM.LLVMBuildCondBr
           (builder,
            emitOperand env2 operand,
            emitDestination env3 dest1,
            emitDestination env3 dest2);
         ())
      | L.INVOKE {cconv, retAttrs, fnPtr, args, fnAttrs, to, unwind} =>
        let
          val argValues =
              Vector.fromList (map (fn (_,x) => emitOperand env2 x) args)
          val (to, toPhis) = findLabel bind to
          val call = LLVM.LLVMBuildInvoke
                       (builder,
                        emitOperand env2 fnPtr,
                        argValues,
                        Word.fromInt (Vector.length argValues),
                        to,
                        emitUnwind (bind, block) unwind,
                        "")
        in
          emitCallAttrs (call, args, cconv, retAttrs, fnAttrs);
          case toPhis of
            [phi] => addIncoming block (phi, LLVM.castCall call)
          | [] => ()
          | _ => raise Bug.Bug "emitLast: INVOKE"
        end
      | L.SWITCH {value, default, branches} =>
        let
          val value = emitOperand env2 value
          val default = emitDestination env3 default
          val numCases = Word.fromInt (length branches)
          val switch = LLVM.LLVMBuildSwitch (builder, value, default, numCases)
        in
          app (fn (const, dest) =>
                  LLVM.LLVMAddCase
                    (switch,
                     emitConst env const,
                     emitDestination env3 dest))
              branches
        end
      | L.UNREACHABLE =>
        (LLVM.LLVMBuildUnreachable builder; ())
      | L.BLOCK {label, phis, body, next} =>
        let
          val bb = LLVM.LLVMAppendBasicBlockInContext
                     (context, func, emitLabel label)
          val _ = LLVM.LLVMPositionBuilderAtEnd (builder, bb)
          val {phiVars, binds} = emitPhis env2 phis
          val refCount = ref 0
          val bind = bindBlock bind (label, bb, phiVars, refCount)
        in
          LLVM.LLVMPositionBuilderAtEnd (builder, block);
          emitBody ((env, bind), block, func) next;
          if !refCount > 0
          then (LLVM.LLVMPositionBuilderAtEnd (builder, bb);
                emitBody ((env, bindVars bind binds), bb, func) body)
          else LLVM.LLVMDeleteBasicBlock bb
        end
      | L.LANDINGPAD {label, argVar=(argVar, argTy), personality, catch,
                      cleanup, body, next} =>
        let
          val bb = LLVM.LLVMAppendBasicBlockInContext
                     (context, func, emitLandingPadLabel label)
          val refCount = ref 0
          val bind = bindHandler bind (label, bb, refCount)
        in
          LLVM.LLVMPositionBuilderAtEnd (builder, block);
          emitBody ((env, bind), block, func) next;
          if !refCount <= 0
          then LLVM.LLVMDeleteBasicBlock bb
          else
            let
              val _ = LLVM.LLVMPositionBuilderAtEnd (builder, bb)
              val v = LLVM.LLVMBuildLandingPad
                        (builder,
                         emitTy context argTy,
                         emitOperand env2 personality,
                         Word.fromInt (length catch),
                         emitVar argVar)
              val _ = if cleanup then LLVM.LLVMSetCleanup (v, 1) else ()
              val _ = app (fn x => LLVM.LLVMAddClause (v, emitOperand env2 x))
                          catch
              val bind = bindVar bind (argVar, LLVM.castLandingPad v)
            in
              emitBody ((env, bind), bb, func) body
            end
        end

  and emitBody (env2 as (env, bind), block, func) ((insns, last):L.body) =
      let
        val bind = emitInsnList env2 insns
      in
        emitLast (((env, bind), block), func) last
      end

  datatype topdec =
      TOPFUNC of LLVM.LLVMValueRef_Function
                 * LLVM.LLVMValueRef VarID.Map.map
                 * L.body
    | TOPGVAR of LLVM.LLVMValueRef_GlobalVariable * (L.ty * L.initializer)

  fun emitTopdec (env as {context, builder, ...}) topdec =
      case topdec of
        TOPFUNC (func, varMap, body) =>
        let
          val bb = LLVM.LLVMAppendBasicBlockInContext (context, func, "")
          val bind = {varMap = varMap,
                      handlerMap = HandlerLabel.Map.empty,
                      blockMap = FunLocalLabel.Map.empty} : bind
        in
(*
print "---\n";
print (Bug.prettyPrint (L.format_body body) ^ "\n");
*)
          LLVM.LLVMPositionBuilderAtEnd (builder, bb);
          emitBody ((env, bind), bb, func) body
        end
      | TOPGVAR (gvar, initializer) =>
        LLVM.LLVMSetInitializer (gvar, emitInitializer env initializer)

  fun defineFunction (context, module)
                     {linkage, cconv, retAttrs, retTy, name, arguments,
                      varArg, fnAttrs, gcname} =
      let
        val retTy = emitTy context retTy
        val args = map (fn (ty,_) => emitTy context ty) arguments
        val argTys = Vector.fromList args
        val numArgs = Word.fromInt (Vector.length argTys)
        val isVarArg = if varArg then 1 else 0
        val funTy = LLVM.LLVMFunctionType (retTy, argTys, numArgs, isVarArg)
        val func = LLVM.LLVMAddFunction (module, name, funTy)
      in
        emitFuncAttr (func, 0w0, map emitParamAttr retAttrs);
        appi (fn (i, (_, attrs)) =>
                 emitFuncAttr (func, i, map emitParamAttr attrs))
             arguments;
        emitFuncAttr (func, Word.notb 0w0, map emitFnAttr fnAttrs);
        case linkage of
          NONE => ()
        | SOME linkage =>
          LLVM.LLVMSetLinkage_Function (func, emitLinkage linkage);
        case cconv of
          NONE => ()
        | SOME cconv =>
          LLVM.LLVMSetFunctionCallConv (func, emitCallConv cconv);
        case gcname of
          NONE => ()
        | SOME name => LLVM.LLVMSetGC (func, name);
        func
      end

  fun defineTopdec (env as (context, module)) topdec =
      case topdec of
        L.DEFINE {linkage, cconv, retAttrs, retTy, name, parameters,
                  fnAttrs, gcname, body} =>
        let
          val func =
              defineFunction
                env
                {linkage = linkage,
                 cconv = cconv,
                 retAttrs = retAttrs,
                 retTy = retTy,
                 name = name,
                 arguments = map (fn (t,a,_) => (t,a)) parameters,
                 varArg = false,
                 fnAttrs = fnAttrs,
                 gcname = gcname}
          val (_, varMap) =
              Array.foldl
                (fn (value, ((_,_,var)::vars, varMap)) =>
                    (LLVM.LLVMSetValueName (value, emitVar var);
                     (vars, VarID.Map.insert (varMap, var, LLVM.castArg value)))
                | _ => raise Bug.Bug "defineTopdec: DEFINE")
                (parameters, VarID.Map.empty)
                (LLVM.LLVMGetParams func)
        in
          (name, FUNC func, [TOPFUNC (func, varMap, body)])
        end
      | L.DECLARE (declare as {name,...}) =>
        let
          val func = defineFunction env declare
        in
          (name, FUNC func, nil)
        end
      | L.GLOBALVAR {name, linkage, constant, ty, initializer, align} =>
        let
          val gvar = LLVM.LLVMAddGlobal (module, emitTy context ty, name)
        in
          case linkage of
            NONE => ()
          | SOME linkage =>
            LLVM.LLVMSetLinkage_GlobalVar (gvar, emitLinkage linkage);
          if constant
          then LLVM.LLVMSetGlobalConstant (gvar, 1)
          else ();
          case align of
            NONE => ()
          | SOME n => LLVM.LLVMSetAlignment (gvar, Word.fromInt n);
          (name, GVAR gvar, [TOPGVAR (gvar, (ty, initializer))])
        end
      | L.EXTERN {name, ty} =>
        let
          val ty = emitTy context ty
          val gvar = LLVM.LLVMAddGlobal (module, ty, name)
        in
          (name, GVAR gvar, nil)
        end

  fun defineTopdecs env nil = (SEnv.empty, nil)
    | defineTopdecs env (dec::decs) =
      let
        val (name, top, decs1) = defineTopdec env dec
        val (topMap, decs2) = defineTopdecs env decs
      in
        if SEnv.inDomain (topMap, name)
        then raise Bug.Bug ("defineTopdecs: duplicated top symbol " ^ name)
        else ();
        (SEnv.insert (topMap, name, top), decs1 @ decs2)
      end

  fun emit ({moduleName, datalayout, triple, topdecs}:L.program) =
      let
        val name = moduleName
        val context = LLVM.LLVMGetGlobalContext ()
        val module = LLVM.LLVMModuleCreateWithNameInContext (name, context)
        val builder = LLVM.LLVMCreateBuilderInContext context
      in
        let
          val _ = case datalayout of
                    NONE => ()
                  | SOME s => LLVM.LLVMSetDataLayout (module, s);
          val _ = case triple of
                    NONE => ()
                  | SOME s => LLVM.LLVMSetTarget (module, s);
          val (topMap, topdecs) = defineTopdecs (context, module) topdecs
          val env = {context = context, builder = builder, topMap = topMap}
(*
          fun loop nil = ()
            | loop (topdec::topdecs : topdec list) =
              (emitTopdec env topdec;
               loop topdecs)
*)
        in
(*
          loop topdecs
*)
          app (emitTopdec env) topdecs
        end
        handle e =>
          (LLVM.LLVMDisposeBuilder builder;
           LLVM.LLVMDisposeModule module;
           raise e);
        LLVM.LLVMDisposeBuilder builder;
        module
      end

  fun disposeModule module =
      LLVM.LLVMDisposeModule module

end
