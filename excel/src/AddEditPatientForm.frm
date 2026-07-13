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
    modUtils.PopulateLovCombo cboReferralSource, "referral_source"
    modUtils.PopulateLovCombo cboReligion, "religion"
    modUtils.PopulateLovCombo cboLanguage, "language"

    If PatientId > 0 Then
        Dim p As Object: Set p = modPatients.GetPatient(PatientId)
        txtMrn.Text = p("mrn") & ""
        txtLastName.Text = p("last_name") & ""
        txtFirstName.Text = p("first_name") & ""
        txtMiddleName.Text = p("middle_name") & ""
        txtPhone.Text = p("phone") & ""
        txtReferralDate.Text = p("date_of_referral") & ""
        cboReferralSource.Value = p("referral_source") & ""
        cboReligion.Value = p("religion") & ""
        cboLanguage.Value = p("language") & ""
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
    If Not modUtils.IsValidIsoDate(Trim(txtReferralDate.Text)) Then
        ShowError "Referral date must be YYYY-MM-DD."
        Exit Sub
    End If

    Dim referralSourceId As Long: referralSourceId = modUtils.LovIdForValue("referral_source", cboReferralSource.Value)
    Dim religionId As Long: religionId = modUtils.LovIdForValue("religion", cboReligion.Value)
    Dim languageId As Long: languageId = modUtils.LovIdForValue("language", cboLanguage.Value)

    modPatients.Save PatientId, Trim(txtMrn.Text), Trim(txtLastName.Text), Trim(txtFirstName.Text), _
        Trim(txtMiddleName.Text), Trim(txtPhone.Text), Trim(txtReferralDate.Text), _
        referralSourceId, religionId, languageId
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub
