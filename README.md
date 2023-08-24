# About

This library brings .NET decimal data type to Nim.
The goal of this library is that computations with decimals in Nim
will give the exact same results as computations with decimals in .NET.

On the other hand we don't intend to preserve formatting and parsing functions.
The reason is that number formatting and number parsing in .NET
depends on current locale and thus it's very hard for programmers
to predict its behavior in various locales.
