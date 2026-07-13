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
    Dim p As Object: Set p = modPatients.GetPatient(PatientId)

    lblPatientName.Caption = Trim(p("first_name") & " " & p("middle_name") & " " & p("last_name"))
    lblMrn.Caption = p("mrn") & ""
    lblPhone.Caption = p("phone") & ""
    lblReferralDate.Caption = p("date_of_referral") & ""
    lblReferralSource.Caption = p("referral_source") & ""
    lblReligion.Caption = p("religion") & ""
    lblLanguage.Caption = p("language") & ""

    Dim currentStatus As String: currentStatus = p("current_status") & ""
    lblStatusBadge.Caption = modPatients.StatusLabel(currentStatus)
    lblStatusBadge.BackColor = StatusBadgeColor(currentStatus)

    ' ColumnWidths was fixed at 7 columns at design time (date/time/type/
    ' consultant/status/last-appt/notes); a form's own code can safely widen
    ' its own control's runtime ColumnCount to smuggle in a leading 0pt ID
    ' column, which is not the same restricted operation as external
    ' automation touching a Designer's own layout properties.
    lstAppointments.Clear
    lstAppointments.ColumnCount = 8
    lstAppointments.ColumnWidths = "0 pt;55 pt;40 pt;55 pt;70 pt;55 pt;25 pt;90 pt"
    Dim ap As Object
    For Each ap In modAppointments.GetForPatient(PatientId)
        lstAppointments.AddItem ap("id")
        Dim apptIdx As Long: apptIdx = lstAppointments.ListCount - 1
        lstAppointments.List(apptIdx, 1) = ap("date")
        lstAppointments.List(apptIdx, 2) = ap("time")
        lstAppointments.List(apptIdx, 3) = ap("type")
        lstAppointments.List(apptIdx, 4) = ap("consultant_name")
        lstAppointments.List(apptIdx, 5) = ap("status")
        lstAppointments.List(apptIdx, 6) = IIf(ap("is_last_appointment") = 1, "Yes", "")
        lstAppointments.List(apptIdx, 7) = ap("notes")
    Next ap

    cboChangeStatus.Clear
    Dim lbl As Variant
    For Each lbl In modPatients.AllStatusLabelsExceptDeleted()
        cboChangeStatus.AddItem CStr(lbl)
    Next lbl
    If currentStatus <> "deleted" Then
        cboChangeStatus.Value = modPatients.StatusLabel(currentStatus)
    End If

    lstStatusHistory.Clear
    lstStatusHistory.ColumnCount = 3
    Dim h As Object
    For Each h In modPatients.GetStatusHistory(PatientId)
        lstStatusHistory.AddItem h("status")
        lstStatusHistory.List(lstStatusHistory.ListCount - 1, 1) = h("changed_by_name")
        lstStatusHistory.List(lstStatusHistory.ListCount - 1, 2) = h("changed_at")
    Next h

    txtSdatBeginScore.Text = p("sdat_begin_score") & ""
    txtSdatBeginDate.Text = p("sdat_begin_date") & ""
    txtSdatEndScore.Text = p("sdat_end_score") & ""
    txtSdatEndDate.Text = p("sdat_end_date") & ""
    If Trim(p("sdat_pct_improvement") & "") = "" Then
        lblSdatPctImprovement.Caption = ""
    Else
        lblSdatPctImprovement.Caption = "Improvement: " & p("sdat_pct_improvement") & "%"
    End If
    txtNotes.Text = p("notes") & ""

    Dim isDeleted As Boolean: isDeleted = (currentStatus = "deleted")
    btnDeletePatient.Visible = Not isDeleted
    btnRestorePatient.Visible = isDeleted
End Sub

' BackColor uses the same BGR-packed OLE_COLOR format as VBA's RGB() function,
' matching the Status Workflow colors from the design spec.
Private Function StatusBadgeColor(currentStatus As String) As Long
    Select Case LCase(currentStatus)
        Case "ready_to_schedule": StatusBadgeColor = RGB(&HC6, &HEF, &HCE)
        Case "scheduled": StatusBadgeColor = RGB(&HFF, &HEB, &H9C)
        Case "completed": StatusBadgeColor = RGB(&H9D, &HC3, &HE6)
        Case "dropped": StatusBadgeColor = RGB(&HFF, &HC7, &HCE)
        Case "on_hold": StatusBadgeColor = RGB(&HD9, &HD9, &HD9)
        Case "deleted": StatusBadgeColor = RGB(&HBF, &HBF, &HBF)
        Case Else: StatusBadgeColor = RGB(255, 255, 255)
    End Select
End Function

Private Sub btnApplyStatus_Click()
    If Trim(cboChangeStatus.Value) = "" Then Exit Sub
    modPatients.ChangeStatus PatientId, modPatients.StatusInternal(cboChangeStatus.Value)
    LoadPatient
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
    AddEditAppointmentForm.AppointmentId = CLng(lstAppointments.Column(0, lstAppointments.ListIndex))
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
    If Not modUtils.IsValidIsoDate(Trim(txtSdatBeginDate.Text)) Or Not modUtils.IsValidIsoDate(Trim(txtSdatEndDate.Text)) Then
        MsgBox "SDAT dates must be YYYY-MM-DD, or blank.", vbExclamation
        Exit Sub
    End If
    modPatients.SaveSdat PatientId, beginScore, Trim(txtSdatBeginDate.Text), endScore, Trim(txtSdatEndDate.Text)
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
    modPatients.SaveNotes PatientId, txtNotes.Text
    LoadPatient
End Sub

Private Sub btnDeletePatient_Click()
    If MsgBox("Delete this patient? This can be undone from the Deleted filter.", _
              vbQuestion + vbYesNo, "Confirm Delete") <> vbYes Then Exit Sub
    modPatients.Delete PatientId
    LoadPatient
End Sub

Private Sub btnRestorePatient_Click()
    modPatients.Restore PatientId
    LoadPatient
End Sub

