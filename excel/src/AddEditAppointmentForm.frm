VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} AddEditAppointmentForm 
   Caption         =   "Add / Edit Appointment"
   ClientHeight    =   5832
   ClientLeft      =   108
   ClientTop       =   456
   ClientWidth     =   6180
   OleObjectBlob   =   "AddEditAppointmentForm.frx":0000
   StartUpPosition =   1  'CenterOwner
End
Attribute VB_Name = "AddEditAppointmentForm"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False

Public PatientId As Long
Public AppointmentId As Long   ' 0 = new appointment

Option Explicit

Private Sub UserForm_Activate()
    modUtils.PopulateLovCombo cboType, "appointment_type"
    modAppointments.PopulateConsultantCombo cboConsultant

    ' The data model has 5 appointment statuses (rescheduled was added in the
    ' v1.1 pass, after this form's original TODO comment was written).
    cboStatus.Clear
    cboStatus.AddItem "scheduled"
    cboStatus.AddItem "completed"
    cboStatus.AddItem "no_show"
    cboStatus.AddItem "cancelled"
    cboStatus.AddItem "rescheduled"

    If AppointmentId > 0 Then
        Dim a As Object: Set a = modAppointments.GetAppointment(AppointmentId)
        txtDate.Text = a("date") & ""
        txtTime.Text = a("time") & ""
        cboType.Value = a("type") & ""
        cboConsultant.Value = a("consultant_name") & ""
        cboStatus.Value = a("status") & ""
        chkLastAppointment.Value = (a("is_last_appointment") = 1)
        txtNotes.Text = a("notes") & ""
        Me.Caption = "Edit Appointment"
    Else
        cboStatus.Value = "scheduled"
        Me.Caption = "Add Appointment"
    End If
End Sub

Private Sub btnSave_Click()
    If Trim(txtDate.Text) = "" Then
        ShowError "Date is required."
        Exit Sub
    End If
    If Not modUtils.IsValidIsoDate(Trim(txtDate.Text)) Then
        ShowError "Date must be YYYY-MM-DD."
        Exit Sub
    End If

    Dim typeId As Long: typeId = modUtils.LovIdForValue("appointment_type", cboType.Value)
    Dim consultantId As Long: consultantId = modAppointments.ConsultantIdForName(cboConsultant.Value)

    modAppointments.Save AppointmentId, PatientId, Trim(txtDate.Text), Trim(txtTime.Text), _
        typeId, consultantId, CBool(chkLastAppointment.Value), cboStatus.Value, txtNotes.Text
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub

