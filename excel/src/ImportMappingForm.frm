VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} ImportMappingForm 
   Caption         =   "Import From Electon Export"
   ClientHeight    =   6636
   ClientLeft      =   108
   ClientTop       =   456
   ClientWidth     =   8184
   OleObjectBlob   =   "ImportMappingForm.frx":0000
   StartUpPosition =   1  'CenterOwner
End
Attribute VB_Name = "ImportMappingForm"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Public SourceFilePath As String   ' set by caller before .Show

Option Explicit

Private Sub UserForm_Activate()
    ' TODO(plan7): populate lstPreview from modExport.PreviewImport(SourceFilePath)
End Sub

Private Sub btnImport_Click()
    lblProgress.Caption = "Importing..."
    Me.Repaint
    ' TODO(plan7): modExport.RunImport SourceFilePath, IIf(optReplace.Value, "replace", "merge")
    lblProgress.Caption = "Done."
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub

