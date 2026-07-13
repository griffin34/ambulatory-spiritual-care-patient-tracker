VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} AddEditPatientForm 
   Caption         =   "Add / Edit Patient"
   ClientHeight    =   5832
   ClientLeft      =   108
   ClientTop       =   456
   ClientWidth     =   6588
   OleObjectBlob   =   "AddEditPatientForm.frx":0000
   StartUpPosition =   1  'CenterOwner
End
Attribute VB_Name = "AddEditPatientForm"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False

Option Explicit
Public PatientId As Long   ' 0 = new patient

Private Sub UserForm_Activate()
    ' TODO(plan3): populate cboReferralSource/cboReligion/cboLanguage from
    ' modUtils.DataSheet("_data_lov") rows for each category.
    If PatientId > 0 Then
        ' TODO(plan3): load modPatients.GetPatient(PatientId) into the fields.
        Me.Caption = "Edit Patient"
    Else
        Me.Caption = "Add Patient"
    End If
End Sub

Private Sub btnSave_Click()
    If Trim(txtLastName.Text) = "" Or Trim(txtFirstName.Text) = "" Then
        ShowError "First and last name are required."
        Exit Sub
    End If
    ' TODO(plan3): validate txtReferralDate as YYYY-MM-DD.
    ' TODO(plan3): modPatients.Save PatientId, txtMrn.Text, txtLastName.Text, ...
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub
