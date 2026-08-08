VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "clsDayBtn"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

' Wraps one dynamically-created day button on CalendarPickerForm so its
' Click event is handled -- VBA can't route multiple controls' events to one
' Sub without a WithEvents wrapper like this per control.
Public WithEvents Btn As MSForms.CommandButton
Attribute Btn.VB_VarHelpID = -1
Public DayValue As Integer
Public Owner As CalendarPickerForm

Private Sub Btn_Click()
    If DayValue > 0 Then
        Owner.NotifyDaySelected DayValue
    End If
End Sub

