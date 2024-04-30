unit HexReader;

interface

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  Vcl.Dialogs,
  System.UITypes,
  System.Classes,
  System.Generics.Collections,
  HexParser;

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
    function Get_First: PHexRecord;
    function Get_Last: PHexRecord;
    procedure DeleteRecord(Index: Integer);
    procedure ClearRecords;
  public
    property FileName: String read FFileName;
    property HexRecord[const Index: Integer]: PHexRecord read Get_HexRecord;

    property First: PHexRecord read Get_First;
    property Last: PHexRecord read Get_Last;

    function LoadFromFile(const AFileName: String): Boolean;
    function ToStream: THexStream;

    constructor Create(const AFileName: String);
    destructor Destroy; override;
  end;

  THexStream = class(TMemoryStream)
  private
    FHexReader: THexReader;
    FBaseAddress: Word;

    procedure GetDataFromHexReader(AHexReader: THexReader);
  public
    property HexReader: THexReader read FHexReader;
    property BaseAddress: Word read FBaseAddress;

    constructor Create(AHexReader: THexReader); reintroduce;
    destructor Destroy; override;
  end;

implementation

{ THexStream }

procedure THexStream.GetDataFromHexReader(AHexReader: THexReader);
var
  tmpHexRecord: PHexRecord;
  isFirstRecord: Boolean;
begin
  self.Clear;
  if not Assigned(AHexReader) then
    Exit;

  tmpHexRecord := AHexReader.Get_HexRecord(0);
  isFirstRecord := True;
  while Assigned(tmpHexRecord) do
  begin
    if (not Assigned(tmpHexRecord^.Rec)) then
      Break;

    if tmpHexRecord^.Rec^.RecType = THexRecType.rtData then
    begin
      if tmpHexRecord^.Rec^.RecLen > 0 then
        self.Write(tmpHexRecord^.Rec^.Data^, tmpHexRecord^.Rec^.RecLen);

      if isFirstRecord then
      begin
        FBaseAddress := tmpHexRecord^.Rec^.Offset;
        isFirstRecord := False;
      end;
    end;

    tmpHexRecord := tmpHexRecord.Next;
  end;
end;

constructor THexStream.Create(AHexReader: THexReader);
begin
  inherited Create;
  FHexReader := AHexReader;
  FBaseAddress := 0;
  GetDataFromHexReader(FHexReader);
end;

destructor THexStream.Destroy;
begin
  inherited Destroy;
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

function THexReader.Get_First: PHexRecord;
begin
  Result := self.Get_HexRecord(0);
end;

function THexReader.Get_Last: PHexRecord;
var
  lastRecIndex: Integer;
begin
  Result := nil;
  if FRecords.Count = 0 then
    Exit;

  lastRecIndex := FRecords.Count-1;
  Result := Get_HexRecord(lastRecIndex);
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
      DisposeHexRec(tmpRecPtr^.Rec);
      ZeroMemory(tmpRecPtr, SizeOf(THexRecord));
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

  previousRecord, thisRecord: PHexRecord;
begin
  Result := False;
  tmpStream := nil;
  lineNumber := 1;
  previousRecord := nil;
  try
    if not TFile.Exists(AFileName) then
      raise EFileNotFoundException.Create(Format('File not found [%s]', [AFileName]));

    tmpStream := TStreamReader.Create(AFileName, TEncoding.Default, True);

    while (not tmpStream.EndOfStream) do
    begin
      thisLine := tmpStream.ReadLine;

      New(thisRecord);
      ZeroMemory(thisRecord, SizeOf(THexRecord));
      thisRecord^.Previous := previousRecord;
      if Assigned(previousRecord) then
        previousRecord^.Next := thisRecord;

      thisRecord^.RecNum := (lineNumber - 1);
      thisRecord^.Rec := NewHexRec();
      ParseHex(thisLine, thisRecord^.Rec);

      FRecords.Add(thisRecord);

      previousRecord := thisRecord;
      Inc(lineNumber, 1);
    end;

    FFileName := AFileName;
    Result := True;
  except
    on E: EHexParserException do
    begin
      MessageDlg(Format('%s (Line: %d)', [E.Message, lineNumber]), TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], 0);
      ClearRecords;
    end;
    on E: Exception do
    begin
      MessageDlg(Format('Exception (%s) occured with message: %s', [E.ClassName, E.Message]), TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], 0);
      ClearRecords;
    end;
  end;

  if Assigned(tmpStream) then
    FreeAndNil(tmpStream);
end;

constructor THexReader.Create(const AFileName: String);
begin
  inherited Create;
  FRecords := TList<PHexRecord>.Create;
  LoadFromFile(AFileName);
end;

destructor THexReader.Destroy;
begin
  ClearRecords;
  FreeAndNil(FRecords);
  inherited Destroy;
end;

end.
