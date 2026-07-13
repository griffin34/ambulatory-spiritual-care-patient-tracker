VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} LoginForm
   Caption         =   "Ambulatory Patient Tracking - Login"
   ClientHeight    =   3432
   ClientLeft      =   108
   ClientTop       =   456
   ClientWidth     =   5784
   OleObjectBlob   =   "LoginForm.frx":0000
   StartUpPosition =   1  'CenterOwner
End
Attribute VB_Name = "LoginForm"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Option Explicit

Private Sub btnLogin_Click()
    Dim email As String
    Dim password As String
    email = Trim(txtEmail.Text)
    password = txtPassword.Text

    If email = "" Or password = "" Then
        ShowError "Email and password are required."
        Exit Sub
    End If

    If modAuth.ValidateLogin(email, password) Then
        Dim ws As Worksheet
        For Each ws In ThisWorkbook.Sheets
            If Left(ws.Name, 5) <> "_data" Then
                ws.Visible = xlSheetVisible
            End If
        Next ws
        ThisWorkbook.Sheets("Splash").Visible = xlSheetHidden
        ThisWorkbook.Sheets("WorkQueue").Activate
        If modAuth.IsAdmin() Then modPurge.RunPurgeCheck
        Unload Me
    Else
        ShowError "Invalid email or password."
        txtPassword.Text = ""
        txtPassword.SetFocus
    End If
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub

Private Sub UserForm_QueryClose(Cancel As Integer, CloseMode As Integer)
    If CloseMode = vbFormControlMenu Then
        Cancel = True
        ThisWorkbook.Close SaveChanges:=False
    End If
End Sub
