!macro NSIS_HOOK_POSTINSTALL
  ; The in-place update keeps files the new installer does not list.
  Delete "$INSTDIR\catalog.json"
!macroend
