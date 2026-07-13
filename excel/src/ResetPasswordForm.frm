VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} ResetPasswordForm 
   Caption         =   "Reset Password"
   ClientHeight    =   3840
   ClientLeft      =   108
   ClientTop       =   456
   ClientWidth     =   5388
   OleObjectBlob   =   "ResetPasswordForm.frx":0000
   StartUpPosition =   1  'CenterOwner
End
Attribute VB_Name = "ResetPasswordForm"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Public UserId As Long   ' set by caller before .Show

Option Explicit

Private Sub UserForm_Activate()
    ' TODO(plan6): lblUserName.Caption = modAdmin.GetUserName(UserId)
End Sub

Private Sub btnSave_Click()
    If txtNewPassword.Text = "" Or txtNewPassword.Text <> txtConfirmPassword.Text Then
        ShowError "Passwords must match and cannot be blank."
        Exit Sub
    End If
    ' TODO(plan6): modAdmin.ResetPassword UserId, txtNewPassword.Text
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub

