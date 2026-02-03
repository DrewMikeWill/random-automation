#Requires AutoHotkey v2.0

; --- State ---
global IsRunning := false
global ConfigPath := A_ScriptDir "\Cook.ini"

; Bank
global BankColor := ""             ; 0xRRGGBB, set with Ctrl+Shift+B
global BankColorVariation := 5

; Withdraw: area (click anywhere to withdraw). Multi-pixel look learned when you start with bank open; used to detect bank open on return.
global WithdrawAreaX1 := 0
global WithdrawAreaY1 := 0
global WithdrawAreaX2 := 0
global WithdrawAreaY2 := 0
global WithdrawAreaSamples := []   ; array of {x, y, color} — area must look the same (multiple pixels) to be "bank open"
global WithdrawVariation := 15

; Cooking status: area + color (color in area = we are cooking)
global CookingStatusX1 := 0
global CookingStatusY1 := 0
global CookingStatusX2 := 0
global CookingStatusY2 := 0
global CookingStatusColor := ""
global CookingStatusVariation := 15

; Fire tile (click to run to fire / click fire)
global FireTileColor := ""
global FireColorVariation := 5

; Last inventory slot: area + empty baseline + raw color. Empty=withdrew; raw=color present=need to cook; cooked=not empty and raw color gone
global InvSlotX1 := 0
global InvSlotY1 := 0
global InvSlotX2 := 0
global InvSlotY2 := 0
global InvSlotEmptyColor := ""     ; auto-captured when area set (slot empty)
global InvSlotRawColor := ""      ; raw food in slot (set with Ctrl+Shift+A)
global InvSlotVariation := 15
global InvSlotOverlayGuis := []
global InvSlotCornerSize := 8

; Deposit all: area (click anywhere to deposit). Multi-pixel look learned when you start with bank open; used to detect bank open on return.
global DepositAllX1 := 0
global DepositAllY1 := 0
global DepositAllX2 := 0
global DepositAllY2 := 0
global DepositAllAreaSamples := []   ; array of {x, y, color} — area must look the same (multiple pixels) to be "bank open"
global DepositAllVariation := 15

; Run duration
global RunDurationMinutes := 0
global RunStartTime := 0

