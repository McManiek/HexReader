## HexReader
Tiny (but ready to use) units to read/parse Intel-Hex files.
Simple example how to load some hex file, and save its binary to a *.bin* file

    HexReader := THexReader.Create('.\test.hex');
    HexStream := THexStream.Create(HexReader);
    HexStream.SaveToFile('.\test.bin');
