{-------------------------------------------------------------------------------
Sepi - Object-oriented script engine for Delphi
Copyright (C) 2006-2007  S�bastien Doeraene
All Rights Reserved

This file is part of Sepi.

Sepi is free software: you can redistribute it and/or modify it under the terms
of the GNU General Public License as published by the Free Software Foundation,
either version 3 of the License, or (at your option) any later version.

Sepi is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
Sepi.  If not, see <http://www.gnu.org/licenses/>.
-------------------------------------------------------------------------------}

{*
  Utilitaires d'analyse lexicale Sepi
  @author sjrd
  @version 1.0
*}
unit SepiLexerUtils;

interface

uses
  SysUtils, Classes, SepiCore, SepiCompilerErrors, SepiParseTrees,
  SepiCompilerConsts;

const
  tkEof = 0; /// Lex�me fin de fichier

type
  {*
    Fonction d'analyse d'un terminal
    @return True si un v�ritable terminal a �t� analys�, False sinon
  *}
  TSepiLexingFunc = function: Boolean of object;

  {*
    Erreur d'analyse lexicale
    @author sjrd
    @version 1.0
  *}
  ESepiLexicalError = class(ESepiError);

  {*
    Marque dans le source - utilis� pour retourner en arri�re dans le code
    @author sjrd
    @version 1.0
  *}
  TSepiLexerBookmark = class(TObject)
  private
    FCursor: Integer;                 /// Index courant dans le source
    FCurrentPos: TSepiSourcePosition; /// Position courante
    FNextPos: TSepiSourcePosition;    /// Prochaine position
    FCurTerminal: TSepiTerminal;      /// Dernier terminal analys�
  public
    constructor Create(ACursor: Integer;
      const ACurrentPos, ANextPos: TSepiSourcePosition;
      ACurTerminal: TSepiTerminal);
    destructor Destroy; override;

    property Cursor: Integer read FCursor;
    property CurrentPos: TSepiSourcePosition read FCurrentPos;
    property NextPos: TSepiSourcePosition read FNextPos;
    property CurTerminal: TSepiTerminal read FCurTerminal;
  end;

  {*
    Classe de base pour les analyseurs lexicaux Sepi
    @author sjrd
    @version 1.0
  *}
  TSepiCustomLexer = class(TObject)
  private
    FErrors: TSepiCompilerErrorList;  /// Erreurs de compilation
    FCode: string;                    /// Code source � analyser
    FCursor: Integer;                 /// Index courant dans le source
    FCurrentPos: TSepiSourcePosition; /// Position courante
    FNextPos: TSepiSourcePosition;    /// Prochaine position
    FCurTerminal: TSepiTerminal;      /// Dernier terminal analys�

    FContext: TSepiNonTerminal; /// Contexte courant (peut �tre nil)
  protected
    procedure MakeError(const ErrorMsg: string;
      Kind: TSepiErrorKind = ekError);

    procedure TerminalParsed(SymbolClass: TSepiSymbolClass;
      const Representation: string);
    procedure NoTerminalParsed;

    procedure CursorForward(Amount: Integer = 1);

    procedure IdentifyKeyword(const Key: string;
      var SymbolClass: TSepiSymbolClass); virtual;
  public
    constructor Create(AErrors: TSepiCompilerErrorList; const ACode: string;
      const AFileName: TFileName = '');
    destructor Destroy; override;

    procedure NextTerminal; virtual; abstract;

    function MakeBookmark: TSepiLexerBookmark;
    procedure ResetToBookmark(Bookmark: TSepiLexerBookmark;
      FreeBookmark: Boolean = True);

    property Errors: TSepiCompilerErrorList read FErrors;
    property Code: string read FCode;

    property Cursor: Integer read FCursor;
    property CurrentPos: TSepiSourcePosition read FCurrentPos;

    property CurTerminal: TSepiTerminal read FCurTerminal;

    property Context: TSepiNonTerminal read FContext write FContext;
  end;

  {*
    Classe de base pour les analyseurs lexicaux Sepi �crits � la main
    @author sjrd
    @version 1.0
  *}
  TSepiCustomManualLexer = class(TSepiCustomLexer)
  protected
    /// Tableau des fonctions d'analyse index� par les caract�res de d�but
    LexingFuncs: array[#0..#255] of TSepiLexingFunc;

    procedure InitLexingFuncs; virtual;

    function ActionUnknown: Boolean;
    function ActionEof: Boolean;
    function ActionBlank: Boolean;
  public
    constructor Create(AErrors: TSepiCompilerErrorList; const ACode: string;
      const AFileName: TFileName = '');

    procedure NextTerminal; override;
  end;

const
  BlankChars = [#9, #10, #13, ' '];

implementation

{--------------------------}
{ TSepiLexerBookmark class }
{--------------------------}

{*
  Cr�e un marque-page
  @param ACursor        Index courant dans le source
  @param ACurrentPos    Position courante
  @param ANextPos       Prochaine position
  @param ACurTerminal   Dernier terminal analys�
*}
constructor TSepiLexerBookmark.Create(ACursor: Integer;
  const ACurrentPos, ANextPos: TSepiSourcePosition;
  ACurTerminal: TSepiTerminal);
begin
  inherited Create;

  FCursor := ACursor;
  FCurrentPos := ACurrentPos;
  FNextPos := ANextPos;

  FCurTerminal := TSepiTerminal.Clone(ACurTerminal);
end;

{*
  [@inheritDoc]
*}
destructor TSepiLexerBookmark.Destroy;
begin
  FCurTerminal.Free;

  inherited;
end;

{------------------------}
{ TSepiCustomLexer class }
{------------------------}

{*
  Cr�e un analyseur lexical
  @param AErrors     Erreurs de compilation
  @param ACode       Code source � analyser
  @param AFileName   Nom du fichier source
*}
constructor TSepiCustomLexer.Create(AErrors: TSepiCompilerErrorList;
  const ACode: string; const AFileName: TFileName = '');
begin
  inherited Create;

  FErrors := AErrors;

  FCode := ACode + #0;
  FCursor := 1;

  if AFileName = '' then
    FNextPos.FileName := AErrors.CurrentFileName
  else
    FNextPos.FileName := AFileName;
  FNextPos.Line := 1;
  FNextPos.Col := 1;

  NoTerminalParsed;

  FCurTerminal := nil;
end;

{*
  [@inheritDoc]
*}
destructor TSepiCustomLexer.Destroy;
begin
  FreeAndNil(FCurTerminal);

  inherited;
end;

{*
  Produit une erreur
  @param ErrorMsg   Message d'erreur
  @param Kind       Type d'erreur (d�faut = Erreur)
*}
procedure TSepiCustomLexer.MakeError(const ErrorMsg: string;
  Kind: TSepiErrorKind = ekError);
begin
  Errors.MakeError(ErrorMsg, Kind, CurrentPos);
end;

{*
  Indique qu'un terminal a �t� analys�
  @param SymbolClass      Class de symbole
  @param Representation   Repr�sentation du terminal
*}
procedure TSepiCustomLexer.TerminalParsed(SymbolClass: TSepiSymbolClass;
  const Representation: string);
begin
  FreeAndNil(FCurTerminal);

  FCurTerminal := TSepiTerminal.Create(SymbolClass, CurrentPos,
    Representation);
  FCurrentPos := FNextPos;
end;

{*
  Indique qu'aucun terminal n'a �t� analys�
*}
procedure TSepiCustomLexer.NoTerminalParsed;
begin
  FCurrentPos := FNextPos;
end;

{*
  Avance le curseur
  @param Amount   Nombre de caract�res � passer (d�faut = 1)
*}
procedure TSepiCustomLexer.CursorForward(Amount: Integer = 1);
var
  I: Integer;
begin
  Assert(Amount >= 0);

  for I := FCursor to FCursor+Amount-1 do
  begin
    if (I > 0) and (Code[I] = #10) and (Code[I-1] = #13) then
      // skip
    else if (Code[I] = #13) or (Code[I] = #10) then
    begin
      Inc(FNextPos.Line);
      FNextPos.Col := 1;
    end else
      Inc(FNextPos.Col);
  end;

  Inc(FCursor, Amount);
end;

{*
  Identifie un mot-clef
  @param Key           Mot-clef �ventuel � identifier
  @param SymbolClass   � modifier selon la classe du mot-clef
*}
procedure TSepiCustomLexer.IdentifyKeyword(const Key: string;
  var SymbolClass: TSepiSymbolClass);
begin
end;

{*
  Construit un marque-page � la position courante
  @return Le marque-page construit
*}
function TSepiCustomLexer.MakeBookmark: TSepiLexerBookmark;
begin
  Result := TSepiLexerBookmark.Create(FCursor, FCurrentPos, FNextPos,
    FCurTerminal);
end;

{*
  Retourne dans le code source � la position d'un marque-page
  @param Bookmark       Marque-page
  @param FreeBookmark   Si True, le marque-page est ensuite d�truit
*}
procedure TSepiCustomLexer.ResetToBookmark(Bookmark: TSepiLexerBookmark;
  FreeBookmark: Boolean = True);
begin
  FCursor := Bookmark.Cursor;
  FCurrentPos := Bookmark.CurrentPos;
  FNextPos := Bookmark.NextPos;

  FreeAndNil(FCurTerminal);
  FCurTerminal := TSepiTerminal.Clone(Bookmark.CurTerminal);

  if FreeBookmark then
    Bookmark.Free;
end;

{------------------------------}
{ TSepiCustomManualLexer class }
{------------------------------}

{*
  [@inheritDoc]
*}
constructor TSepiCustomManualLexer.Create(AErrors: TSepiCompilerErrorList;
  const ACode: string; const AFileName: TFileName = '');
begin
  inherited;

  InitLexingFuncs;
end;

{*
  Initialise le tableau LexingFuncs
*}
procedure TSepiCustomManualLexer.InitLexingFuncs;
var
  C: Char;
begin
  for C := #0 to #255 do
  begin
    if C = #0 then
      LexingFuncs[C] := ActionEof
    else if C in BlankChars then
      LexingFuncs[C] := ActionBlank
    else
      LexingFuncs[C] := ActionUnknown;
  end;
end;

{*
  Action pour un caract�re inconnu - d�clenche une erreur lexicale
  @return Ne retourne jamais
  @raise ESepiLexicalError
*}
function TSepiCustomManualLexer.ActionUnknown: Boolean;
begin
  MakeError(Format(SBadSourceCharacter, [Code[Cursor]]), ekFatalError);
  Result := False;
end;

{*
  Analise un caract�re de fin de fichier
  @return True - la fin de fichier est bien r�elle
*}
function TSepiCustomManualLexer.ActionEof: Boolean;
begin
  TerminalParsed(tkEof, SEndOfFile);
  Result := True;
end;

{*
  Analise un blanc
  @return False - les blancs ne sont pas de v�ritables lex�mes
*}
function TSepiCustomManualLexer.ActionBlank: Boolean;
begin
  while Code[Cursor] in BlankChars do
    CursorForward;

  NoTerminalParsed;
  Result := False;
end;

{*
  [@inheritDoc]
*}
procedure TSepiCustomManualLexer.NextTerminal;
begin
  while not LexingFuncs[Code[Cursor]] do;
end;

end.

