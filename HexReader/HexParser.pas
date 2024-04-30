unit HexParser;

interface

uses
  System.SysUtils,
  Winapi.Windows,
  System.Math;

const
  HEX_RECORD_MARK = ':';

type
  EHexParserException = class(Exception);

  THexRecType = (
      rtUnknown = -1,
      rtData = 0,
      rtEndOfFile = 1,
      rtExtSegmentAddres = 2,
      rtStartSegmentAddress = 3,
      rtExtLinearAddress = 4,
      rtStartLinearAddress = 5
    );

  PHexRec = ^THexRec;
  THexRec = record
    RecLen: Byte;
    Offset: Word;
    RecType: THexRecType;
    Data: Pointer;
    Checksum: Byte;
  end;

  function NewHexRec: PHexRec;
  procedure DisposeHexRec(AHexRec: PHexRec);

  function ParseHex(AString: String; out APtrHexRec: PHexRec): Boolean;

implementation

function NewHexRec: PHexRec;
begin
  New(Result);
  ZeroMemory(Result, SizeOf(THexRec));
end;

procedure DisposeHexRec(AHexRec: PHexRec);
begin
  if not Assigned(AHexRec) then
    Exit;

  try
    if (AHexRec^.RecLen > 0) and (Assigned(AHexRec^.Data)) then
      FreeMem(AHexRec^.Data);

    ZeroMemory(AHexRec, SizeOf(THexRec));
  finally
    Dispose(AHexRec);
  end;
end;

function ReadHexBytes(const AInString: String; var AStartPos: Integer; ABytesToRead: Integer; out AOutInt: LongWord): Boolean;
var
  tmpStr: String;
  tmpErrCode: Integer;
begin
  Result := False;
  if AStartPos > Length(AInString) then
    Exit;

  if ABytesToRead <= 0 then
    Exit;

  if ABytesToRead > SizeOf(Integer) then
    Exit;

  try
    ABytesToRead := ABytesToRead * 2;
    tmpStr := Copy(AInString, AStartPos, ABytesToRead);
    Val('$' + tmpStr, AOutInt, tmpErrCode);
    Result := (tmpErrCode = 0);
  finally
    if Result then
      Inc(AStartPos, ABytesToRead);
  end;
end;

procedure CalcHexChecksum(var AChecksum: LongWord; AInputInt: LongWord; ABytes: Byte);
var
  I: Integer;
  B: Byte;
begin
  for I := 0 to ABytes-1 do
  begin
    B := Byte( (AInputInt shr (I*8)) and $FF );
    Inc(AChecksum, B);
  end;
end;

function ParseHex(AString: String; out APtrHexRec: PHexRec): Boolean;
var
  HexMarkPos: Integer;
  StrPosition: Integer;
  IntVal: LongWord;
  BytesLeft, BytesToRead: Integer;
  tmpDataPtr: PByte;
  tmpChksum: LongWord;
begin
  Result := False;
  HexMarkPos := Pos(HEX_RECORD_MARK, AString);
  if HexMarkPos = 0 then
    Exit;

  Delete(AString, 1, HexMarkPos);
  if not Assigned(APtrHexRec) then
    New(APtrHexRec);

  StrPosition := 1;
  tmpChksum := 0;

  //read record length
  if not ReadHexBytes(AString, StrPosition, 1, IntVal) then
    raise EHexParserException.Create(Format('Failed to read Record length (pos: %d)', [StrPosition]));

  APtrHexRec^.RecLen := Byte(IntVal and $FF);
  CalcHexChecksum(tmpChksum, IntVal, 1);

  //read offset
  if not ReadHexBytes(AString, StrPosition, 2, IntVal) then
    raise EHexParserException.Create(Format('Failed to read offset (pos: %d)', [StrPosition]));

  APtrHexRec^.Offset := Byte(IntVal and $FFFF);
  CalcHexChecksum(tmpChksum, IntVal, 2);

  //read record type
  if not ReadHexBytes(AString, StrPosition, 1, IntVal) then
    raise EHexParserException.Create(Format('Failed to read record type (pos: %d)', [StrPosition]));

  if ((IntVal and $FF) >= Ord(THexRecType.rtData)) and ((IntVal and $FF) <= Ord(THexRecType.rtStartLinearAddress)) then
    APtrHexRec^.RecType := THexRecType( IntVal and $FF );

  if APtrHexRec^.RecType = THexRecType.rtUnknown then
    raise EHexParserException.Create('Invalid or unsupported record type');

  CalcHexChecksum(tmpChksum, IntVal, 1);

  //read data
  if APtrHexRec^.RecLen > 0 then
  begin
    GetMem(APtrHexRec^.Data, APtrHexRec^.RecLen);
    tmpDataPtr := APtrHexRec^.Data;
    BytesLeft := APtrHexRec^.RecLen;

    while BytesLeft > 0 do
    begin
      BytesToRead := Min(1, BytesLeft);
      if BytesToRead = 0 then
        Break;

      if not ReadHexBytes(AString, StrPosition, BytesToRead, IntVal) then
        raise EHexParserException.Create(Format('Failed to read record data (pos: %d)', [StrPosition]));

      CalcHexChecksum(tmpChksum, IntVal, BytesToRead);
      CopyMemory(tmpDataPtr, @IntVal, BytesToRead);
      Inc(tmpDataPtr, BytesToRead);
      Dec(BytesLeft, BytesToRead);
    end;
  end;

  //read checksum
  if not ReadHexBytes(AString, StrPosition, 1, IntVal) then
    raise EHexParserException.Create(Format('Failed to read record checksum (pos: %d)', [StrPosition]));

  APtrHexRec^.Checksum := Byte(IntVal and $FF);

  tmpChksum := $100 - (tmpChksum and $FF);
  if tmpChksum <> APtrHexRec^.Checksum then
    raise EHexParserException.Create('Data integrity test failed (invalid checksum)');

  Result := True;
end;

end.
