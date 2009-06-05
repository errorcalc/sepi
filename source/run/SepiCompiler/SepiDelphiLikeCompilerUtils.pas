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
  Utilitaires pour les compilateurs Sepi de langages ressemblant � Delphi
  @author sjrd
  @version 1.0
*}
unit SepiDelphiLikeCompilerUtils;

interface

uses
  Windows, SysUtils, StrUtils, TypInfo, ScUtils, SepiReflectionCore,
  SepiMembers, SepiSystemUnit, SepiCompiler, SepiExpressions, SepiInstructions,
  SepiCompilerConsts;

type
  {*
    Type de saut sp�cial existant en Delphi
  *}
  TSepiSpecialJumpKind = (sjkContinue, sjkBreak, sjkExit);

  {*
    Pseudo-routine de test d'identificateur
    Ces pseudo-routines (en Delphi : Defined et Declared) sont utilis�es par
    les instructions du pr�-processuer $IF. Aucune impl�mentation de cette
    interface n'est disponible dans cette unit� : les pr�-processeurs les
    d�finiront selon leur mode de fonctionnement.
    @author sjrd
    @version 1.0
  *}
  ISepiIdentifierTestPseudoRoutine = interface(ISepiReadableValue)
    ['{3A4B9066-D284-4690-A4DF-9AF59BEEA79B}']

    function GetIdentifier: string;
    procedure SetIdentifier(const Value: string);

    procedure Complete;

    property Identifier: string read GetIdentifier write SetIdentifier;
  end;

  {*
    Pseudo-routine d'op�ration sur un type
    @author sjrd
    @version 1.0
  *}
  TSepiTypeOperationPseudoRoutine = class(TSepiCustomWithParams,
    ISepiWantingParams, ISepiValue, ISepiReadableValue)
  private
    FTypeOperation: TSepiTypeOperationValue; /// Op�ration sous-jacente
    FTypeOpValue: ISepiReadableValue;        /// Valeur op�ration
  protected
    function QueryInterface(const IID: TGUID;
      out Obj): HResult; override; stdcall;

    procedure AttachToExpression(const Expression: ISepiExpression); override;

    function MakeTypeExpression(SepiType: TSepiType): ISepiTypeExpression;

    procedure CompleteParams; override;

    procedure Finalize;

    function GetValueType: TSepiType;

    function GetIsConstant: Boolean;
    function GetConstValuePtr: Pointer;

    procedure CompileRead(Compiler: TSepiMethodCompiler;
      Instructions: TSepiInstructionList; var Destination: TSepiMemoryReference;
      TempVars: TSepiTempVarsLifeManager);
  public
    constructor Create(AOperation: TSepiTypeOperation;
      ANilIfNoTypeInfo: Boolean = False);
  end;

  {*
    Pseudo-routine de transtypage
    @author sjrd
    @version 1.0
  *}
  TSepiCastPseudoRoutine = class(TSepiCustomWithParams,
    ISepiWantingParams, ISepiValue, ISepiReadableValue)
  private
    FCastOperator: TSepiCastOperator; /// Op�ration sous-jacente
    FCastOpValue: ISepiReadableValue; /// Valeur op�ration
  protected
    function QueryInterface(const IID: TGUID;
      out Obj): HResult; override; stdcall;

    procedure AttachToExpression(const Expression: ISepiExpression); override;

    procedure CompleteParams; override;

    procedure Finalize;

    function GetValueType: TSepiType;

    function GetIsConstant: Boolean;
    function GetConstValuePtr: Pointer;

    procedure CompileRead(Compiler: TSepiMethodCompiler;
      Instructions: TSepiInstructionList; var Destination: TSepiMemoryReference;
      TempVars: TSepiTempVarsLifeManager);
  public
    constructor Create(DestType: TSepiType);
    constructor CreateOrd;
    constructor CreateChr;
  end;

  {*
    Pseudo-routine de jump sp�cial (Continue, Break ou Exit)
    @author sjrd
    @version 1.0
  *}
  TSepiSpecialJumpPseudoRoutine = class(TSepiCustomExpressionPart,
    ISepiExecutable)
  private
    FKind: TSepiSpecialJumpKind; /// Type de saut sp�cial
  protected
    procedure AttachToExpression(const Expression: ISepiExpression); override;

    procedure CompileExecute(Compiler: TSepiMethodCompiler;
      Instructions: TSepiInstructionList);
  public
    constructor Create(AKind: TSepiSpecialJumpKind);

    property Kind: TSepiSpecialJumpKind read FKind;
  end;

