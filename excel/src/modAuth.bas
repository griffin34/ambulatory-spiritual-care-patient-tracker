Attribute VB_Name = "modAuth"
Option Explicit

' ── Session state (module-level; cleared on Workbook_BeforeClose) ─────────────
Public gUserId   As Long     ' 0 = not logged in
Public gUserName As String
Public gUserRole As String   ' "admin" | "coordinator"

' ── Password hashing ──────────────────────────────────────────────────────────
Public Function HashPassword(plaintext As String) As String
    HashPassword = modSHA256.SHA256(plaintext)
End Function

' Case/whitespace-insensitive normalization for security-question answers, so
' "Blue" and " blue " hash identically. Public so modAdmin.CreateUser hashes
' new answers the same way VerifySecurityAnswer re-hashes submitted ones.
Public Function NormalizeAnswer(s As String) As String
    NormalizeAnswer = LCase(Trim(s))
End Function

' Strips dashes/spaces and uppercases a recovery code, so "abcd-efgh-jkmn" and
' "ABCDEFGHJKMN" (typed without the display dashes) hash identically.
Private Function NormalizeCode(s As String) As String
    Dim i As Long, ch As String, result As String
    For i = 1 To Len(s)
        ch = UCase(Mid(s, i, 1))
        If ch <> "-" And ch <> " " Then result = result & ch
    Next i
    NormalizeCode = result
End Function

' ── Self-service password recovery ─────────────────────────────────────────────
' True if `answer` matches the stored security answer for an ACTIVE user with
' this username. False (never a match) if the user is missing, inactive, or
' has no security answer set -- a blank stored hash must never match a blank
' submitted answer.
Public Function VerifySecurityAnswer(username As String, answer As String) As Boolean
    Dim ws As Worksheet
    Set ws = modUtils.DataSheet("_data_users")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    If last < 2 Then Exit Function

    Dim cUsername As Long: cUsername = modUtils.ColIndex(ws, "username")
    Dim cActive As Long: cActive = modUtils.ColIndex(ws, "is_active")
    Dim cHash As Long: cHash = modUtils.ColIndex(ws, "security_answer_hash")

    Dim i As Long
    For i = 2 To last
        If LCase(CStr(ws.Cells(i, cUsername).Value)) = LCase(Trim(username)) And _
           ws.Cells(i, cActive).Value = 1 Then
            Dim storedHash As String: storedHash = CStr(ws.Cells(i, cHash).Value)
            If storedHash = "" Then Exit Function   ' no security answer set -- no bypass
            VerifySecurityAnswer = (HashPassword(NormalizeAnswer(answer)) = storedHash)
            Exit Function
        End If
    Next i
End Function

' ── Break-glass recovery code ───────────────────────────────────────────────────
' True if `code` matches the current recovery code. False if no recovery code
' has ever been generated (recovery_code_hash unset/blank) -- no bypass before
' modAdmin.RotateRecoveryCode has run at least once.
Public Function VerifyRecoveryCode(code As String) As Boolean
    Dim storedHash As String: storedHash = modUtils.GetSetting("recovery_code_hash")
    If storedHash = "" Then Exit Function
    VerifyRecoveryCode = (HashPassword(NormalizeCode(code)) = storedHash)
End Function

' Hashes a freshly-generated plaintext recovery code the same way
' VerifyRecoveryCode re-hashes a submitted one. Used by modAdmin.RotateRecoveryCode.
Public Function HashRecoveryCode(plaintextCode As String) As String
    HashRecoveryCode = HashPassword(NormalizeCode(plaintextCode))
End Function

' ── Login validation ──────────────────────────────────────────────────────────
' Scans _data_users for a matching active row.
' On success: populates session globals and returns True.
' On failure: returns False (globals unchanged).
Public Function ValidateLogin(username As String, password As String) As Boolean
    Dim ws As Worksheet
    Set ws = modUtils.DataSheet("_data_users")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    If last < 2 Then Exit Function    ' no users at all

    ' Cache column indices — avoid re-scanning headers in inner loop
    Dim cUsername As Long: cUsername = modUtils.ColIndex(ws, "username")
    Dim cHash   As Long: cHash   = modUtils.ColIndex(ws, "password_hash")
    Dim cActive As Long: cActive = modUtils.ColIndex(ws, "is_active")
    Dim cId     As Long: cId     = modUtils.ColIndex(ws, "id")
    Dim cName   As Long: cName   = modUtils.ColIndex(ws, "name")
    Dim cRole   As Long: cRole   = modUtils.ColIndex(ws, "role")

    Dim hashPw As String: hashPw = HashPassword(password)

    Dim i As Long
    For i = 2 To last
        If LCase(CStr(ws.Cells(i, cUsername).Value)) = LCase(username) And _
           ws.Cells(i, cActive).Value = 1 And _
           ws.Cells(i, cHash).Value = hashPw Then
            gUserId   = CLng(ws.Cells(i, cId).Value)
            gUserName = CStr(ws.Cells(i, cName).Value)
            gUserRole = LCase(CStr(ws.Cells(i, cRole).Value))
            ValidateLogin = True
            Exit Function
        End If
    Next i
    ValidateLogin = False
End Function

' ── Session management ────────────────────────────────────────────────────────
Public Sub Logout()
    gUserId   = 0
    gUserName = ""
    gUserRole = ""
End Sub

Public Function IsLoggedIn() As Boolean
    IsLoggedIn = (gUserId > 0)
End Function

Public Function IsAdmin() As Boolean
    IsAdmin = (gUserRole = "admin")
End Function

' Logs the current user out without closing the workbook: clears the
' session, re-hides the UI sheets behind Splash (mirroring their state before
' any login), and shows LoginForm again -- the reverse of LoginForm/
' AddUserForm's post-login sheet reveal.
Public Sub UI_Logout()
    If MsgBox("Log out?", vbQuestion + vbYesNo, "Confirm Logout") <> vbYes Then Exit Sub

    Logout

    ' Show Splash BEFORE hiding the other sheets -- same reasoning as
    ' Workbook_Open: Excel refuses to hide the last remaining visible sheet,
    ' and at this point Splash is still hidden from login while all 4 UI
    ' sheets are visible, so hiding them one-by-one with Splash shown first
    ' guarantees there's always at least one visible sheet.
    ThisWorkbook.Sheets("Splash").Visible = xlSheetVisible
    Dim ws As Worksheet
    For Each ws In ThisWorkbook.Sheets
        If Left(ws.Name, 5) <> "_data" And ws.Name <> "Splash" Then
            ws.Visible = xlSheetHidden
        End If
    Next ws
    ThisWorkbook.Sheets("Splash").Activate
    modUtils.AutoSave

    LoginForm.Show
End Sub
