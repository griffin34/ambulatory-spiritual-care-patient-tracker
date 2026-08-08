VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} PurgeConfirmForm 
   Caption         =   "Confirm Data Purge"
   ClientHeight    =   3840
   ClientLeft      =   108
   ClientTop       =   456
   ClientWidth     =   7380
   OleObjectBlob   =   "PurgeConfirmForm.frx":0000
   StartUpPosition =   1  'CenterOwner
End
Attribute VB_Name = "PurgeConfirmForm"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Public StaleCount As Long          ' set by caller before .Show
Public DefaultArchivePath As String

Option Explicit

Private Sub UserForm_Activate()
    lblMessage.Caption = StaleCount & " patient(s) have had no activity within " & _
        "the retention period and will be archived and removed."
    txtArchivePath.Text = DefaultArchivePath
End Sub

Private Sub btnBrowse_Click()
    Dim fd As FileDialog
    Set fd = Application.FileDialog(msoFileDialogSaveAs)
    fd.InitialFileName = txtArchivePath.Text
    If fd.Show = -1 Then
        txtArchivePath.Text = fd.SelectedItems(1)
    End If
End Sub

Private Sub btnConfirm_Click()
    modPurge.ArchiveAndPurge modPurge.gPendingStaleIds, txtArchivePath.Text
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub


