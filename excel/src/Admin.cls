VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "Admin"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = True
Option Explicit

Private Sub Worksheet_Activate()
    modAdmin.RefreshAdmin
    modPurge.RefreshPurgeConfigDisplay
    Application.EnableEvents = False
    Me.Range("C26").Value = modUtils.GetSetting("retention_months")
    Me.Range("E26").Value = modPurge.FrequencyLabel(modUtils.GetSetting("purge_frequency"))
    Application.EnableEvents = True
End Sub

Private Sub Worksheet_Change(ByVal Target As Range)
    On Error GoTo CleanUp

    If Not Intersect(Target, Me.Range("I2")) Is Nothing Then
        modAdmin.RefreshLovTable
        Exit Sub
    End If

    If Not Intersect(Target, Me.Range("C26")) Is Nothing Then
        modUtils.SetSetting "retention_months", CStr(Me.Range("C26").Value)
        Exit Sub
    End If

    If Not Intersect(Target, Me.Range("E26")) Is Nothing Then
        modUtils.SetSetting "purge_frequency", modPurge.FrequencyInternal(CStr(Me.Range("E26").Value))
        Exit Sub
    End If

    Dim tbl As ListObject: Set tbl = Me.ListObjects("tblLov")
    If tbl.DataBodyRange Is Nothing Then Exit Sub
    If Intersect(Target, tbl.DataBodyRange) Is Nothing Then Exit Sub

    Application.EnableEvents = False

    Dim rowOffset As Long: rowOffset = Target.Row - tbl.DataBodyRange.Row + 1
    Dim lovId As Long: lovId = tbl.DataBodyRange(rowOffset, 1).Value
    If lovId = 0 Then GoTo CleanUp

    Dim categoryLabel As String: categoryLabel = CStr(Me.Range("I2").Value)
    Dim category As String: category = modAdmin.CategoryInternal(categoryLabel)

    If category = "consultants" Then
        Dim newName As String: newName = CStr(tbl.DataBodyRange(rowOffset, 2).Value)
        Dim chaplainText As String: chaplainText = CStr(tbl.DataBodyRange(rowOffset, 5).Value)
        Dim isChaplain As Boolean: isChaplain = (UCase(chaplainText) = "YES")
        modAdmin.UpsertConsultant lovId, newName, isChaplain
    Else
        Dim newValue As String: newValue = CStr(tbl.DataBodyRange(rowOffset, 2).Value)
        Dim newSort As Long
        If IsNumeric(tbl.DataBodyRange(rowOffset, 3).Value) Then
            newSort = CLng(tbl.DataBodyRange(rowOffset, 3).Value)
        End If
        modAdmin.UpdateLovRow lovId, newValue, newSort
    End If

CleanUp:
    Application.EnableEvents = True
End Sub
