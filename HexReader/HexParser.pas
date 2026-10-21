unit HexParser;

interface

uses
  System.SysUtils,
  Winapi.Windows;

const
  HEX_RECORD_MARK = ':';

type
  EHexParserException = class(Exception);

  THexRecType = (
      rtUnknown = -1,
      rtData = 0,
      rtEndOfFile = 1,
      rtExtSegmentAddress = 2,
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

  function ParseHex(const AString: String; var APtrHexRec: PHexRec): Boolean;

implementation

procedure InitHexRec(AHexRec: PHexRec);
begin
  ZeroMemory(AHexRec, SizeOf(THexRec));
  AHexRec^.RecType := THexRecType.rtUnknown;
end;

function NewHexRec: PHexRec;
begin
  New(Result);
  InitHexRec(Result);
end;

procedure DisposeHexRec(AHexRec: PHexRec);
begin
  if not Assigned(AHexRec) then
    Exit;

  try
    if Assigned(AHexRec^.Data) then
      FreeMem(AHexRec^.Data);

    ZeroMemory(AHexRec, SizeOf(THexRec));
  finally
    Dispose(AHexRec);
  end;
end;

function IsHexString(const AStr: String): Boolean;
var
  C: Char;
begin
  Result := Length(AStr) > 0;
  for C in AStr do
    if not CharInSet(C, ['0'..'9', 'A'..'F', 'a'..'f']) then
      Exit(False);
end;

function ReadHexBytes(const AInString: String; var AStartPos: Integer; ABytesToRead: Integer; out AOutInt: LongWord): Boolean;
var
  tmpStr: String;
  tmpErrCode: Integer;
begin
  Result := False;
  AOutInt := 0;
  if (AStartPos < 1) or (AStartPos > Length(AInString)) then
    Exit;

  if (ABytesToRead <= 0) or (ABytesToRead > SizeOf(LongWord)) then
    Exit;

  ABytesToRead := ABytesToRead * 2;
  tmpStr := Copy(AInString, AStartPos, ABytesToRead);

  //reject truncated lines and characters Val would tolerate (spaces, signs)
  if (Length(tmpStr) <> ABytesToRead) or (not IsHexString(tmpStr)) then
    Exit;

  Val('$' + tmpStr, AOutInt, tmpErrCode);
  Result := (tmpErrCode = 0);
  if Result then
    Inc(AStartPos, ABytesToRead);
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

function ParseHex(const AString: String; var APtrHexRec: PHexRec): Boolean;
var
  HexMarkPos: Integer;
  RecString: String;
  StrPosition: Integer;
  IntVal: LongWord;
  I: Integer;
  ExpectedLen: Integer;
  tmpDataPtr: PByte;
  tmpChksum: LongWord;
begin
  Result := False;
  HexMarkPos := Pos(HEX_RECORD_MARK, AString);
  if HexMarkPos = 0 then
    Exit;

  RecString := Copy(AString, HexMarkPos + 1, MaxInt);

  if not Assigned(APtrHexRec) then
    APtrHexRec := NewHexRec
  else
  begin
    //record is reused, release data left from a previous parse
    if Assigned(APtrHexRec^.Data) then
      FreeMem(APtrHexRec^.Data);
    InitHexRec(APtrHexRec);
  end;

  StrPosition := 1;
  tmpChksum := 0;

  //read record length
  if not ReadHexBytes(RecString, StrPosition, 1, IntVal) then
    raise EHexParserException.Create(Format('Failed to read Record length (pos: %d)', [StrPosition + HexMarkPos]));

  APtrHexRec^.RecLen := Byte(IntVal and $FF);
  CalcHexChecksum(tmpChksum, IntVal, 1);

  //read offset
  if not ReadHexBytes(RecString, StrPosition, 2, IntVal) then
    raise EHexParserException.Create(Format('Failed to read offset (pos: %d)', [StrPosition + HexMarkPos]));

  APtrHexRec^.Offset := Word(IntVal and $FFFF);
  CalcHexChecksum(tmpChksum, IntVal, 2);

  //read record type
  if not ReadHexBytes(RecString, StrPosition, 1, IntVal) then
    raise EHexParserException.Create(Format('Failed to read record type (pos: %d)', [StrPosition + HexMarkPos]));

  if IntVal > LongWord(Ord(THexRecType.rtStartLinearAddress)) then
    raise EHexParserException.Create(Format('Invalid or unsupported record type (%.2x)', [IntVal]));

  APtrHexRec^.RecType := THexRecType(IntVal);
  CalcHexChecksum(tmpChksum, IntVal, 1);

  //validate record length against record type
  case APtrHexRec^.RecType of
    THexRecType.rtEndOfFile:
      ExpectedLen := 0;
    THexRecType.rtExtSegmentAddress, THexRecType.rtExtLinearAddress:
      ExpectedLen := 2;
    THexRecType.rtStartSegmentAddress, THexRecType.rtStartLinearAddress:
      ExpectedLen := 4;
  else
    ExpectedLen := -1;
  end;

  if (ExpectedLen >= 0) and (APtrHexRec^.RecLen <> ExpectedLen) then
    raise EHexParserException.Create(Format('Invalid record length (%d) for record type %.2x', [APtrHexRec^.RecLen, Ord(APtrHexRec^.RecType)]));

  //read data
  if APtrHexRec^.RecLen > 0 then
  begin
    GetMem(APtrHexRec^.Data, APtrHexRec^.RecLen);
    tmpDataPtr := APtrHexRec^.Data;

    for I := 0 to APtrHexRec^.RecLen-1 do
    begin
      if not ReadHexBytes(RecString, StrPosition, 1, IntVal) then
        raise EHexParserException.Create(Format('Failed to read record data (pos: %d)', [StrPosition + HexMarkPos]));

      CalcHexChecksum(tmpChksum, IntVal, 1);
      tmpDataPtr^ := Byte(IntVal and $FF);
      Inc(tmpDataPtr);
    end;
  end;

  //read checksum
  if not ReadHexBytes(RecString, StrPosition, 1, IntVal) then
    raise EHexParserException.Create(Format('Failed to read record checksum (pos: %d)', [StrPosition + HexMarkPos]));

  APtrHexRec^.Checksum := Byte(IntVal and $FF);

  tmpChksum := ($100 - (tmpChksum and $FF)) and $FF;
  if tmpChksum <> APtrHexRec^.Checksum then
    raise EHexParserException.Create('Data integrity test failed (invalid checksum)');

  Result := True;
end;

end.
