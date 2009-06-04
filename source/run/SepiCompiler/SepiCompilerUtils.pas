unit SepiCompilerUtils;

interface

uses
  SysUtils, Classes, SepiReflectionCore, SepiOrdTypes, SepiMembers,
  SepiSystemUnit,
  SepiExpressions, SepiParseTrees, SepiLexerUtils, SepiParserUtils,
  SepiCompilerErrors, SepiCompiler, SepiCompilerConsts;

type
  {*
    Classe de base pour les constructeurs de membres de type composites
    @author sjrd
    @version 1.0
  *}
  TSepiMemberBuilder = class(TObject)
  private
    FOwner: TSepiMeta; /// Propri�taire du membre � construire

    FOwnerType: TSepiType;         /// Type propri�taire (si applicable)
    FOwnerRecord: TSepiRecordType; /// Record propri�taire (si applicable)
    FOwnerClass: TSepiClass;       /// Classe propri�taire (si applicable)
    FOwnerIntf: TSepiInterface;    /// Interface propri�taire (si applicable)

    FName: string; /// Nom du membre � construire

    FCurrentNode: TSepiParseTreeNode; /// Noeud courant pour les erreurs
  protected
    procedure MakeError(const ErrorMsg: string;
      Kind: TSepiErrorKind = ekError);

    function LookForMember(const MemberName: string): TSepiMeta;
    function LookForMemberOrError(const MemberName: string): TSepiMeta;

    property OwnerType: TSepiType read FOwnerType;
    property OwnerRecord: TSepiRecordType read FOwnerRecord;
    property OwnerClass: TSepiClass read FOwnerClass;
    property OwnerIntf: TSepiInterface read FOwnerIntf;
  public
    constructor Create(AOwner: TSepiMeta);

    {*
      Construit le membre
    *}
    procedure Build; virtual; abstract;

    property Owner: TSepiMeta read FOwner;
    property Name: string read FName write FName;

    property CurrentNode: TSepiParseTreeNode
      read FCurrentNode write FCurrentNode;
  end;

  {*
    Constructeur de propri�t�
    @author sjrd
    @version 1.0
  *}
  TSepiPropertyBuilder = class(TSepiMemberBuilder)
  private
    FSignature: TSepiSignature;     /// Signature
    FReadAccess: TSepiMeta;         /// Accesseur en lecture
    FWriteAccess: TSepiMeta;        /// Accesseur en �criture
    FIndex: Integer;                /// Index
    FIndexType: TSepiOrdType;       /// Type de l'index
    FDefaultValue: Integer;         /// Valeur par d�faut
    FStorage: TSepiPropertyStorage; /// Sp�cificateur de stockage
    FIsDefault: Boolean;            /// True si c'est la propri�t� par d�faut

    function ValidateFieldAccess(Field: TSepiField): Boolean;
    function ValidateMethodAccess(Method: TSepiMethod;
      IsWriteAccess: Boolean): Boolean;
    function ValidateAccess(Access: TSepiMeta; IsWriteAccess: Boolean): Boolean;

    function IsTypeValidForDefault(PropType: TSepiType): Boolean;
    function CheckDefaultAllowed: Boolean;
  public
    constructor Create(AOwner: TSepiMeta);
    destructor Destroy; override;

    function Redefine(Node: TSepiParseTreeNode): Boolean;

    function SetReadAccess(const ReadAccessName: string;
      Node: TSepiParseTreeNode): Boolean;
    function SetWriteAccess(const WriteAccessName: string;
      Node: TSepiParseTreeNode): Boolean;

    function SetIndex(const Value: ISepiReadableValue;
      Node: TSepiParseTreeNode): Boolean;
    function SetDefaultValue(const Value: ISepiReadableValue;
      Node: TSepiParseTreeNode): Boolean;
    function SetNoDefault(Node: TSepiParseTreeNode): Boolean;

    function SetIsDefault(Node: TSepiParseTreeNode): Boolean;

    procedure Build; override;

    property Signature: TSepiSignature read FSignature;
    property ReadAccess: TSepiMeta read FReadAccess;
    property WriteAccess: TSepiMeta read FWriteAccess;
    property Index: Integer read FIndex;
    property IndexType: TSepiOrdType read FIndexType;
    property DefaultValue: Integer read FDefaultValue;
    property Storage: TSepiPropertyStorage read FStorage;
    property IsDefault: Boolean read FIsDefault;
  end;

function RequireReadableValue(const Expression: ISepiExpression;
  out Value: ISepiReadableValue): Boolean;
function RequireWritableValue(const Expression: ISepiExpression;
  out Value: ISepiWritableValue): Boolean;

function ConstValueAsInt64(const Value: ISepiReadableValue): Int64;

procedure TryAndConvertValues(SystemUnit: TSepiSystemUnit;
  var LowerValue, HigherValue: ISepiReadableValue);

function CompileSepiSource(SepiRoot: TSepiRoot;
  Errors: TSepiCompilerErrorList; SourceFile: TStrings;
  const DestFileName: TFileName; RootNodeClass: TSepiParseTreeRootNodeClass;
  RootSymbolClass: TSepiSymbolClass; LexerClass: TSepiCustomLexerClass;
  ParserClass: TSepiCustomParserClass): TSepiUnit;

implementation

{-----------------}
{ Global routines }
{-----------------}

{*
  Requiert une valeur qui peut �tre lue
  En cas d'erreur, Value est affect�e � une valeur erron�e
  @param Expression   Expression
  @param Value        En sortie : l'expression sous forme de valeur lisible
  @return True en cas de succ�s, False sinon
*}
function RequireReadableValue(const Expression: ISepiExpression;
  out Value: ISepiReadableValue): Boolean;
begin
  Result := Supports(Expression, ISepiReadableValue, Value);

  if not Result then
  begin
    Expression.MakeError(SReadableValueRequired);
    Value := TSepiErroneousValue.Create(Expression.SepiRoot);
    Value.AttachToExpression(TSepiExpression.Create(Expression));
  end;
end;

{*
  Requiert une valeur qui peut �tre �crite
  En cas d'erreur, Value est affect�e � nil
  @param Expression   Expression
  @param Value        En sortie : l'expression sous forme de valeur � �crire
  @return True en cas de succ�s, False sinon
*}
function RequireWritableValue(const Expression: ISepiExpression;
  out Value: ISepiWritableValue): Boolean;
begin
  Result := Supports(Expression, ISepiWritableValue, Value);

  if not Result then
    Expression.MakeError(SReadableValueRequired);
end;

{*
  Lit une valeur constante comme un Int64
  @param Value   Valeur � lire
  @return Valeur sous forme d'Int64
*}
function ConstValueAsInt64(const Value: ISepiReadableValue): Int64;
var
  IntegerType: TSepiIntegerType;
begin
  if Value.ValueType is TSepiInt64Type then
    Result := Int64(Value.ConstValuePtr^)
  else
  begin
    IntegerType := TSepiIntegerType(Value.ValueType);

    if IntegerType.Signed then
      Result := IntegerType.ValueAsInteger(Value.ConstValuePtr^)
    else
      Result := IntegerType.ValueAsCardinal(Value.ConstValuePtr^);
  end;
end;

{*
  Essaie de convertir les valeurs pour qu'elles aient le m�me type
  @param SystemUnit    Unit� syst�me
  @param LowerValue    Valeur basse
  @param HigherValue   Valeur haute
*}
procedure TryAndConvertValues(SystemUnit: TSepiSystemUnit;
  var LowerValue, HigherValue: ISepiReadableValue);
var
  LowerType, HigherType, CommonType: TSepiType;
  IntLowerValue, IntHigherValue: Int64;
