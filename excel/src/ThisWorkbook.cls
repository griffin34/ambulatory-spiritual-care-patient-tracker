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
    ' The sheets are protected (build.py) so a stray click-and-type can't
    ' corrupt hidden ID columns or table bodies, but UserInterfaceOnly --
    ' which lets VBA itself keep writing to locked cells (RefreshWorkQueue,
    ' etc.) despite that protection -- does NOT persist across a save/reopen
    ' and must be re-applied every session.
    Dim protectWs As Worksheet
    For Each protectWs In ThisWorkbook.Sheets
        If protectWs.Name = "WorkQueue" Or protectWs.Name = "Appointments" Or _
           protectWs.Name = "Admin" Or protectWs.Name = "Reports" Then
            protectWs.Protect UserInterfaceOnly:=True
        End If
    Next protectWs

    ' Excel refuses to hide the last remaining visible sheet, so the
    ' always-visible Splash sheet stays up while every real UI sheet is hidden.
    ' Splash may have been left hidden by a prior session's login/AddUserForm
    ' (which un-hides the real sheets and hides Splash) -- re-show it first so
    ' the hide loop below never tries to hide the last visible sheet.
    ThisWorkbook.Sheets("Splash").Visible = xlSheetVisible

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
    ' Each data-entry form already saves itself right after a successful
    ' write (see modAdmin/modPatients/modAppointments callers), but this is a
    ' safety net so nothing else (e.g. Admin's inline Activate/Deactivate
    ' buttons) can leave the workbook dirty and trigger Excel's native
    ' "Do you want to save changes?" prompt on close.
    If Not ThisWorkbook.Saved Then ThisWorkbook.Save
End Sub

