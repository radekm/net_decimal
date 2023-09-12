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

test "parsing decimals from strings produced by dollar":
  const cases = [
    "0",
    "79228162514264337593543950335",
    "-79228162514264337593543950335",
    "1.222333",
    "0.9",
    "0.0000000000000000000000000001",
  ]
  for str in cases:
    check $parseDecimal(str) == str

test "parsing decimals from strings not produced by dollar":
  const cases = [
    # Zero.
    ("0000", "0"),
    ("-0000", "0"),
    ("-0000.0", "0"),

    # Traling zeros.
    ("1.0", "1"),
    ("-0.090", "-0.09"),
    ("432.5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", "432.5"),

    # Leading zeros.
    ("000.01", "0.01"),
    ("-00015", "-15"),
  ]
  for (input, output) in cases:
    check $parseDecimal(input) == output

test "parsing decimals which must be rounded":
  const cases = [
    # Last digit 6 doesn't fit into decimal.
    # We round up because 6 > 5.
    ("435.012345678901234567890123456", "435.01234567890123456789012346"),
    # Last digit 5 doesn't fit into decimal.
    # We round up because previous digit 7 is odd and there are no additional non-zero digits.
    ("435.012345678901234567890123475", "435.01234567890123456789012348"),
    # Last digit 5 doesn't fit into decimal.
    # We round down because previous digit 6 is even and there are no additional non-zero digits.
    ("435.012345678901234567890123465", "435.01234567890123456789012346"),
    # Last but one digit 5 doesn't fit into decimal.
    # We round down because previous digit 6 is even and there are no additional non-zero digits.
    ("435.0123456789012345678901234650", "435.01234567890123456789012346"),
    # Last but one digit 5 doesn't fit into decimal.
    # We round up because there are additional non-zero digits.
    ("435.0123456789012345678901234651", "435.01234567890123456789012347"),

    # We round down. No overflow happens.
    ("79228162514264337593543950335.4", "79228162514264337593543950335"),
    # Same as previous case. Sign doesn't affect rounding.
    ("-79228162514264337593543950335.4", "-79228162514264337593543950335"),

    # We round up because last but one digit is odd and there are no additional non-zero digits.
    # But decimal cannot hold 7922816251426433759354395033.6 precisely.
    ("7922816251426433759354395033.55", "7922816251426433759354395034"),

    # Too small number we round to zero.
    ("0.00000000000000000000000000001", "0"),
  ]
  for (input, output) in cases:
    check $parseDecimal(input) == output

test "parsing decimals which results in overflow":
  expect DecimalOverflowDefect:
    discard parseDecimal("100000000000000000000000000000")
  expect DecimalOverflowDefect:
    # Overflow when rounding.
    discard parseDecimal("79228162514264337593543950335.5")
