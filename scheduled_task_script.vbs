Set objShell = CreateObject("WScript.Shell")

command1 = """C:\Program Files (x86)\Schneider Electric\IGSS32\V14.0\GSS\alm.exe"" -fsiem -csv -file""C:\Users\lab\Documents\igss_alarms.csv"" -ts$-90 -te$ -all"
' Run command invisible (0 = hidden), do not wait for completion (False)
objShell.Run command1, 0, True


command1 = "powershell.exe -NoLogo -NonInteractive -WindowStyle Hidden -File ""C:\Users\lab\Documents\process_alarms.ps1"" -ExportAlarms -CsvPath ""C:\Users\lab\Documents\igss_alarms.csv"""
' Run command invisible (0 = hidden), do not wait for completion (False)
objShell.Run command1, 0, True
