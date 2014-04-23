(*
 * native parallel matrix multiplication
 *
 * This is tail recursive version.
 * This program allocates very few objects.
 *)

local

  type pthread_t = unit ptr  (* ToDo: system dependent *)

  val pthread_create =
      _import "pthread_create"
      : __attribute__((suspend))
        (pthread_t ref, unit ptr, unit ptr -> unit ptr, unit ptr) -> int
  val pthread_join =
      _import "pthread_join"
      : __attribute__((suspend))
        (pthread_t, unit ptr ref) -> int

  fun spawn f =
      let
        val r = ref _NULL
        val e = pthread_create (r, _NULL, fn _ => (f () : unit; _NULL), _NULL)
        val ref t = r
      in
        if e = 0 then t else raise Fail "spawn"
      end

  fun join th =
      (pthread_join (th, ref _NULL); ())

  val getenv = _import "getenv" : string -> unit ptr
  val atoi = _import "atoi" : unit ptr -> int
  val numThreads = getenv "NTHREADS"
  val numThreads = if numThreads = _NULL then 1 else atoi numThreads

  val DIM = 3 * 5 * 7 * 8  (* dividable by 1-8 *)
  val matrix1 = Array.array (DIM * DIM, 1.2345678)
  val matrix2 = Array.array (DIM * DIM, 1.2345678)
  val result = Array.array (DIM * DIM, 0.0)

  fun sub (a, i, j) : real =
      Array.sub (a, i * DIM + j)
  fun update (a, i, j, v : real) =
      Array.update (a, i * DIM + j, v)

  fun calc start () =
      let
        val last = start + DIM div numThreads
        fun loop3 (i, j, k, z) =
            if k < DIM
            then loop3 (i, j, k+1, z + sub (matrix1,i,k) * sub (matrix2,k,j))
            else (update (result, i, j, z); loop2 (i, j + 1))
        and loop2 (i, j) =
            if j < DIM then loop3 (i, j, 0, 0.0) else loop1 (i + 1)
        and loop1 i =
            if i < last then loop2 (i, 0) else ()
      in
        loop1 start
      end

  fun calc_cps start () =
      let
        val last = start + DIM div numThreads
        fun loop3 (i, j, k, z, K) =
            if k < DIM
            then loop3 (i, j, k+1, z + sub (matrix1,i,k) * sub (matrix2,k,j), K)
            else K () : unit
        and loop2 (i, j, K) =
            if j < DIM
            then loop3 (i, j, 0, 0.0, fn _ => loop2 (i, j+1, K))
            else K () : unit
        and loop1 i =
            if i < last then loop2 (i, 0, fn _ => loop1 (i+1)) else ()
      in
        loop1 start
      end

  fun main () =
      let
        fun start i =
            if i < numThreads
            then spawn (calc (i * (DIM div numThreads))) :: start (i+1)
            else nil
        fun joinAll nil = ()
          | joinAll (h::t) = (join h; joinAll t)
        val threads = start 1
        val () = calc 0 ()
      in
        joinAll threads
      end

in

val x = main ()

end
