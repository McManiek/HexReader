unit HexReader;

interface

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  System.Classes,
  System.Generics.Collections,
  HexParser;

const
  HEX_DEFAULT_FILL_BYTE = $FF;

type
  PHexRecord = ^THexRecord;
  THexRecord = record
    Rec: PHexRec;

    RecNum: Integer;
    Previous: PHexRecord;
    Next: PHexRecord;
  end;

  THexStream = class;

  THexReader = class
  private
    FFileName: String;
    FRecords: TList<PHexRecord>;

    function Get_HexRecord(const AIndex: Integer): PHexRecord;
    function Get_Count: Integer;
    function Get_First: PHexRecord;
    function Get_Last: PHexRecord;
    procedure DeleteRecord(Index: Integer);
    procedure ClearRecords;
  public
    property FileName: String read FFileName;
    property HexRecord[const Index: Integer]: PHexRecord read Get_HexRecord;
    property Count: Integer read Get_Count;

    property First: PHexRecord read Get_First;
    property Last: PHexRecord read Get_Last;

    function LoadFromFile(const AFileName: String): Boolean;
    function ToStream: THexStream;

    constructor Create(const AFileName: String = '');
    destructor Destroy; override;
  end;

  THexStream = class(TMemoryStream)
  private
    FHexReader: THexReader;
    FBaseAddress: LongWord;
    FFillByte: Byte;

    procedure GetDataFromHexReader(AHexReader: THexReader);
  public
    property HexReader: THexReader read FHexReader;
    property BaseAddress: LongWord read FBaseAddress;
    property FillByte: Byte read FFillByte;

    constructor Create(AHexReader: THexReader; AFillByte: Byte = HEX_DEFAULT_FILL_BYTE); reintroduce;
  end;

implementation

{ THexStream }

function ReadBigEndianWord(AData: Pointer): Word;
begin
  Result := (Word(PByte(AData)[0]) shl 8) or PByte(AData)[1];
end;

//updates upper part of the address on extended address records,
//returns True when ARec is a data record with absolute address in ARecAddress
function GetDataRecordAddress(ARec: PHexRec; var AUpperAddress: UInt64; out ARecAddress: UInt64): Boolean;
begin
  Result := False;
  ARecAddress := 0;
  if not Assigned(ARec) then
    Exit;

  case ARec^.RecType of
    THexRecType.rtExtSegmentAddress:
      AUpperAddress := UInt64(ReadBigEndianWord(ARec^.Data)) shl 4;
    THexRecType.rtExtLinearAddress:
      AUpperAddress := UInt64(ReadBigEndianWord(ARec^.Data)) shl 16;
    THexRecType.rtData:
      if ARec^.RecLen > 0 then
      begin
        ARecAddress := AUpperAddress + ARec^.Offset;
        Result := True;
      end;
  end;
end;

procedure THexStream.GetDataFromHexReader(AHexReader: THexReader);
var
  I: Integer;
  tmpRec: PHexRec;
  upperAddress, recAddress: UInt64;
  minAddress, maxAddress: UInt64;
  hasData: Boolean;
begin
  self.Clear;
  FBaseAddress := 0;
  if not Assigned(AHexReader) then
    Exit;

  //first pass: find the address range covered by data records
  hasData := False;
  minAddress := High(UInt64);
  maxAddress := 0;
  upperAddress := 0;
  for I := 0 to AHexReader.Count-1 do
  begin
    tmpRec := AHexReader.HexRecord[I]^.Rec;
    if not GetDataRecordAddress(tmpRec, upperAddress, recAddress) then
      Continue;

    hasData := True;
    if recAddress < minAddress then
      minAddress := recAddress;
    if recAddress + tmpRec^.RecLen > maxAddress then
      maxAddress := recAddress + tmpRec^.RecLen;
  end;

  if not hasData then
    Exit;

  FBaseAddress := LongWord(minAddress);
  self.Size := Int64(maxAddress - minAddress);
  FillChar(self.Memory^, self.Size, FFillByte);

  //second pass: put data at its address, gaps keep the fill byte
  upperAddress := 0;
  for I := 0 to AHexReader.Count-1 do
  begin
    tmpRec := AHexReader.HexRecord[I]^.Rec;
    if not GetDataRecordAddress(tmpRec, upperAddress, recAddress) then
      Continue;

    self.Position := Int64(recAddress - minAddress);
    self.WriteBuffer(tmpRec^.Data^, tmpRec^.RecLen);
  end;

  self.Position := 0;
