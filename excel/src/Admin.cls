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

' Each condition is checked independently (no Exit Sub after the first match)
' so a single Change event whose Target spans more than one of these tracked
' cells -- e.g. a multi-cell paste or fill-drag across C26:E26 -- still
' handles all of them, not just whichever is checked first.
Private Sub Worksheet_Change(ByVal Target As Range)
    If Not Intersect(Target, Me.Range("I2")) Is Nothing Then
        modAdmin.RefreshLovTable
    End If

    If Not Intersect(Target, Me.Range("C26")) Is Nothing Then
        modUtils.SetSetting "retention_months", CStr(Me.Range("C26").Value)
    End If

    If Not Intersect(Target, Me.Range("E26")) Is Nothing Then
        modUtils.SetSetting "purge_frequency", modPurge.FrequencyInternal(CStr(Me.Range("E26").Value))
    End If
End Sub
