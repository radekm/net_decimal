import std / math

type
  Decimal* = object
    flags: int32
    hi32: uint32
    lo64: uint64

  DecimalDefect* = object of Defect
  DecimalOverflowDefect* = object of DecimalDefect

const
  signMask = 0x80000000'i32
  scaleMask = 0x00FF0000'i32
  scaleShift = 16
  tenToPowerNine = 1000000000'u32

proc decimal*(value: SomeSignedInt): Decimal =
  if value >= 0:
    Decimal(flags: 0, hi32: 0, lo64: value.uint64)
  else:
    # If `value` is the lowest value of its type then `-value` overflows
    # so we have to use `0 -% value`.
    Decimal(flags: signMask, hi32: 0, lo64: (0 -% value).uint64)

proc decimal*(value: SomeUnsignedInt): Decimal =
  Decimal(flags: 0, hi32: 0, lo64: value.uint64)

# Reference source `Decimal.cs`,
# function `bool IsValid(int flags)`.
proc areFlagsValid(flags: int32): bool =
  let
    onlySignOrScaleSet = (flags and (not (signMask or scaleMask))) == 0
    scaleLowerThan28 = (flags and scaleMask).uint32 <= 28'u32 shl scaleShift

  onlySignOrScaleSet and scaleLowerThan28

proc newDecimal*(flags: int32, hi32: uint32, lo64: uint64): Decimal =
  if not areFlagsValid flags:
    raise newException(DecimalDefect, "Invalid flags")

  Decimal(flags: flags, hi32: hi32, lo64: lo64)

proc newDecimal*(negative: bool, scale: uint8, hi32: uint32, lo64: uint64): Decimal =
  if scale > 28:
    raise newException(DecimalDefect, "Invalid scale")

  var flags = scale.int32 shl scaleShift
  if negative:
    flags = flags or signMask

  Decimal(flags: flags, hi32: hi32, lo64: lo64)

proc newDecimal*(negative: bool, scale: uint8, hi32: uint32, mid32: uint32, lo32: uint32): Decimal =
  let lo64 = (mid32.uint64 shl 32) + lo32

  newDecimal(negative = negative, scale = scale, hi32 = hi32, lo64 = lo64)

proc getFlags*(a: Decimal): int32 =
  a.flags

proc isNegative*(a: Decimal): bool =
  (a.flags and signMask) != 0

proc getScale*(a: Decimal): uint8 =
  ((a.flags and scaleMask) shr scaleShift).uint8

proc getHi32*(a: Decimal): uint32 =
  a.hi32

proc getMid32*(a: Decimal): uint32 =
  (a.lo64 shr 32).uint32

proc getLo32*(a: Decimal): uint32 =
  a.lo64.uint32

proc getHi64*(a: Decimal): uint64 =
  (a.hi32.uint64 shl 32) + a.getMid32

proc getLo64*(a: Decimal): uint64 =
  a.lo64

# Reference source `Decimal.DecCalc.cs`,
# function `uint DecDivMod1E9(ref DecCalc value)`.
proc decDivMod1E9(value: var Decimal): uint32 =
  ## In place division. Remainder is returned.

  let
    high64 = value.getHi64
    div64 = high64 div tenToPowerNine

  value.hi32 = (div64 shr 32).uint32

  let
    # Remainder `high64 - div64 * tenToPowerNine` fits into `uint32`
    # so it's ok to ignore higher 32 bits.
    num = ((high64 - div64.uint32 * tenToPowerNine) shl 32) + value.getLo32
    zdiv = (num div tenToPowerNine).uint32

  value.lo64 = (div64 shl 32) + zdiv

  num.uint32 - zdiv * tenToPowerNine

const twoDigitsBytes =
  "00010203040506070809" &
  "10111213141516171819" &
  "20212223242526272829" &
  "30313233343536373839" &
  "40414243444546474849" &
  "50515253545556575859" &
  "60616263646566676869" &
  "70717273747576777879" &
  "80818283848586878889" &
  "90919293949596979899"

# Reference source `Decimal.DecCalc.cs`,
# function `TChar* UInt32ToDecChars<TChar>(TChar* bufferEnd, uint value, int digits) where TChar : unmanaged, IUtfChar<TChar>`.
proc uint32ToDecChars(bufferEnd: ptr char, value: uint32, digits: int): ptr char =
  var
    bufferEnd = bufferEnd
    value = value
    digits = digits
    remainder = 0'u32

  while value >= 100:
    bufferEnd = cast[ptr char](cast[uint](bufferEnd) - 2)
    digits -= 2
    (value, remainder) = divmod(value, 100)
    copyMem(bufferEnd, cast[pointer](cast[uint](twoDigitsBytes.cstring) + 2 * remainder), 2)

  while value != 0 or digits > 0:
    bufferEnd = cast[ptr char](cast[uint](bufferEnd) - 1)
    digits -= 1
    (value, remainder) = divmod(value, 10)
    bufferEnd[] = chr(remainder + '0'.ord)

  bufferEnd

# Reference source `Number.Formatting.cs`,
# function `void DecimalToNumber(scoped ref decimal d, ref NumberBuffer number)`.
proc `$`*(a: Decimal): string =
  # Longest decimals have 29 digits.
  # Implementation in `Number.NumberBuffer.cs` adds 1 for rounding
  # and 1 for terminating null. We don't do rounding and we don't need terminating null.
  const maxDigits = 29
  var
    a = a
    buffer: array[maxDigits, char]  # Buffer with digits.
    bufferPtr = cast[ptr char](cast[uint](addr buffer) + maxDigits)

  while (a.hi32 or a.getMid32) != 0:
    bufferPtr = uint32ToDecChars(bufferPtr, decDivMod1E9(a), 9)
  bufferPtr = uint32ToDecChars(bufferPtr, a.getLo32, 0)

  let
    firstDigitIndex = (cast[uint](bufferPtr) - cast[uint](addr buffer)).int
    digitsCount = maxDigits - firstDigitIndex

  # Following code is a custom logic which intentionally doesn't use current locale
  # nor custom number formats. This makes it more predictable.

  # No digits means that number is zero.
  if digitsCount == 0:
    result = "0"
  # Number is non-zero.
  else:
    let digitsBeforeDecimalDot = digitsCount - a.getScale.int

    # Count trailing zeros.
    var trailingZeros = 0
    while trailingZeros < digitsCount:
      if buffer[maxDigits - 1 - trailingZeros] == '0':
        trailingZeros += 1
      else:
        break

    if a.isNegative:
      result.add('-')
    if digitsBeforeDecimalDot <= 0:
      result.add("0.")
      for i in digitsBeforeDecimalDot ..< 0:
        result.add('0')
      # Copy digits except trailing zeros.
      for i in firstDigitIndex ..< maxDigits - trailingZeros:
        result.add(buffer[i])
    else:
      # We assume that the first digit is not zero.
      for i in 0 ..< digitsBeforeDecimalDot:
        result.add(buffer[firstDigitIndex + i])

      let nonZeroDigitsAfterDecimalDot = digitsCount - digitsBeforeDecimalDot - trailingZeros
      if nonZeroDigitsAfterDecimalDot > 0:
        result.add('.')
        for i in 0 ..< nonZeroDigitsAfterDecimalDot:
          result.add(buffer[firstDigitIndex + digitsBeforeDecimalDot + i])

  # TODO: We should check that formatted string is non-empty and has leading and trailing zeros,
  #       decimal dot and minus sign only when they're necessary.

# Name of public constants starts with `decimal` prefix.
const
  decimalSignMask* = signMask
  decimalScaleMask* = scaleMask
  decimalScaleShift* = scaleShift
