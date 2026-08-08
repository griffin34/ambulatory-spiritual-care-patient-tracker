VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} ForgotPasswordForm 
   Caption         =   "Forgot Password"
   ClientHeight    =   5800
   ClientLeft      =   108
   ClientTop       =   456
   ClientWidth     =   6200
   OleObjectBlob   =   "ForgotPasswordForm.frx":0000
   StartUpPosition =   1  'CenterOwner
End
Attribute VB_Name = "ForgotPasswordForm"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Option Explicit

Private Sub btnContinue_Click()
    Dim username As String: username = Trim(txtUsername.Text)
    If username = "" Then
        ShowError "Enter your username."
        Exit Sub
    End If
    Dim q As String: q = modAdmin.GetSecurityQuestion(username)
    If q = "" Then
        ShowError "No security question is set up for that account. Contact an administrator."
        Exit Sub
    End If
    lblError.Visible = False
    lblQuestion.Caption = q
    lblQuestion.Visible = True: lblAnswer.Visible = True: txtAnswer.Visible = True
    lblNewPassword.Visible = True: txtNewPassword.Visible = True
    lblConfirmPassword.Visible = True: txtConfirmPassword.Visible = True
    btnResetPassword.Visible = True
    txtUsername.Enabled = False: btnContinue.Enabled = False
    txtAnswer.SetFocus
End Sub

Private Sub btnResetPassword_Click()
    If Trim(txtAnswer.Text) = "" Then
        ShowError "Enter your answer."
        Exit Sub
    End If
    If Not modAuth.VerifySecurityAnswer(Trim(txtUsername.Text), txtAnswer.Text) Then
        ShowError "That answer doesn't match."
        Exit Sub
    End If
    If txtNewPassword.Text = "" Or txtNewPassword.Text <> txtConfirmPassword.Text Then
        ShowError "Passwords must match and cannot be blank."
        Exit Sub
    End If
    If Not modAdmin.ResetPasswordByUsername(Trim(txtUsername.Text), txtNewPassword.Text) Then
        ShowError "Unable to reset password for that account."
        Exit Sub
    End If
    MsgBox "Password reset. You can now log in with your new password.", vbInformation
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub

