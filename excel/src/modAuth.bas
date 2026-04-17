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
Public Function ValidateLogin(email As String, password As String) As Boolean
    Dim ws As Worksheet
    Set ws = modUtils.DataSheet("_data_users")
    Dim last As Long: last = modUtils.LastDataRow(ws)
    If last < 2 Then Exit Function    ' no users at all

    ' Cache column indices — avoid re-scanning headers in inner loop
    Dim cEmail  As Long: cEmail  = modUtils.ColIndex(ws, "email")
    Dim cHash   As Long: cHash   = modUtils.ColIndex(ws, "password_hash")
    Dim cActive As Long: cActive = modUtils.ColIndex(ws, "is_active")
    Dim cId     As Long: cId     = modUtils.ColIndex(ws, "id")
    Dim cName   As Long: cName   = modUtils.ColIndex(ws, "name")
    Dim cRole   As Long: cRole   = modUtils.ColIndex(ws, "role")

    Dim hashPw As String: hashPw = HashPassword(password)

    Dim i As Long
    For i = 2 To last
        If LCase(CStr(ws.Cells(i, cEmail).Value)) = LCase(email) And _
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
