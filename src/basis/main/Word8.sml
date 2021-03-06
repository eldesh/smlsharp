(**
 * Word8
 * @author UENO Katsuhiro
 * @author YAMATODANI Kiyoshi
 * @author Atsushi Ohori
 * @copyright 2010, 2011, 2012, 2013, Tohoku University.
 *)

infix 7 * / div mod
infix 6 + -
infixr 5 ::
infix 4 = <> > >= < <=
structure Word8 = SMLSharp_Builtin.Word8

structure Word8 =
struct

  type word = word8
  val wordSize = 8  (* 8-bit unsigned integer *)

  val toLarge = Word8.toWord64
  val toLargeX = Word8.toWord64X
  val toLargeWord = toLarge
  val toLargeWordX = toLargeX
  val fromLarge = SMLSharp_Builtin.Word64.toWord8
  val fromLargeWord = fromLarge
  fun toLargeInt x = Word64.toLargeInt (Word8.toWord64 x)
  fun toLargeIntX x = IntInf.fromInt (Word8.toInt32X x)
  fun fromLargeInt x = SMLSharp_Builtin.Word64.toWord8 (Word64.fromLargeInt x)
  val toInt = Word8.toInt32
  val toIntX = Word8.toInt32X
  val fromInt = Word8.fromInt32
  val andb = Word8.andb
  val orb = Word8.orb
  val xorb = Word8.xorb
  val notb = Word8.notb
  val << = Word8.lshift
  val >> = Word8.rshift
  val ~>> = Word8.arshift
  val op + = Word8.add
  val op - = Word8.sub
  val op * = Word8.mul
  val op div = Word8.div
  val op mod = Word8.mod
  val op < = Word8.lt
  val op <= = Word8.lteq
  val op > = Word8.gt
  val op >= = Word8.gteq
  val ~ = Word8.neg

  fun compare (x, y) =
      if x = y then General.EQUAL
      else if x < y then General.LESS
      else General.GREATER

  fun min (x, y) = if x < y then x else y
  fun max (x, y) = if x > y then x else y

  fun fmt radix n =
      Word64.fmt radix (toLarge n)

  fun scan radix (getc : (char, 'a) StringCvt.reader) strm =
      case Word64.scan radix getc strm of
        NONE => NONE
      | SOME (x, strm) =>
        if SMLSharp_Builtin.Word64.gt (x, 0wxff) then raise Overflow
        else SOME (fromLarge x, strm)

  fun toString n =
      fmt StringCvt.HEX n

  fun fromString s =
      StringCvt.scanString (scan StringCvt.HEX) s

end
