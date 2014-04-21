
structure Test =
struct
  fun main (name:string, _:string list) =
    (
     print "Run\n";
     Main.doit();
     print "Done\n";
     OS.Process.exit OS.Process.success
    )
    handle e => (print (exnName e);OS.Process.exit OS.Process.failure)
end

