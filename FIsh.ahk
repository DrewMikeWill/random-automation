#Requires AutoHotkey v2.0

; --- State ---
global FishingSpotColor := ""       ; 0xRRGGBB, fishing spot highlight color to click
global IsRunning := false
global ColorVariation := 20         ; color tolerance for fishing spot (0–255)
global ConfigPath := A_ScriptDir "\Fish.ini"

; Fishing state: if vibrant green (or set "fishing" color) EXISTS in the area = fishing; else = not fishing
global FishingRegionX1 := 0        ; top-left of area to watch (set with Ctrl+Shift+Y / U)
global FishingRegionY1 := 0
global FishingRegionX2 := 0        ; bottom-right
global FishingRegionY2 := 0
global FishingIndicatorColor := "0x00FF00" ; vibrant green; if this color in area = fishing (set with Ctrl+Shift+V)
global FishingIndicatorVariation := 25       ; color tolerance for fishing check
global IsFishing := false
global FishingCheckInterval := 1000 ; ms between fishing-state checks
global FishingRegionOverlayGuis := []
global FishingCornerMarkSize := 12

; Play area – only search/click inside this rect (0,0,0,0 = full screen)
global PlayAreaX1 := 0
global PlayAreaY1 := 0
global PlayAreaX2 := 0
global PlayAreaY2 := 0
global PlayAreaOverlayGuis := []
global CornerMarkSize := 30

; Last inventory slot – empty baseline captured when area is set; full until slot matches empty again
global InvSlotX1 := 0
global InvSlotY1 := 0
global InvSlotX2 := 0
global InvSlotY2 := 0
global InvSlotEmptyColor := ""   ; color when slot is empty (auto-captured when inv slot area is set)
global InvSlotVariation := 15    ; tolerance when comparing to empty
global IsInventoryFull := false  ; true when slot doesn't match empty; persists until slot matches empty again
global InvSlotCheckInterval := 2000 ; ms between inv slot checks
global InvSlotOverlayGuis := []
global InvSlotCornerSize := 8

; Targeting (fishing spot click)
global FishInterval := 1000        ; ms between fishing attempts when not fishing (fast now that we use green indicator)
global LastFishClickTime := 0      ; tick when we last clicked a fishing spot
global LastFishClickCooldownMs := 0 ; ms to wait after that click (random 5–10 s when we clicked)
global FishClickCooldownMin := 5000 ; ms min wait after fish click
global FishClickCooldownMax := 10000 ; ms max wait after fish click (random between min–max)
global RadiusStep := 120
global ClickJitter := 2
global ClickDelayMs := 35
global BoundsScanStep := 2
global BoundsMaxDist := 50
; Fishing spot / nav: use centroid of matching pixels in a tile-sized window (click tile center, not border)
global FishSpotCentroidRadius := 28 ; half-width of search window around first hit (~56px tile)
global FishSpotCentroidStep := 4   ; sample every N pixels for centroid (4 = fast, 2 = more accurate)

; Run duration (0 = unlimited)
global RunDurationMinutes := 0
global RunStartTime := 0

; Banking mode – nav1 -> wait 3–5 s -> nav2 -> wait 3–5 s -> deposit box -> wait 5–7 s -> done
; Nav tiles and deposit box are color-only (no coordinates); we search for the color on screen each time so moving tiles work
global NavTile1Color := ""       ; 0xRRGGBB, set with Ctrl+Shift+1
global NavTile2Color := ""       ; 0xRRGGBB, set with Ctrl+Shift+2
global DepositBoxColor := ""     ; 0xRRGGBB, set with Ctrl+Shift+D
global BankingStep := 0          ; 0=idle, 1=nav1, 2=wait, 3=nav2, 4=wait, 5=deposit box, 55=wait open+click deposit, 6=wait closed, 7=nav2 return, 8=wait, 9=nav1 return, 10=wait
global BankWaitUntil := 0        ; tick when current wait ends
global BankRecaptureEmptyAt := 0 ; tick when to re-capture empty baseline after deposit (0 = not pending)
global BankDepositAreaLastClickAt := 0 ; tick of last deposit-area click (for retry cooldown in step 6)
global BankNavWaitMin := 2000    ; ms to wait between nav1 and nav2 going to bank (2–3 s)
global BankNavWaitMax := 3000
global BankDepositBoxOpenWaitMin := 7000 ; ms to wait for deposit box to open after clicking it (7–9 s)
global BankDepositBoxOpenWaitMax := 9000
global BankDepositWaitMin := 5000 ; ms to wait after clicking deposit-all (5–7 s before return)
global BankDepositWaitMax := 7000
global BankDepositClosedTimeout := 8000 ; max ms to wait for deposit area color to disappear (box closed)
global BankDepositAreaClickCooldownMs := 2500 ; min ms between deposit-area clicks (retry if color persists = other fish types)
global BankReturnNav2WaitMin := 7000 ; ms after clicking nav 2 on return (7–9 s)
global BankReturnNav2WaitMax := 9000
global BankReturnNav1WaitMin := 2000 ; ms after clicking nav 1 on return (2–3 s)
global BankReturnNav1WaitMax := 3000
global BankingColorVariation := 5  ; deposit box: exact or super close (per-channel tolerance 0–255)
global BankingNavColorVariation := 5 ; nav tiles: exact or super close (reduce false positives)
global BankingImageOffset := 15   ; when using image search: click this many px from top-left of found image

; Deposit box open detection: area + color; when color found in area, deposit box is open
global DepositBoxOpenX1 := 0
global DepositBoxOpenY1 := 0
global DepositBoxOpenX2 := 0
global DepositBoxOpenY2 := 0
global DepositBoxOpenColor := ""
global DepositBoxOpenVariation := 15

; Mode: Banking (bank/deposit/return) or Powerfishing (drop all when full)
global FishingMode := "Banking"
; Powerfishing: up to 27 item slot positions; one hotkey adds current pos, one clears all
global PowerfishSlots := []           ; array of [x, y]
global PowerfishLastDropAt := 0       ; tick when we last ran drop-all (cooldown)
global PowerfishDropCooldownMs := 2000
global PowerfishClickDelayMin := 100 ; ms between each shift+click (0.1–0.4 s)
global PowerfishClickDelayMax := 400
global PowerfishJitter := 3          ; pixels variation per click

CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")

