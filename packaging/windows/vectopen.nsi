; =============================================================================
; Instalador de Vectopen para Windows (NSIS 3, Unicode).
; Lo genera tools/package_release.sh:
;   makensis -DVERSION=0.2.4-beta -DNUM=0.2.4 -DSRC=<carpeta con el .exe>
;            -DICON=<vectopen.ico> -DOUT=<Vectopen-…-setup.exe> vectopen.nsi
; · Por USUARIO (sin administrador) en %LOCALAPPDATA%\Programs\Vectopen: así
;   el actualizador de la app puede instalar la versión nueva en silencio.
; · Menú Inicio, acceso directo en el escritorio (opcional), archivos .vtp
;   asociados, desinstalador en «Aplicaciones instaladas».
; · Actualización desde la app: Vectopen-…-setup.exe /S /RELAUNCH
;   (espera a que Vectopen se cierre, instala encima y lo vuelve a abrir).
; =============================================================================
Unicode true
SetCompressor /SOLID lzma
RequestExecutionLevel user
ManifestDPIAware true

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

!define APP      "Vectopen"
!define EXE      "Vectopen.exe"
!define UNINST   "Software\Microsoft\Windows\CurrentVersion\Uninstall\Vectopen"
!define PROGID   "Vectopen.Document"

Name "${APP} ${VERSION}"
OutFile "${OUT}"
InstallDir "$LOCALAPPDATA\Programs\${APP}"
InstallDirRegKey HKCU "${UNINST}" "InstallLocation"
BrandingText "${APP} ${VERSION}"

VIProductVersion "${NUM}.0"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${NUM}"
VIAddVersionKey "FileDescription" "Instalador de ${APP}"
VIAddVersionKey "LegalCopyright" "MIT"

!define MUI_ICON   "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${SRC}\LICENSE"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Spanish"
!insertmacro MUI_LANGUAGE "English"

LangString SecMain   ${LANG_SPANISH} "Vectopen (necesario)"
LangString SecMain   ${LANG_ENGLISH} "Vectopen (required)"
LangString SecDesk   ${LANG_SPANISH} "Acceso directo en el escritorio"
LangString SecDesk   ${LANG_ENGLISH} "Desktop shortcut"
LangString SecAssoc  ${LANG_SPANISH} "Abrir los archivos .vtp con Vectopen"
LangString SecAssoc  ${LANG_ENGLISH} "Open .vtp files with Vectopen"
LangString DocType   ${LANG_SPANISH} "Documento de Vectopen"
LangString DocType   ${LANG_ENGLISH} "Vectopen document"
LangString StillOpen ${LANG_SPANISH} "Vectopen sigue abierto. Ciérralo y pulsa Reintentar."
LangString StillOpen ${LANG_ENGLISH} "Vectopen is still running. Close it and press Retry."

Var Relaunch

Function .onInit
	StrCpy $Relaunch "0"
	${GetParameters} $0
	ClearErrors
	${GetOptions} $0 "/RELAUNCH" $1
	${IfNot} ${Errors}
		StrCpy $Relaunch "1"
	${EndIf}
FunctionEnd

; Espera a que el Vectopen.exe instalado se pueda reemplazar (la app se cierra
; sola al lanzar la actualización; puede tardar un momento).
Function WaitForApp
	IfFileExists "$INSTDIR\${EXE}" 0 done
	StrCpy $2 0
	retry:
		ClearErrors
		FileOpen $3 "$INSTDIR\${EXE}" a
		${IfNot} ${Errors}
			FileClose $3
			Goto done
		${EndIf}
		IntOp $2 $2 + 1
		${If} $2 < 40
			Sleep 500
			Goto retry
		${EndIf}
		IfSilent done
		MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "$(StillOpen)" IDRETRY 0 IDCANCEL done
		StrCpy $2 0
		Goto retry
	done:
FunctionEnd

Section "$(SecMain)" SEC_MAIN
	SectionIn RO
	SetOutPath "$INSTDIR"
	Call WaitForApp
	SetOverwrite on
	File "${SRC}\${EXE}"
	File "${SRC}\*.dll"
	File "${SRC}\LICENSE"
	File "${SRC}\THIRD_PARTY_NOTICES.txt"
	File /oname=vectopen.ico "${ICON}"
	WriteUninstaller "$INSTDIR\Uninstall.exe"

	CreateDirectory "$SMPROGRAMS\${APP}"
	CreateShortcut "$SMPROGRAMS\${APP}\${APP}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\vectopen.ico"
	CreateShortcut "$SMPROGRAMS\${APP}\Desinstalar ${APP}.lnk" "$INSTDIR\Uninstall.exe"

	WriteRegStr HKCU "${UNINST}" "DisplayName" "${APP}"
	WriteRegStr HKCU "${UNINST}" "DisplayVersion" "${VERSION}"
	WriteRegStr HKCU "${UNINST}" "Publisher" "Casimiro Ondo Obiang"
	WriteRegStr HKCU "${UNINST}" "URLInfoAbout" "https://malabo1990.github.io/vectopen-web/"
	WriteRegStr HKCU "${UNINST}" "DisplayIcon" "$INSTDIR\vectopen.ico"
	WriteRegStr HKCU "${UNINST}" "InstallLocation" "$INSTDIR"
	WriteRegStr HKCU "${UNINST}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
	WriteRegStr HKCU "${UNINST}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
	WriteRegDWORD HKCU "${UNINST}" "NoModify" 1
	WriteRegDWORD HKCU "${UNINST}" "NoRepair" 1
	${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
	IntFmt $0 "0x%08X" $0
	WriteRegDWORD HKCU "${UNINST}" "EstimatedSize" "$0"
SectionEnd

Section "$(SecDesk)" SEC_DESK
	CreateShortcut "$DESKTOP\${APP}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\vectopen.ico"
SectionEnd

Section "$(SecAssoc)" SEC_ASSOC
	WriteRegStr HKCU "Software\Classes\.vtp" "" "${PROGID}"
	WriteRegStr HKCU "Software\Classes\${PROGID}" "" "$(DocType)"
	WriteRegStr HKCU "Software\Classes\${PROGID}\DefaultIcon" "" "$INSTDIR\vectopen.ico"
	WriteRegStr HKCU "Software\Classes\${PROGID}\shell\open\command" "" '"$INSTDIR\${EXE}" "%1"'
	WriteRegStr HKCU "Software\Classes\Applications\${EXE}\shell\open\command" "" '"$INSTDIR\${EXE}" "%1"'
	System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
SectionEnd

Section "-relaunch"
	${If} $Relaunch == "1"
		Exec '"$INSTDIR\${EXE}"'
	${EndIf}
SectionEnd

Section "Uninstall"
	Delete "$INSTDIR\${EXE}"
	Delete "$INSTDIR\*.dll"
	Delete "$INSTDIR\LICENSE"
	Delete "$INSTDIR\THIRD_PARTY_NOTICES.txt"
	Delete "$INSTDIR\vectopen.ico"
	Delete "$INSTDIR\Uninstall.exe"
	RMDir "$INSTDIR"
	Delete "$SMPROGRAMS\${APP}\${APP}.lnk"
	Delete "$SMPROGRAMS\${APP}\Desinstalar ${APP}.lnk"
	RMDir "$SMPROGRAMS\${APP}"
	Delete "$DESKTOP\${APP}.lnk"
	ReadRegStr $0 HKCU "Software\Classes\.vtp" ""
	${If} $0 == "${PROGID}"
		DeleteRegKey HKCU "Software\Classes\.vtp"
	${EndIf}
	DeleteRegKey HKCU "Software\Classes\${PROGID}"
	DeleteRegKey HKCU "Software\Classes\Applications\${EXE}"
	DeleteRegKey HKCU "${UNINST}"
	System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
SectionEnd
