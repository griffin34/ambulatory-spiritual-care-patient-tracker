VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} AdminRecoveryForm 
   Caption         =   "Account Recovery"
   ClientHeight    =   7000
   ClientLeft      =   108
   ClientTop       =   456
   ClientWidth     =   7200
   OleObjectBlob   =   "AdminRecoveryForm.frx":0000
   StartUpPosition =   1  'CenterOwner
End
Attribute VB_Name = "AdminRecoveryForm"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Option Explicit

Private verifiedCode As Boolean

Private Sub btnVerify_Click()
    If Not modAuth.VerifyRecoveryCode(Trim(txtCode.Text)) Then
        ShowError "Invalid recovery code."
        Exit Sub
    End If
    verifiedCode = True
    lblError.Visible = False
    PopulateUsers
    lblUsers.Visible = True: lstUsers.Visible = True
    lblNewPassword.Visible = True: txtNewPassword.Visible = True
    lblConfirmPassword.Visible = True: txtConfirmPassword.Visible = True
    btnResetPassword.Visible = True
    txtCode.Enabled = False: btnVerify.Enabled = False
End Sub

Private Sub PopulateUsers()
    lstUsers.Clear
    Dim users As Collection: Set users = modAdmin.ListUsers()
    Dim u As Object
    For Each u In users
        lstUsers.AddItem u("name")
        lstUsers.List(lstUsers.ListCount - 1, 1) = u("username")
        lstUsers.List(lstUsers.ListCount - 1, 2) = IIf(u("is_active") = 1, "Active", "Inactive")
        lstUsers.List(lstUsers.ListCount - 1, 3) = u("id")
    Next u
End Sub

Private Sub btnResetPassword_Click()
    If Not verifiedCode Then Exit Sub
    If lstUsers.ListIndex = -1 Then
        ShowError "Select an account first."
        Exit Sub
    End If
    If txtNewPassword.Text = "" Or txtNewPassword.Text <> txtConfirmPassword.Text Then
        ShowError "Passwords must match and cannot be blank."
        Exit Sub
    End If
    Dim userId As Long: userId = CLng(lstUsers.List(lstUsers.ListIndex, 3))
    modAdmin.RecoverAccount userId, txtNewPassword.Text
    MsgBox "Password reset and account reactivated. You can now log in.", vbInformation
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub

