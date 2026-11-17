@echo off
REM =====================================================================
REM  Input Tester - keyboard / mouse / controller bench diagnostic
REM  Copyright (c) 2026 Tamim   (GitHub: tamimmadrasa989-art  Snapchat: tamim4561)
REM  Open source under the MIT License (see LICENSE).
REM  Captures input only while focused. Writes no files. No network use.
REM =====================================================================
setlocal enableextensions
powershell -NoProfile -Sta -ExecutionPolicy Bypass -Command "$f=[IO.File]::ReadAllText('%~f0');$m='#:'+'PSCODE:#';iex $f.Substring($f.IndexOf($m))"
exit /b
#:PSCODE:#
# =====================================================================
#  Input Tester  -  keyboard / mouse / controller bench diagnostic
#
#  Copyright (c) 2026 Tamim
#  GitHub:   https://github.com/tamimmadrasa989-art
#  Snapchat: tamim4561
#
#  Open source under the MIT License (see LICENSE).
#  Free to use, study, modify, and share.
#
#  Safety / privacy:
#   - Captures input ONLY while this window is focused (normal window
#     events, NOT a global/system-wide hook). It cannot see what you
#     type in other programs - this is what separates a bench tester
#     from a keylogger.
#   - Writes NOTHING to disk. Makes NO network connection. Nothing is
#     logged, saved, or sent anywhere.
#   - 100% standard, documented Windows APIs (WinForms + XInput).
#   - No installer, no service, no autostart. Close it and it is gone.
#
#  What it does:
#   - Keyboard: every key lights green once seen; red = chatter (switch
#     bounced). A key stuck down stays bright. Numpad/extra keys appear
#     in the live log.
#   - Mouse: button states + click counts, scroll, position, and a
#     double-click / chatter flag for worn switches.
#   - Controller: XInput buttons, triggers, and sticks (watch for drift).
# =====================================================================

$ErrorActionPreference = 'Stop'

# --- hide the launching console window (cosmetic; the GUI is the tool) ---
try {
  Add-Type -Name WinConsole -Namespace Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int n);
'@
  [Native.WinConsole]::ShowWindow([Native.WinConsole]::GetConsoleWindow(), 0) | Out-Null
} catch {}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- custom panel: captures EVERY key (incl. Tab/arrows/Esc) via WndProc,
#     only while focused. Double-buffered for the controller sticks. ---
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Collections;
using System.Windows.Forms;
public class CapturePanel : Panel {
  public Queue KeyQueue = Queue.Synchronized(new Queue());
  public CapturePanel(){
    this.SetStyle(ControlStyles.Selectable, true);
    this.DoubleBuffered = true;
    this.TabStop = true;
  }
  protected override bool IsInputKey(Keys k){ return true; }
  protected override void WndProc(ref Message m){
    int msg = m.Msg;
    if(msg==0x100||msg==0x104||msg==0x101||msg==0x105){
      bool down = (msg==0x100||msg==0x104);
      int vk = (int)m.WParam.ToInt64();
      long lp = m.LParam.ToInt64();
      bool repeat = down && ((lp & 0x40000000L)!=0);
      int scan = (int)((lp>>16)&0xFF);
      bool ext = (lp & 0x01000000L)!=0;
      int rvk = vk;
      if(vk==0x10) rvk = (scan==0x36)?0xA1:0xA0;        // L/R Shift
      else if(vk==0x11) rvk = ext?0xA3:0xA2;            // L/R Ctrl
      else if(vk==0x12) rvk = ext?0xA5:0xA4;            // L/R Alt
      else if(vk==0x0D && ext) rvk = 0x10D;             // numpad Enter
      KeyQueue.Enqueue(new int[]{ rvk, down?1:0, repeat?1:0, Environment.TickCount });
      if(msg==0x100||msg==0x101){ return; }             // swallow normal keys: no ding, no Tab-navigation
    }
    base.WndProc(ref m);
  }
}
'@

# --- XInput (tries xinput1_4, falls back to xinput9_1_0) ---
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class XI {
  [StructLayout(LayoutKind.Sequential)]
  public struct GP { public ushort wButtons; public byte bLT; public byte bRT; public short LX; public short LY; public short RX; public short RY; }
  [StructLayout(LayoutKind.Sequential)]
  public struct ST { public uint packet; public GP Gamepad; }
  [DllImport("xinput1_4.dll", EntryPoint="XInputGetState")] static extern int Get14(int i, ref ST s);
  [DllImport("xinput9_1_0.dll", EntryPoint="XInputGetState")] static extern int Get910(int i, ref ST s);
  static int mode = 0; // 0 unknown, 1 = 1_4, 2 = 9_1_0, 3 = none
  public static int Get(int i, ref ST s){
    if(mode==2) return Get910(i, ref s);
    if(mode==3) return 1167; // ERROR_DEVICE_NOT_CONNECTED
    try { int r = Get14(i, ref s); mode=1; return r; }
    catch { try { int r = Get910(i, ref s); mode=2; return r; } catch { mode=3; return 1167; } }
  }
}
'@

# ---------------------------- theme ----------------------------
$bg         = [Drawing.Color]::FromArgb(24,26,32)
$panelBg    = [Drawing.Color]::FromArgb(32,35,43)
$cellBg     = [Drawing.Color]::FromArgb(48,52,63)
$cellTested = [Drawing.Color]::FromArgb(34,96,64)
$cellActive = [Drawing.Color]::FromArgb(64,196,120)
$cellChatter= [Drawing.Color]::FromArgb(214,72,72)
$fg         = [Drawing.Color]::FromArgb(230,232,238)
$muted      = [Drawing.Color]::FromArgb(150,155,165)
$accent     = [Drawing.Color]::FromArgb(90,170,255)

$fontUI  = New-Object Drawing.Font('Segoe UI', 9)
$fontKey = New-Object Drawing.Font('Segoe UI', 8)
$fontBig = New-Object Drawing.Font('Segoe UI Semibold', 11)

# ---------------------------- state ----------------------------
$cells    = @{}
$kbUnit   = 36
$kbGap    = 4
$kstate   = @{ seen=@{}; held=@{}; lastUp=@{}; chatter=0; presses=0 }
$gp       = @{ lx=0; ly=0; rx=0; ry=0 }
$gpBtn    = @{}

$keyNames = @{
  0x1B='Esc'; 0x09='Tab'; 0x14='Caps'; 0x0D='Enter'; 0x10D='NumEnter'; 0x08='Bksp';
  0x20='Space'; 0xA0='L-Shift'; 0xA1='R-Shift'; 0xA2='L-Ctrl'; 0xA3='R-Ctrl';
  0xA4='L-Alt'; 0xA5='R-Alt'; 0x5B='L-Win'; 0x5C='R-Win'; 0x5D='Menu';
  0x25='Left'; 0x26='Up'; 0x27='Right'; 0x28='Down'; 0x2D='Ins'; 0x2E='Del';
  0x24='Home'; 0x23='End'; 0x21='PgUp'; 0x22='PgDn'; 0x2C='PrtSc'; 0x91='ScrLk';
  0x13='Pause'; 0x90='NumLk'; 0xC0='``'; 0xBD='-'; 0xBB='='; 0xDB='['; 0xDD=']';
  0xDC='\'; 0xBA=';'; 0xDE="'"; 0xBC=','; 0xBE='.'; 0xBF='/'; 0x6A='Num*';
  0x6B='Num+'; 0x6D='Num-'; 0x6E='Num.'; 0x6F='Num/'
}

# ---------------------------- helpers ----------------------------
function Key-Name([int]$vk){
  if($keyNames.ContainsKey($vk)){ return $keyNames[$vk] }
  if($vk -ge 0x30 -and $vk -le 0x39){ return [string][char]$vk }
  if($vk -ge 0x41 -and $vk -le 0x5A){ return [string][char]$vk }
  if($vk -ge 0x60 -and $vk -le 0x69){ return 'Num' + ($vk-0x60) }
  if($vk -ge 0x70 -and $vk -le 0x87){ return 'F' + ($vk-0x6F) }
  return ('VK_0x{0:X2}' -f $vk)
}

function Log-Line([string]$msg,[bool]$warn){
  $ts = (Get-Date).ToString('HH:mm:ss.fff')
  $kbLog.SelectionStart = $kbLog.TextLength
  if($warn){ $kbLog.SelectionColor = $cellChatter } else { $kbLog.SelectionColor = $muted }
  $kbLog.AppendText("[$ts] $msg`n")
  if($kbLog.TextLength -gt 24000){
    $kbLog.Select(0, 8000); $kbLog.SelectedText = ''
  }
  $kbLog.SelectionStart = $kbLog.TextLength
  $kbLog.ScrollToCaret()
}

function Add-Key($parent,[int]$vk,[string]$text,[double]$w,[int]$x,[int]$y){
  $l = New-Object Windows.Forms.Label
  $l.Text = $text
  $l.BackColor = $cellBg
  $l.ForeColor = $fg
  $l.TextAlign = 'MiddleCenter'
  $l.BorderStyle = 'FixedSingle'
  $l.AutoSize = $false
  $l.Width  = [int]($w*$kbUnit + ($w-1)*$kbGap)
  $l.Height = $kbUnit
  $l.Left = $x; $l.Top = $y
  $l.Font = $fontKey
  $parent.Controls.Add($l)
  if($vk -ge 0){ $cells[$vk] = $l }
  return $l
}

function Render-Row($parent,[int]$rowY,[int]$startX,$defs){
  $x = $startX
  foreach($d in $defs){
    $t = $d[0]; $vk = [int]$d[1]; $w = [double]$d[2]
    if($vk -eq -99){ $x += [int]($w*$kbUnit); continue }   # spacer
    $l = Add-Key $parent $vk $t $w $x $rowY
    $x += $l.Width + $kbGap
  }
}

function Process-Key([int]$vk,[bool]$down,[bool]$rep,[int]$t){
  $cell = $cells[$vk]
  $chat = $false
  if($down){
    if(-not $rep){
      if($kstate.lastUp.ContainsKey($vk)){
        $gapMs = $t - $kstate.lastUp[$vk]
        if($gapMs -ge 0 -and $gapMs -lt 50){
          $kstate.chatter++
          Log-Line ("CHATTER  {0}  (re-press {1} ms after release)" -f (Key-Name $vk), $gapMs) $true
          if($cell){ $cell.BackColor = $cellChatter }
          $chat = $true
        }
      }
      $kstate.presses++
      if(-not $kstate.seen.ContainsKey($vk)){ $kstate.seen[$vk] = $true }
      $kstate.held[$vk] = $true
      Log-Line ("DOWN  {0}" -f (Key-Name $vk)) $false
    }
    if($cell -and -not $chat){ $cell.BackColor = $cellActive }
    $lblCur.Text = 'Last key:  ' + (Key-Name $vk)
  } else {
    $kstate.lastUp[$vk] = $t
    if($kstate.held.ContainsKey($vk)){ $kstate.held.Remove($vk) }
    Log-Line ("UP    {0}" -f (Key-Name $vk)) $false
    if($cell){
      if($kstate.seen.ContainsKey($vk)){ $cell.BackColor = $cellTested } else { $cell.BackColor = $cellBg }
    }
  }
  $lblSeen.Text = 'Keys seen:  ' + $kstate.seen.Count
  $lblChat.Text = 'Chatter:  '   + $kstate.chatter
  $lblHeld.Text = 'Held now:  '   + $kstate.held.Count
}

function Reset-Keyboard {
  foreach($k in $cells.Keys){ $cells[$k].BackColor = $cellBg }
  $kstate.seen.Clear(); $kstate.held.Clear(); $kstate.lastUp.Clear()
  $kstate.chatter = 0; $kstate.presses = 0
  $kbLog.Clear()
  $lblCur.Text='Last key:  -'; $lblSeen.Text='Keys seen:  0'
  $lblChat.Text='Chatter:  0'; $lblHeld.Text='Held now:  0'
  $kb.Focus() | Out-Null
}

# ---------------------------- form ----------------------------
[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = 'Input Tester  -  Keyboard / Mouse / Controller   (by Tamim)'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object Drawing.Size(1000, 600)
$form.MinimumSize = New-Object Drawing.Size(840, 560)
$form.BackColor = $bg
$form.ForeColor = $fg
$form.Font = $fontUI

$tabs = New-Object Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tabKb = New-Object Windows.Forms.TabPage; $tabKb.Text = 'Keyboard'; $tabKb.BackColor = $panelBg
$tabMs = New-Object Windows.Forms.TabPage; $tabMs.Text = 'Mouse';    $tabMs.BackColor = $panelBg
$tabGp = New-Object Windows.Forms.TabPage; $tabGp.Text = 'Controller'; $tabGp.BackColor = $panelBg
$tabs.Controls.AddRange(@($tabKb,$tabMs,$tabGp))
$form.Controls.Add($tabs)

# ====================== KEYBOARD TAB ======================
$kbTop = New-Object Windows.Forms.Panel
$kbTop.Dock = 'Top'; $kbTop.Height = 72; $kbTop.BackColor = $panelBg

$lblInfo = New-Object Windows.Forms.Label
$lblInfo.Text = 'Click here, then press every key. Each lights green once seen; a key stuck down stays bright; RED = chatter (switch bounced). Numpad/extra keys show in the log.'
$lblInfo.ForeColor = $muted; $lblInfo.Left = 16; $lblInfo.Top = 8; $lblInfo.Width = 860; $lblInfo.Height = 30

$lblCur  = New-Object Windows.Forms.Label; $lblCur.Text='Last key:  -'; $lblCur.ForeColor=$fg; $lblCur.Font=$fontBig; $lblCur.Left=16;  $lblCur.Top=40; $lblCur.Width=220; $lblCur.Height=24
$lblSeen = New-Object Windows.Forms.Label; $lblSeen.Text='Keys seen:  0'; $lblSeen.ForeColor=$fg; $lblSeen.Left=250; $lblSeen.Top=42; $lblSeen.Width=130; $lblSeen.Height=24
$lblChat = New-Object Windows.Forms.Label; $lblChat.Text='Chatter:  0';   $lblChat.ForeColor=$fg; $lblChat.Left=380; $lblChat.Top=42; $lblChat.Width=110; $lblChat.Height=24
$lblHeld = New-Object Windows.Forms.Label; $lblHeld.Text='Held now:  0';  $lblHeld.ForeColor=$fg; $lblHeld.Left=490; $lblHeld.Top=42; $lblHeld.Width=110; $lblHeld.Height=24

$btnReset = New-Object Windows.Forms.Button
$btnReset.Text='Reset'; $btnReset.Left=760; $btnReset.Top=38; $btnReset.Width=90; $btnReset.Height=28
$btnReset.FlatStyle='Flat'; $btnReset.BackColor=$cellBg; $btnReset.ForeColor=$fg; $btnReset.TabStop=$false
$btnReset.Add_Click({ Reset-Keyboard })

$kbTop.Controls.AddRange(@($lblInfo,$lblCur,$lblSeen,$lblChat,$lblHeld,$btnReset))

$kbBottom = New-Object Windows.Forms.Panel
$kbBottom.Dock = 'Bottom'; $kbBottom.Height = 140; $kbBottom.BackColor = $panelBg; $kbBottom.Padding = New-Object Windows.Forms.Padding(8)
$kbLog = New-Object Windows.Forms.RichTextBox
$kbLog.Dock='Fill'; $kbLog.ReadOnly=$true; $kbLog.BackColor=[Drawing.Color]::FromArgb(18,20,25); $kbLog.ForeColor=$muted
$kbLog.BorderStyle='None'; $kbLog.Font=New-Object Drawing.Font('Consolas',8.5); $kbLog.TabStop=$false
$kbLog.Add_Enter({ $kb.Focus() | Out-Null })
$kbBottom.Controls.Add($kbLog)

$kb = New-Object CapturePanel
$kb.Dock='Fill'; $kb.BackColor=$panelBg

# layout rows: @(label, vk, widthUnits)  (vk -99 = spacer)
$rowFn = @( @('Esc',0x1B,1.0), @('',-99,0.5),
  @('F1',0x70,1.0),@('F2',0x71,1.0),@('F3',0x72,1.0),@('F4',0x73,1.0), @('',-99,0.5),
  @('F5',0x74,1.0),@('F6',0x75,1.0),@('F7',0x76,1.0),@('F8',0x77,1.0), @('',-99,0.5),
  @('F9',0x78,1.0),@('F10',0x79,1.0),@('F11',0x7A,1.0),@('F12',0x7B,1.0), @('',-99,0.5),
  @('PrSc',0x2C,1.0),@('ScLk',0x91,1.0),@('Paus',0x13,1.0) )
$row1 = @( @('``',0xC0,1.0),@('1',0x31,1.0),@('2',0x32,1.0),@('3',0x33,1.0),@('4',0x34,1.0),@('5',0x35,1.0),@('6',0x36,1.0),@('7',0x37,1.0),@('8',0x38,1.0),@('9',0x39,1.0),@('0',0x30,1.0),@('-',0xBD,1.0),@('=',0xBB,1.0),@('Bksp',0x08,2.0), @('',-99,0.25),
  @('Ins',0x2D,1.0),@('Hom',0x24,1.0),@('PgU',0x21,1.0) )
$row2 = @( @('Tab',0x09,1.5),@('Q',0x51,1.0),@('W',0x57,1.0),@('E',0x45,1.0),@('R',0x52,1.0),@('T',0x54,1.0),@('Y',0x59,1.0),@('U',0x55,1.0),@('I',0x49,1.0),@('O',0x4F,1.0),@('P',0x50,1.0),@('[',0xDB,1.0),@(']',0xDD,1.0),@('\',0xDC,1.5), @('',-99,0.25),
  @('Del',0x2E,1.0),@('End',0x23,1.0),@('PgD',0x22,1.0) )
$row3 = @( @('Caps',0x14,1.75),@('A',0x41,1.0),@('S',0x53,1.0),@('D',0x44,1.0),@('F',0x46,1.0),@('G',0x47,1.0),@('H',0x48,1.0),@('J',0x4A,1.0),@('K',0x4B,1.0),@('L',0x4C,1.0),@(';',0xBA,1.0),@("'",0xDE,1.0),@('Enter',0x0D,2.25) )
$row4 = @( @('Shift',0xA0,2.25),@('Z',0x5A,1.0),@('X',0x58,1.0),@('C',0x43,1.0),@('V',0x56,1.0),@('B',0x42,1.0),@('N',0x4E,1.0),@('M',0x4D,1.0),@(',',0xBC,1.0),@('.',0xBE,1.0),@('/',0xBF,1.0),@('Shift',0xA1,2.75), @('',-99,1.25),
  @('Up',0x26,1.0) )
$row5 = @( @('Ctrl',0xA2,1.25),@('Win',0x5B,1.25),@('Alt',0xA4,1.25),@('Space',0x20,6.25),@('Alt',0xA5,1.25),@('Win',0x5C,1.25),@('Menu',0x5D,1.25),@('Ctrl',0xA3,1.25), @('',-99,0.25),
  @('Lt',0x25,1.0),@('Dn',0x28,1.0),@('Rt',0x27,1.0) )

$sx = 16
Render-Row $kb 12  $sx $rowFn
Render-Row $kb 58  $sx $row1
Render-Row $kb 98  $sx $row2
Render-Row $kb 138 $sx $row3
Render-Row $kb 178 $sx $row4
Render-Row $kb 218 $sx $row5

$tabKb.Controls.Add($kbBottom)
$tabKb.Controls.Add($kbTop)
$tabKb.Controls.Add($kb)
$kb.BringToFront()

# ====================== MOUSE TAB ======================
$msTop = New-Object Windows.Forms.Panel
$msTop.Dock='Top'; $msTop.Height=168; $msTop.BackColor=$panelBg

$lblMInfo = New-Object Windows.Forms.Label
$lblMInfo.Text='Move, click, and scroll inside the dark area below. Buttons light up; counts increment. A single physical click registering twice (gap under ~35 ms) is flagged as chatter.'
$lblMInfo.ForeColor=$muted; $lblMInfo.Left=16; $lblMInfo.Top=8; $lblMInfo.Width=900; $lblMInfo.Height=30

$mBtn = @{}
$mCount = @{}
$mbOrder = @('L','R','M','X1','X2')
$mbLabel = @{ 'L'='Left'; 'R'='Right'; 'M'='Middle'; 'X1'='Back (X1)'; 'X2'='Fwd (X2)' }
$mx = 16
foreach($k in $mbOrder){
  $ind = New-Object Windows.Forms.Label
  $ind.Text=$mbLabel[$k]; $ind.Left=$mx; $ind.Top=46; $ind.Width=96; $ind.Height=34
  $ind.TextAlign='MiddleCenter'; $ind.BorderStyle='FixedSingle'; $ind.BackColor=$cellBg; $ind.ForeColor=$fg
  $cnt = New-Object Windows.Forms.Label
  $cnt.Text='0'; $cnt.Left=$mx; $cnt.Top=82; $cnt.Width=96; $cnt.Height=20
  $cnt.TextAlign='MiddleCenter'; $cnt.ForeColor=$muted
  $msTop.Controls.Add($ind); $msTop.Controls.Add($cnt)
  $mBtn[$k]=$ind; $mCount[$k]=$cnt
  $mx += 104
}

$lblScroll = New-Object Windows.Forms.Label; $lblScroll.Text='Scroll  up: 0   down: 0'; $lblScroll.Left=560; $lblScroll.Top=48; $lblScroll.Width=240; $lblScroll.Height=22; $lblScroll.ForeColor=$fg
$lblPos    = New-Object Windows.Forms.Label; $lblPos.Text='Pos:  -';                   $lblPos.Left=560;   $lblPos.Top=74; $lblPos.Width=240; $lblPos.Height=22; $lblPos.ForeColor=$fg
$lblMChat  = New-Object Windows.Forms.Label; $lblMChat.Text='Double-click / chatter:  0'; $lblMChat.Left=560; $lblMChat.Top=100; $lblMChat.Width=260; $lblMChat.Height=22; $lblMChat.ForeColor=$fg
$lblMInt   = New-Object Windows.Forms.Label; $lblMInt.Text='Last click gap:  -';        $lblMInt.Left=16;   $lblMInt.Top=120; $lblMInt.Width=400; $lblMInt.Height=22; $lblMInt.ForeColor=$muted

$btnMReset = New-Object Windows.Forms.Button
$btnMReset.Text='Reset'; $btnMReset.Left=760; $btnMReset.Top=120; $btnMReset.Width=90; $btnMReset.Height=28
$btnMReset.FlatStyle='Flat'; $btnMReset.BackColor=$cellBg; $btnMReset.ForeColor=$fg; $btnMReset.TabStop=$false

$msTop.Controls.AddRange(@($lblMInfo,$lblScroll,$lblPos,$lblMChat,$lblMInt,$btnMReset))

$ms = New-Object CapturePanel
$ms.Dock='Fill'; $ms.BackColor=[Drawing.Color]::FromArgb(18,20,25)

$mHint = New-Object Windows.Forms.Label
$mHint.Text='move / click / scroll here'; $mHint.AutoSize=$true; $mHint.ForeColor=[Drawing.Color]::FromArgb(70,75,88)
$mHint.Left=20; $mHint.Top=14; $mHint.BackColor=[Drawing.Color]::Transparent
$ms.Controls.Add($mHint)

$mDot = New-Object Windows.Forms.Label
$mDot.Width=12; $mDot.Height=12; $mDot.BackColor=$accent; $mDot.Left=-20; $mDot.Top=-20
$ms.Controls.Add($mDot)

$mstate = @{ up=0; down=0; chatter=0; last=@{}; cnt=@{} }
foreach($k in $mbOrder){ $mstate.cnt[$k]=0 }

function MButton-Key($b){
  switch($b){
    'Left'    { 'L' }
    'Right'   { 'R' }
    'Middle'  { 'M' }
    'XButton1'{ 'X1' }
    'XButton2'{ 'X2' }
    default   { $null }
  }
}

$ms.Add_MouseDown({ param($s,$e)
  $k = MButton-Key $e.Button.ToString()
  if($k){
    $mBtn[$k].BackColor = $cellActive
    $t = [Environment]::TickCount
    if($mstate.last.ContainsKey($k)){
      $g = $t - $mstate.last[$k]
      $lblMInt.Text = "Last $($mbLabel[$k]) gap:  $g ms"
      if($g -ge 0 -and $g -lt 35){ $mstate.chatter++; $lblMChat.Text = "Double-click / chatter:  $($mstate.chatter)"; $mBtn[$k].BackColor = $cellChatter }
    }
    $mstate.last[$k] = $t
    $mstate.cnt[$k]++; $mCount[$k].Text = [string]$mstate.cnt[$k]
  }
})
$ms.Add_MouseUp({ param($s,$e)
  $k = MButton-Key $e.Button.ToString()
  if($k){ $mBtn[$k].BackColor = $cellBg }
})
$ms.Add_MouseMove({ param($s,$e)
  $lblPos.Text = "Pos:  $($e.X), $($e.Y)"
  $mDot.Left = $e.X - 6; $mDot.Top = $e.Y - 6
})
$ms.Add_MouseWheel({ param($s,$e)
  if($e.Delta -gt 0){ $mstate.up++ } elseif($e.Delta -lt 0){ $mstate.down++ }
  $lblScroll.Text = "Scroll  up: $($mstate.up)   down: $($mstate.down)"
})
$ms.Add_MouseEnter({ $ms.Focus() | Out-Null })

$btnMReset.Add_Click({
  foreach($k in $mbOrder){ $mstate.cnt[$k]=0; $mCount[$k].Text='0'; $mBtn[$k].BackColor=$cellBg }
  $mstate.up=0; $mstate.down=0; $mstate.chatter=0; $mstate.last.Clear()
  $lblScroll.Text='Scroll  up: 0   down: 0'; $lblPos.Text='Pos:  -'
  $lblMChat.Text='Double-click / chatter:  0'; $lblMInt.Text='Last click gap:  -'
  $ms.Focus() | Out-Null
})

$tabMs.Controls.Add($ms)
$tabMs.Controls.Add($msTop)
$ms.BringToFront()

# ====================== CONTROLLER TAB ======================
$gpPanel = New-Object Windows.Forms.Panel
$gpPanel.Dock='Fill'; $gpPanel.BackColor=$panelBg

$gpStatus = New-Object Windows.Forms.Label
$gpStatus.Text='Looking for a controller...'; $gpStatus.ForeColor=$muted
$gpStatus.Left=16; $gpStatus.Top=12; $gpStatus.Width=700; $gpStatus.Height=22; $gpStatus.Font=$fontBig

# button indicators (two rows)
$btnOrder = @('A','B','X','Y','LB','RB','Back','Start','LS','RS','Up','Down','Left','Right')
$bx=16; $by=48; $i2=0
foreach($k in $btnOrder){
  $ind = New-Object Windows.Forms.Label
  $ind.Text=$k; $ind.Width=72; $ind.Height=30; $ind.TextAlign='MiddleCenter'
  $ind.BorderStyle='FixedSingle'; $ind.BackColor=$cellBg; $ind.ForeColor=$fg
  $ind.Left=$bx; $ind.Top=$by
  $gpPanel.Controls.Add($ind); $gpBtn[$k]=$ind
  $i2++
  if($i2 -eq 7){ $bx=16; $by=84 } else { $bx += 78 }
}

# triggers
$lblLT = New-Object Windows.Forms.Label; $lblLT.Text='LT: 0'; $lblLT.Left=16; $lblLT.Top=130; $lblLT.Width=70; $lblLT.Height=18; $lblLT.ForeColor=$fg
$ltTrack = New-Object Windows.Forms.Panel; $ltTrack.Left=92; $ltTrack.Top=130; $ltTrack.Width=180; $ltTrack.Height=16; $ltTrack.BackColor=$cellBg
$ltFill  = New-Object Windows.Forms.Panel; $ltFill.Left=0; $ltFill.Top=0; $ltFill.Width=0; $ltFill.Height=16; $ltFill.BackColor=$cellActive
$ltTrack.Controls.Add($ltFill)
$lblRT = New-Object Windows.Forms.Label; $lblRT.Text='RT: 0'; $lblRT.Left=300; $lblRT.Top=130; $lblRT.Width=70; $lblRT.Height=18; $lblRT.ForeColor=$fg
$rtTrack = New-Object Windows.Forms.Panel; $rtTrack.Left=376; $rtTrack.Top=130; $rtTrack.Width=180; $rtTrack.Height=16; $rtTrack.BackColor=$cellBg
$rtFill  = New-Object Windows.Forms.Panel; $rtFill.Left=0; $rtFill.Top=0; $rtFill.Width=0; $rtFill.Height=16; $rtFill.BackColor=$cellActive
$rtTrack.Controls.Add($rtFill)
$gpPanel.Controls.AddRange(@($lblLT,$ltTrack,$lblRT,$rtTrack))

# sticks
$lblLHdr = New-Object Windows.Forms.Label; $lblLHdr.Text='Left stick'; $lblLHdr.Left=16; $lblLHdr.Top=160; $lblLHdr.Width=130; $lblLHdr.Height=18; $lblLHdr.ForeColor=$muted
$lblRHdr = New-Object Windows.Forms.Label; $lblRHdr.Text='Right stick'; $lblRHdr.Left=176; $lblRHdr.Top=160; $lblRHdr.Width=130; $lblRHdr.Height=18; $lblRHdr.ForeColor=$muted

$stickLP = New-Object CapturePanel; $stickLP.Left=16;  $stickLP.Top=180; $stickLP.Width=130; $stickLP.Height=130; $stickLP.BackColor=$panelBg
$stickRP = New-Object CapturePanel; $stickRP.Left=176; $stickRP.Top=180; $stickRP.Width=130; $stickRP.Height=130; $stickRP.BackColor=$panelBg

$lblLRaw = New-Object Windows.Forms.Label; $lblLRaw.Text='L stick: 0, 0'; $lblLRaw.Left=16;  $lblLRaw.Top=314; $lblLRaw.Width=150; $lblLRaw.Height=18; $lblLRaw.ForeColor=$fg
$lblRRaw = New-Object Windows.Forms.Label; $lblRRaw.Text='R stick: 0, 0'; $lblRRaw.Left=176; $lblRRaw.Top=314; $lblRRaw.Width=150; $lblRRaw.Height=18; $lblRRaw.ForeColor=$fg

$lblDrift = New-Object Windows.Forms.Label
$lblDrift.Text="At rest, both axes should read near 0 (within a few hundred). A large standing value = stick drift (shown red)."
$lblDrift.Left=340; $lblDrift.Top=180; $lblDrift.Width=320; $lblDrift.Height=120; $lblDrift.ForeColor=$muted

$gpPanel.Controls.AddRange(@($gpStatus,$lblLHdr,$lblRHdr,$stickLP,$stickRP,$lblLRaw,$lblRRaw,$lblDrift))

$stickPaint = {
  param($s,$e)
  $g = $e.Graphics
  $g.SmoothingMode = 'AntiAlias'
  $w = $s.ClientSize.Width; $h = $s.ClientSize.Height
  $g.Clear($panelBg)
  $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(70,75,88))
  $g.DrawRectangle($pen, 0, 0, $w-1, $h-1)
  $g.DrawLine($pen, [int]($w/2), 0, [int]($w/2), $h)
  $g.DrawLine($pen, 0, [int]($h/2), $w, [int]($h/2))
  if($s -eq $stickLP){ $vx = $gp.lx; $vy = $gp.ly } else { $vx = $gp.rx; $vy = $gp.ry }
  $cx = [int]($w/2 + ($vx/32767.0)*($w/2-10))
  $cy = [int]($h/2 - ($vy/32767.0)*($h/2-10))
  $br = New-Object Drawing.SolidBrush($accent)
  $g.FillEllipse($br, $cx-6, $cy-6, 12, 12)
  $pen.Dispose(); $br.Dispose()
}
$stickLP.Add_Paint($stickPaint)
$stickRP.Add_Paint($stickPaint)

$tabGp.Controls.Add($gpPanel)

function Poll-Controller {
  $st = New-Object 'XI+ST'
  $found = -1
  for($i=0; $i -lt 4; $i++){
    $r = [XI]::Get($i, [ref]$st)
    if($r -eq 0){ $found = $i; break }
  }
  if($found -lt 0){
    $gpStatus.Text = 'No controller detected - connect an Xbox-compatible (XInput) controller.'
    $gpStatus.ForeColor = $muted
    foreach($k in $gpBtn.Keys){ $gpBtn[$k].BackColor = $cellBg }
    $gp.lx=0; $gp.ly=0; $gp.rx=0; $gp.ry=0
    $ltFill.Width=0; $rtFill.Width=0; $lblLT.Text='LT: 0'; $lblRT.Text='RT: 0'
    $lblLRaw.Text='L stick: 0, 0'; $lblLRaw.ForeColor=$fg
    $lblRRaw.Text='R stick: 0, 0'; $lblRRaw.ForeColor=$fg
    $stickLP.Invalidate(); $stickRP.Invalidate()
    return
  }
  $gpStatus.Text = "Controller $found connected (XInput)."
  $gpStatus.ForeColor = $cellActive
  $b = $st.Gamepad.wButtons
  $map = @{ 'A'=0x1000;'B'=0x2000;'X'=0x4000;'Y'=0x8000;'LB'=0x100;'RB'=0x200;'Back'=0x20;'Start'=0x10;'LS'=0x40;'RS'=0x80;'Up'=0x1;'Down'=0x2;'Left'=0x4;'Right'=0x8 }
  foreach($k in $map.Keys){
    if(($b -band $map[$k]) -ne 0){ $gpBtn[$k].BackColor = $cellActive } else { $gpBtn[$k].BackColor = $cellBg }
  }
  $lt = [int]$st.Gamepad.bLT; $rt = [int]$st.Gamepad.bRT
  $lblLT.Text = "LT: $lt"; $lblRT.Text = "RT: $rt"
  $ltFill.Width = [int]($lt/255.0*180); $rtFill.Width = [int]($rt/255.0*180)
  $gp.lx=[int]$st.Gamepad.LX; $gp.ly=[int]$st.Gamepad.LY; $gp.rx=[int]$st.Gamepad.RX; $gp.ry=[int]$st.Gamepad.RY
  $lblLRaw.Text = "L stick: $($gp.lx), $($gp.ly)"
  $lblRRaw.Text = "R stick: $($gp.rx), $($gp.ry)"
  if([math]::Abs($gp.lx) -gt 6000 -or [math]::Abs($gp.ly) -gt 6000){ $lblLRaw.ForeColor=$cellChatter } else { $lblLRaw.ForeColor=$fg }
  if([math]::Abs($gp.rx) -gt 6000 -or [math]::Abs($gp.ry) -gt 6000){ $lblRRaw.ForeColor=$cellChatter } else { $lblRRaw.ForeColor=$fg }
  $stickLP.Invalidate(); $stickRP.Invalidate()
}

# ---------------------------- loop ----------------------------
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 15
$timer.Add_Tick({
  while($kb.KeyQueue.Count -gt 0){
    $e = $kb.KeyQueue.Dequeue()
    Process-Key ([int]$e[0]) ($e[1] -eq 1) ($e[2] -eq 1) ([int]$e[3])
  }
  if($tabs.SelectedTab -eq $tabGp){ Poll-Controller }
})

$tabs.Add_SelectedIndexChanged({
  if($tabs.SelectedTab -eq $tabKb){ $kb.Focus() | Out-Null }
  elseif($tabs.SelectedTab -eq $tabMs){ $ms.Focus() | Out-Null }
})
$form.Add_Shown({ $kb.Focus() | Out-Null; $timer.Start() })
$form.Add_FormClosing({ $timer.Stop() })

[void]$form.ShowDialog()
