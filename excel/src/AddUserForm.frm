VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} AddUserForm 
   Caption         =   "Add User"
   ClientHeight    =   5040
   ClientLeft      =   108
   ClientTop       =   456
   ClientWidth     =   5784
   OleObjectBlob   =   "AddUserForm.frx":0000
   StartUpPosition =   1  'CenterOwner
End
Attribute VB_Name = "AddUserForm"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Public FirstRunMode As Boolean   ' set by caller before .Show

Option Explicit

Private Sub UserForm_Activate()
    cboRole.AddItem "admin"
    cboRole.AddItem "coordinator"
    If FirstRunMode Then
        Me.Caption = "Create Admin Account"
        cboRole.value = "admin"
        cboRole.Enabled = False
        btnCancel.Visible = False
    Else
        Me.Caption = "Add User"
        cboRole.value = "coordinator"
    End If
End Sub

Private Sub btnSave_Click()
    If Trim(txtName.Text) = "" Or Trim(txtEmail.Text) = "" Then
        ShowError "Name and email are required."
        Exit Sub
    End If
    If txtPassword.Text = "" Or txtPassword.Text <> txtConfirmPassword.Text Then
        ShowError "Passwords must match and cannot be blank."
        Exit Sub
    End If
    modAdmin.CreateUser Trim(txtName.Text), Trim(txtEmail.Text), txtPassword.Text, cboRole.value
    If FirstRunMode Then
        modAuth.ValidateLogin Trim(txtEmail.Text), txtPassword.Text
        Dim ws As Worksheet
        For Each ws In ThisWorkbook.Sheets
            If Left(ws.name, 5) <> "_data" Then
                ws.Visible = xlSheetVisible
            End If
        Next ws
        ThisWorkbook.Sheets("Splash").Visible = xlSheetHidden
        ThisWorkbook.Sheets("WorkQueue").Activate
        If modAuth.IsAdmin() Then modPurge.RunPurgeCheck
    End If
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub

