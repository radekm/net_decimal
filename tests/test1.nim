import unittest

import net_decimal

test "simple decimals":
  check $Decimal() == "0"
  check $(-32'i32.decimal) == "-32"
  check $newDecimal(flags = 7 shl decimalScaleShift, hi32 = 1234, lo64 = 1234) ==
    "2276328218695758.6695378"

test "signed integers can be converted to decimal":
  discard low(int16).decimal
  discard low(int32).decimal
  discard low(int64).decimal
  discard low(int).decimal

  discard high(int16).decimal
  discard high(int32).decimal
  discard high(int64).decimal
  discard high(int).decimal

test "unsigned integers can be converted to decimal":
  discard low(uint16).decimal
  discard low(uint32).decimal
  discard low(uint64).decimal
  discard low(uint).decimal

  discard high(uint16).decimal
  discard high(uint32).decimal
  discard high(uint64).decimal
  discard high(uint).decimal

test "decimal is formatted to string":
  # Negative zero - minus sign must be ignored.
  check $newDecimal(negative = true, scale = 5, hi32 = 0, lo64 = 0) == "0"

  # Max and min.
  check $newDecimal(negative = false, scale = 0, hi32 = high(uint32), lo64 = high(uint64)) ==
    "79228162514264337593543950335"
  check $newDecimal(negative = true, scale = 0, hi32 = high(uint32), lo64 = high(uint64)) ==
    "-79228162514264337593543950335"

  # Formattting 1000000900000000000000000000 with different scales.
  const cases = [
    (0'u8, "1000000900000000000000000000"),  # Trailing zeros are necessary.
    (5, "10000009000000000000000"),
    (20, "10000009"),
    (21, "1000000.9"),  # Decimal dot is necessary.
    (22, "100000.09"),
    (23, "10000.009"),
    (27, "1.0000009"),
    (28, "0.10000009"),  # Leading zero is necessary.
  ]
  for (scale, expected) in cases:
    check $newDecimal(negative = false, scale = scale,
      hi32 = 54210157, mid32 = 1775423445, lo32 = 1670381568) == expected

  # Extra zeros after decimal dot must be inserted.
  check $newDecimal(negative = true, scale = 8, hi32 = 0, lo64 = 98765) == "-0.00098765"