begin
  LowerType := LowerValue.ValueType;
  HigherType := HigherValue.ValueType;

  if (LowerType is TSepiEnumType) and (HigherType is TSepiEnumType) then
  begin
    // Enumeration types

    CommonType := TSepiEnumType(LowerType).BaseType;

    if TSepiEnumType(HigherType).BaseType = CommonType then
    begin
      if LowerType <> CommonType then
        LowerValue := TSepiCastOperator.CastValue(
          CommonType, LowerValue) as ISepiReadableValue;

      if HigherType <> CommonType then
        HigherValue := TSepiCastOperator.CastValue(
          CommonType, HigherValue) as ISepiReadableValue;
    end;
  end else
  begin
    // Integer or char types

    if ((LowerType is TSepiIntegerType) or (LowerType is TSepiInt64Type)) and
      ((HigherType is TSepiIntegerType) or (HigherType is TSepiInt64Type)) then
    begin
      // Integer types

      IntLowerValue := ConstValueAsInt64(LowerValue);
      IntHigherValue := ConstValueAsInt64(HigherValue);

      if (Integer(IntLowerValue) = IntLowerValue) and
        (Integer(IntHigherValue) = IntHigherValue) then
        CommonType := SystemUnit.Integer
      else if (Cardinal(IntLowerValue) = IntLowerValue) and
        (Cardinal(IntHigherValue) = IntHigherValue) then
        CommonType := SystemUnit.Cardinal
      else
        CommonType := SystemUnit.Int64;
    end else if (LowerType is TSepiCharType) and
      (HigherType is TSepiCharType) then
    begin
      // Char types

      if LowerType.Size >= HigherType.Size then
        CommonType := LowerType
      else
        CommonType := HigherType;
    end else
    begin
      // Error
      Exit;
    end;

    if LowerType <> CommonType then
      LowerValue := TSepiConvertOperation.ConvertValue(
        CommonType, LowerValue);

    if HigherType <> CommonType then
      HigherValue := TSepiConvertOperation.ConvertValue(
        CommonType, HigherValue) as ISepiReadableValue;
  end;
end;

{*
  Compile un fichier source Sepi
  @param SepiRoot          Racine Sepi
  @param Errors            Gestionnaire d'erreurs
  @param SourceFile        Source � compiler
  @param DestFileName      Nom du fichier de sortie
  @param RootNodeClass     Classe du noeud racine
  @param RootSymbolClass   Classe de symboles du noeud racine
  @param LexerClass        Classe de l'analyseur lexical
  @param ParserClass       Classe de l'analyseur syntaxique
  @return Unit� Sepi compil�e
*}
function CompileSepiSource(SepiRoot: TSepiRoot;
  Errors: TSepiCompilerErrorList; SourceFile: TStrings;
  const DestFileName: TFileName; RootNodeClass: TSepiParseTreeRootNodeClass;
  RootSymbolClass: TSepiSymbolClass; LexerClass: TSepiCustomLexerClass;
  ParserClass: TSepiCustomParserClass): TSepiUnit;
var
  DestFile: TStream;
  RootNode: TSepiParseTreeRootNode;
  Compiler: TSepiUnitCompiler;
begin
  // Silence the compiler warning
  Result := nil;

  DestFile := nil;
  RootNode := nil;
  try
    // Actually compile the source file
    RootNode := RootNodeClass.Create(RootSymbolClass, SepiRoot, Errors);
    try
      ParserClass.Parse(RootNode, LexerClass.Create(Errors,
        SourceFile.Text, Errors.CurrentFileName));
    except
      on Error: ESepiCompilerFatalError do
        raise;
      on Error: Exception do
      begin
        Errors.MakeError(Error.Message, ekFatalError,
          RootNode.FindRightMost.SourcePos);
      end;
    end;

    // Check for errors
    Errors.CheckForErrors;

    // Fetch Sepi unit compiler and unit
    Compiler := RootNode.UnitCompiler;
    Result := Compiler.SepiUnit;

    // Compile and write compiled unit to destination stream
    try
      DestFile := TFileStream.Create(DestFileName, fmCreate);
      Compiler.WriteToStream(DestFile);
    except
      on EStreamError do
        Errors.MakeError(Format(SCantOpenDestFile, [DestFileName]),
          ekFatalError);
      on Error: ESepiCompilerFatalError do
        raise;
      on Error: Exception do
        Errors.MakeError(Error.Message, ekFatalError);
    end;
  finally
    RootNode.Free;
    DestFile.Free;
  end;
end;

{--------------------------}
{ TSepiMemberBuilder class }
{--------------------------}

{*
  Cr�e un nouveau constructeur de membre
  @param AOwner   Propri�taire du membre � construire
*}
constructor TSepiMemberBuilder.Create(AOwner: TSepiMeta);
begin
  inherited Create;

  FOwner := AOwner;

  if Owner is TSepiType then
  begin
    FOwnerType := TSepiType(Owner);

    if Owner is TSepiRecordType then
      FOwnerRecord := TSepiRecordType(Owner)
    else if Owner is TSepiClass then
      FOwnerClass := TSepiClass(Owner)
    else if Owner is TSepiInterface then
      FOwnerIntf := TSepiInterface(Owner);
  end;
end;

{*
  Produit un message d'erreur
  @param ErrorMsg   Message d'erreur
  @param Kind       Type d'erreur
*}
procedure TSepiMemberBuilder.MakeError(const ErrorMsg: string;
  Kind: TSepiErrorKind = ekError);
begin
  CurrentNode.MakeError(ErrorMsg, Kind);
end;

{*
  Cherche un membre du type englobant d'apr�s son nom
  @param MemberName   Nom du membre
  @return Membre recherch�, ou nil si non trouv�
*}
function TSepiMemberBuilder.LookForMember(const MemberName: string): TSepiMeta;
begin
  if OwnerRecord <> nil then
    Result := OwnerRecord.GetMeta(MemberName)
  else if OwnerClass <> nil then
    Result := OwnerClass.LookForMember(MemberName)
  else if OwnerIntf <> nil then
    Result := OwnerIntf.LookForMember(MemberName)
  else
    Result := nil;
end;

{*
  Cherche un membre du type englobant d'apr�s son nom
  En cas d'erreur, produit un message d'erreur.
  @param MemberName   Nom du membre
  @return Membre recherch�, ou nil si non trouv�
*}
function TSepiMemberBuilder.LookForMemberOrError(
  const MemberName: string): TSepiMeta;
begin
  Result := LookForMember(MemberName);
  CheckIdentFound(Result, MemberName, CurrentNode);
end;

{----------------------------}
{ TSepiPropertyBuilder class }
{----------------------------}

{*
  Cr�e un nouveau constructeur de propri�t�
  @param AOwner   Propri�taire du membre � construire
*}
constructor TSepiPropertyBuilder.Create(AOwner: TSepiMeta);
begin
  inherited Create(AOwner);

  FSignature := TSepiSignature.CreateConstructing(Owner.OwningUnit, OwnerType);
  FSignature.Kind := skProperty;

  FIndex := NoIndex;
  FDefaultValue := NoDefaultValue;
  FStorage.Kind := pskConstant;
  FStorage.Stored := True;
end;

{*
  [@inheritDoc]
*}
destructor TSepiPropertyBuilder.Destroy;
begin
  FSignature.Free;

  inherited;
end;

{*
  Valide un acc�s via un champ
  @param Field   Champ accesseur
  @return True si le champ est valide, False sinon
*}
function TSepiPropertyBuilder.ValidateFieldAccess(Field: TSepiField): Boolean;
begin
  if Signature.ParamCount > 0 then
  begin
    MakeError(SParametersMismatch);
    Result := False;
  end else if Field.FieldType <> Signature.ReturnType then
  begin
    MakeError(Format(STypeMismatch,
      [Field.FieldType.DisplayName, Signature.ReturnType.DisplayName]));
    Result := False;
  end else
  begin
    Result := True;
  end;
end;

{*
  Valide un acc�s via une m�thode
  @param Method          M�thode accesseur
  @param IsWriteAccess   Indique si c'est l'acc�s en �criture
  @return True si la m�thode est valide, False sinon
*}
function TSepiPropertyBuilder.ValidateMethodAccess(Method: TSepiMethod;
  IsWriteAccess: Boolean): Boolean;
var
  ParamCount, I: Integer;
  Param: TSepiParam;
begin
  ParamCount := Signature.ParamCount;
  if Index <> NoIndex then
    Inc(ParamCount);
  if IsWriteAccess then
    Inc(ParamCount);

  if Method.Signature.ParamCount <> ParamCount then
  begin
    MakeError(SParametersMismatch);
    Result := False;
    Exit;
  end;

  Result := True;

  // Check parameters
  for I := 0 to Signature.ParamCount-1 do
  begin
    if not Method.Signature.Params[I].Equals(Signature.Params[I],
      pcoCompatibility) then
    begin
      Result := False;
      Break;
    end;
  end;

  // Check index
  if Result and (Index <> NoIndex) then
  begin
    Param := Method.Signature.Params[Signature.ParamCount];

    if (Param.Kind in [pkVar, pkOut]) or (Param.ParamType = nil) then
      Result := False;

    if (IndexType <> nil) and
      (not Param.ParamType.CompatibleWith(IndexType)) then
      Result := False;
  end;

  // Check property type
  if Result then
  begin
    if IsWriteAccess then
    begin
      Param := Method.Signature.Params[Method.Signature.ParamCount-1];

      if (Param.Kind in [pkVar, pkOut]) or
        (Param.ParamType <> Signature.ReturnType) then
        Result := False;
    end else
    begin
      if Method.Signature.ReturnType <> Signature.ReturnType then
        Result := False;
    end;
  end;

  // Error message
  if not Result then
    MakeError(SParametersMismatch);
end;

{*
  Valide un accesseur
  @param Access          Accesseur
  @param IsWriteAccess   Indique si c'est l'acc�s en �criture
  @return True si l'accesseur est valide, False sinon
*}
function TSepiPropertyBuilder.ValidateAccess(Access: TSepiMeta;
  IsWriteAccess: Boolean): Boolean;
begin
  if Access = nil then
    Result := False
  else if Access is TSepiField then
    Result := ValidateFieldAccess(TSepiField(Access))
  else if Access is TSepiMethod then
    Result := ValidateMethodAccess(TSepiMethod(Access), IsWriteAccess)
  else
  begin
    MakeError(SFieldOrMethodRequired);
    Result := False;
  end;
end;

{*
  Teste si un type de propri�t� peut avoir un default
*}
function TSepiPropertyBuilder.IsTypeValidForDefault(
  PropType: TSepiType): Boolean;
begin
  if PropType is TSepiOrdType then
    Result := True
  else if (PropType is TSepiSetType) and (PropType.Size <= SizeOf(Integer)) then
    Result := True
  else
    Result := False;
end;

{*
  V�rifie que default ou nodefault est valide
  @return True si autoris�, False sinon
*}
function TSepiPropertyBuilder.CheckDefaultAllowed: Boolean;
begin
  if Signature.ParamCount > 0 then
  begin
    MakeError(SScalarPropertyRequired);
    Result := False;
  end else if not IsTypeValidForDefault(Signature.ReturnType) then
  begin
    MakeError(SOrdinalTypeRequired);
    Result := False;
  end else
  begin
    Result := True;
  end;
end;

{*
  Red�finit une propri�t� h�rit�e
  @param Node   Noeud utilis� pour produire les erreurs
  @return True en cas de succ�s, False sinon
*}
function TSepiPropertyBuilder.Redefine(Node: TSepiParseTreeNode): Boolean;
var
  PreviousMeta: TSepiMeta;
  Previous: TSepiProperty;
  I: Integer;
begin
  CurrentNode := Node;

  PreviousMeta := LookForMember(Name);
  if not (PreviousMeta is TSepiProperty) then
  begin
    MakeError(SPropertyNotFoundInBaseClass);
    Signature.ReturnType := Node.SystemUnit.Integer;
    Result := False;
    Exit;
  end;

  Previous := TSepiProperty(PreviousMeta);

  for I := 0 to Previous.Signature.ParamCount-1 do
    TSepiParam.Clone(Signature, Previous.Signature.Params[I]);
  Signature.ReturnType := Previous.Signature.ReturnType;

  FReadAccess := Previous.ReadAccess.Meta;
  FWriteAccess := Previous.WriteAccess.Meta;
  FIndex := Previous.Index;
  FDefaultValue := Previous.DefaultValue;
  FStorage := Previous.Storage;
  FIsDefault := Previous.IsDefault;

  Result := True;
end;

{*
  Sp�cifie l'accesseur en lecture
  @param ReadAccessName   Nom de l'accesseur
  @param Node             Noeud utilis� pour produire les erreurs
  @return True en cas de succ�s, False sinon
*}
function TSepiPropertyBuilder.SetReadAccess(const ReadAccessName: string;
  Node: TSepiParseTreeNode): Boolean;
var
  Access: TSepiMeta;
begin
  CurrentNode := Node;

  Access := LookForMemberOrError(ReadAccessName);
  Result := ValidateAccess(Access, False);

  if Result then
    FReadAccess := Access;
end;

{*
  Sp�cifie l'accesseur en �criture
  @param ReadAccessName   Nom de l'accesseur
  @param Node             Noeud utilis� pour produire les erreurs
  @return True en cas de succ�s, False sinon
*}
function TSepiPropertyBuilder.SetWriteAccess(const WriteAccessName: string;
  Node: TSepiParseTreeNode): Boolean;
var
  Access: TSepiMeta;
begin
  CurrentNode := Node;

  Access := LookForMemberOrError(WriteAccessName);
  Result := ValidateAccess(Access, True);

  if Result then
    FWriteAccess := Access;
end;

{*
  Sp�cifie l'index
  @param Value   Valeur index
  @param Node    Noeud utilis� pour produire les erreurs
  @return True en cas de succ�s, False sinon
*}
function TSepiPropertyBuilder.SetIndex(
  const Value: ISepiReadableValue; Node: TSepiParseTreeNode): Boolean;
begin
  CurrentNode := Node;

  if not (Value.ValueType is TSepiOrdType) then
  begin
    MakeError(SOrdinalTypeRequired);
    Result := False;
  end else if not Value.IsConstant then
  begin
    MakeError(SConstExpressionRequired);
    Result := False;
  end else
  begin
    FIndexType := TSepiOrdType(Value.ValueType);
    FIndex := FIndexType.ValueAsInteger(Value.ConstValuePtr^);
    Result := True;
  end;
end;

{*
  Sp�cifie la valeur par d�faut
  @param Value   Valeur par d�faut
  @param Node    Noeud utilis� pour produire les erreurs
  @return True en cas de succ�s, False sinon
*}
function TSepiPropertyBuilder.SetDefaultValue(
  const Value: ISepiReadableValue; Node: TSepiParseTreeNode): Boolean;
begin
  CurrentNode := Node;

  if not CheckDefaultAllowed then
  begin
    Result := False;
  end else if not Value.ValueType.Equals(Signature.ReturnType) then
  begin
    MakeError(Format(STypeMismatch,
      [Signature.ReturnType.DisplayName, Value.ValueType.DisplayName]));
    Result := False;
  end else if not Value.IsConstant then
  begin
    MakeError(SConstExpressionRequired);
    Result := False;
  end else
  begin
    FDefaultValue := TSepiOrdType(Value.ValueType).ValueAsInteger(
      Value.ConstValuePtr^);
    Result := True;
  end;
end;

{*
  Sp�cifie qu'il n'y a pas de valeur par d�faut
  @param Node   Noeud utilis� pour produire les erreurs
  @return True en cas de succ�s, False sinon
*}
function TSepiPropertyBuilder.SetNoDefault(Node: TSepiParseTreeNode): Boolean;
begin
  CurrentNode := Node;

  Result := CheckDefaultAllowed;

  if Result then
    FDefaultValue := NoDefaultValue;
end;

{*
  Sp�cifie que c'est la propri�t� par d�faut
  @param Node   Noeud utilis� pour produire les erreurs
  @return True en cas de succ�s, False sinon
*}
function TSepiPropertyBuilder.SetIsDefault(Node: TSepiParseTreeNode): Boolean;
begin
  CurrentNode := Node;

  if IsDefault then
  begin
    MakeError(SDuplicateDefaultDirective);
    Result := False;
  end else if Signature.ParamCount = 0 then
  begin
    MakeError(SArrayPropertyRequired);
    Result := False;
  end else if (OwnerClass <> nil) and
    (OwnerClass.DefaultProperty <> nil) and
    (OwnerClass.DefaultProperty.Owner = Owner) then
  begin
    MakeError(SDuplicateDefaultProperty);
    Result := False;
  end else
  begin
    FIsDefault := True;
    Result := True;
  end;
end;

{*
  [@inheritDoc]
*}
procedure TSepiPropertyBuilder.Build;
begin
  TSepiProperty.Create(Owner, Name, Signature, ReadAccess, WriteAccess,
    Index, DefaultValue, Storage, IsDefault);
end;

end.

