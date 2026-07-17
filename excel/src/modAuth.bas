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
