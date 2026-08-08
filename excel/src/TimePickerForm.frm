VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E98-00AA00574A4F} TimePickerForm 
   Caption         =   "Select Time"
   ClientHeight    =   2640
   ClientLeft      =   108
   ClientTop       =   456
   ClientWidth     =   3588
   OleObjectBlob   =   "TimePickerForm.frx":0000
   StartUpPosition =   1  'CenterOwner
End
Attribute VB_Name = "TimePickerForm"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False

Option Explicit

Public SelectedTime As String   ' "HH:MM" 24-hour; "" if the user cancelled
Public InitialTime As String    ' set by caller before .Show (optional), "HH:MM" 24-hour

Private Sub UserForm_Initialize()
    cboHour.Clear
    Dim h As Integer
    For h = 1 To 12
        cboHour.AddItem Format(h, "00")
    Next h
    cboMinute.Clear
    cboMinute.AddItem "00"
    cboMinute.AddItem "15"
    cboMinute.AddItem "30"
    cboMinute.AddItem "45"
    cboAmPm.Clear
    cboAmPm.AddItem "AM"
    cboAmPm.AddItem "PM"
End Sub

' Reading InitialTime has to happen here, not UserForm_Initialize -- Initialize
' fires the moment the caller's very first reference to this predeclared
' instance is evaluated (e.g. "TimePickerForm.InitialTime = x" instantiates
' the object *before* performing that assignment), so InitialTime would still
' be "" at that point. UserForm_Activate fires on .Show, safely after the
' caller has already finished setting InitialTime.
Private Sub UserForm_Activate()
    Dim h24 As Integer, m As Integer
    If Trim(InitialTime) <> "" And modUtils.IsValidTime(Trim(InitialTime)) Then
        h24 = CInt(Left(InitialTime, 2))
        m = CInt(Right(InitialTime, 2))
    Else
        h24 = Hour(Now)
        m = Minute(Now)
    End If

    Dim h12 As Integer, ampm As String
    If h24 = 0 Then
        h12 = 12: ampm = "AM"
    ElseIf h24 < 12 Then
        h12 = h24: ampm = "AM"
    ElseIf h24 = 12 Then
        h12 = 12: ampm = "PM"
    Else
        h12 = h24 - 12: ampm = "PM"
    End If

    cboHour.value = Format(h12, "00")
    ' Snap to the nearest 15-minute increment this picker offers.
    Dim snappedMin As Integer: snappedMin = (m \ 15) * 15
    If snappedMin >= 60 Then snappedMin = 45
    cboMinute.value = Format(snappedMin, "00")
    cboAmPm.value = ampm
End Sub

Private Sub btnOK_Click()
    Dim h12 As Integer: h12 = CInt(cboHour.value)
    Dim m As Integer: m = CInt(cboMinute.value)
    Dim ampm As String: ampm = cboAmPm.value
    Dim h24 As Integer
    If ampm = "AM" Then
        h24 = IIf(h12 = 12, 0, h12)
    Else
        h24 = IIf(h12 = 12, 12, h12 + 12)
    End If
    SelectedTime = Format(h24, "00") & ":" & Format(m, "00")
    ' Hide, NOT Unload -- see CalendarPickerForm's NotifyDaySelected for why.
    Me.Hide
End Sub

Private Sub btnCancel_Click()
    SelectedTime = ""
    Me.Hide
End Sub