const
  /// Noms des op�rations sur des types
  TypeOperationNames: array[TSepiTypeOperation] of string = (
    'SizeOf', 'TypeInfo', 'Low', 'High', 'Length'
  );

  /// Nom de la pseudo-routine Ord
  OrdName = 'Ord';

  /// Nom de la pseudo-routine Chr
  ChrName = 'Chr';

  SpecialJumpNames: array[TSepiSpecialJumpKind] of string = (
    'Continue', 'Break', 'Exit'
  );

procedure AddMetaToExpression(const Expression: ISepiExpression;
  Meta: TSepiMeta);
function AddPseudoRoutineToExpression(const Expression: ISepiExpression;
  const Identifier: string): Boolean;

function UnitResolveIdent(UnitCompiler: TSepiUnitCompiler;
  const Identifier: string): ISepiExpression;
function MethodResolveIdent(Compiler: TSepiMethodCompiler;
  const Identifier: string): ISepiExpression;

function FieldSelection(SepiContext: TSepiMeta;
  const BaseExpression: ISepiExpression;
  const FieldName: string): ISepiExpression;

implementation

{*
  Ajoute un meta � une expression selon les m�mes r�gles qu'en Delphi
  @param Expression   Expression
  @param Meta         Meta (peut �tre nil)
*}
procedure AddMetaToExpression(const Expression: ISepiExpression;
  Meta: TSepiMeta);
var
  MetaClassValue: TSepiMetaClassValue;
begin
  if Meta = nil then
    Exit;

  // Simply the meta
  ISepiExpressionPart(
    TSepiMetaExpression.Create(Meta)).AttachToExpression(Expression);

  if Meta is TSepiType then
  begin
    // Type
    ISepiExpressionPart(TSepiTypeExpression.Create(
      TSepiType(Meta))).AttachToExpression(Expression);

    if Meta is TSepiClass then
    begin
      MetaClassValue := TSepiMetaClassValue.Create(TSepiClass(Meta));
      ISepiExpressionPart(MetaClassValue).AttachToExpression(Expression);
      MetaClassValue.Complete;
    end;
  end else if Meta is TSepiConstant then
  begin
    // Constant
    ISepiExpressionPart(TSepiTrueConstValue.Create(
      TSepiConstant(Meta))).AttachToExpression(Expression);
  end else if Meta is TSepiVariable then
  begin
    // Variable
    ISepiExpressionPart(TSepiVariableValue.Create(
      TSepiVariable(Meta))).AttachToExpression(Expression);
  end else if Meta is TSepiMethod then
  begin
    // Method
    ISepiExpressionPart(TSepiMethodCall.Create(
      TSepiMethod(Meta))).AttachToExpression(Expression);
  end else if Meta is TSepiOverloadedMethod then
  begin
    // Method
    ISepiExpressionPart(TSepiMethodCall.Create(
      TSepiOverloadedMethod(Meta))).AttachToExpression(Expression);
  end;
end;

{*
  Ajoute une pseudo-routine � une expression
  @param Expression   Expression
  @param Identifier   Identificateur de la pseudo-routine
  @return True si une pseudo-routine a �t� trouv�e, False sinon
*}
function AddPseudoRoutineToExpression(const Expression: ISepiExpression;
  const Identifier: string): Boolean;
var
  TypeOpIndex, SpecialJumpIndex: Integer;
begin
  Result := True;

  // Type operation pseudo-routine
  TypeOpIndex := AnsiIndexText(Identifier, TypeOperationNames);
  if TypeOpIndex >= 0 then
  begin
    ISepiExpressionPart(TSepiTypeOperationPseudoRoutine.Create(
      TSepiTypeOperation(TypeOpIndex))).AttachToExpression(Expression);
    Exit;
  end;

  // Ord pseudo-routine
  if AnsiSameText(Identifier, OrdName) then
  begin
    ISepiExpressionPart(TSepiCastPseudoRoutine.CreateOrd).AttachToExpression(
      Expression);
    Exit;
  end;

  // Chr pseudo-routine
  if AnsiSameText(Identifier, ChrName) then
  begin
    ISepiExpressionPart(TSepiCastPseudoRoutine.CreateChr).AttachToExpression(
      Expression);
    Exit;
  end;

  // Special jump pseudo-routine
  SpecialJumpIndex := AnsiIndexText(Identifier, SpecialJumpNames);
  if SpecialJumpIndex >= 0 then
  begin
    ISepiExpressionPart(TSepiSpecialJumpPseudoRoutine.Create(
      TSepiSpecialJumpKind(SpecialJumpIndex))).AttachToExpression(Expression);
    Exit;
  end;

  Result := False;
end;

{*
  R�soud un identificateur dans le contexte d'une unit�
  @param UnitCompiler   Compilateur d'unit�
  @param Identifier     Identificateur recherch�
  @return Expression repr�sentant l'identificateur, ou nil si non trouv�
*}
function UnitResolveIdent(UnitCompiler: TSepiUnitCompiler;
  const Identifier: string): ISepiExpression;
var
  Meta: TSepiMeta;
begin
  Result := TSepiExpression.Create(UnitCompiler);

  // Meta
  Meta := UnitCompiler.SepiUnit.LookFor(Identifier);
  if Meta <> nil then
  begin
    AddMetaToExpression(Result, Meta);
    Exit;
  end;

  // Pseudo-routine
  if AddPseudoRoutineToExpression(Result, Identifier) then
    Exit;

  Result := nil;
end;

{*
  R�soud un identificateur dans le contexte d'une m�thode
  @param Compiler     Compilateur de m�thode
  @param Identifier   Identificateur recherch�
  @return Expression repr�sentant l'identificateur, ou nil si non trouv�
*}
function MethodResolveIdent(Compiler: TSepiMethodCompiler;
  const Identifier: string): ISepiExpression;
var
  LocalVar: TSepiLocalVar;
  MetaOwner, Meta: TSepiMeta;
  SelfExpression, FieldExpression: ISepiExpression;
begin
  Result := TSepiExpression.Create(Compiler);

  // Variables locales
  LocalVar := Compiler.Locals.GetVarByName(Identifier);
  if LocalVar <> nil then
  begin
    ISepiExpressionPart(
      TSepiLocalVarValue.Create(LocalVar)).AttachToExpression(Result);
    Exit;
  end;

  // Meta
  if Compiler.HasLocalNamespace then
    MetaOwner := Compiler.LocalNamespace
  else
    MetaOwner := Compiler.SepiMethod;
  Meta := MetaOwner.LookFor(Identifier);

  // Meta in the method itself
  if (Meta <> nil) and (Meta.Owner = MetaOwner) then
  begin
    AddMetaToExpression(Result, Meta);
    Exit;
  end;

  // Field selection on Self
  if Compiler.SepiMethod.Signature.SelfParam <> nil then
  begin
    LocalVar := Compiler.Locals.GetVarByName(HiddenParamNames[hpSelf]);
    SelfExpression := TSepiExpression.Create(Result);
    ISepiExpressionPart(
      TSepiLocalVarValue.Create(LocalVar)).AttachToExpression(SelfExpression);
    FieldExpression := FieldSelection(Compiler.SepiMethod,
      SelfExpression, Identifier);

    if FieldExpression <> nil then
    begin
      Result := FieldExpression;
      Exit;
    end;
  end;

  // Meta out of the method itself
  if Meta <> nil then
  begin
    AddMetaToExpression(Result, Meta);
    Exit;
  end;

  // Pseudo-routine
  if AddPseudoRoutineToExpression(Result, Identifier) then
    Exit;

  Result := nil;
end;

{*
  S�lection de champ d'une valeur classe, meta-classe ou interface
  @param SepiContext   Contexte Sepi depuis lequel chercher
  @param BaseValue     Valeur de base
  @param FieldName     Nom du champ
  @param Expression    Expression destination
  @return True si r�ussi, False sinon
*}
function ClassIntfMemberSelection(SepiContext: TSepiMeta;
  const BaseValue: ISepiReadableValue; const FieldName: string;
  const Expression: ISepiExpression): Boolean;
const
  mkClassMethods = [mkClassProcedure, mkClassFunction];
  mkConstrClassMethods = [mkConstructor] + mkClassMethods;
var
  Value: ISepiReadableValue;
  ContainerType: TSepiType;
  FromClass: TSepiMeta;
  Member: TSepiMeta;
