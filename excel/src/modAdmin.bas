Attribute VB_Name = "modAdmin"
Option Explicit

' Creates a new user account with a hashed password and appends it to _data_users.
Public Sub CreateUser(name As String, email As String, password As String, role As String)
    Dim ws As Worksheet
    Set ws = modUtils.DataSheet("_data_users")
    Dim newRow As Long
    newRow = modUtils.LastDataRow(ws) + 1

    ws.Cells(newRow, 1).Value = modUtils.NextId(ws)
    ws.Cells(newRow, 2).Value = name
    ws.Cells(newRow, 3).Value = email
    ws.Cells(newRow, 4).Value = modAuth.HashPassword(password)
    ws.Cells(newRow, 5).Value = role
    ws.Cells(newRow, 6).Value = 1
    ws.Cells(newRow, 7).Value = modUtils.NowISO()
End Sub
