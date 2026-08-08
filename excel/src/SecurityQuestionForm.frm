VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} SecurityQuestionForm 
   Caption         =   "Security Question"
   ClientHeight    =   4600
   ClientLeft      =   108
   ClientTop       =   456
   ClientWidth     =   6000
   OleObjectBlob   =   "SecurityQuestionForm.frx":0000
   StartUpPosition =   1  'CenterOwner
End
Attribute VB_Name = "SecurityQuestionForm"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Option Explicit

Public UserId As Long   ' set by caller before .Show

Private Sub UserForm_Activate()
    lblUserName.Caption = modAdmin.GetUserName(UserId)
    Dim q As String: q = modAdmin.GetSecurityQuestionById(UserId)
    If q = "" Then
        lblCurrentQuestion.Caption = "No security question is currently set."
    Else
        lblCurrentQuestion.Caption = "Current question: " & q
    End If
End Sub

Private Sub btnSave_Click()
    If (Trim(txtQuestion.Text) = "") <> (Trim(txtAnswer.Text) = "") Then
        ShowError "Enter both a question and an answer, or leave both blank to remove it."
        Exit Sub
    End If
    modAdmin.SetSecurityQuestion UserId, txtQuestion.Text, txtAnswer.Text
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub

