VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} AddEditLovForm 
   Caption         =   "Add Value"
   ClientHeight    =   3432
   ClientLeft      =   108
   ClientTop       =   456
   ClientWidth     =   5784
   OleObjectBlob   =   "AddEditLovForm.frx":0000
   StartUpPosition =   1  'CenterOwner
End
Attribute VB_Name = "AddEditLovForm"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Option Explicit

Public Category As String   ' set by caller before .Show, e.g. "referral_source" or "consultants"
Public LovId As Long         ' 0 = new; >0 = editing an existing row

Private Sub UserForm_Activate()
    Dim isConsultant As Boolean: isConsultant = (Category = "consultants")

    lblValue.Caption = IIf(isConsultant, "Name:", "Value:")
    lblSortOrder.Visible = Not isConsultant
    txtSortOrder.Visible = Not isConsultant
    chkChaplain.Visible = isConsultant

    lblError.Visible = False
    txtValue.Text = ""
    txtSortOrder.Text = ""
    chkChaplain.value = False

    If LovId > 0 Then
        Me.Caption = "Edit " & modAdmin.CategoryDisplayName(Category)
        If isConsultant Then
            Dim cons As Object: Set cons = modAdmin.FindConsultantById(LovId)
            If Not cons Is Nothing Then
                txtValue.Text = cons("name") & ""
                chkChaplain.value = (cons("is_chaplain") = 1)
            End If
        Else
            Dim lov As Object: Set lov = modAdmin.FindLov(LovId)
            If Not lov Is Nothing Then
                txtValue.Text = lov("value") & ""
                txtSortOrder.Text = lov("sort_order") & ""
            End If
        End If
    Else
        Me.Caption = "Add " & modAdmin.CategoryDisplayName(Category)
        If Not isConsultant Then
            txtSortOrder.Text = CStr(modAdmin.NextLovSortOrder(Category))
        End If
    End If
End Sub

Private Sub btnSave_Click()
    Dim isConsultant As Boolean: isConsultant = (Category = "consultants")

    If Trim(txtValue.Text) = "" Then
        ShowError IIf(isConsultant, "Name is required.", "Value is required.")
        Exit Sub
    End If

    If isConsultant Then
        modAdmin.UpsertConsultant LovId, Trim(txtValue.Text), CBool(chkChaplain.value)
    Else
        If Not IsNumeric(txtSortOrder.Text) Then
            ShowError "Sort order must be a number."
            Exit Sub
        End If
        Dim sortOrder As Long: sortOrder = CLng(txtSortOrder.Text)
        If LovId > 0 Then
            modAdmin.UpdateLovRow LovId, Trim(txtValue.Text), sortOrder
        Else
            modAdmin.UpsertLov Category, Trim(txtValue.Text), sortOrder
        End If
    End If

    modUtils.AutoSave
    Unload Me
End Sub

Private Sub btnCancel_Click()
    Unload Me
End Sub

Private Sub ShowError(msg As String)
    lblError.Caption = msg
    lblError.Visible = True
End Sub

