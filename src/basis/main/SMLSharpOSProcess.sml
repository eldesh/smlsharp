(**
 * Integer related structures.
 * @author YAMATODANI Kiyoshi
 * @author UENO Katsuhiro
 * @copyright 2010, 2011, Tohoku University.
 *)
_interface "SMLSharpOSProcess.smi"

structure SMLSharpOSProcess : OS_PROCESS =
struct

infix 7 * / div mod
infix 6 + -
infixr 5 ::
infix 4 = <> > >= < <=
infix 3 :=

  val prim_exit =
      _import "prim_GenericOS_exit"
      : __attribute__((no_callback)) int -> unit
  val prim_getenv =
      _import "getenv"
      : __attribute__((no_callback)) string -> char ptr
  val prim_sleep =
      _import "nanosleep"
      : __attribute__((no_callback)) (int * word, int * word) -> int
  val prim_system =
      _import "system"
      : __attribute__((no_callback)) string -> int

  type status = int
  val success = 0 : status
  val failure = 1 : status
  fun isSuccess x = x = success

  fun system cmd =
      let
        val status = prim_system cmd
      in
        if SMLSharp.Int.lt (status, 0)
        then raise SMLSharpRuntime.OS_SysErr ()
        else status
      end

  datatype atExitState =
      EXIT of exn
    | ATEXIT of (unit -> unit) list

  val atExitStateRef = ref (ATEXIT nil)

  fun atExit finalizer =
      case atExitStateRef of
        ref (EXIT _) => ()
      | ref (ATEXIT finalizers) =>
        atExitStateRef := ATEXIT (finalizer::finalizers)

  fun exit status =
      case atExitStateRef of
        ref (EXIT exn) => raise exn
      | ref (ATEXIT finalizers) =>
        let
          exception Exit
          val _ = atExitStateRef := EXIT Exit
          fun loop nil = ()
            | loop (h::t) = (h () handle _ => (); loop t)
        in
          (* ToDo : flushes and close all I/O streams opened using the
           * Library. *)
          loop finalizers;
          SMLSharpSMLNJ_CleanUp.clean SMLSharpSMLNJ_CleanUp.AtExit;
          prim_exit status;
          raise Fail "OS.Process.exit"
        end

  fun terminate status =
      (prim_exit status; raise Fail "OS.Process.terminate")

  fun getEnv name =
      SMLSharpRuntime.str_new_option (prim_getenv name)

  fun sleep time =
      let
        fun nano_part tm = Word.fromLargeInt (Time.toNanoseconds (Time.- (tm, Time.fromSeconds (Time.toSeconds tm))))
        fun from_tm tm : Time.time = Time.+ (Time.fromSeconds     (LargeInt.fromInt (#1 tm))
                                            ,Time.fromNanoseconds (Word.toLargeInt  (#2 tm)))
        val rem_time = ref time
        val sleep_max = LargeInt.fromWord 0wxFFFFFFFF
      in
        while (Time.< (Time.zeroTime, (!rem_time))) do
        ( let
            val sec = LargeInt.min (sleep_max, Time.toSeconds (!rem_time))
            val req_tm = (LargeInt.toInt sec, nano_part(!rem_time))
            val rem_tm = (0, 0w0)
          in
            rem_time := (if prim_sleep (req_tm, rem_tm)=0
                         then
                           Time.- (!rem_time, from_tm req_tm)
                         else (* ~1 *)
                           Time.+ ( Time.- (!rem_time, from_tm req_tm), from_tm rem_tm))
          end
        )
      end
end

