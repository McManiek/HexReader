## HexReader
Tiny (but ready to use) Delphi units to read/parse Intel HEX files.

- `HexParser.pas` – parses a single Intel HEX record (line) into a `THexRec`.
- `HexReader.pas` – loads a whole file (`THexReader`) and converts it to a binary image (`THexStream`).

### Example
Load a hex file and save its binary to a *.bin* file:

```pascal
var
  HexReader: THexReader;
  HexStream: THexStream;
begin
  HexReader := THexReader.Create('.\test.hex');
  try
    HexStream := THexStream.Create(HexReader);   // or HexReader.ToStream
    try
      HexStream.SaveToFile('.\test.bin');
    finally
      HexStream.Free;
    end;
  finally
    HexReader.Free;
  end;
end;
```

### THexReader
- `Create(AFileName)` – creates the reader and loads the file (pass `''` to skip loading).
- `LoadFromFile(AFileName)` – (re)loads a file, previously loaded records are cleared.
- `Count`, `HexRecord[Index]`, `First`, `Last` – access to loaded records. Records are also linked through `Previous` / `Next`.

Lines without a `:` record mark (e.g. blank lines) are skipped, reading stops at the End Of File record.

### THexStream
A `TMemoryStream` holding the binary image of the loaded file:
- data records are placed at their absolute addresses (Extended Segment / Extended Linear Address records are taken into account),
- gaps between data are filled with `FillByte` (`$FF` by default, set via the constructor's `AFillByte` parameter),
- `BaseAddress` is the address of the first byte in the stream (the lowest data address),
- stream `Position` is 0 after creation.

Note that a file with data far apart (e.g. at `0x00000000` and `0x08000000`) produces a stream covering the whole range.

### Supported record types
`00` Data, `01` End Of File, `02` Extended Segment Address, `03` Start Segment Address, `04` Extended Linear Address, `05` Start Linear Address.

### Errors
Errors are raised as exceptions:
- `EHexParserException` – malformed record (invalid characters, truncated line, unknown record type, wrong record length, checksum mismatch); the message contains the line number,
- `EFileNotFoundException` – file does not exist.

When loading fails, no records are kept.
