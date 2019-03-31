Attribute VB_Name = "modConvert"
Option Explicit

Const WithMark = "_WithVar_"

Dim WithLevel As Long, MaxWithLevel As Long
Dim WithVars As String, WithTypes As String, WithAssign As String
Dim FormName As String

Dim CurrSub As String

Public Function ConvertProject(ByVal vbpFile As String)
  Prg 0, 1, "Preparing..."
  ScanRefs
  CreateProjectFile vbpFile
  CreateProjectSupportFiles
  ConvertFileList FilePath(vbpFile), VBPModules(vbpFile) & vbCrLf & VBPClasses(vbpFile) & vbCrLf & VBPForms(vbpFile) '& vbCrLf & VBPUserControls(vbpFile)
  MsgBox "Complete."
End Function

Public Function ConvertFileList(ByVal Path As String, ByVal List As String, Optional ByVal Sep As String = vbCrLf) As Boolean
  Dim L, V As Long, N As Long
  V = StrCnt(List, Sep) + 1
  Prg 0, V, N & "/" & V & "..."
  For Each L In Split(List, Sep)
    N = N + 1
    If L = "" Then GoTo NextItem
    
    If L = "modFunctionList.bas" Then GoTo NextItem
    
    ConvertFile Path & L
    
NextItem:
    Prg N, , N & "/" & V & ": " & L
    DoEvents
  Next
  Prg
End Function

Public Function ConvertFile(ByVal someFile As String, Optional ByVal UIOnly As Boolean = False) As Boolean
  If Not IsInStr(someFile, "\") Then someFile = vbpPath & someFile
  Select Case LCase(FileExt(someFile))
    Case ".bas": ConvertFile = ConvertModule(someFile)
    Case ".cls": ConvertFile = ConvertClass(someFile)
    Case ".frm": FormName = FileBaseName(someFile): ConvertFile = ConvertForm(someFile, UIOnly)
'      Case ".ctl": ConvertModule  someFile
    Case Else: MsgBox "UNKNOWN VB TYPE: " & someFile
  End Select
  FormName = ""
End Function

Public Function ConvertForm(ByVal frmFile As String, Optional ByVal UIOnly As Boolean = False) As Boolean
  Dim S As String, J As Long, Preamble As String, Code As String, Globals As String, Functions As String
  Dim X As String, FName As String
  Dim F As String
  If Not FileExists(frmFile) Then
    MsgBox "File not found in ConvertForm: " & frmFile
    Exit Function
  End If
  S = ReadEntireFile(frmFile)
  FName = ModuleName(S)
  
  J = CodeSectionLoc(S)
  Preamble = Left(S, J - 1)
  Code = Mid(S, J)
  
  X = ConvertFormUi(Preamble, Code)
  F = FName & ".xaml"
  WriteOut F, X, frmFile
  If UIOnly Then Exit Function
  
  J = CodeSectionGlobalEndLoc(Code)
  Globals = ConvertGlobals(Left(Code, J))
  InitLocalFuncs FormControls(FName, Preamble)
  Functions = ConvertCodeSegment(Mid(Code, J))
  
  X = ""
  X = X & UsingEverything(FName) & vbCrLf
  X = X & vbCrLf
  X = X & "namespace " & AssemblyName & ".Forms" & vbCrLf
  X = X & "{" & vbCrLf
  X = X & "public partial class " & FName & " : Window {" & vbCrLf
  X = X & "  private static " & FName & " _instance;" & vbCrLf
  X = X & "  public static " & FName & " instance { set { _instance = null; } get { return _instance ?? (_instance = new " & FName & "()); }}"
  X = X & "  public " & FName & "() { InitializeComponent(); }" & vbCrLf
  X = X & vbCrLf
  X = X & vbCrLf
  X = X & Globals & vbCrLf & vbCrLf & Functions
  X = X & vbCrLf & "}"
  X = X & vbCrLf & "}"
  
  X = deWS(X)
  
  F = FName & ".xaml.cs"
  WriteOut F, X, frmFile
End Function


Public Function ConvertModule(ByVal basFile As String)
  Dim S As String, J As Long, Code As String, Globals As String, Functions As String
  Dim F As String, X As String, FName As String
  If Not FileExists(basFile) Then
    MsgBox "File not found in ConvertModule: " & basFile
    Exit Function
  End If
  S = ReadEntireFile(basFile)
  FName = ModuleName(S)
  Code = Mid(S, CodeSectionLoc(S))
  
  J = CodeSectionGlobalEndLoc(Code)
  Globals = ConvertGlobals(Left(Code, J - 1), True)
  Functions = ConvertCodeSegment(Mid(Code, J), True)
  
  X = ""
  X = X & UsingEverything(FName) & vbCrLf
  X = X & vbCrLf
  X = X & "static class " & FName & " {" & vbCrLf
  X = X & nlTrim(Globals & vbCrLf & vbCrLf & Functions)
  X = X & vbCrLf & "}"
  
  X = deWS(X)
  
  F = FName & ".cs"
  WriteOut F, X, basFile
End Function



Public Function ConvertClass(ByVal clsFile As String)
  Dim S As String, J As Long, Code As String, Globals As String, Functions As String
  Dim F As String, X As String, FName As String
  Dim cName As String
  If Not FileExists(clsFile) Then
    MsgBox "File not found in ConvertModule: " & clsFile
    Exit Function
  End If
  S = ReadEntireFile(clsFile)
  FName = ModuleName(S)
  Code = Mid(S, CodeSectionLoc(S))
  
  J = CodeSectionGlobalEndLoc(Code)
  Globals = ConvertGlobals(Left(Code, J - 1))
  Functions = ConvertCodeSegment(Mid(Code, J))
  
  X = ""
  X = X & UsingEverything(FName) & vbCrLf
  X = X & vbCrLf
  X = X & "public class " & FName & " {" & vbCrLf
  X = X & Globals & vbCrLf & vbCrLf & Functions
  X = X & vbCrLf & "}"
  
  X = deWS(X)
  
  F = FName & ".cs"
  WriteOut F, X, clsFile
End Function

Public Function GetMultiLineSpace(ByVal Prv As String, ByVal Nxt As String) As String
  Dim pC As String, nC As String
  GetMultiLineSpace = " "
  pC = Right(Prv, 1)
  nC = Left(Nxt, 1)
  If nC = "(" Then GetMultiLineSpace = ""
End Function

Public Function SanitizeCode(ByVal Str As String)
  Const NamedParamSrc = ":="
  Const NamedParamTok = "###NAMED-PARAMETER###"
  Dim Sp, L
  Dim F As String
  Dim R As String, N As String
  Dim Building As String
  Dim FinishSplitIf As Boolean
  
  R = "": N = vbCrLf
  Sp = Split(Str, vbCrLf)
  Building = ""
  

  For Each L In Sp
'If IsInStr(L, "Set objSourceArNo = New_CDbTypeAhead") Then Stop
    If Right(L, 1) = "_" Then
      Dim C As String
      C = Trim(Left(L, Len(L) - 1))
      Building = Building & GetMultiLineSpace(Building, C) & C
      GoTo NextLine
    End If
    If Building <> "" Then
      L = Building & GetMultiLineSpace(Building, Trim(L)) & Trim(L)
      Building = ""
    End If
    
'    If IsInStr(L, "'") Then Stop
    L = DeComment(L)
    L = DeString(L)
'If IsInStr(L, "CustRec <> 0") Then Stop
    
    FinishSplitIf = False
    If tLeft(L, 3) = "If " And Right(RTrim(L), 5) <> " Then" Then
      FinishSplitIf = True
      F = nextBy(L, " Then ") & " Then"
      R = R & N & F
      L = Mid(L, Len(F) + 2)
      If nextBy(L, " Else ", 2) <> "" Then
        R = R & SanitizeCode(nextBy(L, " Else ", 1))
        R = R & N & "Else"
        L = nextBy(L, "Else ", 2)
      End If
    End If
    
    If nextBy(L, ":") <> L Then
      If RegExTest(Trim(L), "^[a-zA-Z_][a-zA-Z_0-9]*:$") Then ' Goto Label
        R = R & N & ReComment(L)
      Else
        Do
          L = Replace(L, NamedParamSrc, NamedParamTok)
          F = nextBy(L, ":")
          F = Replace(F, NamedParamTok, NamedParamSrc)
          R = R & N & ReComment(F, True)
          L = Replace(L, NamedParamTok, NamedParamSrc)
          If F = L Then Exit Do
          L = Trim(Mid(L, Len(F) + 2))
          R = R & SanitizeCode(L)

        Loop While False
      End If
    Else
      R = R & N & ReComment(L, True)
    End If
    
    If FinishSplitIf Then R = R & N & "End If"
NextLine:
  Next
  
  SanitizeCode = R
End Function

Public Function ConvertCodeSegment(ByVal S As String, Optional ByVal asModule As Boolean = False) As String
  Dim P As String, N As Long
  Dim F As String, T As Long, E As Long, K As String, X As Long
  Dim Pre As String, Body As String
  Dim R As String
  
  ClearProperties
  
  InitDeString
'WriteFile "C:\Users\benja\Desktop\code.txt", S, True
  S = SanitizeCode(S)
'WriteFile "C:\Users\benja\Desktop\sani.txt", S, True
  Do
    P = "(Public |Private |)(Function |Sub |Property Get |Property Let |Property Set )" & patToken & "[ ]*\("
    N = -1
    Do
      N = N + 1
      F = RegExNMatch(S, P, N)
      T = RegExNPos(S, P, N)
    Loop While Not IsInCode(S, T) And F <> ""
    If F = "" Then Exit Do
    
    If IsInStr(F, " Function ") Then K = "End Function"
    If IsInStr(F, " Sub ") Then K = "End Sub"
    If IsInStr(F, " Property ") Then K = "End Property"
    N = -1
    Do
      N = N + 1
      E = RegExNPos(Mid(S, T), K, N) + Len(K) + T
    Loop While Not IsInCode(S, E) And E <> 0
    
    If T > 1 Then Pre = nlTrim(Left(S, T - 1)) Else Pre = ""
    Do Until Mid(S, E, 1) = vbCr Or Mid(S, E, 1) = vbLf Or Mid(S, E, 1) = ""
      E = E + 1
    Loop
    Body = nlTrim(Mid(S, T, E - T))
      
    S = nlTrim(Mid(S, E + 1))
    
    R = R & CommentBlock(Pre) & ConvertSub(Body, asModule) & vbCrLf
  Loop While True
  
  R = ReadOutProperties(asModule) & vbCrLf2 & R
  
  R = ReString(R, True)
  
  ConvertCodeSegment = R
End Function

Public Function CommentBlock(ByVal Str As String) As String
  Dim S As String
  If nlTrim(Str) = "" Then Exit Function
  S = ""
  S = S & "/*" & vbCrLf
  S = S & Replace(Str, "*/", "* /") & vbCrLf
  S = S & "*/" & vbCrLf
  CommentBlock = S
End Function

Public Function ConvertDeclare(ByVal S As String, ByVal Ind As Long, Optional ByVal isGlobal As Boolean, Optional ByVal asModule As Boolean = False) As String
  Dim Sp, L, SS As String
  Dim asPrivate As Boolean
  Dim pName As String, pType As String, pWithEvents As Boolean
  Dim Res As String
  Dim ArraySpec As String, isArr As Boolean, aMax As String, aMin As String, aTodo As String
  Res = ""
  
  SS = S
  
  If tLeft(S, 7) = "Public " Then S = tMid(S, 8)
  If tLeft(S, 4) = "Dim " Then S = Mid(Trim(S), 5): asPrivate = True
  If tLeft(S, 8) = "Private " Then S = tMid(S, 9): asPrivate = True
  
  Sp = Split(S, ",")
  For Each L In Sp
    L = Trim(L)
    If LMatch(L, "WithEvents ") Then L = Trim(tMid(L, 12)): Res = Res & "// TODO: WithEvents not supported on " & RegExNMatch(L, patToken) & vbCrLf
    pName = RegExNMatch(L, patToken)
    L = Trim(tMid(L, Len(pName) + 1))
    If isGlobal Then Res = Res & IIf(asPrivate, "private ", "public ")
    If asModule Then Res = Res & "static "
    If tLeft(L, 1) = "(" Then
      isArr = True
      ArraySpec = nextBy(Mid(L, 2), ")")
      If ArraySpec = "" Then
        aMin = -1
        aMax = -1
        L = Trim(tMid(L, 3))
      Else
        L = Trim(tMid(L, Len(ArraySpec) + 3))
        aMin = 0
        aMax = SplitWord(ArraySpec)
        ArraySpec = Trim(tMid(ArraySpec, Len(aMax) + 1))
        If tLeft(ArraySpec, 3) = "To " Then
          aMin = aMax
          aMax = tMid(ArraySpec, 4)
        End If
      End If
    End If
    If SplitWord(L, 1) = "As" Then
      pType = SplitWord(L, 2)
    Else
      pType = "Variant"
    End If
    
    If Not isArr Then
      Res = Res & sSpace(Ind) & ConvertDataType(pType) & " " & pName
      Res = Res & " = " & ConvertDefaultDefault(pType)
      Res = Res & ";" & vbCrLf
    Else
      aTodo = IIf(aMin = 0, "", " // TODO - Specified Minimum Array Boundary Not Supported: " & SS)
      If Not IsNumeric(aMax) Then
        Res = Res & sSpace(Ind) & "List<" & ConvertDataType(pType) & "> " & pName & " = new List<" & ConvertDataType(pType) & "> (new " & ConvertDataType(pType) & "[(" & aMax & " + 1)]);  // TODO: Confirm Array Size By Token" & aTodo & vbCrLf
      ElseIf Val(aMax) = -1 Then
        Res = Res & sSpace(Ind) & "List<" & ConvertDataType(pType) & "> " & pName & " = new List<" & ConvertDataType(pType) & "> {};" & aTodo & vbCrLf
      Else
        Res = Res & sSpace(Ind) & "List<" & ConvertDataType(pType) & "> " & pName & " = new List<" & ConvertDataType(pType) & "> (new " & ConvertDataType(pType) & "[" & (Val(aMax) + 1) & "]);" & aTodo & vbCrLf
      End If
    End If
    
    SubParamDecl pName, pType, IIf(isArr, aMax, ""), False, False
  Next
  
  ConvertDeclare = Res
End Function

Public Function ConvertAPIDef(ByVal S As String) As String
'Private Declare Function CreateFile Lib "kernel32" Alias "CreateFileA" (ByVal lpFileName As String, ByVal dwDesiredAccess As Long, ByVal dwShareMode As Long, ByVal lpSecurityAttributes As Long, ByVal dwCreationDisposition As Long, ByVal dwFlagsAndAttributes As Long, ByVal hTemplateFile As Long) As Long
'[DllImport("User32.dll")]
'public static extern int MessageBox(int h, string m, string c, int type);
  Dim isPrivate As Boolean, isSub As Boolean
  Dim aName As String
  Dim aLib As String
  Dim aAlias As String
  Dim aArgs As String
  Dim aReturn As String
  Dim tArg As String, has As Boolean
  If tLeft(S, 8) = "Private " Then S = tMid(S, 9): isPrivate = True
  If tLeft(S, 7) = "Public " Then S = tMid(S, 8)
  If tLeft(S, 8) = "Declare " Then S = tMid(S, 9)
  If tLeft(S, 4) = "Sub " Then S = tMid(S, 5): isSub = True
  If tLeft(S, 9) = "Function " Then S = tMid(S, 10)
  aName = RegExNMatch(S, patToken)
  S = Trim(tMid(S, Len(aName) + 1))
  If tLeft(S, 4) = "Lib " Then
    S = Trim(tMid(S, 5))
    aLib = SplitWord(S, 1)
    S = Trim(tMid(S, Len(aLib) + 1))
    If Left(aLib, 1) = """" Then aLib = Mid(aLib, 2)
    If Right(aLib, 1) = """" Then aLib = Left(aLib, Len(aLib) - 1)
    If LCase(Right(aLib, 4)) <> ".dll" Then aLib = aLib & ".dll"
    aLib = LCase(aLib)
  End If
  If tLeft(S, 6) = "Alias " Then
    S = Trim(tMid(S, 7))
    aAlias = SplitWord(S, 1)
    S = Trim(tMid(S, Len(aAlias) + 1))
    If Left(aAlias, 1) = """" Then aAlias = Mid(aAlias, 2)
    If Right(aAlias, 1) = """" Then aAlias = Left(aAlias, Len(aAlias) - 1)
    End If
  If tLeft(S, 1) = "(" Then S = tMid(S, 2)
  aArgs = nextBy(S, ")")
  S = Trim(tMid(S, Len(aArgs) + 2))
  If tLeft(S, 3) = "As " Then
    S = Trim(tMid(S, 4))
    aReturn = SplitWord(S, 1)
    S = Trim(tMid(S, Len(aReturn) + 1))
  Else
    aReturn = "Variant"
  End If
  
  S = ""
  S = S & "[DllImport(""" & aLib & """" & IIf(aAlias = "", "", ", EntryPoint = """ & aAlias & """") & ")] "
  S = S & IIf(isPrivate, "private ", "public ")
  S = S & "static extern "
  S = S & IIf(isSub, "void ", ConvertDataType(aReturn)) & " "
  S = S & aName
  S = S & "("
  Do
    If aArgs = "" Then Exit Do
    tArg = Trim(nextBy(aArgs, ","))
    aArgs = tMid(aArgs, Len(tArg) + 2)
    S = S & IIf(has, ", ", "") & ConvertParameter(tArg)
    has = True
  Loop While True
  S = S & ");"
  
  
  ConvertAPIDef = S
End Function

Public Function ConvertConstant(ByVal S As String, Optional ByVal isGlobal As Boolean = True) As String
  Dim cName As String, cType As String, cVal As String, isPrivate As Boolean
  If tLeft(S, 7) = "Public " Then S = Mid(Trim(S), 8)
  If tLeft(S, 7) = "Global " Then S = Mid(Trim(S), 8)
  If tLeft(S, 8) = "Private " Then S = Mid(Trim(S), 9): isPrivate = True
  If tLeft(S, 6) = "Const " Then S = Mid(Trim(S), 7)
  cName = SplitWord(S, 1)
  S = Trim(Mid(Trim(S), Len(cName) + 1))
  If tLeft(S, 3) = "As " Then
    S = Trim(Mid(Trim(S), 3))
    cType = SplitWord(S, 1)
    S = Trim(tMid(S, Len(cType) + 1))
  Else
    cType = "Variant"
  End If
  
  If Left(S, 1) = "=" Then
    S = Trim(Mid(S, 2))
    cVal = ConvertValue(S)
  Else
    cVal = ConvertDefaultDefault(cType)
  End If
  
  If cType = "Date" Then
    ConvertConstant = IIf(isGlobal, IIf(isPrivate, "private ", "public "), "") & "static readonly " & ConvertDataType(cType) & " " & cName & " = " & cVal & ";"
  Else
    ConvertConstant = IIf(isGlobal, IIf(isPrivate, "private ", "public "), "") & "const " & ConvertDataType(cType) & " " & cName & " = " & cVal & ";"
  End If
End Function


Public Function ConvertEvent(ByVal S As String) As String
  Dim cName As String, cArgs As String, tArgs As String, isPrivate As Boolean
  Dim R As String, N As String, M As String
  Dim I As Long, J As Long
  Dim A As String
  If tLeft(S, 7) = "Public " Then S = Mid(Trim(S), 8)
  If tLeft(S, 8) = "Private " Then S = Mid(Trim(S), 9): isPrivate = True
  If tLeft(S, 6) = "Event " Then S = Mid(Trim(S), 7)
  cName = RegExNMatch(S, patToken)
  cArgs = Trim(Mid(Trim(S), Len(cName) + 1))
  If Left(cArgs, 1) = "(" Then cArgs = Mid(cArgs, 2)
  If Right(cArgs, 1) = ")" Then cArgs = Left(cArgs, Len(cArgs) - 1)
  
  N = 0
  Do
    N = N + 1
    A = nextBy(cArgs, ",", N)
    If A = "" Then Exit Do
    tArgs = tArgs & IIf(N = 1, "", ", ")
    tArgs = tArgs & ConvertParameter(A, True)
  Loop While True
  
  N = vbCrLf
  M = ""
  R = ""
  R = R & M & "public delegate void " & cName & "Handler(" & tArgs & ");"
  R = R & N & "public event " & cName & "Handler event" & cName & ";"
  
  ConvertEvent = R
End Function


Public Function ConvertEnum(ByVal S As String)
  Dim isPrivate As Boolean, EName As String
  Dim Res As String, has As Boolean
  If tLeft(S, 7) = "Public " Then S = tMid(S, 8)
  If tLeft(S, 8) = "Private " Then S = tMid(S, 9): isPrivate = True
  If tLeft(S, 5) = "Enum " Then S = tMid(S, 6)
  EName = RegExNMatch(S, patToken, 0)
  S = nlTrim(tMid(S, Len(EName) + 1))
  
  Res = "public enum " & EName & " {"
  
  Do While tLeft(S, 8) <> "End Enum" And S <> ""
    EName = RegExNMatch(S, patToken, 0)
    Res = Res & IIf(has, ",", "") & vbCrLf & sSpace(SpIndent) & EName
    has = True

    S = nlTrim(tMid(S, Len(EName) + 1))
    If tLeft(S, 1) = "=" Then
      S = nlTrim(Mid(S, 3))
      If Left(S, 1) = "&" Then
        EName = ConvertElement(RegExNMatch(S, "&H[0-9A-F]+"))
      Else
        EName = RegExNMatch(S, "[0-9]*", 0)
      End If
      Res = Res & " = " & EName
      S = nlTrim(tMid(S, Len(EName) + 1))
    End If
  Loop
  Res = Res & vbCrLf & "}"
  
  ConvertEnum = Res
End Function

Public Function ConvertType(ByVal S As String)
  Dim isPrivate As Boolean, EName As String, eArr As String, eType As String
  Dim Res As String
  Dim N As String
  If tLeft(S, 7) = "Public " Then S = tMid(S, 8)
  If tLeft(S, 8) = "Private " Then S = tMid(S, 9): isPrivate = True
  If tLeft(S, 5) = "Type " Then S = tMid(S, 6)
  EName = RegExNMatch(S, patToken, 0)
  S = nlTrim(tMid(S, Len(EName) + 1))
'If IsInStr(eName, "OSVERSIONINFO") Then Stop
  
  Res = IIf(isPrivate, "private ", "public ") & "class " & EName & " {"
  
  Do While tLeft(S, 8) <> "End Type" And S <> ""
    EName = RegExNMatch(S, patToken, 0)
    S = nlTrim(tMid(S, Len(EName) + 1))
    eArr = ""
    If LMatch(S, "(") Then
      N = nextBy(Mid(S, 2), ")")
      S = nlTrim(Mid(S, Len(N) + 3))
      N = ConvertValue(N)
      eArr = "[" & N & "]"
    End If
    
    If tLeft(S, 3) = "As " Then
      S = nlTrim(Mid(S, 4))
      eType = RegExNMatch(S, patToken, 0)
      S = nlTrim(tMid(S, Len(eType) + 1))
    Else
      eType = "Variant"
    End If
    Res = Res & vbCrLf & " public " & ConvertDataType(eType) & IIf(eArr = "", "", "[]") & " " & EName
    If eArr = "" Then
      Res = Res & " = " & ConvertDefaultDefault(eType)
    Else
      Res = Res & " = new " & ConvertDataType(eType) & eArr
    End If
    Res = Res & ";"
    If tLMatch(S, "* ") Then
      S = Mid(LTrim(S), 3)
      N = RegExNMatch(S, "[0-9]+", 0)
      S = nlTrim(Mid(LTrim(S), Len(N) + 1))
      Res = Res & " //TODO: Fixed Length Strings Not Supported: * " & N
    End If

  Loop
  Res = Res & vbCrLf & "}"
  
  ConvertType = Res
End Function

Public Function ConvertParameter(ByVal S As String, Optional ByVal NeverUnused As Boolean = False) As String
  Dim isOptional As Boolean
  Dim isByRef As Boolean, asOut As Boolean
  Dim Res As String
  Dim pName As String, pType As String, pDef As String
  Dim tName As String
  
  S = Trim(S)
  If tLeft(S, 9) = "Optional " Then isOptional = True: S = Mid(S, 10)
  isByRef = True
  If tLeft(S, 6) = "ByVal " Then isByRef = False: S = Mid(S, 7)
  If tLeft(S, 6) = "ByRef " Then isByRef = True: S = Mid(S, 7)
  pName = SplitWord(S, 1)
  If isByRef And SubParam(pName).AssignedBeforeUsed Then asOut = True
  S = Trim(Mid(S, Len(pName) + 1))
  If tLeft(S, 2) = "As" Then
    S = tMid(S, 4)
    pType = SplitWord(S, 1, "=")
    S = Trim(Mid(S, Len(pType) + 1))
  Else
    pType = "Variant"
  End If
  If Left(S, 1) = "=" Then
    pDef = ConvertValue(Trim(Mid(Trim(S), 2)))
    S = ""
  Else
    pDef = ConvertDefaultDefault(pType)
  End If
  
  Res = ""
  If isByRef Then Res = Res & IIf(asOut, "out ", "ref ")
  Res = Res & ConvertDataType(pType) & " "
  tName = pName
  If Not NeverUnused Then
    If Not SubParam(pName).Used And Not (SubParam(pName).Param And SubParam(pName).Assigned) Then
      tName = tName & "_UNUSED"
    End If
  End If
  Res = Res & tName
  If isOptional And Not isByRef Then
    Res = Res & "= " & pDef
  End If
  
  SubParamDecl pName, pType, False, True, False
  ConvertParameter = Trim(Res)
End Function

Public Function ConvertPrototype(ByVal S As String, Optional ByRef returnVariable As String, Optional ByVal asModule As Boolean = False, Optional ByRef asName As String) As String
  Const retToken = "#RET#"
  Dim Res As String
  Dim FName As String, fArgs As String, retType As String, T As String
  Dim tArg As String
  Dim isSub As Boolean
  Dim hArgs As Boolean
  
  Res = ""
  returnVariable = ""
  isSub = False
  If tLeft(S, 7) = "Public " Then Res = Res & "public ": S = Mid(S, 8)
  If tLeft(S, 8) = "Private " Then Res = Res & "private ": S = Mid(S, 9)
  If asModule Then Res = Res & "static "
  If tLeft(S, 4) = "Sub " Then Res = Res & "void ": S = Mid(S, 5): isSub = True
  If tLeft(S, 9) = "Function " Then Res = Res & retToken & " ": S = Mid(S, 10)
  
  FName = Trim(SplitWord(Trim(S), 1, "("))
  asName = FName
  S = Trim(tMid(S, Len(FName) + 2))
  If Left(S, 1) = "(" Then S = Trim(tMid(S, 2))
  fArgs = Trim(nextBy(S, ")"))
  S = Mid(S, Len(fArgs) + 2)
  If Left(S, 1) = ")" Then S = Trim(tMid(S, 2))
  
  If Not isSub Then
    If tLeft(S, 2) = "As" Then
      retType = Trim(Mid(Trim(S), 3))
    Else
      retType = "Variant"
    End If
    Res = Replace(Res, retToken, ConvertDataType(retType))
  End If
  
  Res = Res & FName
  Res = Res & "("
  hArgs = False
  Do
    If Trim(fArgs) = "" Then Exit Do
    tArg = nextBy(fArgs, ",")
    fArgs = LTrim(Mid(fArgs, Len(tArg) + 2))
    
    Res = Res & IIf(hArgs, ", ", "") & ConvertParameter(tArg)
    hArgs = True
  Loop Until Len(fArgs) = 0
  
  Res = Res & ") {"
  If retType <> "" Then
    returnVariable = FName
    Res = Res & vbCrLf & sSpace(SpIndent) & ConvertDataType(retType) & " " & returnVariable & " = " & ConvertDefaultDefault(retType) & ";"
    SubParamDecl returnVariable, retType, False, False, True
  End If
  
  ConvertPrototype = Trim(Res)
End Function

Public Function ConvertCondition(ByVal S As String) As String
  ConvertCondition = "(" & S & ")"
End Function

Public Function ConvertElement(ByVal S As String) As String
'Debug.Print "ConvertElement: " & S
'If IsInStr(S, "frmSetup") Then Stop
  Dim FirstToken As String, FirstWord As String
  Dim T As String, Complete As Boolean
  S = Trim(S)
  If S = "" Then Exit Function
  
  If Left(Trim(S), 2) = "&H" Then
    ConvertElement = "0x" & Mid(Trim(S), 3)
    Exit Function
  End If
  
  If IsNumeric(Trim(S)) Then
    ConvertElement = Val(S)
    If IsInStr(S, ".") Then ConvertElement = ConvertElement & "m"
    Exit Function
  End If
  
  If RegExTest(S, "#[0-9]+/[0-9]+/[0-9]+#") Then
    ConvertElement = "DateValue(""" & Mid(S, 2, Len(S) - 2) & """)"
    Exit Function
  End If
 
'If IsInStr(S, "RS!") Then Stop
'If IsInStr(S, ".SetValueDisplay Row") Then Stop
'If IsInStr(S, "cmdSaleTotals.Move") Then Stop
'If IsInStr(S, "2830") Then Stop
'If IsInStr(S, "True") Then Stop
'If IsInStr(S, ":=") Then Stop
'If IsInStr(S, "GetRecordNotFound") Then Stop
'If IsInStr(S, "Nonretro_14day") Then Stop

  S = RegExReplace(S, patNotToken & patToken & "!" & patToken & patNotToken, "$1$2(""$3"")$4") ' RS!Field -> RS("Field")
  S = RegExReplace(S, "^" & patToken & "!" & patToken & patNotToken, "$1(""$2"")$3") ' RS!Field -> RS("Field")

  S = RegExReplace(S, "([^a-zA-Z0-9_.])NullDate([^a-zA-Z0-9_.])", "$1NullDate()$2")
  
  S = ConvertVb6Specific(S, Complete)
  If Complete Then ConvertElement = S: Exit Function
  
  If RegExTest(Trim(S), "^" & patToken & "$") Then
    If IsFuncRef(Trim(S)) And S <> CurrSub Then
      ConvertElement = Trim(S) & "()"
      Exit Function
    ElseIf IsEnumRef(Trim(S)) Then
      ConvertElement = EnumRefRepl(Trim(S))
      Exit Function
    End If
  End If
  
  If IsControlRef(Trim(S), FormName) Then
    S = FormControlRepl(S, FormName)
  End If
  
  If IsFormRef(Trim(S)) Then
    ConvertElement = FormRefRepl(Trim(S))
    Exit Function
  End If
  

  
  FirstToken = RegExNMatch(S, patTokenDot, 0)
  FirstWord = SplitWord(S, 1)
  If FirstWord = "Not" Then
    S = "!" & Mid(S, 5)
    FirstWord = SplitWord(Mid(S, 2))
  End If
  If S = FirstWord Then ConvertElement = S: GoTo ManageFunctions
  If S = FirstToken Then ConvertElement = S & "()": GoTo ManageFunctions
  
  If FirstToken = FirstWord And Not isOperator(SplitWord(S, 2)) Then ' Sub without parenthesis
    ConvertElement = FirstWord & "(" & SplitWord(S, 2, , , True) & ")"
  Else
    ConvertElement = S
  End If
  
ManageFunctions:
'If IsInStr(ConvertElement, "New_CDbTypeAhead") Then Stop
  If RegExTest(ConvertElement, "^[a-zA-Z0-9_.]+[ ]*\(.*\)$") Then
    ConvertElement = ConvertFunctionCall(ConvertElement)
  End If

DoReplacements:
  ConvertElement = Replace(ConvertElement, " & ", " + ")
  ConvertElement = Replace(ConvertElement, ":=", ": ")
  ConvertElement = Replace(ConvertElement, " = ", " == ")
  ConvertElement = Replace(ConvertElement, "<>", "!=")
  ConvertElement = Replace(ConvertElement, " Not ", " !")
  ConvertElement = Replace(ConvertElement, "(Not ", "(!")
  ConvertElement = Replace(ConvertElement, " Or ", " || ")
  ConvertElement = Replace(ConvertElement, " And ", " && ")
  ConvertElement = Replace(ConvertElement, " Mod ", " % ")
  ConvertElement = Replace(ConvertElement, "Err.", "Err().")
  ConvertElement = Replace(ConvertElement, "Debug.Print", "Console.WriteLn")
  
  ConvertElement = Replace(ConvertElement, "NullDate", "NullDate")
  Do While IsInStr(ConvertElement, ", ,")
    ConvertElement = Replace(ConvertElement, ", ,", ", _,")
  Loop
  ConvertElement = Replace(ConvertElement, "(,", "(_,")

'If IsInStr(ConvertElement, "&H") And Right(ConvertElement, 1) = "&" Then Stop
'If IsInStr(ConvertElement, "1/1/2001") Then Stop

  ConvertElement = RegExReplace(ConvertElement, "([0-9])#", "$1")
  
  If Left(ConvertElement, 2) = "&H" Then
    ConvertElement = "0x" & Mid(ConvertElement, 3)
    If Right(ConvertElement, 1) = "&" Then ConvertElement = Left(ConvertElement, Len(ConvertElement) - 1)
  End If
  
  If WithLevel > 0 Then
    T = Stack(WithVars, , True)
    ConvertElement = Trim(RegExReplace(ConvertElement, "([ (])(\.)" & patToken, "$1" & T & "$2$3"))
    If Left(ConvertElement, 1) = "." Then ConvertElement = T & ConvertElement
  End If
End Function

Public Function ConvertFunctionCall(ByVal fCall As String) As String
  Dim I As Long, N As Long, TB As String, TS As String, tName As String
  Dim TV As String
  Dim vP As Variable
'Debug.Print "ConvertFunctionCall: " & fCall

  TB = ""
  tName = RegExNMatch(fCall, "^[a-zA-Z0-9_.]*")
  TB = TB & tName

  TS = Mid(fCall, Len(tName) + 2)
  TS = Left(TS, Len(TS) - 1)
  
  vP = SubParam(tName)
  If ConvertDataType(vP.asType) = "Recordset" Then
    TB = TB & ".Fields["
    TB = TB & ConvertValue(TS)
    TB = TB & "].Value"
  ElseIf vP.asArray <> "" Then
    TB = TB & "["
    TB = TB & ConvertValue(TS)
    TB = TB & "]"
'    TB = Replace(TB, ", ", "][")
  Else
    N = nextByPCt(TS, ",")
    TB = TB & "("
    For I = 1 To N
      If I <> 1 Then TB = TB & ", "
      TV = nextByP(TS, ",", I)
      If IsFuncRef(tName) Then
        If Trim(TV) = "" Then
          TB = TB & ConvertElement(FuncRefArgDefault(tName, I))
        Else
          If FuncRefArgByRef(tName, I) Then TB = TB & "ref "
          TB = TB & ConvertValue(TV)
        End If
      Else
        TB = TB & ConvertValue(TV)
      End If
    Next
    TB = TB & ")"
  End If
  ConvertFunctionCall = TB
End Function


Public Function ConvertValue(ByVal S As String) As String
  Dim F As String, Op As String, OpN As String
  Dim O As String
  O = ""
  S = Trim(S)
  If S = "" Then Exit Function
  
'If IsInStr(S, "GetMaxFieldValue") Then Stop
'If IsInStr(S, "DBAccessGeneral") Then Stop
'If IsInStr(S, "tallable") Then Stop
'If Left(S, 3) = "RS(" Then Stop
'If Left(S, 6) = "DBName" Then Stop
'If Left(S, 6) = "fName" Then Stop

  SubParamUsedList TokenList(S)
  
  Do While True
    F = NextByOp(S, 1, Op)
    If F = "" Then Exit Do
    Select Case Trim(Op)
      Case "\":    OpN = "/"
      Case "=":    OpN = " == "
      Case "<>":   OpN = " != "
      Case "&":    OpN = " + "
      Case "Mod":  OpN = " % "
      Case "Is":   OpN = " == "
      Case "Like": OpN = " == "
      Case "And":  OpN = " && "
      Case "Or":   OpN = " || "
      Case Else:   OpN = Op
    End Select
    
    If Left(F, 1) = "(" And Right(F, 1) = ")" Then
      O = O & "(" & ConvertValue(Mid(F, 2, Len(F) - 2)) & ")" & OpN
    Else
      O = O & ConvertElement(F) & OpN
    End If
    
    If Op = "" Then Exit Do
    S = Mid(S, Len(F) + Len(Op) + 1)
    If S = "" Or Op = "" Then Exit Do
  Loop
  ConvertValue = O
End Function

Public Function ConvertGlobals(ByVal Str As String, Optional ByVal asModule As Boolean = False) As String
  Dim Res As String
  Dim S, L, O As String
  Dim Ind As Long
  Dim Building As String
  Dim inCase As Long
  Dim returnVariable As String
  Dim N As Long
  
  Res = ""
  Building = ""
  Str = Replace(Str, vbLf, "")
  S = Split(Str, vbCr)
  Ind = 0
  N = 0
'  Prg 0, UBound(S) - LBound(S) + 1, "Globals..."
  InitDeString
  For Each L In S
    L = DeComment(L)
    L = DeString(L)
    O = ""
    If Building <> "" Then
      Building = Building & vbCrLf & L
      If tLeft(L, 8) = "End Type" Then
        O = ConvertType(Building)
        Building = ""
      ElseIf tLeft(L, 8) = "End Enum" Then
        O = ConvertEnum(Building)
        Building = ""
      End If
    ElseIf L Like "Option *" Then
      O = "// " & L
    ElseIf RegExTest(L, "^(Public |Private |)Declare ") Then
      O = ConvertAPIDef(L)
    ElseIf RegExTest(L, "^(Global |Public |Private |)Const ") Then
      O = ConvertConstant(L, True)
    ElseIf RegExTest(L, "^(Public |Private |)Event ") Then
      O = ConvertEvent(L)
    ElseIf RegExTest(L, "^(Public |Private |)Enum ") Then
      Building = L
    ElseIf RegExTest(LTrim(L), "^(Public |Private |)Type ") Then
      Building = L
    ElseIf tLeft(L, 8) = "Private " Or tLeft(L, 7) = "Public " Or tLeft(L, 4) = "Dim " Then
      O = ConvertDeclare(L, 0, True, asModule)
    End If
      
    O = ReComment(O)
    Res = Res & ReComment(O) & IIf(O = "" Or Right(O, 2) = vbCrLf, "", vbCrLf)
    N = N + 1
'    Prg N
'    If N Mod 10000 = 0 Then Stop
  Next
'  Prg

  Res = ReString(Res, True)
  ConvertGlobals = Res
End Function

Public Function ConvertCodeLine(ByVal S As String) As String
  Dim T As Long, A As String, B As String
  Dim P As String, V As Variable
  Dim FirstWord As String, Rest As String
  Dim N As Long

'If IsInStr(S, "dbClose") Then Stop
'If IsInStr(S, "Nothing") Then Stop
'If IsInStr(S, "Close ") Then Stop
'If IsInStr(S, "& functionType & fieldInfo &") Then Stop
'If IsInStr(S, " & vbCrLf2 & Res)") Then Stop
'If IsInStr(S, "Res = CompareSI(SI1, SI2)") Then Stop

  If Trim(S) = "" Then ConvertCodeLine = "": Exit Function
  S = ConvertVb6Syntax(S)
  
  If RegExTest(Trim(S), "^[a-zA-Z0-9_.()]+ \= ") Or RegExTest(Trim(S), "^Set [a-zA-Z0-9_.()]+ \= ") Then
    T = InStr(S, "=")
    A = Trim(Left(S, T - 1))
    If tLeft(A, 4) = "Set " Then A = Trim(Mid(A, 5))
    SubParamAssign RegExNMatch(A, patToken)
    If RegExTest(A, "^" & patToken & "\(""[^""]+""\)") Then
      P = RegExNMatch(A, "^" & patToken)
      V = SubParam(P)
      If V.Name = P Then
        SubParamAssign P
        Select Case V.asType
          Case "Recordset", "ADODB.Recordset"
            ConvertCodeLine = RegExReplace(A, "^" & patToken & "(\("")([^""]+)(""\))", "$1.Fields[""$3""].Value")
          Case Else
            If Left(A, 1) = "." Then A = Stack(WithVars, , True) & A
            ConvertCodeLine = A
      End Select
      End If
    Else
      If Left(A, 1) = "." Then A = Stack(WithVars, , True) & A
      ConvertCodeLine = A
    End If
    
    ConvertCodeLine = ConvertValue(ConvertCodeLine) & " = "

    B = ConvertValue(Trim(Mid(S, T + 1)))
    ConvertCodeLine = ConvertCodeLine & B
  Else
'Debug.Print S
    FirstWord = SplitWord(Trim(S))
    Rest = SplitWord(Trim(S), 2, , , True)
    If Rest = "" Then
      ConvertCodeLine = S & IIf(Right(S, 1) <> ")", "()", "")
    ElseIf FirstWord = "RaiseEvent" Then
      ConvertCodeLine = ConvertValue(S)
    ElseIf StrQCnt(FirstWord, "(") = 0 Then
      ConvertCodeLine = ""
      ConvertCodeLine = ConvertCodeLine & FirstWord & "("
      N = 0
      Do
        N = N + 1
        B = nextByP(Rest, ", ", N)
        If B = "" Then Exit Do
        ConvertCodeLine = ConvertCodeLine & IIf(N = 1, "", ", ") & ConvertValue(B)
      Loop While True
      ConvertCodeLine = ConvertCodeLine & ")"
    Else
      ConvertCodeLine = ConvertValue(S)
    End If
    If WithLevel > 0 And Left(Trim(ConvertCodeLine), 1) = "." Then ConvertCodeLine = Stack(WithVars, , True) & Trim(ConvertCodeLine)
  End If
  
If IsInStr(ConvertCodeLine, ",,,,,,,") Then Stop
  ConvertCodeLine = ConvertCodeLine & ";"
'Debug.Print ConvertCodeLine
End Function



Public Function ConvertSub(ByVal Str As String, Optional ByVal asModule As Boolean = False, Optional ByVal ScanFirst As VbTriState = vbUseDefault)
  Dim oStr As String
  Dim Res As String
  Dim S, L, O As String, T As String, U As String, V As String
  Dim CM As Long, cN As Long
  Dim K As Long
  Dim Ind As Long
  Dim inCase As Long
  Dim returnVariable As String
  
  Select Case ScanFirst
    Case vbUseDefault:  oStr = Str
                        ConvertSub oStr, asModule, vbTrue
                        ConvertSub = ConvertSub(oStr, asModule, vbFalse)
                        Exit Function
    Case vbTrue:        SubBegin
    Case vbFalse:       SubBegin True
  End Select
  

  
  Res = ""
  Str = Replace(Str, vbLf, "")
  S = Split(Str, vbCr)
  Ind = 0
    
'If IsInStr(Str, " WinCDSDataPath(") Then Stop
'If IsInStr(Str, " RunShellExecute(") Then Stop
'If IsInStr(Str, " ValidateSI(") Then Stop
  For Each L In S
'If IsInStr(L, "MsgBox") Then Stop
    L = DeComment(L)
    L = DeString(L)
    O = ""

'If IsInStr(L, "1/1/2001") Then Stop
'If ScanFirst = vbFalse Then Stop
'If IsInStr(L, "Public Function GetFileAutonumber") Then Stop

    If LMatch(L, "Sub ") Or LMatch(L, "Private Sub ") Or LMatch(L, "Public Sub ") Or _
       LMatch(L, "Function ") Or LMatch(L, "Private Function ") Or LMatch(L, "Public Function ") Then
      Dim nK As Long
      If LMatch(L, "Function ") Then CurrSub = nextBy(L, "(", 2)
      O = sSpace(Ind) & ConvertPrototype(L, returnVariable, asModule, CurrSub)
      Ind = Ind + SpIndent
    ElseIf L Like "*Property *" Then
      AddProperty Str
      Exit Function    ' repacked later...  not added here.
    ElseIf tLMatch(L, "End Sub") Or tLMatch(L, "End Function") Then
      If returnVariable <> "" Then
        O = O & sSpace(Ind) & "return " & returnVariable & ";" & vbCrLf
      End If
      Ind = Ind - SpIndent
      O = O & sSpace(Ind) & "}"
    ElseIf tLMatch(L, "Exit Function") Or tLMatch(L, "Exit Sub") Then
      If returnVariable <> "" Then
        O = O & sSpace(Ind) & "return " & returnVariable & ";" & vbCrLf
      Else
        O = O & "return;" & vbCrLf
      End If
    ElseIf RegExTest(Trim(L), "^[a-zA-Z_][a-zA-Z_0-9]*:$") Then ' Goto Label
      O = O & L
    ElseIf tLeft(L, 3) = "Dim" Then
      O = ConvertDeclare(L, Ind)
    ElseIf tLeft(L, 5) = "Const" Then
      O = sSpace(Ind) & ConvertConstant(L, False)
    ElseIf tLeft(L, 3) = "If " Then  ' Code sanitization prevents all single-line ifs.
'If IsInStr(L, "Development") Then Stop
      T = Mid(Trim(L), 4, Len(Trim(L)) - 8)
      O = sSpace(Ind) & "if (" & ConvertValue(T) & ") {"
      Ind = Ind + SpIndent
    ElseIf tLeft(L, 7) = "ElseIf " Then
      T = tMid(L, 8)
      If Right(Trim(L), 5) = " Then" Then T = Left(T, Len(T) - 5)
      O = sSpace(Ind - SpIndent) & "} else if (" & ConvertValue(T) & ") {"
    ElseIf tLeft(L, 5) = "Else" Then
      O = sSpace(Ind - SpIndent) & "} else {"
    ElseIf tLeft(L, 6) = "End If" Then
      Ind = Ind - SpIndent
      O = sSpace(Ind) & "}"
    ElseIf tLeft(L, 12) = "Select Case " Then
      O = O & sSpace(Ind) & "switch(" & ConvertValue(tMid(L, 13)) & ") {"
      Ind = Ind + SpIndent
    ElseIf tLeft(L, 10) = "End Select" Then
      If inCase > 0 Then Ind = Ind - SpIndent: inCase = inCase - 1
      Ind = Ind - SpIndent
      O = O & "break;" & vbCrLf
      O = O & "}"
    ElseIf tLeft(L, 9) = "Case Else" Then
      If inCase > 0 Then O = O & sSpace(Ind) & "break;" & vbCrLf: Ind = Ind - SpIndent: inCase = inCase - 1
      O = O & sSpace(Ind) & "default:"
      inCase = inCase + 1
      Ind = Ind + SpIndent
    ElseIf tLeft(L, 5) = "Case " Then
      T = Mid(Res, InStrRev(Res, "switch("))
      If RegExTest(T, "case [^:]+:") Then O = O & sSpace(Ind) & "break;" & vbCrLf: Ind = Ind - SpIndent: inCase = inCase - 1
      T = tMid(L, 6)
      If tLeft(T, 5) = "Like " Or tLeft(T, 3) = "Is " Or T Like "* = *" Then
        O = O & "// TODO: Cannot convert case: " & T & vbCrLf
        O = O & sSpace(Ind) & "case 0: "
      ElseIf nextBy(T, ",", 2) <> "" Then
        O = O & sSpace(Ind)
        Do
          U = nextBy(T, ", ")
          If U = "" Then Exit Do
          T = Trim(Mid(T, Len(U) + 1))
          O = O & "case " & ConvertValue(U) & ": "
        Loop While True
      ElseIf T Like "* To *" Then
        O = O & "// CONVERSION: Case was " & T & vbCrLf
        O = O & sSpace(Ind)
        cN = Val(SplitWord(T, 1, " To "))
        CM = Val(SplitWord(T, 2, " To "))
        For K = cN To CM
          O = O & "case " & K & ": "
        Next
      Else
        O = O & sSpace(Ind) & "case " & ConvertValue(T) & ":"
      End If
      inCase = inCase + 1
      Ind = Ind + SpIndent
    ElseIf Trim(L) = "Do" Then
      O = O & sSpace(Ind) & "do {"
      Ind = Ind + SpIndent
    ElseIf tLeft(L, 9) = "Do While " Then
      O = O & sSpace(Ind) & "while(" & ConvertValue(tMid(L, 10)) & ") {"
      Ind = Ind + SpIndent
    ElseIf tLeft(L, 9) = "Do Until " Then
      O = O & sSpace(Ind) & "while(!(" & ConvertValue(tMid(L, 10)) & ")) {"
      Ind = Ind + SpIndent
    ElseIf tLeft(L, 9) = "For Each " Then
      L = tMid(L, 10)
      O = O & sSpace(Ind) & "foreach(var " & SplitWord(L, 1, " In ") & " in " & SplitWord(L, 2, " In ") & ") {"
      Ind = Ind + SpIndent
    ElseIf tLeft(L, 4) = "For " Then
      Dim forKey As String, forStr As String, forEnd As String
      L = tMid(L, 5)
      forKey = SplitWord(L, 1, "=")
      L = SplitWord(L, 2, "=")
      forStr = SplitWord(L, 1, " To ")
      forEnd = SplitWord(L, 2, " To ")
      O = O & sSpace(Ind) & "for(" & ConvertElement(forKey) & "=" & ConvertElement(forStr) & "; " & ConvertElement(forKey) & "<" & ConvertElement(forEnd) & "; " & ConvertElement(forKey) & "++) {"
      Ind = Ind + SpIndent
    ElseIf tLeft(L, 11) = "Loop While " Then
      Ind = Ind - SpIndent
      O = O & sSpace(Ind) & "} while(!(" & ConvertValue(tMid(L, 12)) & ");"
    ElseIf tLeft(L, 11) = "Loop Until " Then
      Ind = Ind - SpIndent
      O = O & sSpace(Ind) & "} while(!(" & ConvertValue(tMid(L, 12)) & ");"
    ElseIf tLeft(L, 5) = "Loop" Then
      Ind = Ind - SpIndent
      O = O & sSpace(Ind) & "}"
    ElseIf tLeft(L, 8) = "Exit For" Or tLeft(L, 7) = "Exit Do" Or tLeft(L, 10) = "Exit While" Then
      O = O & sSpace(Ind) & "break;"
    ElseIf tLeft(L, 5) = "Next" Then
      Ind = Ind - SpIndent
      O = sSpace(Ind) & "}"
    ElseIf tLeft(L, 5) = "With " Then
      WithLevel = WithLevel + 1

      T = ConvertValue(tMid(L, 6))
      U = ConvertDataType(SubParam(T).asType)
      V = WithMark & IIf(SubParam(T).Name <> "", T, Random)
      If U = "" Then U = DefaultDataType
      
      Stack WithAssign, T
      Stack WithTypes, U
      Stack WithVars, V
      
      O = O & sSpace(Ind) & U & " " & V & ";" & vbCrLf
      MaxWithLevel = MaxWithLevel + 1
      O = O & sSpace(Ind) & V & " = " & T & ";"
      Ind = Ind + SpIndent
    ElseIf tLeft(L, 8) = "End With" Then
      WithLevel = WithLevel - 1
      T = Stack(WithAssign)
      U = Stack(WithTypes)
      V = Stack(WithVars)
      If SubParam(T).Name <> "" Then
        O = O & sSpace(Ind) & T & " = " & V & ";"
      End If
      Ind = Ind - SpIndent
    ElseIf IsInStr(L, "On Error ") Or IsInStr(L, "Resume ") Then
      O = sSpace(Ind) & "// TODO (not supported): " & L
    Else
'If IsInStr(L, "ComputeAgeing dtpArrearControlDate") Then Stop
      O = sSpace(Ind) & ConvertCodeLine(L)
    End If
    O = ReComment(O)
    Res = Res & ReComment(O) & IIf(O = "", "", vbCrLf)
  Next
  
  ConvertSub = Res
End Function
