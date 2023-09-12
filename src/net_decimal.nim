import std / [math, strutils]

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
  # Longest decimals have 29 digits. Decimal cannot represent more than 29 digits.
  # When parsing decimals we read one extra digit if available and then use it for rounding.
  maxDigits = 29

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

proc computeFlags(negative: bool, scale: uint8): int32 =
  if scale > 28:
    raise newException(DecimalDefect, "Invalid scale")

  result = scale.int32 shl scaleShift
  if negative:
    result = result or signMask

proc newDecimal*(flags: int32, hi32: uint32, lo64: uint64): Decimal =
  if not areFlagsValid flags:
    raise newException(DecimalDefect, "Invalid flags")

  Decimal(flags: flags, hi32: hi32, lo64: lo64)

proc newDecimal*(negative: bool, scale: uint8, hi32: uint32, lo64: uint64): Decimal =
  Decimal(flags: computeFlags(negative, scale), hi32: hi32, lo64: lo64)

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
  var
    a = a
    buffer: array[maxDigits, char]
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

type
  # Represents the number
  # `(-1)^negative * (0 . digits[0] digits[1] ... digits[digitCount - 1]) * 10^exponent`.
  # To ensure that the representation is unique the first digit `digits[0]`
  # and the last digit `digits[digitCount - 1]` are non-zero.
  ParsedNumber = object
    negative: bool
    # If available we read one extra digit and use it for rounding.
    digits: array[maxDigits + 1, char]
    # How many digits are stored in `digits` array. From the range `0 .. digits.len`.
    digitCount: int
    exponent: int
    # If there are some non-zero digits which don't fit into `digits` array.
    hasNonZeroTail: bool

# Reference source `Number.Parsing.cs`,
# function `bool TryParseNumber<TChar>(scoped ref TChar* str, TChar* strEnd, NumberStyles styles, ref NumberBuffer number, NumberFormatInfo info) where TChar : unmanaged, IUtfChar<TChar>`.
# This function is simplified version of `TryParseNumber`. Most features were removed.
# We renamed variable `scale` to `exponent` because it's not scale of decimal.
proc tryParseNumber(str: string, parsed: var ParsedNumber): bool =
  ## Rules:
  ## - `str` must be non-empty.
  ## - `str` may start with minus sign.
  ## - `str` may contain decimal dot.
  ## - Minus sign must be followed by digit.
  ## - Decimal dot must be surrounded by digits.
  ## - Scientific notation is not supported.
  ## - If `false` is returned then decimal was not successfully parsed and `parsed`
  ##   may contain a garbage.

  # NOTE: If the number in `str` is really super long (length close to `high(int)`)
  #       then parsing may fail with overflow of `parsed.exponent`.
  #       Otherwise this function should not fail with an exception.

  if str.len == 0:
    # Empty string is not valid number
    return false

  assert not parsed.negative
  assert parsed.digitCount == 0
  assert parsed.exponent == 0
  assert not parsed.hasNonZeroTail

  var
    # - `stateDigits == false` means that we are expecting a digit.
    #   Initially we start in this state and we switch to this state after reading decimal dot.
    # - `stateNonZero == true` means that the number is non-zero.
    #   Ie. at least one non-zero digit was read.
    #   This state is crucial to determine what to do with zero digit - store it vs ignore it.
    # - `stateDecimal == true` means that decimal dot has been read.
    stateDigits, stateNonZero, stateDecimal: bool
    numberOfTralingZeros: int
    i: int

  if str[0] == '-':
    parsed.negative = true
    i = 1

  while i < str.len:
    let ch = str[i]

    if ch.isDigit:
      stateDigits = true

      if ch != '0' or stateNonZero:
        stateNonZero = true

        if parsed.digitCount < parsed.digits.len:
          parsed.digits[parsed.digitCount] = ch

          if ch == '0':
            numberOfTralingZeros += 1
          else:
            numberOfTralingZeros = 0

          parsed.digitCount += 1

        elif ch != '0':
          # Digit is non-zero but we don't have any space in `parsed.digits` array to store it.
          parsed.hasNonZeroTail = true

        # We continue updating `exponent` even after we have filled `parsed.digits` array.
        if not stateDecimal:
          parsed.exponent += 1  # In this case we count digits before decimal dot.
      elif stateDecimal:
        # We're after decimal dot but we have seen only zero digits so far.
        # Current digit `ch` is also zero.
        parsed.exponent -= 1
    elif not stateDecimal and ch == '.':
      if not stateDigits:
        # Decimal dot must be preceded by a digit.
        return false

      stateDecimal = true

      # Decimal dot must be followed by a digit.
      stateDigits = false
    else:
      # Unexpected character.
      return false

    i += 1

  if not stateDigits:
    # Either no digit found at all or no digit found after decimal dot.
    return false

  # Ignore trailing zeros.
  parsed.digitCount -= numberOfTralingZeros

  return true

