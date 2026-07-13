VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "WorkQueue"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = True
Option Explicit

Private Sub Worksheet_Activate()
    modPatients.RefreshWorkQueue
End Sub

Private Sub Worksheet_BeforeDoubleClick(ByVal Target As Range, Cancel As Boolean)
    Dim tbl As ListObject: Set tbl = Me.ListObjects("tblWorkQueue")
    If tbl.DataBodyRange Is Nothing Then Exit Sub
    If Intersect(Target, tbl.DataBodyRange) Is Nothing Then Exit Sub
    Cancel = True
    Dim rowOffset As Long: rowOffset = Target.Row - tbl.DataBodyRange.Row + 1
    Dim pid As Long: pid = tbl.DataBodyRange(rowOffset, 1).Value
    PatientDetailForm.PatientId = pid
    PatientDetailForm.Show
    modPatients.RefreshWorkQueue
End Sub
