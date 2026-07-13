VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "ThisWorkbook"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = True
Option Explicit

Private Sub Workbook_Open()
    ' Excel refuses to hide the last remaining visible sheet, so the
    ' always-visible Splash sheet stays up while every real UI sheet is hidden.
    Dim ws As Worksheet
    For Each ws In ThisWorkbook.Sheets
        If Left(ws.Name, 5) <> "_data" And ws.Name <> "Splash" Then
            ws.Visible = xlSheetHidden
        End If
    Next ws

    Dim usersWs As Worksheet
    Set usersWs = modUtils.DataSheet("_data_users")
    If modUtils.LastDataRow(usersWs) < 2 Then
        AddUserForm.FirstRunMode = True
        AddUserForm.Show
        Exit Sub
    End If

    LoginForm.Show
End Sub

Private Sub Workbook_BeforeClose(Cancel As Boolean)
    modAuth.Logout
End Sub