# Reference source `Number.Parsing.cs`,
# function `bool TryNumberToDecimal(ref NumberBuffer number, ref decimal value)`.
proc tryNumberToDecimal(parsed: var ParsedNumber, value: var Decimal): bool =
  const decimalPrecision = maxDigits
  var e = parsed.exponent

  # No non-zero digit found.
  if parsed.digitCount == 0:
    # Original C# code preserves sign and sometimes even scale.
    # It's not necessary because the number is zero.
    value.flags = 0
    value.hi32 = 0
    value.lo64 = 0
    return true

  if e > decimalPrecision:
    # Number is too big for `Decimal`.
    return false

  var
    i = 0  # Index into `parsed.digits`. Never bigger than `parsed.digitCount`.
    low64 = 0'u64
  while e > -28:
    let c = parsed.digits[i]

    e -= 1
    low64 *= 10
    low64 += (ord(c) - ord('0')).uint64

    i += 1
    if low64 >= high(uint64) div 10:
      # `low64` may not be sufficient for processing the next digit.
      # We may need to use `high32`.
      break

    if i == parsed.digitCount:
      # All digits have been processed.
      while e > 0:
        e -= 1
        low64 *= 10
        if low64 >= high(uint64) div 10:
          break
      break

  var high32 = 0'u32

  # Each iteration multiplies the resulting decimal by 10 and adds `i`-th input digit (if any).
  #
  # Before processing the next input digit we must ensure that the resulting decimal
  # won't overflow. This is guaranteed if at least one of these conditions holds:
  # - We can process any input digit when `high32 < high(uint32) div 10`.
  # - When `high32 == high(uint32) div 10` we must ensure that carry from `low64`
  #   is <= 5. This is satisfied either when `low64 < 0x99999999_99999999'u64`
  #   or when `low64 == 0x99999999_99999999'u64` and the next input digit is <= 5
  #   (if `i == parsed.digitCount` then the next input digit is assumed zero).
  #
  # NOTE: There are more non-zero digits if `i == parsed.digitCount` and `parsed.hasNonZeroTail`.
  #       But these digits won't be processed in the while loop which follows
  #       because there are at least `maxDigits + 1` more significant digits before them
  #       so these less significant digits can't fit into the resulting decimal without overflow.
  while
    (e > 0 or (i != parsed.digitCount and e > -28)) and
    # The resulting decimal can store the next input digit without overflow.
    ((high32 < high(uint32) div 10) or
      ((high32 == high(uint32) div 10) and
        (low64 < 0x99999999_99999999'u64 or
          (low64 == 0x99999999_99999999'u64 and
            (i == parsed.digitCount or parsed.digits[i] <= '5'))))):

    # Multiply by 10.
    let
      tmpLow = low64.uint32 * 10'u64  # Multiply `low32`.
      tmp64 = (low64 shr 32) * 10'u64 + (tmpLow shr 32)  # Multiply `mid32` and add carry.
    low64 = tmpLow.uint32 + (tmp64 shl 32)
    high32 = (tmp64 shr 32).uint32 + high32 * 10'u32

    # Add `i`-th digit (if exists).
    if i != parsed.digitCount:
      let c = (ord(parsed.digits[i]) - ord('0')).uint64
      low64 += c
      if low64 < c:
        high32 += 1

      i += 1

    e -= 1

  # Rounding.
  if i != parsed.digitCount and parsed.digits[i] >= '5':
    # We may need to round up.
    # The only situation when we round down is when `i`-th digit is `5`
    # and it's the last non-zero digit and additionally the digit before it is even.
    # The first two conditions imply that the number being parsed is exactly halfway between
    # two numbers and in these cases we look at digit before and if it is even then
    # we round down and if it's odd then we round up.
    #
    # Note that the original C# code needs to check remaining digits in `parsed.digits`
    # whether there's non-zero digit. Our code doesn't have to because we don't store
    # trailing zeros in `parsed.digits`. So our code just checks whether there are more digits
    # which implies that there's non-zero digit.

    if
      parsed.digits[i] != '5' or
      parsed.hasNonZeroTail or
      i + 1 != parsed.digitCount or
      (low64 and 1) == 1:

      # Round up.
      low64 += 1
      if low64 == 0:
        high32 += 1
        if high32 == 0:
          low64 = 0x99999999_9999999A'u64
          high32 = high(uint32) div 10
          e += 1

  if e > 0:
    return false
  elif e <= -decimalPrecision:
    # This case should happen only for very small numbers which round to zero.
    # Original C# code preserves sign and sets scale to `decimalPrecision - 1`.
    # We believe it's not necessary because the resulting number is zero.
    value.flags = 0
    value.hi32 = 0
    value.lo64 = 0
    return true
  else:
    value.flags = computeFlags(parsed.negative, (-e).uint8)
    value.hi32 = high32
    value.lo64 = low64
    return true

type
  ParsingStatus = enum
    ok, failed, overflow

# Reference source `Number.Parsing.cs`,
# function `ParsingStatus TryParseDecimal<TChar>(ReadOnlySpan<TChar> value, NumberStyles styles, NumberFormatInfo info, out decimal result) where TChar : unmanaged, IUtfChar<TChar>`.
proc tryParseDecimal*(str: string, value: var Decimal): ParsingStatus =
  var parsed: ParsedNumber

  if not tryParseNumber(str, parsed):
    result = failed
  elif not tryNumberToDecimal(parsed, value):
    result = overflow
  else:
    result = ok

# Reference source `Number.Parsing.cs`,
# function `decimal ParseDecimal<TChar>(ReadOnlySpan<TChar> value, NumberStyles styles, NumberFormatInfo info) where TChar : unmanaged, IUtfChar<TChar>`.
proc parseDecimal*(str: string): Decimal =
  case tryParseDecimal(str, result)
  of ok:
    discard
  of failed:
    raise newException(DecimalDefect, "Cannot parse number from string")
  of overflow:
    raise newException(DecimalOverflowDefect, "Cannot convert number to Decimal")

# Name of public constants starts with `decimal` prefix.
const
  decimalSignMask* = signMask
  decimalScaleMask* = scaleMask
  decimalScaleShift* = scaleShift
