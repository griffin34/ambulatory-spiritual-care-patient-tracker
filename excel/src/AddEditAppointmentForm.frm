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
    ' TODO(plan4): populate cboType from _data_lov category=appointment_type,
    ' cboConsultant from _data_consultants, cboStatus from the fixed list
    ' (scheduled/completed/no_show/cancelled).
    If AppointmentId > 0 Then
        ' TODO(plan4): load modAppointments.Get(AppointmentId) into the fields.
        Me.Caption = "Edit Appointment"
    Else
        Me.Caption = "Add Appointment"
    End If
End Sub

Private Sub btnSave_Click()
    If Trim(txtDate.Text) = "" Then
        ShowError "Date is required."
        Exit Sub
    End If
    ' TODO(plan4): validate txtDate/txtTime, then
    ' modAppointments.Save AppointmentId, PatientId, txtDate.Text, ...
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub

