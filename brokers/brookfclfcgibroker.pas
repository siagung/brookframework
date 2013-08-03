(*
  Brook FCL FastCGI Broker unit.

  Copyright (C) 2013 Silvio Clecio.

  http://brookframework.org

  All contributors:
  Plase see the file CONTRIBUTORS.txt, included in this
  distribution.

  See the file LICENSE.txt, included in this distribution,
  for details about the copyright.

  This library is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
*)

unit BrookFCLFCGIBroker;

{$mode objfpc}{$H+}

interface

uses
  BrookClasses, BrookApplication, BrookException, BrookMessages, BrookConsts,
  BrookHTTPConsts, BrookRouter, BrookUtils, HTTPDefs, CustWeb, CustFCGI, FPJSON,
  JSONParser, Classes, SysUtils, StrUtils;

type
  TBrookFCGIApplication = class;

  { TBrookApplication }

  TBrookApplication = class(TBrookInterfacedObject, IBrookApplication)
  private
    FApp: TBrookFCGIApplication;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    function Instance: TObject;
    procedure Run;
  end;

  { TBrookFCGIApplication }

  TBrookFCGIApplication = class(TCustomFCGIApplication)
  protected
    function InitializeWebHandler: TWebHandler; override;
  end;

  { TBrookFCGIRequest }

  TBrookFCGIRequest = class(TFCGIRequest)
  protected
    procedure DeleteTempUploadedFiles; override;
    function GetTempUploadFileName(
      const {%H-}AName, AFileName: string; {%H-}ASize: Int64): string; override;
    function RequestUploadDir: string; override;
    procedure InitRequestVars; override;
    procedure HandleUnknownEncoding(
      const AContentType: string; AStream: TStream); override;
  end;

  { TBrookFCGIResponse }

  TBrookFCGIResponse = class(TFCGIResponse)
  protected
    procedure CollectHeaders(AHeaders: TStrings); override;
  end;

  { TBrookFCGIHandler }

  TBrookFCGIHandler = class(TFCGIHandler)
  protected
    function CreateRequest: TFCGIRequest; override;
    function CreateResponse(ARequest: TFCGIRequest): TFCGIResponse; override;
    function FormatContentType: string;
  public
    procedure HandleRequest(ARequest: TRequest; AResponse: TResponse); override;
    procedure ShowRequestException(R: TResponse; E: Exception); override;
  end;

implementation

{ TBrookApplication }

constructor TBrookApplication.Create;
begin
  FApp := TBrookFCGIApplication.Create(nil);
  FApp.Initialize;
end;

destructor TBrookApplication.Destroy;
begin
  FApp.Free;
  inherited Destroy;
end;

function TBrookApplication.Instance: TObject;
begin
  Result := FApp;
end;

procedure TBrookApplication.Run;
begin
  FApp.Run;
end;

{ TBrookFCGIApplication }

function TBrookFCGIApplication.InitializeWebHandler: TWebHandler;
begin
  Result := TBrookFCGIHandler.Create(Self);
end;

{ TBrookFCGIRequest }

procedure TBrookFCGIRequest.DeleteTempUploadedFiles;
begin
  if BrookSettings.DeleteUploadedFiles then
    inherited;
end;

function TBrookFCGIRequest.GetTempUploadFileName(
  const AName, AFileName: string; ASize: Int64): string;
begin
  if BrookSettings.KeepUploadedNames then
    Result := RequestUploadDir + AFileName
  else
    Result := inherited GetTempUploadFileName(AName, AFileName, ASize);
end;

function TBrookFCGIRequest.RequestUploadDir: string;
begin
  Result := BrookSettings.DirectoryForUploads;
  if Result = '' then
    Result := GetTempDir;
  Result := IncludeTrailingPathDelimiter(Result);
end;

procedure TBrookFCGIRequest.InitRequestVars;
var
  VMethod: ShortString;
begin
  VMethod := Method;
  if VMethod = ES then
    raise Exception.Create(SBrookNoRequestMethodError);
  case VMethod of
    BROOK_HTTP_REQUEST_METHOD_DELETE, BROOK_HTTP_REQUEST_METHOD_PUT,
      BROOK_HTTP_REQUEST_METHOD_PATCH:
      begin
        InitPostVars;
        if HandleGetOnPost then
          InitGetVars;
      end;
  else
    inherited;
  end;
end;

procedure TBrookFCGIRequest.HandleUnknownEncoding(const AContentType: string;
  AStream: TStream);

  procedure ProcessJSONObject(AJSON: TJSONObject);
  var
    I: Integer;
  begin
    for I := 0 to Pred(AJSON.Count) do
      ContentFields.Add(AJSON.Names[I] + EQ + AJSON.Items[I].AsString);
  end;

  procedure ProcessJSONArray(AJSON: TJSONArray);
  var
    I: Integer;
  begin
    for I := 0 to Pred(AJSON.Count) do
      if AJSON[I].JSONType = jtObject then
        ProcessJSONObject(AJSON.Objects[I])
      else
        raise Exception.CreateFmt('%s: Unsupported JSON format.', [ClassName]);
  end;

var
  VJSON: TJSONData;
  VParser: TJSONParser;
begin
  if Copy(AContentType, 1, Length(BROOK_HTTP_CONTENT_TYPE_APP_JSON)) =
    BROOK_HTTP_CONTENT_TYPE_APP_JSON then
    if BrookSettings.AcceptsJSONContent then
    begin
      AStream.Position := 0;
      VParser := TJSONParser.Create(AStream);
      try
        VJSON := VParser.Parse;
        case VJSON.JSONType of
          jtArray: ProcessJSONArray(TJSONArray(VJSON));
          jtObject: ProcessJSONObject(TJSONObject(VJSON));
        else
          raise Exception.CreateFmt('%s: Unsupported JSON format.', [ClassName]);
        end;
      finally
        VParser.Free;
      end;
    end
    else
      ProcessURLEncoded(AStream, ContentFields)
  else
    inherited HandleUnknownEncoding(AContentType, AStream);
end;

{ TBrookFCGIResponse }

procedure TBrookFCGIResponse.CollectHeaders(AHeaders: TStrings);
begin
  AHeaders.Add(BROOK_HTTP_HEADER_X_POWERED_BY + HS +
    'Brook framework and FCL-Web.');
  inherited CollectHeaders(AHeaders);
end;

{ TBrookFCGIHandler }

function TBrookFCGIHandler.CreateRequest: TFCGIRequest;
begin
  Result := TBrookFCGIRequest.Create;
  if ApplicationURL = ES then
    ApplicationURL := TBrookRouter.RootUrl;
end;

function TBrookFCGIHandler.CreateResponse(ARequest: TFCGIRequest): TFCGIResponse;
begin
  Result := TBrookFCGIResponse.Create(ARequest);
end;

function TBrookFCGIHandler.FormatContentType: string;
begin
  if BrookSettings.Charset <> ES then
    Result := BrookSettings.ContentType + BROOK_HTTP_HEADER_CHARSET +
      BrookSettings.Charset
  else
    Result := BrookSettings.ContentType;
end;

procedure TBrookFCGIHandler.HandleRequest(ARequest: TRequest; AResponse: TResponse);
begin
  AResponse.ContentType := FormatContentType;
  if BrookSettings.Language <> BROOK_DEFAULT_LANGUAGE then
    TBrookMessages.Service.SetLanguage(BrookSettings.Language);
  try
    TBrookRouter.Service.Route(ARequest, AResponse);
    TBrookFCGIRequest(ARequest).DeleteTempUploadedFiles;
  except
    on E: Exception do
      ShowRequestException(AResponse, E);
  end;
end;

procedure TBrookFCGIHandler.ShowRequestException(R: TResponse; E: Exception);
var
  VHandled: Boolean = False;

  procedure HandleHTTP404;
  begin
    if not R.HeadersSent then begin
      R.Code := BROOK_HTTP_STATUS_CODE_NOT_FOUND;
      R.CodeText := BROOK_HTTP_REASON_PHRASE_NOT_FOUND;
      R.ContentType := FormatContentType;
    end;

    if (BrookSettings.Page404File <> ES) and FileExists(BrookSettings.Page404File) then
      R.Contents.LoadFromFile(BrookSettings.Page404File)
    else
      R.Content := BrookSettings.Page404;

    R.Content := StringsReplace(R.Content, ['@root'],
      [BrookSettings.RootUrl], [rfIgnoreCase, rfReplaceAll]);
    // how I could find out path of requested file to insert into error message?

    R.SendContent;
    VHandled := true;
  end;

  procedure HandleHTTP500;
  var
    ExceptionMessage,StackDumpString: TJSONStringType;
  begin
    if not R.HeadersSent then begin
      R.Code := BROOK_HTTP_STATUS_CODE_INTERNAL_SERVER_ERROR;
      R.CodeText := BROOK_HTTP_REASON_PHRASE_INTERNAL_SERVER_ERROR;
      R.ContentType := FormatContentType;
    end;

    if (BrookSettings.Page500File <> ES) and FileExists(BrookSettings.Page500File) then begin
      R.Contents.LoadFromFile(BrookSettings.Page500File);
      R.Content := StringsReplace(R.Content, ['@error'],
        [E.Message], [rfIgnoreCase, rfReplaceAll]);
      if Pos('@trace',LowerCase(R.Content))>0 then
        R.Content := StringsReplace(R.Content, ['@trace'],
          [BrookDumpStack], [rfIgnoreCase, rfReplaceAll]); // DumpStack is slow and not thread safe
    end else begin
      R.Content := BrookSettings.Page500;
      StackDumpString := '';
      if BrookSettings.ContentType = BROOK_HTTP_CONTENT_TYPE_APP_JSON then begin
        ExceptionMessage := StringToJSONString(E.Message);
        if Pos('@trace',LowerCase(R.Content))>0 then
          StackDumpString  := StringToJSONString(BrookDumpStack(LF));
      end else begin
        ExceptionMessage := E.Message;
        if Pos('@trace',LowerCase(R.Content))>0 then
           StackDumpString  := BrookDumpStack;
      end;
      R.Content := StringsReplace(BrookSettings.Page500, ['@error', '@trace'],
        [ExceptionMessage, StackDumpString], [rfIgnoreCase, rfReplaceAll]);
    end;

    R.SendContent;
    VHandled := true;
  end;

begin
  if R.ContentSent then
    Exit;
  if Assigned(BrookSettings.OnError) then
  begin
    BrookSettings.OnError(R, E, VHandled);
    if VHandled then
      Exit;
  end;
  if Assigned(OnShowRequestException) then
  begin
    OnShowRequestException(R, E, VHandled);
    if VHandled then
      Exit;
  end;
  if RedirectOnError and not R.HeadersSent then
  begin
    R.SendRedirect(Format(RedirectOnErrorURL, [HTTPEncode(E.Message)]));
    R.SendContent;
    Exit;
  end;
  if E is EBrookHTTP404 then begin
    HandleHTTP404;
  end else begin
    HandleHTTP500;
  end
end;

initialization
  BrookRegisterApp(TBrookApplication.Create);

end.