begin
  Result := False;
  Value := BaseValue;

  // Fetch container value
  ContainerType := Value.ValueType;
  if ContainerType is TSepiMetaClass then
    ContainerType := TSepiMetaClass(ContainerType).SepiClass;

  // Fetch member
  if ContainerType is TSepiClass then
  begin
    // Set FromClass
    FromClass := SepiContext;
    while (FromClass <> nil) and (not (FromClass is TSepiClass)) do
      FromClass := FromClass.Owner;

    Member := TSepiClass(ContainerType).LookForMember(
      FieldName, SepiContext.OwningUnit, TSepiClass(FromClass));
  end else if ContainerType is TSepiInterface then
  begin
    Member := TSepiInterface(ContainerType).LookForMember(FieldName);
  end else
  begin
    Assert(False);
    Member := nil;
  end;

  // Exit if no member found, or if it is not a member
  if Member = nil then
    Exit;
  if (not (Member is TSepiField)) and (not (Member is TSepiMethod)) and
    (not (Member is TSepiOverloadedMethod)) and
    (not (Member is TSepiProperty)) then
    Exit;

  // OK
  if Member is TSepiField then
  begin
    // Field
    ISepiExpressionPart(TSepiObjectFieldValue.Create(
      Value, TSepiField(Member))).AttachToExpression(Expression);
  end else if Member is TSepiMethod then
  begin
    // Method
    ISepiExpressionPart(TSepiMethodCall.Create(TSepiMethod(Member),
      Value)).AttachToExpression(Expression);
  end else if Member is TSepiOverloadedMethod then
  begin
    // Overloaded method
    ISepiExpressionPart(TSepiMethodCall.Create(TSepiOverloadedMethod(Member),
      Value)).AttachToExpression(Expression);
  end else
  begin
    // Property
    Assert(Member is TSepiProperty);
    ISepiExpressionPart(TSepiPropertyValue.Create(Value,
      TSepiProperty(Member))).AttachToExpression(Expression);
  end;

  Result := True;
end;

{*
  S�lection de champ d'une expression selon les r�gles du Delphi
  @param SepiContext      Contexte Sepi depuis lequel chercher
  @param BaseExpression   Expression de base
  @param FieldName        Nom du champ
  @return Expression repr�sentant le champ s�lectionn� (ou nil si inexistant)
*}
function FieldSelection(SepiContext: TSepiMeta;
  const BaseExpression: ISepiExpression;
  const FieldName: string): ISepiExpression;
var
  CancelResult: Boolean;
  MetaExpression: ISepiMetaExpression;
  Meta: TSepiMeta;
  Value: ISepiValue;
  ReadableValue: ISepiReadableValue;
begin
  Result := TSepiExpression.Create(BaseExpression);
  CancelResult := True;

  // Meta child
  if Supports(BaseExpression, ISepiMetaExpression, MetaExpression) then
  begin
    Meta := MetaExpression.Meta.GetMeta(FieldName);

    if Meta <> nil then
    begin
      AddMetaToExpression(Result, Meta);
      CancelResult := False;
    end;
  end;

  // Record field
  if Supports(BaseExpression, ISepiValue, Value) then
  begin
    if Value.ValueType is TSepiRecordType then
    begin
      Meta := TSepiRecordType(Value.ValueType).GetMeta(FieldName);

      if Meta is TSepiField then
      begin
        ISepiExpressionPart(TSepiRecordFieldValue.Create(
          Value, TSepiField(Meta))).AttachToExpression(Result);
        CancelResult := False;
      end;
    end;
  end;

  // Class or interface method
  if Supports(BaseExpression, ISepiReadableValue, ReadableValue) then
  begin
    if (ReadableValue.ValueType is TSepiClass) or
      (ReadableValue.ValueType is TSepiMetaClass) or
      (ReadableValue.ValueType is TSepiInterface) then
    begin
      if ClassIntfMemberSelection(SepiContext, ReadableValue,
        FieldName, Result) then
        CancelResult := False;
    end;
  end;

  if CancelResult then
    Result := nil;
end;

{---------------------------------------}
{ TSepiTypeOperationPseudoRoutine class }
{---------------------------------------}

{*
  Cr�e une pseudo-routine op�ration sur un type
  @param AOperation         Op�ration
  @param ANilIfNoTypeInfo   Si True, TypeInfo peut renvoyer nil
*}
constructor TSepiTypeOperationPseudoRoutine.Create(
  AOperation: TSepiTypeOperation; ANilIfNoTypeInfo: Boolean = False);
begin
  inherited Create;

  FTypeOperation := TSepiTypeOperationValue.Create(AOperation,
    ANilIfNoTypeInfo);
  FTypeOpValue := FTypeOperation;
end;

{*
  [@inheritDoc]
*}
function TSepiTypeOperationPseudoRoutine.QueryInterface(const IID: TGUID;
  out Obj): HResult;