; --- Load config ---
LoadConfig() {
    global FishingSpotColor, ConfigPath
    global FishingRegionX1, FishingRegionY1, FishingRegionX2, FishingRegionY2, FishingIndicatorColor
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    global InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotEmptyColor
    global NavTile1Color, NavTile2Color, DepositBoxColor
    global DepositBoxOpenX1, DepositBoxOpenY1, DepositBoxOpenX2, DepositBoxOpenY2, DepositBoxOpenColor
    global FishingMode, PowerfishSlots, RunDurationMinutes
    try {
        if FileExist(ConfigPath) {
            c := IniRead(ConfigPath, "Settings", "FishingSpotColor", "")
            if (c != "")
                FishingSpotColor := "0x" c
            FishingRegionX1 := Integer(IniRead(ConfigPath, "FishingRegion", "X1", "0"))
            FishingRegionY1 := Integer(IniRead(ConfigPath, "FishingRegion", "Y1", "0"))
            FishingRegionX2 := Integer(IniRead(ConfigPath, "FishingRegion", "X2", "0"))
            FishingRegionY2 := Integer(IniRead(ConfigPath, "FishingRegion", "Y2", "0"))
            fic := IniRead(ConfigPath, "FishingRegion", "FishingIndicatorColor", "")
            if (fic != "")
                FishingIndicatorColor := "0x" fic
            PlayAreaX1 := Integer(IniRead(ConfigPath, "PlayArea", "X1", "0"))
            PlayAreaY1 := Integer(IniRead(ConfigPath, "PlayArea", "Y1", "0"))
            PlayAreaX2 := Integer(IniRead(ConfigPath, "PlayArea", "X2", "0"))
            PlayAreaY2 := Integer(IniRead(ConfigPath, "PlayArea", "Y2", "0"))
            InvSlotX1 := Integer(IniRead(ConfigPath, "InvSlot", "X1", "0"))
            InvSlotY1 := Integer(IniRead(ConfigPath, "InvSlot", "Y1", "0"))
            InvSlotX2 := Integer(IniRead(ConfigPath, "InvSlot", "X2", "0"))
            InvSlotY2 := Integer(IniRead(ConfigPath, "InvSlot", "Y2", "0"))
            ec := IniRead(ConfigPath, "InvSlot", "EmptyColor", "")
            if (ec != "")
                InvSlotEmptyColor := "0x" ec
            n1 := IniRead(ConfigPath, "Banking", "NavTile1Color", "")
            if (n1 != "")
                NavTile1Color := "0x" n1
            n2 := IniRead(ConfigPath, "Banking", "NavTile2Color", "")
            if (n2 != "")
                NavTile2Color := "0x" n2
            db := IniRead(ConfigPath, "Banking", "DepositBoxColor", "")
            if (db != "")
                DepositBoxColor := "0x" db
            DepositBoxOpenX1 := Integer(IniRead(ConfigPath, "DepositBoxOpen", "X1", "0"))
            DepositBoxOpenY1 := Integer(IniRead(ConfigPath, "DepositBoxOpen", "Y1", "0"))
            DepositBoxOpenX2 := Integer(IniRead(ConfigPath, "DepositBoxOpen", "X2", "0"))
            DepositBoxOpenY2 := Integer(IniRead(ConfigPath, "DepositBoxOpen", "Y2", "0"))
            dboc := IniRead(ConfigPath, "DepositBoxOpen", "Color", "")
            if (dboc != "")
                DepositBoxOpenColor := "0x" dboc
            mode := IniRead(ConfigPath, "Settings", "FishingMode", "Banking")
            if (mode = "Powerfishing" || mode = "Banking")
                FishingMode := mode
            PowerfishSlots := []
            try {
                count := Integer(IniRead(ConfigPath, "Powerfishing", "SlotCount", "0"))
                loop count {
                    s := IniRead(ConfigPath, "Powerfishing", "Slot" A_Index, "")
                    if (s != "") {
                        parts := StrSplit(s, ",")
                        if (parts.Length >= 2)
                            PowerfishSlots.Push([Integer(parts[1]), Integer(parts[2])])
                    }
                }
            } catch
                {}
            RunDurationMinutes := Integer(IniRead(ConfigPath, "Settings", "RunDurationMinutes", "0"))
            if (RunDurationMinutes < 0)
                RunDurationMinutes := 0
        }
    } catch {
        FishingSpotColor := ""
    }
}
LoadConfig()

; --- Status menu (small, top-right, always on top) ---
global StatusGui := ""

SetGuiText(ctrl, str) {
    try
        ctrl.Text := str
    catch
        try
            ctrl.Value := str
        catch
            {}
}

BuildStatusGui() {
    global StatusGui, RunDurationMinutes, FishingMode
    StatusGui := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox +ToolWindow")
    StatusGui.BackColor := "1e1e1e"
    StatusGui.SetFont("s9 cD0D0D0", "Segoe UI")
    StatusGui.MarginX := 12
    StatusGui.MarginY := 6
    StatusGui.Add("Text", "Section", "Fishing Bot")
    StatusGui.Add("Text", "vStatusText xs", "Paused  |  Not fishing  |  Inv: --")
    StatusGui.Add("Text", "vTimerText xs", "Time left: --")
    StatusGui.Add("Text", "xs Section", "Run (min):")
    StatusGui.Add("Edit", "vRunMinutes x+6 yp-2 w44", String(RunDurationMinutes))
    StatusGui["RunMinutes"].SetFont("cBlack")
    StatusGui.Add("Text", "x+6 yp+2", "0 = unlimited")
    modeChoice := (FishingMode = "Powerfishing") ? 2 : 1
    StatusGui.Add("Text", "xs Section y+4", "Mode:")
    StatusGui.Add("DDL", "vModeChoose x+6 yp-2 w90 Choose" modeChoice, ["Banking", "Powerfishing"])
    StatusGui["ModeChoose"].SetFont("cBlack")
    StatusGui.Add("Text", "xs Section y+8", "Configuration (set when game is ready):")
    StatusGui.Add("Text", "vSpotRow xs y+2", "[—] Fishing spot     Ctrl+Shift+C")
    StatusGui.Add("Text", "vPlayRow xs", "[—] Play area        Ctrl+Shift+B (TL)  Ctrl+Shift+N (BR)")
    StatusGui.Add("Text", "vFishingRow xs", "[—] Fishing state   Ctrl+Shift+Y (TL)  Ctrl+Shift+U (BR)  Ctrl+Shift+V (fishing color)")
    StatusGui.Add("Text", "vInvSlotRow xs", "[—] Inv slot         Ctrl+Shift+I (TL)  Ctrl+Shift+O (BR)")
    StatusGui.Add("Text", "vNav1Row xs", "[—] Nav tile 1       Ctrl+Shift+1")
    StatusGui.Add("Text", "vNav2Row xs", "[—] Nav tile 2       Ctrl+Shift+2")
    StatusGui.Add("Text", "vDepositRow xs", "[—] Deposit box      Ctrl+Shift+D")
    StatusGui.Add("Text", "vDepositOpenRow xs", "[—] Deposit open    Ctrl+Shift+E (TL)  Ctrl+Shift+R (BR)  Ctrl+Shift+F (color)")
    StatusGui.Add("Text", "vPowerfishRow xs", "[—] Powerfish slots  Ctrl+Shift+A add  Ctrl+Shift+Z clear")
    StatusGui.Add("Text", "xs y+8", "Hotkeys:")
    StatusGui.Add("Text", "vHotkeysRow xs y+2", "Start Ctrl+Shift+Q  |  Pause Ctrl+Shift+W  |  Exit Ctrl+Shift+X")
    x := A_ScreenWidth - 420
    y := 10
    StatusGui.Show("x" x " y" y " NoActivate w400")
}

UpdateStatusGui() {
    global StatusGui, IsRunning, IsFishing, IsInventoryFull, BankingStep, RunDurationMinutes, RunStartTime, ConfigPath
    global FishingSpotColor, PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    global FishingRegionX1, FishingRegionY1, FishingRegionX2, FishingRegionY2
    global InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotEmptyColor
    global NavTile1Color, NavTile2Color, DepositBoxColor
    global DepositBoxOpenX1, DepositBoxOpenY1, DepositBoxOpenX2, DepositBoxOpenY2, DepositBoxOpenColor
    global FishingMode, PowerfishSlots, BankingStep, ConfigPath
    if !StatusGui
        return
    ; Sync mode from dropdown every tick (DDL Value = 1-based index: 1=Banking, 2=Powerfishing)
    try {
        modeVal := StatusGui["ModeChoose"].Value
        if (modeVal = 2 || modeVal = "Powerfishing")
            newMode := "Powerfishing"
        else if (modeVal = 1 || modeVal = "Banking")
            newMode := "Banking"
        else
            newMode := "Banking"
        FishingMode := newMode
        ; When Powerfishing is selected, clear banking state so we never run banking steps
        if (FishingMode = "Powerfishing")
            BankingStep := 0
        try
            IniWrite(FishingMode, ConfigPath, "Settings", "FishingMode")
        catch
            {}
    } catch
        {}
    runMin := 0
    try
        runMin := Integer(StatusGui["RunMinutes"].Value)
    catch
        {}
    if (runMin < 0)
        runMin := 0
    if (IsRunning && runMin = 0 && RunDurationMinutes > 0)
        runMin := RunDurationMinutes
    if (IsRunning && runMin > 0 && RunStartTime > 0) {
        elapsedMs := A_TickCount - RunStartTime
        if (elapsedMs >= (runMin * 60000)) {
            PauseFishing()
            ToolTip("Run duration reached (" runMin " min).")
            SetTimer(() => ToolTip(), 3000)
            return
        }
        remainingMs := (runMin * 60000) - elapsedMs
        remainingSec := Max(0, Round(remainingMs / 1000))
        timerMin := remainingSec // 60
        timerSec := Mod(remainingSec, 60)
        timerStr := "Time left: " timerMin ":" (timerSec < 10 ? "0" : "") timerSec
        SetGuiText(StatusGui["TimerText"], timerStr)
    } else {
        SetGuiText(StatusGui["TimerText"], "Time left: --")
    }
    runText := IsRunning ? "Running" : "Paused"
    ; Show state: Dropping (powerfishing), Returning, Deposit box open, Banking, or Fishing
    inBanking := IsInventoryFull || (BankingStep > 0)
    if (FishingMode = "Powerfishing" && IsInventoryFull)
        fishText := "Dropping"
    else if (inBanking && BankingStep >= 7 && BankingStep <= 10)
        fishText := "Returning"
    else if (inBanking && IsDepositBoxOpen())
        fishText := "Deposit box open"
    else if (inBanking)
        fishText := "Banking"
    else
        fishText := IsFishing ? "Fishing" : "Not fishing"
    invText := (InvSlotX2 > InvSlotX1 && InvSlotY2 > InvSlotY1) ? (IsInventoryFull ? "Inv: Full" : "Inv: OK") : "Inv: --"
    SetGuiText(StatusGui["StatusText"], runText "  |  " fishText "  |  " invText)
    paX1 := 0
    paY1 := 0
    paX2 := 0
    paY2 := 0
    if FileExist(ConfigPath) {
        try {
            paX1 := Integer(IniRead(ConfigPath, "PlayArea", "X1", "0"))
            paY1 := Integer(IniRead(ConfigPath, "PlayArea", "Y1", "0"))
            paX2 := Integer(IniRead(ConfigPath, "PlayArea", "X2", "0"))
            paY2 := Integer(IniRead(ConfigPath, "PlayArea", "Y2", "0"))
        } catch
            {}
    }
    playSet := (paX2 > paX1 && paY2 > paY1)
    spotSet := (FishingSpotColor != "")
    fishSet := (FishingRegionX2 > FishingRegionX1 && FishingRegionY2 > FishingRegionY1)
    invSet := (InvSlotX2 > InvSlotX1 && InvSlotY2 > InvSlotY1 && InvSlotEmptyColor != "")
    nav1Set := (NavTile1Color != "")
    nav2Set := (NavTile2Color != "")
    depositSet := (DepositBoxColor != "")
    depositOpenSet := (DepositBoxOpenX2 > DepositBoxOpenX1 && DepositBoxOpenY2 > DepositBoxOpenY1 && DepositBoxOpenColor != "")
    st := spotSet ? "✓" : "—"
    pt := playSet ? "✓" : "—"
    ft := fishSet ? "✓" : "—"
    it := invSet ? "✓" : "—"
    n1 := nav1Set ? "✓" : "—"
    n2 := nav2Set ? "✓" : "—"
    dt := depositSet ? "✓" : "—"
    dto := depositOpenSet ? "✓" : "—"
    SetGuiText(StatusGui["SpotRow"], "[" st "] Fishing spot     Ctrl+Shift+C")
    SetGuiText(StatusGui["PlayRow"], "[" pt "] Play area        Ctrl+Shift+B (TL)  Ctrl+Shift+N (BR)")
    SetGuiText(StatusGui["FishingRow"], "[" ft "] Fishing state   Ctrl+Shift+Y (TL)  Ctrl+Shift+U (BR)  Ctrl+Shift+V (fishing color)")
    SetGuiText(StatusGui["InvSlotRow"], "[" it "] Inv slot         Ctrl+Shift+I (TL)  Ctrl+Shift+O (BR)")
    SetGuiText(StatusGui["Nav1Row"], "[" n1 "] Nav tile 1       Ctrl+Shift+1")
    SetGuiText(StatusGui["Nav2Row"], "[" n2 "] Nav tile 2       Ctrl+Shift+2")
    SetGuiText(StatusGui["DepositRow"], "[" dt "] Deposit box      Ctrl+Shift+D")
    SetGuiText(StatusGui["DepositOpenRow"], "[" dto "] Deposit open    Ctrl+Shift+E (TL)  Ctrl+Shift+R (BR)  Ctrl+Shift+F (color)")
    pfCount := PowerfishSlots.Length
    pfSt := (FishingMode = "Powerfishing" && pfCount > 0) ? "✓" : "—"
    SetGuiText(StatusGui["PowerfishRow"], "[" pfSt "] Powerfish slots (" pfCount ")  Ctrl+Shift+A add  Ctrl+Shift+Z clear")
}

; --- Play area overlay (red L-shaped corners) ---
BuildPlayAreaOverlay() {
    global PlayAreaOverlayGuis, PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2, CornerMarkSize
    for overlayWin in PlayAreaOverlayGuis {
        try
            overlayWin.Destroy()
        catch
            {}
    }
    PlayAreaOverlayGuis := []
    if (PlayAreaX2 <= PlayAreaX1 || PlayAreaY2 <= PlayAreaY1)
        return
    L := CornerMarkSize
    W := 4
    line(x, y, w, h) {
        g := Gui("+AlwaysOnTop +ToolWindow -Caption +E0x20")
        g.BackColor := "FF0000"
        g.Show("x" x " y" y " w" w " h" h " NoActivate")
        return g
    }
    PlayAreaOverlayGuis.Push(line(PlayAreaX1, PlayAreaY1, W, L))
    PlayAreaOverlayGuis.Push(line(PlayAreaX1, PlayAreaY1, L, W))
    PlayAreaOverlayGuis.Push(line(PlayAreaX2 - W, PlayAreaY1, W, L))
    PlayAreaOverlayGuis.Push(line(PlayAreaX2 - L, PlayAreaY1, L, W))
    PlayAreaOverlayGuis.Push(line(PlayAreaX1, PlayAreaY2 - L, W, L))
    PlayAreaOverlayGuis.Push(line(PlayAreaX1, PlayAreaY2 - W, L, W))
    PlayAreaOverlayGuis.Push(line(PlayAreaX2 - W, PlayAreaY2 - L, W, L))
    PlayAreaOverlayGuis.Push(line(PlayAreaX2 - L, PlayAreaY2 - W, L, W))
}

; --- Last inventory slot overlay (cyan corners) ---
BuildInvSlotOverlay() {
    global InvSlotOverlayGuis, InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotCornerSize
    for overlayWin in InvSlotOverlayGuis {
        try
            overlayWin.Destroy()
        catch
            {}
    }
    InvSlotOverlayGuis := []
    if (InvSlotX2 <= InvSlotX1 || InvSlotY2 <= InvSlotY1)
        return
    L := InvSlotCornerSize
    W := 2
    line(x, y, w, h) {
        g := Gui("+AlwaysOnTop +ToolWindow -Caption +E0x20")
        g.BackColor := "00FFFF"
        g.Show("x" x " y" y " w" w " h" h " NoActivate")
        return g
    }
    InvSlotOverlayGuis.Push(line(InvSlotX1, InvSlotY1, W, L))
    InvSlotOverlayGuis.Push(line(InvSlotX1, InvSlotY1, L, W))
    InvSlotOverlayGuis.Push(line(InvSlotX2 - W, InvSlotY1, W, L))
    InvSlotOverlayGuis.Push(line(InvSlotX2 - L, InvSlotY1, L, W))
    InvSlotOverlayGuis.Push(line(InvSlotX1, InvSlotY2 - L, W, L))
    InvSlotOverlayGuis.Push(line(InvSlotX1, InvSlotY2 - W, L, W))
    InvSlotOverlayGuis.Push(line(InvSlotX2 - W, InvSlotY2 - L, W, L))
    InvSlotOverlayGuis.Push(line(InvSlotX2 - L, InvSlotY2 - W, L, W))
}

; --- Hotkeys ---
^+q:: StartFishing()
^+w:: PauseFishing()
^+x:: ExitFishing()
^+c:: SetFishingSpotColor()         ; set fishing spot highlight color at cursor
^+y:: SetFishingRegionTopLeft()     ; set fishing state area top-left
^+u:: SetFishingRegionBottomRight() ; set fishing state area bottom-right
^+v:: SetFishingIndicatorColor()    ; set "fishing" color at cursor (green in area = fishing)
^+b:: SetPlayAreaTopLeft()
^+n:: SetPlayAreaBottomRight()
^+i:: SetInvSlotTopLeft()           ; set last inventory slot top-left
^+o:: SetInvSlotBottomRight()       ; set last inventory slot bottom-right
^+1:: SetNavTile1Color()            ; set first navigation tile color (walk to bank)
^+2:: SetNavTile2Color()            ; set second navigation tile color
^+d:: SetDepositBoxColor()          ; set deposit box color
^+e:: SetDepositBoxOpenTopLeft()    ; deposit box open area top-left
^+r:: SetDepositBoxOpenBottomRight() ; deposit box open area bottom-right
^+f:: SetDepositBoxOpenColor()     ; deposit box open color (at cursor)
^+a:: AddPowerfishSlot()          ; add current mouse pos to powerfish slot list (max 27)
^+z:: ClearPowerfishSlots()       ; clear all powerfish slot positions

; --- Start ---
StartFishing() {
    global FishingSpotColor, IsRunning, RunDurationMinutes, RunStartTime, StatusGui, ConfigPath
    if (FishingSpotColor = "") {
        MsgBox("No fishing spot color set. Move cursor over the fishing spot highlight and press Ctrl+Shift+C.", "Fishing Bot", "Icon!")
        return
    }
    if IsRunning
        return
    runMinVal := 0
    try
        runMinVal := Integer(StatusGui["RunMinutes"].Value)
    catch
        runMinVal := RunDurationMinutes
    if (runMinVal < 0)
        runMinVal := 0
    RunDurationMinutes := runMinVal
    try
        IniWrite(String(RunDurationMinutes), ConfigPath, "Settings", "RunDurationMinutes")
    catch
        {}
    RunStartTime := A_TickCount
    IsRunning := true
    SetTimer(UpdateFishingState, FishingCheckInterval)
    SetTimer(DoFishingOrBanking, FishInterval)
    if (RunDurationMinutes > 0)
        UpdateStatusGui()
    ToolTip("Fishing bot: Running" (RunDurationMinutes > 0 ? " (" RunDurationMinutes " min)" : ""))
    SetTimer(() => ToolTip(), 2000)
}

; --- Pause ---
PauseFishing() {
    global IsRunning, RunStartTime
    IsRunning := false
    RunStartTime := 0
    SetTimer(UpdateFishingState, 0)
    SetTimer(DoFishingOrBanking, 0)
    ToolTip("Fishing bot: Paused")
    SetTimer(() => ToolTip(), 2000)
}

; --- Quit ---
ExitFishing() {
    global IsRunning
    IsRunning := false
    SetTimer(UpdateFishingState, 0)
    SetTimer(DoFishingOrBanking, 0)
    ToolTip()
    ExitApp()
}

; --- Set fishing spot color at cursor ---
SetFishingSpotColor() {
    global FishingSpotColor, ConfigPath
    MouseGetPos(&mx, &my)
    FishingSpotColor := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(FishingSpotColor, 3), ConfigPath, "Settings", "FishingSpotColor")
    catch
        {}
    ToolTip("Fishing spot color set: " FishingSpotColor)
    SetTimer(() => ToolTip(), 2000)
}

; --- Set navigation tile and deposit box colors at cursor (color only; we search for it each time so moving tiles work) ---
SetNavTile1Color() {
    global NavTile1Color, ConfigPath
    MouseGetPos(&mx, &my)
    NavTile1Color := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(NavTile1Color, 3), ConfigPath, "Banking", "NavTile1Color")
    catch
        {}
    ToolTip("Nav tile 1 color set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetNavTile2Color() {
    global NavTile2Color, ConfigPath
    MouseGetPos(&mx, &my)
    NavTile2Color := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(NavTile2Color, 3), ConfigPath, "Banking", "NavTile2Color")
    catch
        {}
    ToolTip("Nav tile 2 color set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetDepositBoxColor() {
    global DepositBoxColor, ConfigPath
    MouseGetPos(&mx, &my)
    DepositBoxColor := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(DepositBoxColor, 3), ConfigPath, "Banking", "DepositBoxColor")
    catch
        {}
    ToolTip("Deposit box color set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

; --- Deposit box open area (corners) and color; when color in area = deposit box is open ---
SetDepositBoxOpenTopLeft() {
    global DepositBoxOpenX1, DepositBoxOpenY1, ConfigPath
    MouseGetPos(&mx, &my)
    DepositBoxOpenX1 := mx
    DepositBoxOpenY1 := my
    try {
        IniWrite(String(mx), ConfigPath, "DepositBoxOpen", "X1")
        IniWrite(String(my), ConfigPath, "DepositBoxOpen", "Y1")
    } catch
        {}
    ToolTip("Deposit open area TOP-LEFT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetDepositBoxOpenBottomRight() {
    global DepositBoxOpenX2, DepositBoxOpenY2, ConfigPath
    MouseGetPos(&mx, &my)
    DepositBoxOpenX2 := mx
    DepositBoxOpenY2 := my
    try {
        IniWrite(String(mx), ConfigPath, "DepositBoxOpen", "X2")
        IniWrite(String(my), ConfigPath, "DepositBoxOpen", "Y2")
    } catch
        {}
    ToolTip("Deposit open area BOTTOM-RIGHT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetDepositBoxOpenColor() {
    global DepositBoxOpenColor, ConfigPath
    MouseGetPos(&mx, &my)
    DepositBoxOpenColor := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(DepositBoxOpenColor, 3), ConfigPath, "DepositBoxOpen", "Color")
    catch
        {}
    ToolTip("Deposit open color set at " mx "," my " (color in area = box open)")
    SetTimer(() => ToolTip(), 2000)
}

; --- Powerfishing: add/clear item slot positions for drop-all ---
AddPowerfishSlot() {
    global PowerfishSlots, ConfigPath
    if (PowerfishSlots.Length >= 27) {
        ToolTip("Powerfish slots full (27 max)")
        SetTimer(() => ToolTip(), 2000)
        return
    }
    MouseGetPos(&mx, &my)
    PowerfishSlots.Push([mx, my])
    SavePowerfishSlots()
    ToolTip("Powerfish slot " PowerfishSlots.Length " added at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

ClearPowerfishSlots() {
    global PowerfishSlots, ConfigPath
    PowerfishSlots := []
    SavePowerfishSlots()
    ToolTip("Powerfish slots cleared")
    SetTimer(() => ToolTip(), 2000)
}

SavePowerfishSlots() {
    global PowerfishSlots, ConfigPath
    try {
        IniWrite(String(PowerfishSlots.Length), ConfigPath, "Powerfishing", "SlotCount")
        loop PowerfishSlots.Length {
            pt := PowerfishSlots[A_Index]
            IniWrite(pt[1] "," pt[2], ConfigPath, "Powerfishing", "Slot" A_Index)
        }
    } catch
        {}
}

; Returns true if deposit box open area + color are set and the color is found in the area
IsDepositBoxOpen() {
    global DepositBoxOpenX1, DepositBoxOpenY1, DepositBoxOpenX2, DepositBoxOpenY2
    global DepositBoxOpenColor, DepositBoxOpenVariation
    if (DepositBoxOpenX2 <= DepositBoxOpenX1 || DepositBoxOpenY2 <= DepositBoxOpenY1 || DepositBoxOpenColor = "")
        return false
    try {
        if PixelSearch(&outX, &outY, DepositBoxOpenX1, DepositBoxOpenY1, DepositBoxOpenX2, DepositBoxOpenY2, Integer(DepositBoxOpenColor), DepositBoxOpenVariation)
            return true
    } catch
        {}
    return false
}

; Find DepositBoxOpenColor in the deposit area and click it (e.g. Deposit-all button). Returns true if found and clicked.
ClickColorInDepositArea() {
    global DepositBoxOpenX1, DepositBoxOpenY1, DepositBoxOpenX2, DepositBoxOpenY2
    global DepositBoxOpenColor, DepositBoxOpenVariation, ClickJitter, ClickDelayMs
    if (DepositBoxOpenX2 <= DepositBoxOpenX1 || DepositBoxOpenY2 <= DepositBoxOpenY1 || DepositBoxOpenColor = "")
        return false
    try {
        if PixelSearch(&outX, &outY, DepositBoxOpenX1, DepositBoxOpenY1, DepositBoxOpenX2, DepositBoxOpenY2, Integer(DepositBoxOpenColor), DepositBoxOpenVariation) {
            clickX := outX
            clickY := outY
            if (ClickJitter > 0) {
                clickX += Random(-ClickJitter, ClickJitter)
                clickY += Random(-ClickJitter, ClickJitter)
            }
            MouseMove(clickX, clickY)
            if (ClickDelayMs > 0)
                Sleep(ClickDelayMs)
            Click()
            return true
        }
    } catch
        {}
    return false
}

; --- Fishing state region: area to check for fishing indicator color (green = fishing) ---
SetFishingRegionTopLeft() {
    global FishingRegionX1, FishingRegionY1, ConfigPath
    MouseGetPos(&mx, &my)
    FishingRegionX1 := mx
    FishingRegionY1 := my
    try {
        IniWrite(String(mx), ConfigPath, "FishingRegion", "X1")
        IniWrite(String(my), ConfigPath, "FishingRegion", "Y1")
    } catch
        {}
    ToolTip("Fishing state region TOP-LEFT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildFishingRegionOverlay()
}

SetFishingRegionBottomRight() {
    global FishingRegionX2, FishingRegionY2, ConfigPath
    MouseGetPos(&mx, &my)
    FishingRegionX2 := mx
    FishingRegionY2 := my
    try {
        IniWrite(String(mx), ConfigPath, "FishingRegion", "X2")
        IniWrite(String(my), ConfigPath, "FishingRegion", "Y2")
    } catch
        {}
    ToolTip("Fishing state region BOTTOM-RIGHT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildFishingRegionOverlay()
}

SetFishingIndicatorColor() {
    global FishingIndicatorColor, ConfigPath
    MouseGetPos(&mx, &my)
    FishingIndicatorColor := PixelGetColor(mx, my, "RGB")
    try
        IniWrite(SubStr(FishingIndicatorColor, 3), ConfigPath, "FishingRegion", "FishingIndicatorColor")
    catch
        {}
    ToolTip("Fishing color set at " mx "," my " (this color in area = fishing)")
    SetTimer(() => ToolTip(), 2000)
}

; --- Draw small yellow L-shaped corner marks for fishing state region ---
BuildFishingRegionOverlay() {
    global FishingRegionOverlayGuis, FishingRegionX1, FishingRegionY1, FishingRegionX2, FishingRegionY2, FishingCornerMarkSize
    for overlayWin in FishingRegionOverlayGuis {
        try
            overlayWin.Destroy()
        catch
            {}
    }
    FishingRegionOverlayGuis := []
    if (FishingRegionX2 <= FishingRegionX1 || FishingRegionY2 <= FishingRegionY1)
        return
    L := FishingCornerMarkSize
    W := 2
    line(x, y, w, h) {
        g := Gui("+AlwaysOnTop +ToolWindow -Caption +E0x20")
        g.BackColor := "FFFF00"
        g.Show("x" x " y" y " w" w " h" h " NoActivate")
        return g
    }
    FishingRegionOverlayGuis.Push(line(FishingRegionX1, FishingRegionY1, W, L))
    FishingRegionOverlayGuis.Push(line(FishingRegionX1, FishingRegionY1, L, W))
    FishingRegionOverlayGuis.Push(line(FishingRegionX2 - W, FishingRegionY1, W, L))
    FishingRegionOverlayGuis.Push(line(FishingRegionX2 - L, FishingRegionY1, L, W))
    FishingRegionOverlayGuis.Push(line(FishingRegionX1, FishingRegionY2 - L, W, L))
    FishingRegionOverlayGuis.Push(line(FishingRegionX1, FishingRegionY2 - W, L, W))
    FishingRegionOverlayGuis.Push(line(FishingRegionX2 - W, FishingRegionY2 - L, W, L))
    FishingRegionOverlayGuis.Push(line(FishingRegionX2 - L, FishingRegionY2 - W, L, W))
}

; --- Set play area ---
SetPlayAreaTopLeft() {
    global PlayAreaX1, PlayAreaY1, ConfigPath
    MouseGetPos(&mx, &my)
    PlayAreaX1 := mx
    PlayAreaY1 := my
    try {
        IniWrite(String(mx), ConfigPath, "PlayArea", "X1")
        IniWrite(String(my), ConfigPath, "PlayArea", "Y1")
    } catch
        {}
    ToolTip("Play area TOP-LEFT set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildPlayAreaOverlay()
}

SetPlayAreaBottomRight() {
    global PlayAreaX2, PlayAreaY2, ConfigPath
    MouseGetPos(&mx, &my)
    PlayAreaX2 := mx
    PlayAreaY2 := my
    try {
        IniWrite(String(mx), ConfigPath, "PlayArea", "X2")
        IniWrite(String(my), ConfigPath, "PlayArea", "Y2")
    } catch
        {}
    ToolTip("Play area BOTTOM-RIGHT set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildPlayAreaOverlay()
}

; --- Set last inventory slot area ---
SetInvSlotTopLeft() {
    global InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotEmptyColor, ConfigPath
    MouseGetPos(&mx, &my)
    InvSlotX1 := mx
    InvSlotY1 := my
    try {
        IniWrite(String(mx), ConfigPath, "InvSlot", "X1")
        IniWrite(String(my), ConfigPath, "InvSlot", "Y1")
    } catch
        {}
    ; Auto-capture empty when area is complete (bottom-right already set)
    if (InvSlotX2 > InvSlotX1 && InvSlotY2 > InvSlotY1) {
        cx := (InvSlotX1 + InvSlotX2) // 2
        cy := (InvSlotY1 + InvSlotY2) // 2
        InvSlotEmptyColor := PixelGetColor(cx, cy, "RGB")
        try
            IniWrite(SubStr(InvSlotEmptyColor, 3), ConfigPath, "InvSlot", "EmptyColor")
        catch
            {}
    }
    ToolTip("Inv slot TOP-LEFT set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildInvSlotOverlay()
}

SetInvSlotBottomRight() {
    global InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotEmptyColor, ConfigPath
    MouseGetPos(&mx, &my)
    InvSlotX2 := mx
    InvSlotY2 := my
    try {
        IniWrite(String(mx), ConfigPath, "InvSlot", "X2")
        IniWrite(String(my), ConfigPath, "InvSlot", "Y2")
    } catch
        {}
    ; Auto-capture what empty looks like when area is set (assume slot is empty when setting)
    if (InvSlotX2 > InvSlotX1 && InvSlotY2 > InvSlotY1) {
        cx := (InvSlotX1 + InvSlotX2) // 2
        cy := (InvSlotY1 + InvSlotY2) // 2
        InvSlotEmptyColor := PixelGetColor(cx, cy, "RGB")
        try
            IniWrite(SubStr(InvSlotEmptyColor, 3), ConfigPath, "InvSlot", "EmptyColor")
        catch
            {}
    }
    ToolTip("Inv slot BOTTOM-RIGHT set at " mx "," my " (empty baseline captured)")
    SetTimer(() => ToolTip(), 2000)
    BuildInvSlotOverlay()
}

; --- Inv slot state: full when slot doesn't match empty baseline; not full when slot matches empty again ---
; Sample 5 points in slot (center + 4 corners); full if 3+ don't match empty (more robust than single pixel)
UpdateInvSlotState() {
    global IsInventoryFull, InvSlotEmptyColor, InvSlotVariation, BankingStep, BankRecaptureEmptyAt, ConfigPath
    global InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2

    if (InvSlotX2 <= InvSlotX1 || InvSlotY2 <= InvSlotY1)
        return

    ; Re-capture empty baseline a few seconds after deposit (slot should be empty then)
    if (BankRecaptureEmptyAt > 0 && A_TickCount >= BankRecaptureEmptyAt) {
        BankRecaptureEmptyAt := 0
        cx := (InvSlotX1 + InvSlotX2) // 2
        cy := (InvSlotY1 + InvSlotY2) // 2
        try {
            InvSlotEmptyColor := PixelGetColor(cx, cy, "RGB")
            IniWrite(SubStr(InvSlotEmptyColor, 3), ConfigPath, "InvSlot", "EmptyColor")
        } catch
            {}
    }

    if (InvSlotEmptyColor = "")
        return

    ; Sample 5 points: center and 4 points 1/4 from edges (more robust than center only)
    cx := (InvSlotX1 + InvSlotX2) // 2
    cy := (InvSlotY1 + InvSlotY2) // 2
    q1x := InvSlotX1 + (InvSlotX2 - InvSlotX1) // 4
    q3x := InvSlotX1 + 3 * (InvSlotX2 - InvSlotX1) // 4
    q1y := InvSlotY1 + (InvSlotY2 - InvSlotY1) // 4
    q3y := InvSlotY1 + 3 * (InvSlotY2 - InvSlotY1) // 4
    mismatch := 0
    for pt in [[cx, cy], [q1x, q1y], [q3x, q1y], [q1x, q3y], [q3x, q3y]] {
        try {
            c := PixelGetColor(pt[1], pt[2], "RGB")
            if !ColorsMatch(c, InvSlotEmptyColor, InvSlotVariation)
                mismatch++
        } catch
            {}
    }
    ; Full if 3 or more of 5 points don't match empty
    if (mismatch >= 3) {
        IsInventoryFull := true
    } else {
        IsInventoryFull := false
        ; Do NOT set BankingStep := 0 here – we may be in returning (steps 7–10). Only TryBankWhenFull clears it after step 10.
    }
}

; --- Fishing state: if vibrant green (or set "fishing" color) exists in area = fishing; else = not fishing ---
UpdateFishingState() {
    global IsFishing, FishingRegionX1, FishingRegionY1, FishingRegionX2, FishingRegionY2
    global FishingIndicatorColor, FishingIndicatorVariation

    if (FishingRegionX2 <= FishingRegionX1 || FishingRegionY2 <= FishingRegionY1)
        return

    colorToFind := (FishingIndicatorColor != "") ? FishingIndicatorColor : "0x00FF00"
    try {
        ; If this color exists in the region = fishing (e.g. green fishing indicator)
        if PixelSearch(&outX, &outY, FishingRegionX1, FishingRegionY1, FishingRegionX2, FishingRegionY2, Integer(colorToFind), FishingIndicatorVariation)
            IsFishing := true
        else
            IsFishing := false
    } catch {
        IsFishing := false
    }
}

; --- Find image in play area and click offset from top-left; for marked tiles (outline/shaded). Returns true if found ---
; Put nav1.png, nav2.png, deposit.png in script folder; *50 = color variation for ImageSearch
; Searches only within play area (same as fishing/nav color); if play area not set, uses full screen
FindAndClickImage(imagePath, offsetPx := 15) {
    global ClickDelayMs, BankingImageOffset, PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    if (imagePath = "" || !FileExist(imagePath))
        return false
    x1 := PlayAreaX1
    y1 := PlayAreaY1
    x2 := PlayAreaX2
    y2 := PlayAreaY2
    if (x2 <= x1 || y2 <= y1) {
        x1 := 0
        y1 := 0
        x2 := A_ScreenWidth
        y2 := A_ScreenHeight
    }
    try {
        if ImageSearch(&foundX, &foundY, x1, y1, x2, y2, "*50 " imagePath) {
            clickX := foundX + offsetPx
            clickY := foundY + offsetPx
            clickX := Max(x1, Min(x2, clickX))
            clickY := Max(y1, Min(y2, clickY))
            MouseMove(clickX, clickY)
            if (ClickDelayMs > 0)
                Sleep(ClickDelayMs)
            Click()
            return true
        }
    } catch
        {}
    return false
}

; --- Swap R and B for 0xRRGGBB (OSRS/client may use BGR) ---
SwapColorBGR(c) {
    c := Integer(c)
    return "0x" Format("{:06X}", ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF))
}

; --- Find color in area and click center of matching region; returns true if found and clicked ---
; No coordinates stored: we PixelSearch for the color each time (so moving targets like nav tiles work).
; useFullScreen=true: search full screen; false = search play area only.
; useCentroid=true (fishing spot only): sample all matching pixels in a tile-sized window and click their centroid (tile center, not border).
FindAndClickColor(targetColor, colorVariation, useFullScreen := false, useCentroid := false) {
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    global RadiusStep, ClickJitter, ClickDelayMs, BoundsScanStep, BoundsMaxDist
    global FishSpotCentroidRadius, FishSpotCentroidStep
    if (targetColor = "")
        return false
    if (useFullScreen) {
        paX1 := 0
        paY1 := 0
        paX2 := A_ScreenWidth
        paY2 := A_ScreenHeight
    } else {
        paX1 := PlayAreaX1
        paY1 := PlayAreaY1
        paX2 := PlayAreaX2
        paY2 := PlayAreaY2
        if (paX2 <= paX1 || paY2 <= paY1) {
            paX1 := 0
            paY1 := 0
            paX2 := A_ScreenWidth
            paY2 := A_ScreenHeight
        }
    }
    cx := (paX1 + paX2) // 2
    cy := (paY1 + paY2) // 2
    radius := 0
    maxR := Max(paX2 - paX1, paY2 - paY1) // 2 + RadiusStep
    foundX := 0
    foundY := 0
    while (radius <= maxR) {
        x1 := Max(paX1, cx - radius)
        y1 := Max(paY1, cy - radius)
        x2 := Min(paX2, cx + radius)
        y2 := Min(paY2, cy + radius)
        if PixelSearch(&foundX, &foundY, x1, y1, x2, y2, Integer(targetColor), colorVariation)
            break
        radius += RadiusStep
    }
    if (radius > maxR)
        return false

    ; When useCentroid (fishing spot): sample all matching pixels in a tile-sized window; click their centroid = tile center
    if (useCentroid) {
        x1 := Max(paX1, foundX - FishSpotCentroidRadius)
        y1 := Max(paY1, foundY - FishSpotCentroidRadius)
        x2 := Min(paX2, foundX + FishSpotCentroidRadius)
        y2 := Min(paY2, foundY + FishSpotCentroidRadius)
        sumX := 0
        sumY := 0
        count := 0
        y := y1
        while (y <= y2) {
            x := x1
            while (x <= x2) {
                try {
                    if ColorsMatch(PixelGetColor(x, y, "RGB"), targetColor, colorVariation) {
                        sumX += x
                        sumY += y
                        count++
                    }
                } catch
                    {}
                x += FishSpotCentroidStep
            }
            y += FishSpotCentroidStep
        }
        if (count > 0) {
            clickX := sumX // count
            clickY := sumY // count
        } else {
            clickX := foundX
            clickY := foundY
        }
    } else {
        ; Original: expand bbox along cross from first hit, click bbox center
        minX := foundX
        maxX := foundX
        minY := foundY
        maxY := foundY
        limitL := Max(paX1, foundX - BoundsMaxDist)
        limitR := Min(paX2, foundX + BoundsMaxDist)
        limitT := Max(paY1, foundY - BoundsMaxDist)
        limitB := Min(paY2, foundY + BoundsMaxDist)
        x := foundX - BoundsScanStep
        while (x >= limitL) {
            try {
                if ColorsMatch(PixelGetColor(x, foundY, "RGB"), targetColor, colorVariation)
                    minX := x
                else
                    break
            } catch
                break
            x -= BoundsScanStep
        }
        x := foundX + BoundsScanStep
        while (x <= limitR) {
            try {
                if ColorsMatch(PixelGetColor(x, foundY, "RGB"), targetColor, colorVariation)
                    maxX := x
                else
                    break
            } catch
                break
            x += BoundsScanStep
        }
        y := foundY - BoundsScanStep
        while (y >= limitT) {
            try {
                if ColorsMatch(PixelGetColor(foundX, y, "RGB"), targetColor, colorVariation)
                    minY := y
                else
                    break
            } catch
                break
            y -= BoundsScanStep
        }
        y := foundY + BoundsScanStep
        while (y <= limitB) {
            try {
                if ColorsMatch(PixelGetColor(foundX, y, "RGB"), targetColor, colorVariation)
                    maxY := y
                else
                    break
            } catch
                break
            y += BoundsScanStep
        }
        clickX := (minX + maxX) // 2
        clickY := (minY + maxY) // 2
    }
    if (ClickJitter > 0) {
        clickX += Random(-ClickJitter, ClickJitter)
        clickY += Random(-ClickJitter, ClickJitter)
    }
    clickX := Max(paX1, Min(paX2, clickX))
    clickY := Max(paY1, Min(paY2, clickY))
    MouseMove(clickX, clickY)
    if (ClickDelayMs > 0)
        Sleep(ClickDelayMs)
    Click()
    return true
}

; --- When running: if full do banking or powerfish drop; else try to fish ---
DoFishingOrBanking() {
    global FishingMode
    ; Banking: run when full or mid-return (BankingStep > 0). Powerfishing: run ONLY when full.
    ; When Powerfishing we never run banking; when Banking we run until return is done.
    runBanking := (FishingMode = "Banking") && (IsInventoryFull || BankingStep > 0)
    runPowerfish := (FishingMode = "Powerfishing") && IsInventoryFull
    if (runBanking) {
        TryBankWhenFull()
        SetTimer(DoFishingOrBanking, 1000)
    } else if (runPowerfish) {
        TryPowerfishWhenFull()
        SetTimer(DoFishingOrBanking, 1000)
    } else {
        TryFishWhenNotFishing()
        SetTimer(DoFishingOrBanking, FishInterval)
    }
}

; --- Powerfishing: shift+click each item slot with jitter and delay, then back to fishing ---
TryPowerfishWhenFull() {
    global PowerfishSlots, PowerfishLastDropAt, PowerfishDropCooldownMs
    global PowerfishClickDelayMin, PowerfishClickDelayMax, PowerfishJitter
    if (PowerfishSlots.Length = 0) {
        ToolTip("Powerfishing: Add slot positions (Ctrl+Shift+A). Clear with Ctrl+Shift+Z.")
        SetTimer(() => ToolTip(), 4000)
        return
    }
    if (A_TickCount - PowerfishLastDropAt < PowerfishDropCooldownMs)
        return
    for slot in PowerfishSlots {
        jx := slot[1] + Random(-PowerfishJitter, PowerfishJitter)
        jy := slot[2] + Random(-PowerfishJitter, PowerfishJitter)
        MouseMove(jx, jy)
        Send("{Shift down}")
        Sleep(80)   ; hold shift long enough for game to register before click
        Click()
        Sleep(50)   ; keep shift held briefly after click so it registers as shift+click
        Send("{Shift up}")
        Sleep(Random(PowerfishClickDelayMin, PowerfishClickDelayMax))
    }
    PowerfishLastDropAt := A_TickCount
}

; --- Banking mode: nav1 -> wait 3–5 s -> nav2 -> wait 3–5 s -> deposit -> wait 5–7 s -> done ---
; Tries image first (nav1.png, nav2.png, deposit.png in script folder), then color, then BGR color
TryBankWhenFull() {
    global BankingStep, BankWaitUntil, BankNavWaitMin, BankNavWaitMax
    global BankDepositBoxOpenWaitMin, BankDepositBoxOpenWaitMax
    global BankDepositWaitMin, BankDepositWaitMax, BankRecaptureEmptyAt
    global BankDepositAreaLastClickAt, BankDepositAreaClickCooldownMs
    global NavTile1Color, NavTile2Color, DepositBoxColor, BankingColorVariation, BankingNavColorVariation, BankingImageOffset
    global DepositBoxOpenX1, DepositBoxOpenY1, DepositBoxOpenX2, DepositBoxOpenY2, DepositBoxOpenColor
    if (BankingStep = 0)
        BankingStep := 1
    if (BankingStep = 1) {
        path1 := A_ScriptDir "\nav1.png"
        ok := FindAndClickImage(path1, BankingImageOffset)
        if (!ok && NavTile1Color != "")
            ok := FindAndClickColor(NavTile1Color, BankingNavColorVariation, false, true)
        if (!ok && NavTile1Color != "")
            ok := FindAndClickColor(SwapColorBGR(NavTile1Color), BankingNavColorVariation, false, true)
        if (ok) {
            BankingStep := 2
            BankWaitUntil := A_TickCount + Random(BankNavWaitMin, BankNavWaitMax)
        } else if (NavTile1Color = "" && !FileExist(path1))
            ToolTip("Banking: Set nav tile 1 (Ctrl+Shift+1) or add nav1.png")
        else
            ToolTip("Nav 1: no match – add nav1.png (screenshot tile) or raise BankingNavColorVariation")
        if (!ok)
            SetTimer(() => ToolTip(), 4000)
        return
    }
    if (BankingStep = 2) {
        if (A_TickCount >= BankWaitUntil)
            BankingStep := 3
        return
    }
    if (BankingStep = 3) {
        path2 := A_ScriptDir "\nav2.png"
        ok := FindAndClickImage(path2, BankingImageOffset)
        if (!ok && NavTile2Color != "")
            ok := FindAndClickColor(NavTile2Color, BankingNavColorVariation, false, true)
        if (!ok && NavTile2Color != "")
            ok := FindAndClickColor(SwapColorBGR(NavTile2Color), BankingNavColorVariation, false, true)
        if (ok) {
            BankingStep := 4
            BankWaitUntil := A_TickCount + Random(BankNavWaitMin, BankNavWaitMax)
        } else if (NavTile2Color = "" && !FileExist(path2))
            ToolTip("Banking: Set nav tile 2 (Ctrl+Shift+2) or add nav2.png")
        else
            ToolTip("Nav 2: no match – add nav2.png or raise BankingNavColorVariation")
        if (!ok)
            SetTimer(() => ToolTip(), 4000)
        return
    }
    if (BankingStep = 4) {
        if (A_TickCount >= BankWaitUntil)
            BankingStep := 5
        return
    }
    if (BankingStep = 5) {
        pathD := A_ScriptDir "\deposit.png"
        ok := FindAndClickImage(pathD, BankingImageOffset)
        if (!ok && DepositBoxColor != "")
            ok := FindAndClickColor(DepositBoxColor, BankingColorVariation, false)
        if (!ok && DepositBoxColor != "")
            ok := FindAndClickColor(SwapColorBGR(DepositBoxColor), BankingColorVariation, false)
        if (ok) {
            ; If deposit box open detection is set, wait for open (or 5s timeout) before starting deposit-done timer
            if (DepositBoxOpenX2 > DepositBoxOpenX1 && DepositBoxOpenY2 > DepositBoxOpenY1 && DepositBoxOpenColor != "") {
                BankingStep := 55
                BankWaitUntil := A_TickCount + Random(BankDepositBoxOpenWaitMin, BankDepositBoxOpenWaitMax)
            } else {
                BankingStep := 6
                BankWaitUntil := A_TickCount + Random(BankDepositWaitMin, BankDepositWaitMax)
            }
        } else if (DepositBoxColor = "" && !FileExist(pathD))
            ToolTip("Banking: Set deposit box (Ctrl+Shift+D) or add deposit.png")
        else
            ToolTip("Deposit: no match – add deposit.png or raise BankingColorVariation")
        if (!ok)
            SetTimer(() => ToolTip(), 4000)
        return
    }
    if (BankingStep = 55) {
        ; Wait for deposit box open (color in area) or 5 s timeout
        if (IsDepositBoxOpen()) {
            ; Box is open: click the color in the deposit area (e.g. Deposit-all)
            if (ClickColorInDepositArea()) {
                BankDepositAreaLastClickAt := A_TickCount
                BankingStep := 6
                BankWaitUntil := A_TickCount + BankDepositClosedTimeout
            }
        } else if (A_TickCount >= BankWaitUntil) {
            ; Timeout and box still not open: go back to step 5 to retry clicking deposit box
            BankingStep := 5
        }
        return
    }
    if (BankingStep = 6) {
        ; Deposited = set color no longer in deposit area (box closed). If color persists, click again (other fish types).
        depositOpenSet := (DepositBoxOpenX2 > DepositBoxOpenX1 && DepositBoxOpenY2 > DepositBoxOpenY1 && DepositBoxOpenColor != "")
        if (depositOpenSet) {
            if (!IsDepositBoxOpen() || A_TickCount >= BankWaitUntil)
                BankingStep := 7
            else if (A_TickCount - BankDepositAreaLastClickAt >= BankDepositAreaClickCooldownMs) {
                ; Color still there = deposit box still open (e.g. other fish types); click deposit area again
                if (ClickColorInDepositArea())
                    BankDepositAreaLastClickAt := A_TickCount
            }
        } else {
            if (A_TickCount >= BankWaitUntil)
                BankingStep := 7
        }
        return
    }
    if (BankingStep = 7) {
        ; Returning: click nav 2, then wait 7–9 s, then nav 1, wait 2–3 s, then fishing
        path2 := A_ScriptDir "\nav2.png"
        ok := FindAndClickImage(path2, BankingImageOffset)
        if (!ok && NavTile2Color != "")
            ok := FindAndClickColor(NavTile2Color, BankingNavColorVariation, false, true)
        if (!ok && NavTile2Color != "")
            ok := FindAndClickColor(SwapColorBGR(NavTile2Color), BankingNavColorVariation, false, true)
        if (ok) {
            BankingStep := 8
            BankWaitUntil := A_TickCount + Random(BankReturnNav2WaitMin, BankReturnNav2WaitMax)
        } else
            ToolTip("Returning: nav 2 not found – check tile or add nav2.png")
        if (!ok)
            SetTimer(() => ToolTip(), 4000)
        return
    }
    if (BankingStep = 8) {
        if (A_TickCount >= BankWaitUntil)
            BankingStep := 9
        return
    }
    if (BankingStep = 9) {
        ; Click nav 1 (back to fishing spot), then wait 2–3 s and return to fishing
        path1 := A_ScriptDir "\nav1.png"
        ok := FindAndClickImage(path1, BankingImageOffset)
        if (!ok && NavTile1Color != "")
            ok := FindAndClickColor(NavTile1Color, BankingNavColorVariation, false, true)
        if (!ok && NavTile1Color != "")
            ok := FindAndClickColor(SwapColorBGR(NavTile1Color), BankingNavColorVariation, false, true)
        if (ok) {
            BankingStep := 10
            BankWaitUntil := A_TickCount + Random(BankReturnNav1WaitMin, BankReturnNav1WaitMax)
        } else
            ToolTip("Returning: nav 1 not found – check tile or add nav1.png")
        if (!ok)
            SetTimer(() => ToolTip(), 4000)
        return
    }
    if (BankingStep = 10) {
        if (A_TickCount >= BankWaitUntil) {
            BankingStep := 0
            BankRecaptureEmptyAt := A_TickCount + 2500
        }
        return
    }
}

; --- When not fishing and not full: find fishing spot and click (only inside play area) ---
TryFishWhenNotFishing() {
    global IsFishing, FishingSpotColor, ColorVariation
    global LastFishClickTime, LastFishClickCooldownMs, FishClickCooldownMin, FishClickCooldownMax
    if IsFishing || (FishingSpotColor = "")
        return
    if IsInventoryFull
        return
    ; After clicking a fishing spot, wait 5–10 s before clicking again (does not affect other clicks)
    if (LastFishClickTime > 0 && (A_TickCount - LastFishClickTime) < LastFishClickCooldownMs)
        return
    if FindAndClickColor(FishingSpotColor, ColorVariation, false, true) {
        LastFishClickTime := A_TickCount
        LastFishClickCooldownMs := Random(FishClickCooldownMin, FishClickCooldownMax)
    }
}

ColorsMatch(c1, c2, variation) {
    c1 := Integer(c1)
    c2 := Integer(c2)
    r1 := (c1 >> 16) & 0xFF
    g1 := (c1 >> 8) & 0xFF
    b1 := c1 & 0xFF
    r2 := (c2 >> 16) & 0xFF
    g2 := (c2 >> 8) & 0xFF
    b2 := c2 & 0xFF
    return (Abs(r1 - r2) <= variation && Abs(g1 - g2) <= variation && Abs(b1 - b2) <= variation)
}

; --- Build overlays and start status timer ---
BuildStatusGui()
BuildPlayAreaOverlay()
BuildFishingRegionOverlay()
BuildInvSlotOverlay()
SetTimer(UpdateStatusGui, 500)
SetTimer(UpdateInvSlotState, InvSlotCheckInterval)
UpdateStatusGui()
