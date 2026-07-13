VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} PatientDetailForm 
   Caption         =   "Patient Detail"
   ClientHeight    =   10632
   ClientLeft      =   108
   ClientTop       =   456
   ClientWidth     =   10980
   OleObjectBlob   =   "PatientDetailForm.frx":0000
   StartUpPosition =   1  'CenterOwner
End
Attribute VB_Name = "PatientDetailForm"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False

Option Explicit

Private Sub UserForm_Activate()
    LoadPatient
End Sub

Private Sub LoadPatient()
    ' TODO(plan3): replace with modPatients.GetPatient(PatientId) and
    ' populate lblPatientName/lblMrn/lblPhone/lblReferralDate/
    ' lblReferralSource/lblReligion/lblLanguage/lblStatusBadge from it.
    ' TODO(plan3): populate cboChangeStatus from the status list EXCLUDING
    ' "deleted", select current_status.
    ' TODO(plan3): populate lstStatusHistory via modPatients.GetStatusHistory.
    ' TODO(plan4): populate lstAppointments via modAppointments.GetForPatient.
    ' TODO(plan3): populate txtSdatBeginScore/txtSdatBeginDate/txtSdatEndScore/
    ' txtSdatEndDate/txtNotes and lblSdatPctImprovement from the patient row.
    ' TODO(plan3): toggle btnDeletePatient/btnRestorePatient.Visible based on
    ' whether current_status = "deleted".
End Sub

Private Sub btnApplyStatus_Click()
    ' TODO(plan3): modPatients.ChangeStatus PatientId, cboChangeStatus.Value
    ' then LoadPatient to refresh the badge and history list.
End Sub

Private Sub btnEditPatient_Click()
    AddEditPatientForm.PatientId = PatientId
    AddEditPatientForm.Show
    LoadPatient
End Sub

Private Sub btnAddAppointment_Click()
    AddEditAppointmentForm.PatientId = PatientId
    AddEditAppointmentForm.AppointmentId = 0
    AddEditAppointmentForm.Show
    LoadPatient
End Sub

Private Sub btnEditAppointment_Click()
    If lstAppointments.ListIndex = -1 Then Exit Sub
    ' TODO(plan4): AddEditAppointmentForm.AppointmentId = <id from selected row>
    AddEditAppointmentForm.PatientId = PatientId
    AddEditAppointmentForm.Show
    LoadPatient
End Sub

Private Sub btnSaveSdat_Click()
    Dim beginScore As Variant, endScore As Variant
    beginScore = ParsedScore(txtSdatBeginScore.Text)
    endScore = ParsedScore(txtSdatEndScore.Text)
    If beginScore = "invalid" Or endScore = "invalid" Then
        MsgBox "SDAT scores must be a whole number between 0 and 40, or blank.", vbExclamation
        Exit Sub
    End If
    ' TODO(plan3): modPatients.SaveSdat PatientId, beginScore, txtSdatBeginDate.Text, _
    '     endScore, txtSdatEndDate.Text
    ' (modPatients recomputes and stores sdat_pct_improvement, same as patients.js)
    LoadPatient
End Sub

' Returns a Long 0-40, Empty for a blank string, or the string "invalid".
Private Function ParsedScore(s As String) As Variant
    If Trim(s) = "" Then
        ParsedScore = Empty
    ElseIf Not IsNumeric(s) Then
        ParsedScore = "invalid"
    ElseIf CLng(s) <> CDbl(s) Or CLng(s) < 0 Or CLng(s) > 40 Then
        ParsedScore = "invalid"
    Else
        ParsedScore = CLng(s)
    End If
End Function

Private Sub btnSaveNotes_Click()
    If Len(txtNotes.Text) > 256 Then
        MsgBox "Notes must be 256 characters or fewer.", vbExclamation
        Exit Sub
    End If
    ' TODO(plan3): modPatients.SaveNotes PatientId, txtNotes.Text
    LoadPatient
End Sub

Private Sub btnDeletePatient_Click()
    If MsgBox("Delete this patient? This can be undone from the Deleted filter.", _
              vbQuestion + vbYesNo, "Confirm Delete") <> vbYes Then Exit Sub
    ' TODO(plan3): modPatients.Delete PatientId
    LoadPatient
End Sub

Private Sub btnRestorePatient_Click()
    ' TODO(plan3): modPatients.Restore PatientId (sets current_status = "on_hold")
    LoadPatient
End Sub