begin
  if SameGUID(IID, ISepiWantingParams) and ParamsCompleted then
    Result := E_NOINTERFACE
  else if (SameGUID(IID, ISepiValue) or SameGUID(IID, ISepiReadableValue)) and
    (not ParamsCompleted) then
    Result := E_NOINTERFACE
  else
    Result := inherited QueryInterface(IID, Obj);
end;

{*
  [@inheritDoc]
*}
procedure TSepiTypeOperationPseudoRoutine.AttachToExpression(
  const Expression: ISepiExpression);
var
  AsExpressionPart: ISepiExpressionPart;
begin
  AsExpressionPart := Self;

  if not ParamsCompleted then
    Expression.Attach(ISepiWantingParams, AsExpressionPart)
  else
  begin
    Expression.Attach(ISepiValue, AsExpressionPart);
    Expression.Attach(ISepiReadableValue, AsExpressionPart);
  end;
end;

{*
  Construit une expression pour un type
  @param SepiType   Type
  @return Expression repr�sentant le type
*}
function TSepiTypeOperationPseudoRoutine.MakeTypeExpression(
  SepiType: TSepiType): ISepiTypeExpression;
begin
  Result := TSepiTypeExpression.Create(SepiType);
  Result.AttachToExpression(TSepiExpression.Create(Expression));
end;

{*
  [@inheritDoc]
*}
procedure TSepiTypeOperationPseudoRoutine.CompleteParams;
var
  Param: ISepiExpression;
  TypeExpression: ISepiTypeExpression;
  Value: ISepiValue;
begin
  inherited;

  FTypeOpValue.AttachToExpression(TSepiExpression.Create(Expression));

  if ParamCount < 1 then
  begin
    MakeError(SNotEnoughActualParameters);
  end else
  begin
    Param := Params[0];

    if Supports(Param, ISepiTypeExpression, TypeExpression) then
      FTypeOperation.Operand := TypeExpression
    else if Supports(Param, ISepiValue, Value) then
      FTypeOperation.Operand := MakeTypeExpression(Value.ValueType)
    else
      Param.MakeError(STypeIdentifierRequired);

    if ParamCount > 1 then
      MakeError(STooManyActualParameters);
  end;

  if FTypeOperation.Operand = nil then
    FTypeOperation.Operand := MakeTypeExpression(
      (SepiRoot.SystemUnit as TSepiSystemUnit).Integer);

  FTypeOperation.Complete;

  if Expression <> nil then
    AttachToExpression(Expression);
end;

{*
  [@inheritDoc]
*}
procedure TSepiTypeOperationPseudoRoutine.Finalize;
begin
  FTypeOpValue.Finalize;
end;

{*
  [@inheritDoc]
*}
function TSepiTypeOperationPseudoRoutine.GetValueType: TSepiType;
begin
  Result := FTypeOpValue.ValueType;
end;

{*
  [@inheritDoc]
*}
function TSepiTypeOperationPseudoRoutine.GetIsConstant: Boolean;
begin
  Result := FTypeOpValue.IsConstant;
end;

{*
  [@inheritDoc]
*}
function TSepiTypeOperationPseudoRoutine.GetConstValuePtr: Pointer;
begin
  Result := FTypeOpValue.ConstValuePtr;
end;

{*
  [@inheritDoc]
*}
procedure TSepiTypeOperationPseudoRoutine.CompileRead(
  Compiler: TSepiMethodCompiler; Instructions: TSepiInstructionList;
  var Destination: TSepiMemoryReference; TempVars: TSepiTempVarsLifeManager);
begin
  FTypeOpValue.CompileRead(Compiler, Instructions, Destination, TempVars);
end;

{------------------------------}
{ TSepiCastPseudoRoutine class }
{------------------------------}

{*
  Cr�e une pseudo-routine op�rateur de transtypage
  @param ADestType   Type de destination
*}
constructor TSepiCastPseudoRoutine.Create(DestType: TSepiType);
begin
  inherited Create;

  FCastOperator := TSepiCastOperator.Create(DestType);
  FCastOpValue := FCastOperator;
end;

{*
  Cr�e une pseudo-routine op�rateur de transtypage Ord
*}
constructor TSepiCastPseudoRoutine.CreateOrd;
begin
  inherited Create;

  FCastOperator := TSepiCastOperator.CreateOrd;
  FCastOpValue := FCastOperator;
end;

{*
  Cr�e une pseudo-routine op�rateur de transtypage Chr
*}
constructor TSepiCastPseudoRoutine.CreateChr;
begin
  inherited Create;

  FCastOperator := TSepiCastOperator.CreateChr;
  FCastOpValue := FCastOperator;
