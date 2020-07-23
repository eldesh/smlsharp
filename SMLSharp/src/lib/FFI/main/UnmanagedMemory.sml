(**
 * functions to manipulate memory blocks which are allocated outside of the
 * managed heap.
 * @author YAMATODANI Kiyoshi
 * @copyright 2010, Tohoku University.
 * @version $Id: UnmanagedMemory.sml,v 1.11 2007/04/02 09:42:29 katsu Exp $
 *)
structure UnmanagedMemory : UNMANAGED_MEMORY =
struct

  (***************************************************************************)

  type address = unit ptr

  (***************************************************************************)

  fun addressToWord (address:address) = _cast(address) : Word32.word

  fun wordToAddress (word:word) = _cast(word) : address

  val NULL = NULL : address

  fun isNULL address = NULL = address

  fun advance (address : address, offset) =
      _cast((_cast(address) : Int32.int) + offset) : address

  val allocate = SMLSharp.Runtime.UnmanagedMemory_allocate

  val release = SMLSharp.Runtime.UnmanagedMemory_release

  fun import (memory, bytes) =
      (* NOTE: trailing '\0' character is appended by UnmanagedMemory_import.
       * This is necessary because Word8Vector.vector and string share the
       * same internal representation. *)
      let
        val byteArray = SMLSharp.Runtime.UnmanagedMemory_import (memory, bytes)
      in _cast(byteArray) : Word8Vector.vector
      end

  fun exportSlice (vector:Word8Vector.vector, start, length) =
      SMLSharp.Runtime.UnmanagedMemory_export
          (_cast(vector) : string, start, length)

  fun export vector = exportSlice (vector, 0, Word8Vector.length vector)

  fun sub (x:address) = !! (_cast(x) : Word8.word ptr)

  fun update (x:address, y) =
      '_Pointer_store' (_cast(x) : Word8.word ptr, y)

  fun subWord (x:address) = !! (_cast(x) : word ptr)

  fun updateWord (x:address, y) =
      '_Pointer_store' (_cast(x) : word ptr, y)

  fun subInt (x:address) = !! (_cast(x) : int ptr)

  fun updateInt (x:address, y) =
      '_Pointer_store' (_cast(x) : int ptr, y)

  fun subReal (x:address) = !! (_cast(x) : real ptr)

  fun updateReal (x:address, y) =
      '_Pointer_store' (_cast(x) : real ptr, y)

  fun subPtr (x:address) = !! (_cast(x) : unit ptr ptr)

  fun updatePtr (x:address, y) =
      '_Pointer_store' (_cast(x) : unit ptr ptr, y)

  (***************************************************************************)

end