end;

constructor THexStream.Create(AHexReader: THexReader; AFillByte: Byte);
begin
  inherited Create;
  FHexReader := AHexReader;
  FBaseAddress := 0;
  FFillByte := AFillByte;
  GetDataFromHexReader(FHexReader);
end;

{ THexReader }

function THexReader.ToStream: THexStream;
begin
  Result := THexStream.Create(self);
end;

function THexReader.Get_HexRecord(const AIndex: Integer): PHexRecord;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex < FRecords.Count) then
    Result := FRecords[AIndex];
end;

function THexReader.Get_Count: Integer;
begin
  Result := FRecords.Count;
end;

function THexReader.Get_First: PHexRecord;
begin
  Result := self.Get_HexRecord(0);
end;

function THexReader.Get_Last: PHexRecord;
begin
  Result := self.Get_HexRecord(FRecords.Count-1);
end;

procedure THexReader.DeleteRecord(Index: Integer);
var
  tmpRecPtr: PHexRecord;
begin
  if (Index < 0) or (Index >= FRecords.Count) then
    Exit;

  tmpRecPtr := FRecords[Index];
  try
    if Assigned(tmpRecPtr) then
    begin
      if Assigned(tmpRecPtr^.Previous) then
        tmpRecPtr^.Previous^.Next := tmpRecPtr^.Next;
      if Assigned(tmpRecPtr^.Next) then
        tmpRecPtr^.Next^.Previous := tmpRecPtr^.Previous;

      DisposeHexRec(tmpRecPtr^.Rec);
      ZeroMemory(tmpRecPtr, SizeOf(THexRecord));
      Dispose(tmpRecPtr);
    end;
  finally
    FRecords.Delete(Index);
  end;
end;

procedure THexReader.ClearRecords;
var
  I: Integer;
begin
  try
    for I := FRecords.Count-1 downto 0 do
      DeleteRecord(I);
  finally
    FRecords.Clear;
  end;
end;

function THexReader.LoadFromFile(const AFileName: String): Boolean;
var
  tmpStream: TStreamReader;
  thisLine: String;
  lineNumber: Integer;
  tmpRec: PHexRec;

  previousRecord, thisRecord: PHexRecord;
begin
  ClearRecords;
  FFileName := '';
  lineNumber := 0;
  previousRecord := nil;

  if not TFile.Exists(AFileName) then
    raise EFileNotFoundException.Create(Format('File not found [%s]', [AFileName]));

  try
    tmpStream := TStreamReader.Create(AFileName, TEncoding.Default, True);
    try
      while (not tmpStream.EndOfStream) do
      begin
        thisLine := tmpStream.ReadLine;
        Inc(lineNumber, 1);

        tmpRec := nil;
        try
          //lines without record mark (e.g. empty lines) are skipped
          if not ParseHex(thisLine, tmpRec) then
            Continue;
        except
          DisposeHexRec(tmpRec);
          raise;
        end;

        New(thisRecord);
        ZeroMemory(thisRecord, SizeOf(THexRecord));
        thisRecord^.Rec := tmpRec;
        thisRecord^.RecNum := FRecords.Count;
        thisRecord^.Previous := previousRecord;
        if Assigned(previousRecord) then
          previousRecord^.Next := thisRecord;

        FRecords.Add(thisRecord);
        previousRecord := thisRecord;

        //anything after end of file record is ignored
        if tmpRec^.RecType = THexRecType.rtEndOfFile then
          Break;
      end;
    finally
      FreeAndNil(tmpStream);
    end;

    FFileName := AFileName;
    Result := True;
  except
    on E: EHexParserException do
    begin
      ClearRecords;
      raise EHexParserException.Create(Format('%s (Line: %d)', [E.Message, lineNumber]));
    end;
    on E: Exception do
    begin
      ClearRecords;
      raise;
    end;
  end;
end;

constructor THexReader.Create(const AFileName: String);
begin
  inherited Create;
  FRecords := TList<PHexRecord>.Create;
  if AFileName <> '' then
    LoadFromFile(AFileName);
end;

destructor THexReader.Destroy;
begin
  if Assigned(FRecords) then
    ClearRecords;
  FreeAndNil(FRecords);
  inherited Destroy;
end;

end.