end;

{*
  [@inheritDoc]
*}
function TSepiCastPseudoRoutine.QueryInterface(const IID: TGUID;
  out Obj): HResult;
begin
  if SameGUID(IID, ISepiWantingParams) and ParamsCompleted then
    Result := E_NOINTERFACE
  else if (SameGUID(IID, ISepiValue) or SameGUID(IID, ISepiReadableValue)) and
    (not ParamsCompleted) then
    Result := E_NOINTERFACE
  else
    Result := inherited QueryInterface(IID, Obj);
end;

{*
  [@inheritDoc]
*}
procedure TSepiCastPseudoRoutine.AttachToExpression(
  const Expression: ISepiExpression);
var
  AsExpressionPart: ISepiExpressionPart;
begin
  AsExpressionPart := Self;

  if not ParamsCompleted then
    Expression.Attach(ISepiWantingParams, AsExpressionPart)
  else
  begin
    Expression.Attach(ISepiValue, AsExpressionPart);
    Expression.Attach(ISepiReadableValue, AsExpressionPart);
  end;
end;

{*
  [@inheritDoc]
*}
procedure TSepiCastPseudoRoutine.CompleteParams;
var
  Param: ISepiExpression;
  Value: ISepiValue;
begin
  inherited;

  FCastOpValue.AttachToExpression(TSepiExpression.Create(Expression));

  if ParamCount < 1 then
  begin
    MakeError(SNotEnoughActualParameters);
  end else
  begin
    Param := Params[0];

    if Supports(Param, ISepiValue, Value) then
      FCastOperator.Operand := Value
    else
      Param.MakeError(SValueRequired);

    if ParamCount > 1 then
      MakeError(STooManyActualParameters);
  end;

  if FCastOperator.Operand = nil then
  begin
    FCastOperator.Operand := TSepiErroneousValue.Create(SepiRoot);
    FCastOperator.Operand.AttachToExpression(
      TSepiExpression.Create(Expression));
  end;

  FCastOperator.Complete;

  if Expression <> nil then
    AttachToExpression(Expression);
end;

{*
  [@inheritDoc]
*}
procedure TSepiCastPseudoRoutine.Finalize;
begin
  FCastOpValue.Finalize;
end;

{*
  [@inheritDoc]
*}
function TSepiCastPseudoRoutine.GetValueType: TSepiType;
begin
  Result := FCastOpValue.ValueType;
end;

{*
  [@inheritDoc]
*}
function TSepiCastPseudoRoutine.GetIsConstant: Boolean;
begin
  Result := FCastOpValue.IsConstant;
end;

{*
  [@inheritDoc]
*}
function TSepiCastPseudoRoutine.GetConstValuePtr: Pointer;
begin
  Result := FCastOpValue.ConstValuePtr;
end;

{*
  [@inheritDoc]
*}
procedure TSepiCastPseudoRoutine.CompileRead(
  Compiler: TSepiMethodCompiler; Instructions: TSepiInstructionList;
  var Destination: TSepiMemoryReference; TempVars: TSepiTempVarsLifeManager);
begin
  FCastOpValue.CompileRead(Compiler, Instructions, Destination, TempVars);
end;

{-------------------------------------}
{ TSepiSpecialJumpPseudoRoutine class }
{-------------------------------------}

{*
  Cr�e la pseudo-routine de jump sp�cial
  @param AKind   Type de saut sp�cial
*}
constructor TSepiSpecialJumpPseudoRoutine.Create(AKind: TSepiSpecialJumpKind);
begin
  inherited Create;
  FKind := AKind;
end;

{*
  [@inheritDoc]
*}
procedure TSepiSpecialJumpPseudoRoutine.AttachToExpression(
  const Expression: ISepiExpression);
var
  AsExpressionPart: ISepiExpressionPart;
begin
  AsExpressionPart := Self;

  Expression.Attach(ISepiExecutable, AsExpressionPart);
end;

{*
  [@inheritDoc]
*}
procedure TSepiSpecialJumpPseudoRoutine.CompileExecute(
  Compiler: TSepiMethodCompiler; Instructions: TSepiInstructionList);
begin
  case Kind of
    sjkContinue: Instructions.Add(TSepiContinue.Create(Compiler));
    sjkBreak:    Instructions.Add(TSepiBreak.Create(Compiler));
    sjkExit:     Instructions.Add(TSepiExit.Create(Compiler));
  end;
end;

end.