; Flow: 0=idle, 1=click bank wait 9-11s, 2=at bank (deposit all then withdraw), 3=withdraw until full, 4=click fire wait 9-11s, 5=space wait, 6=check cooking status, 7=cooking until done, 8=click bank wait 9-11s
global CookStep := 0
global CookWaitUntil := 0
global CookStep3SawEmpty := false   ; true after we see empty slot in step 3 (so we don't treat stale "raw" as full)
global CookRestartingCooking := false   ; true when step 7 sent us to step 4 (already at fire, short wait before Space)
global CookBankClickTime := 0       ; when we clicked bank (step 1 or 8); don't check bank-open until min wait has passed
global CookPendingDeposit := false ; true after we see bank open; wait 0.5-2s (human-like) before clicking deposit
global CookJustStarted := false    ; true when Start was pressed; step 2 will update withdraw/deposit area samples then proceed
global CookStatusAction := ""       ; short phrase shown in GUI: "Click withdraw", "Wait bank open", etc.
global CookDebugLine := ""         ; debug: Step=N Inv=empty sawEmpty=0
global BankOpenWaitMin := 9000
global BankOpenWaitMax := 11000
global SpaceWaitMin := 2000
global SpaceWaitMax := 3500
global CookingStatusCheckMs := 3000
global CookCentroidRadius := 28
global CookCentroidStep := 4
global ClickJitter := 2
global ClickDelayMs := 35
global RadiusStep := 120
global BoundsScanStep := 2
global BoundsMaxDist := 50

; Play area – only search/click inside this rect (0,0,0,0 = full screen)
global PlayAreaX1 := 0
global PlayAreaY1 := 0
global PlayAreaX2 := 0
global PlayAreaY2 := 0
global PlayAreaOverlayGuis := []
global PlayAreaCornerSize := 30

; Last slot state: "empty" | "raw" | "cooked"
global InvSlotState := "empty"
global InvSlotCheckInterval := 800

; Cooking status: sample for "did it update" (we store previous and compare)
global LastCookingStatusSample := Map()
global CookingStatusSampleStep := 4

CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")

; --- Load config ---
LoadConfig() {
    global ConfigPath
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    global BankColor, WithdrawAreaX1, WithdrawAreaY1, WithdrawAreaX2, WithdrawAreaY2, WithdrawAreaSamples
    global CookingStatusX1, CookingStatusY1, CookingStatusX2, CookingStatusY2, CookingStatusColor
    global FireTileColor, InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotEmptyColor, InvSlotRawColor
    global DepositAllX1, DepositAllY1, DepositAllX2, DepositAllY2, DepositAllAreaSamples, RunDurationMinutes
    try {
        if FileExist(ConfigPath) {
            PlayAreaX1 := Integer(IniRead(ConfigPath, "PlayArea", "X1", "0"))
            PlayAreaY1 := Integer(IniRead(ConfigPath, "PlayArea", "Y1", "0"))
            PlayAreaX2 := Integer(IniRead(ConfigPath, "PlayArea", "X2", "0"))
            PlayAreaY2 := Integer(IniRead(ConfigPath, "PlayArea", "Y2", "0"))
            bc := IniRead(ConfigPath, "Bank", "Color", "")
            if (bc != "") BankColor := "0x" bc
            WithdrawAreaX1 := Integer(IniRead(ConfigPath, "Withdraw", "X1", "0"))
            WithdrawAreaY1 := Integer(IniRead(ConfigPath, "Withdraw", "Y1", "0"))
            WithdrawAreaX2 := Integer(IniRead(ConfigPath, "Withdraw", "X2", "0"))
            WithdrawAreaY2 := Integer(IniRead(ConfigPath, "Withdraw", "Y2", "0"))
            WithdrawAreaSamples := []
            wcnt := Integer(IniRead(ConfigPath, "Withdraw", "SampleCount", "0"))
            loop wcnt
            {
                i := A_Index
                wx := Integer(IniRead(ConfigPath, "Withdraw", "Sample" i "X", "0"))
                wy := Integer(IniRead(ConfigPath, "Withdraw", "Sample" i "Y", "0"))
                wc := IniRead(ConfigPath, "Withdraw", "Sample" i "Color", "")
                if (wc != "") {
                    WithdrawAreaSamples.Push( { x: wx, y: wy, color: "0x" wc } )
                }
            }
            CookingStatusX1 := Integer(IniRead(ConfigPath, "CookingStatus", "X1", "0"))
            CookingStatusY1 := Integer(IniRead(ConfigPath, "CookingStatus", "Y1", "0"))
            CookingStatusX2 := Integer(IniRead(ConfigPath, "CookingStatus", "X2", "0"))
            CookingStatusY2 := Integer(IniRead(ConfigPath, "CookingStatus", "Y2", "0"))
            csc := IniRead(ConfigPath, "CookingStatus", "Color", "")
            if (csc != "") CookingStatusColor := "0x" csc
            fc := IniRead(ConfigPath, "Fire", "Color", "")
            if (fc != "") FireTileColor := "0x" fc
            InvSlotX1 := Integer(IniRead(ConfigPath, "InvSlot", "X1", "0"))
            InvSlotY1 := Integer(IniRead(ConfigPath, "InvSlot", "Y1", "0"))
            InvSlotX2 := Integer(IniRead(ConfigPath, "InvSlot", "X2", "0"))
            InvSlotY2 := Integer(IniRead(ConfigPath, "InvSlot", "Y2", "0"))
            ec := IniRead(ConfigPath, "InvSlot", "EmptyColor", "")
            if (ec != "") InvSlotEmptyColor := "0x" ec
            rc := IniRead(ConfigPath, "InvSlot", "RawColor", "")
            if (rc != "") InvSlotRawColor := "0x" rc
            DepositAllX1 := Integer(IniRead(ConfigPath, "DepositAll", "X1", "0"))
            DepositAllY1 := Integer(IniRead(ConfigPath, "DepositAll", "Y1", "0"))
            DepositAllX2 := Integer(IniRead(ConfigPath, "DepositAll", "X2", "0"))
            DepositAllY2 := Integer(IniRead(ConfigPath, "DepositAll", "Y2", "0"))
            DepositAllAreaSamples := []
            dcnt := Integer(IniRead(ConfigPath, "DepositAll", "SampleCount", "0"))
            loop dcnt
            {
                i := A_Index
                dx := Integer(IniRead(ConfigPath, "DepositAll", "Sample" i "X", "0"))
                dy := Integer(IniRead(ConfigPath, "DepositAll", "Sample" i "Y", "0"))
                dc := IniRead(ConfigPath, "DepositAll", "Sample" i "Color", "")
                if (dc != "") {
                    DepositAllAreaSamples.Push( { x: dx, y: dy, color: "0x" dc } )
                }
            }
            RunDurationMinutes := Integer(IniRead(ConfigPath, "Settings", "RunDurationMinutes", "0"))
            if (RunDurationMinutes < 0)
                RunDurationMinutes := 0
        }
    }
    catch as err {
        ; ignore load errors
    }
}
LoadConfig()

; --- Status GUI ---
global StatusGui := ""

SetGuiText(ctrl, str) {
    try
        ctrl.Text := str
    catch {
        try
            ctrl.Value := str
        catch {
        }
    }
}

BuildStatusGui() {
    global StatusGui, RunDurationMinutes
    StatusGui := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox +ToolWindow")
    StatusGui.BackColor := "1e1e1e"
    StatusGui.SetFont("s9 cD0D0D0", "Segoe UI")
    StatusGui.MarginX := 12
    StatusGui.MarginY := 6
    StatusGui.Add("Text", "Section", "Cooking Bot")
    StatusGui.Add("Text", "vStatusText xs", "Paused  |  Idle")
    StatusGui.Add("Edit", "vActionText xs ReadOnly r1 w470 Background1e1e1e", "Action: —")
    StatusGui["ActionText"].SetFont("cA0D0A0")
    StatusGui.Add("Edit", "vDebugText xs ReadOnly r1 w470 Background1e1e1e", "Debug: —")
    StatusGui["DebugText"].SetFont("c808080")
    StatusGui.Add("Text", "vTimerText xs", "Time left: --")
    StatusGui.Add("Text", "xs Section", "Run (min):")
    StatusGui.Add("Edit", "vRunMinutes x+6 yp-2 w44", String(RunDurationMinutes))
    StatusGui["RunMinutes"].SetFont("cBlack")
    StatusGui.Add("Text", "x+6 yp+2", "0 = unlimited")
    StatusGui.Add("Text", "xs Section y+8", "Configuration:")
    StatusGui.Add("Text", "vPlayAreaRow xs y+2", "[—] Play area       Ctrl+Shift+P (TL)  Ctrl+Shift+L (BR)")
    StatusGui.Add("Text", "vBankRow xs", "[—] Bank             Ctrl+Shift+B")
    StatusGui.Add("Text", "vWithdrawRow xs", "[—] Withdraw area    Ctrl+Shift+J (TL)  Ctrl+Shift+K (BR)")
    StatusGui.Add("Text", "vCookingRow xs", "[—] Cooking status   Ctrl+Shift+Y (TL)  Ctrl+Shift+U (BR)  Ctrl+Shift+V (color)")
    StatusGui.Add("Text", "vFireRow xs", "[—] Fire tile         Ctrl+Shift+F")
    StatusGui.Add("Text", "vInvRow xs", "[—] Last inv slot     Ctrl+Shift+I (TL)  Ctrl+Shift+O (BR)  Ctrl+Shift+A (raw color)")
    StatusGui.Add("Text", "vDepositRow xs", "[—] Deposit all      Ctrl+Shift+D (TL)  Ctrl+Shift+N (BR)")
    StatusGui.Add("Text", "xs y+8", "Hotkeys:")
    StatusGui.Add("Text", "vHotkeysRow xs y+2", "Start Ctrl+Shift+Q  |  Pause Ctrl+Shift+W  |  Exit Ctrl+Shift+X")
    StatusGui.Show("x" (A_ScreenWidth - 520) " y10 NoActivate w500")
}

UpdateStatusGui() {
    global StatusGui, IsRunning, CookStep, RunDurationMinutes, RunStartTime, ConfigPath
    global CookWaitUntil, InvSlotState, CookStep3SawEmpty
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    global BankColor, WithdrawAreaX1, WithdrawAreaY1, WithdrawAreaX2, WithdrawAreaY2, WithdrawAreaSamples
    global CookingStatusX1, CookingStatusY1, CookingStatusX2, CookingStatusY2, CookingStatusColor
    global FireTileColor, InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotEmptyColor, InvSlotRawColor
    global DepositAllX1, DepositAllY1, DepositAllX2, DepositAllY2, DepositAllAreaSamples
    if !StatusGui
        return
    try {
        runMin := Integer(StatusGui["RunMinutes"].Value)
        if (runMin < 0) runMin := 0
        if (IsRunning && runMin > 0 && RunStartTime > 0) {
            elapsed := A_TickCount - RunStartTime
            if (elapsed >= runMin * 60000) {
                PauseCooking()
                ToolTip("Run duration reached (" runMin " min).")
                SetTimer(() => ToolTip(), 3000)
                return
            }
            rem := (runMin * 60000) - elapsed
            sec := Max(0, Round(rem / 1000))
            SetGuiText(StatusGui["TimerText"], "Time left: " (sec // 60) ":" (Format("{:02}", Mod(sec, 60))))
        } else
            SetGuiText(StatusGui["TimerText"], "Time left: --")
    } catch {
        SetGuiText(StatusGui["TimerText"], "Time left: --")
    }
    runTxt := IsRunning ? "Running" : "Paused"
    stepNames := Map(0, "Idle", 1, "Opening bank", 2, "At bank", 3, "Withdrawing", 4, "To fire", 5, "Space", 6, "Check cooking", 7, "Cooking", 8, "To bank")
    stepTxt := stepNames.Has(CookStep) ? stepNames[CookStep] : "Idle"
    ; Build Action and Debug from current state so they always show (no dependency on DoCookingStep timer)
    actionTxt := "—"
    debugTxt := "Step=" CookStep " Inv=" InvSlotState " sawEmpty=" (CookStep3SawEmpty ? "1" : "0")
    if (IsRunning && CookStep >= 1) {
        if (CookStep = 1)
            actionTxt := "Click bank (find color)"
        else if (CookStep = 2) {
            if (A_TickCount < CookWaitUntil)
                actionTxt := "Wait for bank to open..."
            else
                actionTxt := "Check bank open → click deposit-all"
        }
        else if (CookStep = 3) {
            if (InvSlotState = "raw" && CookStep3SawEmpty)
                actionTxt := "Inv full (raw) — go to fire"
            else
                actionTxt := "Click withdraw (inv=" InvSlotState ")"
        }
        else if (CookStep = 4)
            actionTxt := "Click fire tile"
        else if (CookStep = 5) {
            if (A_TickCount < CookWaitUntil)
                actionTxt := "Wait before Space..."
            else
                actionTxt := "Press Space (open cook menu)"
        }
        else if (CookStep = 6) {
            if (A_TickCount < CookWaitUntil)
                actionTxt := "Wait after Space..."
            else
                actionTxt := "Check cooking → step 7"
        }
        else if (CookStep = 7) {
            if (InvSlotState = "cooked")
                actionTxt := "All cooked — go to bank"
            else
                actionTxt := "Cooking (wait inv=cooked)"
        }
        else if (CookStep = 8)
            actionTxt := "Click bank (return)"
    } else
        debugTxt := "—"
    SetGuiText(StatusGui["StatusText"], runTxt "  |  " stepTxt)
    StatusGui["ActionText"].Value := "Action: " actionTxt
    StatusGui["DebugText"].Value := "Debug: " debugTxt
    ; Config checkmarks
    pSet := (PlayAreaX2 > PlayAreaX1 && PlayAreaY2 > PlayAreaY1)
    bSet := (BankColor != "")
    wSet := (WithdrawAreaX2 > WithdrawAreaX1 && WithdrawAreaY2 > WithdrawAreaY1)
    cSet := (CookingStatusX2 > CookingStatusX1 && CookingStatusY2 > CookingStatusY1 && CookingStatusColor != "")
    fSet := (FireTileColor != "")
    iSet := (InvSlotX2 > InvSlotX1 && InvSlotY2 > InvSlotY1 && InvSlotEmptyColor != "" && InvSlotRawColor != "")
    dSet := (DepositAllX2 > DepositAllX1 && DepositAllY2 > DepositAllY1)
    SetGuiText(StatusGui["PlayAreaRow"], "[" (pSet ? "✓" : "—") "] Play area       Ctrl+Shift+P (TL)  Ctrl+Shift+L (BR)")
    SetGuiText(StatusGui["BankRow"], "[" (bSet ? "✓" : "—") "] Bank             Ctrl+Shift+B")
    SetGuiText(StatusGui["WithdrawRow"], "[" (wSet ? "✓" : "—") "] Withdraw area    Ctrl+Shift+J (TL)  Ctrl+Shift+K (BR)")
    SetGuiText(StatusGui["CookingRow"], "[" (cSet ? "✓" : "—") "] Cooking status   Ctrl+Shift+Y (TL)  Ctrl+Shift+U (BR)  Ctrl+Shift+V (color)")
    SetGuiText(StatusGui["FireRow"], "[" (fSet ? "✓" : "—") "] Fire tile         Ctrl+Shift+F")
    SetGuiText(StatusGui["InvRow"], "[" (iSet ? "✓" : "—") "] Last inv slot     Ctrl+Shift+I (TL)  Ctrl+Shift+O (BR)  Ctrl+Shift+A (raw color)")
    SetGuiText(StatusGui["DepositRow"], "[" (dSet ? "✓" : "—") "] Deposit all      Ctrl+Shift+D (TL)  Ctrl+Shift+N (BR)")
}

; --- Overlays ---
; Play area overlay (red L-shaped corners)
BuildPlayAreaOverlay() {
    global PlayAreaOverlayGuis, PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2, PlayAreaCornerSize
    for g in PlayAreaOverlayGuis {
        try
            g.Destroy()
        catch {
        }
    }
    PlayAreaOverlayGuis := []
    if (PlayAreaX2 <= PlayAreaX1 || PlayAreaY2 <= PlayAreaY1)
        return
    L := PlayAreaCornerSize
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

BuildInvSlotOverlay() {
    global InvSlotOverlayGuis, InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotCornerSize
    for g in InvSlotOverlayGuis {
        try
            g.Destroy()
        catch {
        }
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
^+q:: StartCooking()
^+w:: PauseCooking()
^+x:: ExitCooking()
^+p:: SetPlayAreaTL()
^+l:: SetPlayAreaBR()
^+b:: SetBankColor()
^+j:: SetWithdrawAreaTL()
^+k:: SetWithdrawAreaBR()
^+y:: SetCookingStatusTL()
^+u:: SetCookingStatusBR()
^+v:: SetCookingStatusColor()
^+f:: SetFireTileColor()
^+i:: SetInvSlotTL()
^+o:: SetInvSlotBR()
^+a:: SetInvSlotRawColor()
^+d:: SetDepositAllTL()
^+n:: SetDepositAllBR()

; --- Start / Pause / Exit ---
StartCooking() {
    global IsRunning, RunDurationMinutes, RunStartTime, StatusGui, ConfigPath, CookStep, CookJustStarted
    if (IsRunning)
        return
    runMin := 0
    try
        runMin := Integer(StatusGui["RunMinutes"].Value)
    catch as err {
    }
    if (runMin < 0) runMin := 0
    RunDurationMinutes := runMin
    try
        IniWrite(String(RunDurationMinutes), ConfigPath, "Settings", "RunDurationMinutes")
    catch as err {
    }
    RunStartTime := A_TickCount
    IsRunning := true
    CookJustStarted := true
    CookStep := 2
    SetTimer(DoCookingStep, 1000)
    SetTimer(UpdateInvSlotState, InvSlotCheckInterval)
    if (RunDurationMinutes > 0) UpdateStatusGui()
    ToolTip("Cooking bot: Running")
    SetTimer(() => ToolTip(), 2000)
}

PauseCooking() {
    global IsRunning, RunStartTime
    IsRunning := false
    RunStartTime := 0
    SetTimer(DoCookingStep, 0)
    SetTimer(UpdateInvSlotState, 0)
    ToolTip("Cooking bot: Paused")
    SetTimer(() => ToolTip(), 2000)
}

ExitCooking() {
    global IsRunning
    IsRunning := false
    SetTimer(DoCookingStep, 0)
    SetTimer(UpdateInvSlotState, 0)
    ToolTip()
    ExitApp()
}

; --- Config setters ---
SetPlayAreaTL() {
    global PlayAreaX1, PlayAreaY1, ConfigPath
    MouseGetPos(&mx, &my)
    PlayAreaX1 := mx
    PlayAreaY1 := my
    try {
        IniWrite(String(mx), ConfigPath, "PlayArea", "X1")
        IniWrite(String(my), ConfigPath, "PlayArea", "Y1")
    } catch {
    }
    ToolTip("Play area TOP-LEFT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildPlayAreaOverlay()
}

SetPlayAreaBR() {
    global PlayAreaX2, PlayAreaY2, ConfigPath
    MouseGetPos(&mx, &my)
    PlayAreaX2 := mx
    PlayAreaY2 := my
    try {
        IniWrite(String(mx), ConfigPath, "PlayArea", "X2")
        IniWrite(String(my), ConfigPath, "PlayArea", "Y2")
    } catch {
    }
    ToolTip("Play area BOTTOM-RIGHT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildPlayAreaOverlay()
}

SetBankColor() {
    global BankColor, ConfigPath
    MouseGetPos(&mx, &my)
    BankColor := PixelGetColor(mx, my, "RGB")
    try IniWrite(SubStr(BankColor, 3), ConfigPath, "Bank", "Color")
    catch {
    }
    ToolTip("Bank color set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetWithdrawAreaTL() {
    global WithdrawAreaX1, WithdrawAreaY1, ConfigPath
    MouseGetPos(&mx, &my)
    WithdrawAreaX1 := mx
    WithdrawAreaY1 := my
    try {
        IniWrite(String(mx), ConfigPath, "Withdraw", "X1")
        IniWrite(String(my), ConfigPath, "Withdraw", "Y1")
    } catch {
    }
    ToolTip("Withdraw area TOP-LEFT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetWithdrawAreaBR() {
    global WithdrawAreaX2, WithdrawAreaY2, ConfigPath
    MouseGetPos(&mx, &my)
    WithdrawAreaX2 := mx
    WithdrawAreaY2 := my
    try {
        IniWrite(String(mx), ConfigPath, "Withdraw", "X2")
        IniWrite(String(my), ConfigPath, "Withdraw", "Y2")
    } catch {
    }
    ToolTip("Withdraw area BOTTOM-RIGHT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetCookingStatusTL() {
    global CookingStatusX1, CookingStatusY1, ConfigPath
    MouseGetPos(&mx, &my)
    CookingStatusX1 := mx
    CookingStatusY1 := my
    try {
        IniWrite(String(mx), ConfigPath, "CookingStatus", "X1")
        IniWrite(String(my), ConfigPath, "CookingStatus", "Y1")
    } catch {
    }
    ToolTip("Cooking status area TOP-LEFT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetCookingStatusBR() {
    global CookingStatusX2, CookingStatusY2, ConfigPath
    MouseGetPos(&mx, &my)
    CookingStatusX2 := mx
    CookingStatusY2 := my
    try {
        IniWrite(String(mx), ConfigPath, "CookingStatus", "X2")
        IniWrite(String(my), ConfigPath, "CookingStatus", "Y2")
    } catch {
    }
    ToolTip("Cooking status area BOTTOM-RIGHT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetCookingStatusColor() {
    global CookingStatusColor, ConfigPath
    MouseGetPos(&mx, &my)
    CookingStatusColor := PixelGetColor(mx, my, "RGB")
    try IniWrite(SubStr(CookingStatusColor, 3), ConfigPath, "CookingStatus", "Color")
    catch {
    }
    ToolTip("Cooking status color set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetFireTileColor() {
    global FireTileColor, ConfigPath
    MouseGetPos(&mx, &my)
    FireTileColor := PixelGetColor(mx, my, "RGB")
    try IniWrite(SubStr(FireTileColor, 3), ConfigPath, "Fire", "Color")
    catch {
    }
    ToolTip("Fire tile color set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetInvSlotTL() {
    global InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotEmptyColor, ConfigPath
    MouseGetPos(&mx, &my)
    InvSlotX1 := mx
    InvSlotY1 := my
    try {
        IniWrite(String(mx), ConfigPath, "InvSlot", "X1")
        IniWrite(String(my), ConfigPath, "InvSlot", "Y1")
    } catch {
    }
    if (InvSlotX2 > InvSlotX1 && InvSlotY2 > InvSlotY1) {
        cx := (InvSlotX1 + InvSlotX2) // 2
        cy := (InvSlotY1 + InvSlotY2) // 2
        InvSlotEmptyColor := PixelGetColor(cx, cy, "RGB")
        try IniWrite(SubStr(InvSlotEmptyColor, 3), ConfigPath, "InvSlot", "EmptyColor")
        catch {
        }
    }
    ToolTip("Last inv slot TOP-LEFT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
    BuildInvSlotOverlay()
}

SetInvSlotBR() {
    global InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotEmptyColor, ConfigPath
    MouseGetPos(&mx, &my)
    InvSlotX2 := mx
    InvSlotY2 := my
    try {
        IniWrite(String(mx), ConfigPath, "InvSlot", "X2")
        IniWrite(String(my), ConfigPath, "InvSlot", "Y2")
    } catch {
    }
    if (InvSlotX2 > InvSlotX1 && InvSlotY2 > InvSlotY1) {
        cx := (InvSlotX1 + InvSlotX2) // 2
        cy := (InvSlotY1 + InvSlotY2) // 2
        InvSlotEmptyColor := PixelGetColor(cx, cy, "RGB")
        try IniWrite(SubStr(InvSlotEmptyColor, 3), ConfigPath, "InvSlot", "EmptyColor")
        catch {
        }
    }
    ToolTip("Last inv slot BOTTOM-RIGHT (empty baseline captured)")
    SetTimer(() => ToolTip(), 2000)
    BuildInvSlotOverlay()
}

SetInvSlotRawColor() {
    global InvSlotRawColor, ConfigPath
    MouseGetPos(&mx, &my)
    InvSlotRawColor := PixelGetColor(mx, my, "RGB")
    try IniWrite(SubStr(InvSlotRawColor, 3), ConfigPath, "InvSlot", "RawColor")
    catch {
    }
    ToolTip("Raw food color in slot set at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetDepositAllTL() {
    global DepositAllX1, DepositAllY1, ConfigPath
    MouseGetPos(&mx, &my)
    DepositAllX1 := mx
    DepositAllY1 := my
    try {
        IniWrite(String(mx), ConfigPath, "DepositAll", "X1")
        IniWrite(String(my), ConfigPath, "DepositAll", "Y1")
    } catch {
    }
    ToolTip("Deposit all area TOP-LEFT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

SetDepositAllBR() {
    global DepositAllX2, DepositAllY2, ConfigPath
    MouseGetPos(&mx, &my)
    DepositAllX2 := mx
    DepositAllY2 := my
    try {
        IniWrite(String(mx), ConfigPath, "DepositAll", "X2")
        IniWrite(String(my), ConfigPath, "DepositAll", "Y2")
    } catch {
    }
    ToolTip("Deposit all area BOTTOM-RIGHT at " mx "," my)
    SetTimer(() => ToolTip(), 2000)
}

; Sample center pixel of withdraw and deposit-all areas, save to config. Used when starting with bank open.
; Sample multiple pixels in a rect (5 points: center + four corners inset). Returns array of {x, y, color}.
SampleAreaPixels(x1, y1, x2, y2) {
    samples := []
    w := x2 - x1
    h := y2 - y1
    if (w < 2 || h < 2)
        return samples
    ; 5 points: center, and 4 corners inset by 1/4
    pts := [[x1 + w//2, y1 + h//2], [x1 + w//4, y1 + h//4], [x1 + (3*w)//4, y1 + h//4], [x1 + w//4, y1 + (3*h)//4], [x1 + (3*w)//4, y1 + (3*h)//4]]
    for pt in pts {
        try
            c := PixelGetColor(pt[1], pt[2], "RGB")
        catch
            continue
        samples.Push({x: pt[1], y: pt[2], color: c})
    }
    return samples
}

; True if current screen at saved sample positions matches (allow 1 mismatching pixel so cursor/tooltip don't break it).
AreaLooksSame(samples, variation) {
    if (samples.Length < 4)
        return false
    matchCount := 0
    for s in samples {
        try
            c := PixelGetColor(s.x, s.y, "RGB")
        catch
            continue
        if (ColorsMatch(c, s.color, variation))
            matchCount++
    }
    ; Need at least 4 matches, or (samples - 1) so one bad pixel (cursor, lighting) doesn't fail
    return (matchCount >= Max(4, samples.Length - 1))
}

; Returns true if both areas were valid and multi-pixel look was learned.
LearnBankColors() {
    global WithdrawAreaX1, WithdrawAreaY1, WithdrawAreaX2, WithdrawAreaY2, WithdrawAreaSamples
    global DepositAllX1, DepositAllY1, DepositAllX2, DepositAllY2, DepositAllAreaSamples
    global ConfigPath
    if (WithdrawAreaX2 <= WithdrawAreaX1 || WithdrawAreaY2 <= WithdrawAreaY1)
        return false
    if (DepositAllX2 <= DepositAllX1 || DepositAllY2 <= DepositAllY1)
        return false
    WithdrawAreaSamples := SampleAreaPixels(WithdrawAreaX1, WithdrawAreaY1, WithdrawAreaX2, WithdrawAreaY2)
    DepositAllAreaSamples := SampleAreaPixels(DepositAllX1, DepositAllY1, DepositAllX2, DepositAllY2)
    if (WithdrawAreaSamples.Length < 4 || DepositAllAreaSamples.Length < 4)
        return false
    try {
        IniWrite(String(WithdrawAreaSamples.Length), ConfigPath, "Withdraw", "SampleCount")
        for i, s in WithdrawAreaSamples {
            IniWrite(String(s.x), ConfigPath, "Withdraw", "Sample" i "X")
            IniWrite(String(s.y), ConfigPath, "Withdraw", "Sample" i "Y")
            IniWrite(SubStr(s.color, 3), ConfigPath, "Withdraw", "Sample" i "Color")
        }
        IniWrite(String(DepositAllAreaSamples.Length), ConfigPath, "DepositAll", "SampleCount")
        for i, s in DepositAllAreaSamples {
            IniWrite(String(s.x), ConfigPath, "DepositAll", "Sample" i "X")
            IniWrite(String(s.y), ConfigPath, "DepositAll", "Sample" i "Y")
            IniWrite(SubStr(s.color, 3), ConfigPath, "DepositAll", "Sample" i "Color")
        }
    } catch {
    }
    return true
}

; --- Helpers ---
ColorsMatch(c1, c2, variation) {
    c1 := Integer(c1)
    c2 := Integer(c2)
    return (Abs((c1>>16)&0xFF - (c2>>16)&0xFF) <= variation && Abs((c1>>8)&0xFF - (c2>>8)&0xFF) <= variation && Abs(c1&0xFF - c2&0xFF) <= variation)
}

; Search/click only inside play area when set; else full screen.
FindAndClickColorFullScreen(targetColor, colorVariation, useCentroid := true) {
    global PlayAreaX1, PlayAreaY1, PlayAreaX2, PlayAreaY2
    global ClickJitter, ClickDelayMs, RadiusStep, CookCentroidRadius, CookCentroidStep
    if (targetColor = "")
        return false
    if (PlayAreaX2 > PlayAreaX1 && PlayAreaY2 > PlayAreaY1) {
        paX1 := PlayAreaX1
        paY1 := PlayAreaY1
        paX2 := PlayAreaX2
        paY2 := PlayAreaY2
    } else {
        paX1 := 0
        paY1 := 0
        paX2 := A_ScreenWidth
        paY2 := A_ScreenHeight
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
    if (useCentroid) {
        x1 := Max(paX1, foundX - CookCentroidRadius)
        y1 := Max(paY1, foundY - CookCentroidRadius)
        x2 := Min(paX2, foundX + CookCentroidRadius)
        y2 := Min(paY2, foundY + CookCentroidRadius)
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
                } catch {
                }
                x += CookCentroidStep
            }
            y += CookCentroidStep
        }
        clickX := count > 0 ? (sumX // count) : foundX
        clickY := count > 0 ? (sumY // count) : foundY
    } else {
        clickX := foundX
        clickY := foundY
    }
    if (ClickJitter > 0) {
        clickX += Random(-ClickJitter, ClickJitter)
        clickY += Random(-ClickJitter, ClickJitter)
    }
    MouseMove(clickX, clickY)
    if (ClickDelayMs > 0) Sleep(ClickDelayMs)
    Click()
    return true
}

ColorInArea(x1, y1, x2, y2, targetColor, variation) {
    try
        return PixelSearch(&ox, &oy, x1, y1, x2, y2, Integer(targetColor), variation)
    catch {
        return false
    }
}

; Click anywhere inside the rect (center + jitter). Use when any click in the area is valid (e.g. withdraw area).
ClickInRect(x1, y1, x2, y2) {
    global ClickJitter, ClickDelayMs
    if (x2 <= x1 || y2 <= y1)
        return false
    clickX := (x1 + x2) // 2
    clickY := (y1 + y2) // 2
    if (ClickJitter > 0) {
        clickX += Random(-ClickJitter, ClickJitter)
        clickY += Random(-ClickJitter, ClickJitter)
        clickX := Max(x1, Min(x2, clickX))
        clickY := Max(y1, Min(y2, clickY))
    }
    MouseMove(clickX, clickY)
    if (ClickDelayMs > 0) Sleep(ClickDelayMs)
    Click()
    return true
}

ClickColorInRect(x1, y1, x2, y2, targetColor, variation) {
    global ClickJitter, ClickDelayMs
    if (x2 <= x1 || y2 <= y1 || targetColor = "")
        return false
    try {
        if PixelSearch(&ox, &oy, x1, y1, x2, y2, Integer(targetColor), variation) {
            clickX := ox + (ClickJitter ? Random(-ClickJitter, ClickJitter) : 0)
            clickY := oy + (ClickJitter ? Random(-ClickJitter, ClickJitter) : 0)
            MouseMove(clickX, clickY)
            if (ClickDelayMs > 0) Sleep(ClickDelayMs)
            Click()
            return true
        }
    } catch {
    }
    return false
}

UpdateInvSlotState() {
    global InvSlotState, InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, InvSlotEmptyColor, InvSlotRawColor, InvSlotVariation
    if (InvSlotX2 <= InvSlotX1 || InvSlotY2 <= InvSlotY1)
        return
    if (InvSlotEmptyColor = "" || InvSlotRawColor = "")
        return
    ; Search the whole last-slot area: raw color anywhere = we have raw meat to cook
    try {
        if (PixelSearch(&ox, &oy, InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, Integer(InvSlotRawColor), InvSlotVariation)) {
            InvSlotState := "raw"
            return
        }
        if (PixelSearch(&ox, &oy, InvSlotX1, InvSlotY1, InvSlotX2, InvSlotY2, Integer(InvSlotEmptyColor), InvSlotVariation)) {
            InvSlotState := "empty"
            return
        }
    } catch {
    }
    InvSlotState := "cooked"
}

CookingStatusUpdated() {
    global CookingStatusX1, CookingStatusY1, CookingStatusX2, CookingStatusY2, CookingStatusColor, CookingStatusVariation
    global LastCookingStatusSample, CookingStatusSampleStep
    if (CookingStatusX2 <= CookingStatusX1 || CookingStatusY2 <= CookingStatusY1 || CookingStatusColor = "")
        return false
    current := Map()
    y := CookingStatusY1
    while (y <= CookingStatusY2) {
        x := CookingStatusX1
        while (x <= CookingStatusX2) {
            key := x "," y
            try current[key] := PixelGetColor(x, y, "RGB")
            catch {
            }
            x += CookingStatusSampleStep
        }
        y += CookingStatusSampleStep
    }
    changed := 0
    for key, cur in current {
        if LastCookingStatusSample.Has(key) {
            if !ColorsMatch(cur, LastCookingStatusSample[key], 20)
                changed++
        }
    }
    LastCookingStatusSample := Map()
    for k, v in current
        LastCookingStatusSample[k] := v
    return (changed > 0)
}

DoCookingStep() {
    global CookStep, CookWaitUntil, CookBankClickTime, CookPendingDeposit, CookJustStarted, BankColor, BankColorVariation
    global WithdrawAreaX1, WithdrawAreaY1, WithdrawAreaX2, WithdrawAreaY2, WithdrawAreaSamples, WithdrawVariation
    global FireTileColor, FireColorVariation
    global InvSlotState, CookStep3SawEmpty
    global DepositAllX1, DepositAllY1, DepositAllX2, DepositAllY2, DepositAllAreaSamples, DepositAllVariation
    global BankOpenWaitMin, BankOpenWaitMax, SpaceWaitMin, SpaceWaitMax
    global CookStatusAction, CookDebugLine
    global CookingStatusX1, CookingStatusY1, CookingStatusX2, CookingStatusY2, CookingStatusColor, CookingStatusVariation
    if (CookStep = 0) {
        CookStatusAction := "Idle"
        CookDebugLine := "Step=0"
        return
    }
    CookDebugLine := "Step=" CookStep " Inv=" InvSlotState " sawEmpty=" (CookStep3SawEmpty ? "1" : "0")
    if (CookStep = 1) {
        ; If bank is already open (e.g. we retried from step 2 but area check had flaked), go to step 2 instead of clicking again
        if (WithdrawAreaSamples.Length >= 4 && DepositAllAreaSamples.Length >= 4) {
            bankOpen := AreaLooksSame(WithdrawAreaSamples, WithdrawVariation) && AreaLooksSame(DepositAllAreaSamples, DepositAllVariation)
            if (bankOpen) {
                CookStatusAction := "Bank already open — use it"
                CookStep := 2
                CookPendingDeposit := true
                CookWaitUntil := A_TickCount + Random(500, 2000)
                CookBankClickTime := 0
                return
            }
        }
        CookStatusAction := "Click bank (find color)"
        if FindAndClickColorFullScreen(BankColor, BankColorVariation, true) {
            CookStep := 2
            CookBankClickTime := A_TickCount
            CookWaitUntil := A_TickCount + Random(BankOpenWaitMin, BankOpenWaitMax)
            CookStatusAction := "Clicked bank — wait " (BankOpenWaitMin//1000) "-" (BankOpenWaitMax//1000) "s"
        } else
            CookStatusAction := "Click bank — not found, retry"
        return
    }
    if (CookStep = 2) {
        ; Whenever we start (or first run): update withdraw and deposit-all area samples from current screen, then deposit and withdraw.
        if (CookJustStarted || WithdrawAreaSamples.Length = 0 || DepositAllAreaSamples.Length = 0) {
            CookJustStarted := false
            if (LearnBankColors()) {
                CookStatusAction := "Click deposit-all (updated area looks)"
                ClickInRect(DepositAllX1, DepositAllY1, DepositAllX2, DepositAllY2)
                Sleep(800)
                CookStep := 3
                CookStep3SawEmpty := true
                CookStatusAction := "Deposited — now withdraw"
            } else
                CookStatusAction := "Set withdraw and deposit-all areas first"
            return
        }
        ; Returning to bank: wait at least 3s after clicking bank, then only proceed when BOTH areas look the same (multiple pixels match)
        minBankWaitMs := 3000
        if (A_TickCount - CookBankClickTime < minBankWaitMs) {
            CookStatusAction := "Wait for bank to open..."
            return
        }
        ; Once we see bank open, wait 0.5-2s (human-like) before clicking deposit
        if (CookPendingDeposit) {
            if (A_TickCount >= CookWaitUntil) {
                CookPendingDeposit := false
                CookStatusAction := "Click deposit-all"
                ClickInRect(DepositAllX1, DepositAllY1, DepositAllX2, DepositAllY2)
                Sleep(800)
                CookStep := 3
                CookStep3SawEmpty := true
                CookStatusAction := "Deposited — now withdraw"
            } else
                CookStatusAction := "Bank open — short delay..."
            return
        }
        bankOpen := AreaLooksSame(WithdrawAreaSamples, WithdrawVariation) && AreaLooksSame(DepositAllAreaSamples, DepositAllVariation)
        if (bankOpen) {
            CookPendingDeposit := true
            CookWaitUntil := A_TickCount + Random(500, 2000)
            CookStatusAction := "Bank open — short delay..."
            return
        }
        ; Areas don't match yet — if we've exceeded max wait, retry bank
        if (A_TickCount >= CookWaitUntil) {
            CookPendingDeposit := false
            CookStatusAction := "Bank not open (areas don't match) — retry bank"
            CookStep := 1
            return
        }
        CookStatusAction := "Wait for bank to open..."
        return
    }
    if (CookStep = 3) {
        ; Click withdraw area each tick until last slot shows raw color (meat) — then go cook
        ClickInRect(WithdrawAreaX1, WithdrawAreaY1, WithdrawAreaX2, WithdrawAreaY2)
        Sleep(300)
        ; Last slot raw color = we have meat to cook, go to fire
        if (InvSlotState = "raw") {
            CookStatusAction := "Inv full (raw) — go to fire"
            CookStep := 4
            return
        }
        CookStatusAction := "Clicked withdraw (inv=" InvSlotState ")"
        return
    }
    if (CookStep = 4) {
        global CookRestartingCooking
        CookStatusAction := "Click fire tile"
        if FindAndClickColorFullScreen(FireTileColor, FireColorVariation, true) {
            CookStep := 5
            ; Restarting (already at fire): short wait before Space. First time: wait to arrive.
            if (CookRestartingCooking) {
                CookRestartingCooking := false
                CookWaitUntil := A_TickCount + 1200
                CookStatusAction := "Clicked fire — short wait then Space"
            } else {
                CookWaitUntil := A_TickCount + Random(BankOpenWaitMin, BankOpenWaitMax)
                CookStatusAction := "Clicked fire — wait to arrive"
            }
        } else
            CookStatusAction := "Click fire — not found"
        return
    }
    if (CookStep = 5) {
        if (A_TickCount < CookWaitUntil) {
            CookStatusAction := "Wait before Space..."
            return
        }
        CookStatusAction := "Press Space (open cook menu)"
        Send("{Space}")
        CookStep := 6
        CookWaitUntil := A_TickCount + Random(SpaceWaitMin, SpaceWaitMax)
        return
    }
    if (CookStep = 6) {
        if (A_TickCount < CookWaitUntil) {
            CookStatusAction := "Wait after Space..."
            return
        }
        CookStatusAction := "Check cooking status → step 7"
        CookStep := 7
        return
    }
    if (CookStep = 7) {
        SetTimer(DoCookingStep, 400)   ; check cooking status often (e.g. level-up stops cooking)
        UpdateInvSlotState()          ; fresh read so we don't miss the transition (timer runs every 800ms)
        CookStatusAction := "Cooking (wait inv=cooked)"
        ; Treat both "cooked" and "empty" as done: cooked = slot has cooked food (no raw); empty = slot empty or misdetected (e.g. cooked color near EmptyColor). Either way last slot is "gone" and we should bank.
        if (InvSlotState = "cooked" || InvSlotState = "empty") {
            CookStatusAction := "All cooked — go to bank"
            CookStep := 8
            SetTimer(DoCookingStep, 1000)
            return
        }
        ; Cooking status area: if that color exists we're cooking. If not and we still have raw, restart (e.g. levelled and stopped)
        isCooking := (CookingStatusColor != "" && CookingStatusX2 > CookingStatusX1 && CookingStatusY2 > CookingStatusY1)
            && ColorInArea(CookingStatusX1, CookingStatusY1, CookingStatusX2, CookingStatusY2, CookingStatusColor, CookingStatusVariation)
        if (!isCooking && InvSlotState = "raw") {
            CookStatusAction := "Not cooking but have raw — click fire then Space to restart"
            CookRestartingCooking := true
            CookStep := 4
            SetTimer(DoCookingStep, 1000)
            return
        }
        return
    }
    if (CookStep = 8) {
        SetTimer(DoCookingStep, 1000)
        ; If bank is already open, go to step 2 instead of clicking again
        if (WithdrawAreaSamples.Length >= 4 && DepositAllAreaSamples.Length >= 4) {
            bankOpen := AreaLooksSame(WithdrawAreaSamples, WithdrawVariation) && AreaLooksSame(DepositAllAreaSamples, DepositAllVariation)
            if (bankOpen) {
                CookStatusAction := "Bank already open — use it"
                CookStep := 2
                CookPendingDeposit := true
                CookWaitUntil := A_TickCount + Random(500, 2000)
                CookBankClickTime := 0
                return
            }
        }
        CookStatusAction := "Click bank (return)"
        if FindAndClickColorFullScreen(BankColor, BankColorVariation, true) {
            CookStep := 2
            CookBankClickTime := A_TickCount
            CookWaitUntil := A_TickCount + Random(BankOpenWaitMin, BankOpenWaitMax)
            CookStatusAction := "Clicked bank — wait to open"
        } else
            CookStatusAction := "Click bank — not found"
        return
    }
}

BuildStatusGui()
BuildPlayAreaOverlay()
BuildInvSlotOverlay()
SetTimer(UpdateStatusGui, 500)
UpdateStatusGui()