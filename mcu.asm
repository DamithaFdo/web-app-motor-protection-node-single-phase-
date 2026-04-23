;------------------------------------------------------------------------------
; FINAL MCU 1: PREDICTIVE MONITOR W/ SAFETY INTERLOCKS & DUAL ALARMS
; A0=X, A1=Y, A2=Z, A3=MUX_OUT (PC3)
; MUX S0=PB3, S1=PB4, S2=PB5
; BUTTONS: PD2=Relay Toggle, PD3=Calibrate (Short=Calib, Long=Reset)
; LEDS: PD4=Calib, PD5=RelayON(Green), PD6=RelayOFF(Red)
; RELAY IN: PB0
; SDA=PC4, SCL=PC5
;------------------------------------------------------------------------------
.include "m328Pdef.inc"
.equ BAUD_RATE = 103 

.equ LCD_ADDR = 0x4E       
.equ RS = 0
.equ EN = 2
.equ BL = 3

.dseg
.org 0x0100
BASE_X_L: .byte 1
BASE_X_H: .byte 1
BASE_Y_L: .byte 1
BASE_Y_H: .byte 1
BASE_Z_L: .byte 1
BASE_Z_H: .byte 1
RR_STATE: .byte 1       
RR_TICKS: .byte 1       
CALIB_FLAG: .byte 1    
VIB_FAULT_COUNT: .byte 1    ; Retriggerable Timer for Sine Waves

.cseg
.org 0x0000
    rjmp RESET

; --- STORED TEXT STRINGS (16-CHARS MAX) ---
STR_BOOT:   .db "System Booting..", 0, 0
STR_TEST:   .db "Power ON Test.. ", 0, 0
STR_WAIT:   .db "Testing...      ", 0, 0
STR_READY:  .db "Ready to start  ", 0, 0
STR_REQ:    .db "Calib Required! ", 0, 0
STR_HOLD:   .db "Press Calib Btn ", 0, 0
STR_WARN:   .db "I Exceeds Rated!", 0, 0
STR_TRIP:   .db "TRIPPED: OVER I!", 0, 0
STR_VWARN:  .db "VIB WARN > 2.5! ", 0, 0
STR_CALIB:  .db "Calibrating..   ", 0, 0
STR_REM:    .db " s remain  ", 0
STR_RESET1: .db "Reset EPROM     ", 0, 0
STR_RESET2: .db "Success         ", 0, 0
STR_X:      .db "X:", 0, 0
STR_Y:      .db " Y:", 0
STR_Z:      .db "Z:", 0, 0
STR_V:      .db " V:", 0     
STR_I:      .db " I:", 0     
STR_T:      .db " T:", 0     
STR_V_RDY:  .db "V:", 0, 0

RESET:
    ldi r16, LOW(RAMEND)
    out SPL, r16
    ldi r16, HIGH(RAMEND)
    out SPH, r16

    ldi r16, 0
    sts RR_STATE, r16
    sts RR_TICKS, r16
    sts VIB_FAULT_COUNT, r16

    ldi r16, 0x70       
    out DDRD, r16
    ldi r16, 0x4C       
    out PORTD, r16

    ldi r16, 0x39       
    out DDRB, r16
    ldi r16, 0x00
    out PORTB, r16

    ldi r16, LOW(BAUD_RATE)
    sts UBRR0L, r16
    ldi r16, HIGH(BAUD_RATE)
    sts UBRR0H, r16
    ldi r16, (1<<TXEN0) 
    sts UCSR0B, r16
    ldi r16, (1<<UCSZ01) + (1<<UCSZ00) 
    sts UCSR0C, r16

    ldi r16, (1<<ADEN) + (1<<ADPS2) + (1<<ADPS1) + (1<<ADPS0)
    sts ADCSRA, r16

    rcall TWI_INIT
    rcall DELAY_MS_50
    rcall LCD_INIT

    ldi ZL, LOW(2*STR_BOOT)
    ldi ZH, HIGH(2*STR_BOOT)
    rcall PRINT_STRING

    rcall LOAD_EEPROM_TO_SRAM
    rcall DELAY_MS_50
    rcall DELAY_MS_50

    rjmp START_POWER_TEST

;==============================================================================
; SAFETY LAYER 1: 10-SECOND BLIND WAIT & INSTANT SNAPSHOT TEST
;==============================================================================
START_POWER_TEST:
    ldi r16, 0x80
    rcall LCD_CMD
    ldi ZL, LOW(2*STR_TEST)
    ldi ZH, HIGH(2*STR_TEST)
    rcall PRINT_STRING

POT_RESTART:
    ldi r28, 200        
    ldi r16, 10
    mov r2, r16         
    ldi r16, 20
    mov r3, r16         

    rcall PRINT_POT_TIME

POT_WAIT_LOOP:
    dec r3              
    brne POT_SKIP_LCD
    ldi r16, 20
    mov r3, r16         
    dec r2              
    rcall PRINT_POT_TIME
POT_SKIP_LCD:
    rcall DELAY_MS_50
    dec r28
    brne POT_WAIT_LOOP

POT_CHECK_INSTANT:
    ; 1. Check Voltage Bounds
    cbi PORTB, 5
    cbi PORTB, 4
    cbi PORTB, 3
    rcall DELAY_MS_5
    ldi r16, (1<<REFS0) + 0x03
    sts ADMUX, r16
    rcall READ_AC_PEAK    
    rcall SCALE_VOLT
    mov r12, r24        

    tst r25             
    brne POT_FAIL       
    cpi r24, 0        
    brcs POT_FAIL       
    cpi r24, 250        
    brcc POT_FAIL       

    ; 2. Check Temp Bounds
    cbi PORTB, 5
    sbi PORTB, 4
    cbi PORTB, 3
    rcall DELAY_MS_5
    ldi r16, (1<<REFS0) + 0x03
    sts ADMUX, r16
    rcall READ_ADC
    rcall SCALE_TEMP
    mov r10, r24        

    tst r25
    brne POT_FAIL       
    cpi r24, 60         
    brcc POT_FAIL       

    rjmp POT_PASSED

POT_FAIL:
    rjmp POT_RESTART

PRINT_POT_TIME:
    ldi r16, 0xC0
    rcall LCD_CMD
    ldi ZL, LOW(2*STR_WAIT)
    ldi ZH, HIGH(2*STR_WAIT)
    rcall PRINT_STRING

    ldi r16, 0xCB       
    rcall LCD_CMD
    mov r24, r2
    clr r25
    rcall PRINT_NUM
    ldi r16, 's'
    rcall LCD_DATA
    ldi r16, ' '        
    rcall LCD_DATA
    ret

POT_PASSED:
    in r16, PORTB
    ori r16, 0x01
    out PORTB, r16
    sbi PORTD, 5
    cbi PORTD, 6
    
    ldi r16, 0x80
    rcall LCD_CMD
    ldi ZL, LOW(2*STR_READY)
    ldi ZH, HIGH(2*STR_READY)
    rcall PRINT_STRING
    ldi r16, 0xC0
    rcall LCD_CMD
    ldi ZL, LOW(2*STR_V_RDY)
    ldi ZH, HIGH(2*STR_V_RDY)
    rcall PRINT_STRING
    mov r24, r12
    clr r25
    rcall PRINT_NUM
    ldi ZL, LOW(2*STR_T)
    ldi ZH, HIGH(2*STR_T)
    rcall PRINT_STRING
    mov r24, r10
    clr r25
    rcall PRINT_NUM
    
    ldi r26, 60
READY_DELAY:
    rcall DELAY_MS_50
    dec r26
    brne READY_DELAY

;==============================================================================
; SAFETY LAYER 2: CALIBRATION STATUS LOCK (DEBOUNCED)
;==============================================================================
CHECK_CALIB_STATUS:
    lds r16, CALIB_FLAG
    cpi r16, 1
    breq ENTER_MAIN_LOOP

CALIB_LOCKED:
    ldi r16, 0x80
    rcall LCD_CMD
    ldi ZL, LOW(2*STR_REQ)
    ldi ZH, HIGH(2*STR_REQ)
    rcall PRINT_STRING
    ldi r16, 0xC0
    rcall LCD_CMD
    ldi ZL, LOW(2*STR_HOLD)
    ldi ZH, HIGH(2*STR_HOLD)
    rcall PRINT_STRING
    
CALIB_WAIT_BTN:
    sbic PIND, 3            
    rjmp CALIB_WAIT_BTN
    rcall DELAY_MS_50       
    
CALIB_WAIT_REL:
    sbis PIND, 3            
    rjmp CALIB_WAIT_REL
    rcall DELAY_MS_50       
    
    rcall RUN_CALIBRATION   
    rjmp CHECK_CALIB_STATUS 

ENTER_MAIN_LOOP:
    ldi r16, 0x01       
    rcall LCD_CMD
    rcall DELAY_MS_5
    clr r23             

;==============================================================================
; MAIN DATA ACQUISITION LOOP
;==============================================================================
MAIN_LOOP:
    sbic PIND, 2
    rjmp CHECK_CALIB_BTN
    rcall TOGGLE_RELAY

CHECK_CALIB_BTN:
    sbic PIND, 3
    rjmp READ_SENSORS

    ldi r26, 100        
CHECK_HOLD:
    rcall DELAY_MS_50
    sbic PIND, 3        
    rjmp DO_CALIBRATE   
    dec r26
    brne CHECK_HOLD     

    rcall FACTORY_RESET_EEPROM
    rjmp CHECK_CALIB_STATUS    

DO_CALIBRATE:
    rcall RUN_CALIBRATION
    rjmp READ_SENSORS

READ_SENSORS:
    ; --- 1. READ ADXL335 (X) ---
    ldi r16, (1<<REFS0)
    sts ADMUX, r16
    rcall READ_ADC
    lds r16, BASE_X_L
    lds r17, BASE_X_H
    sub r24, r16        
    sbc r25, r17        
    rcall SCALE_AXIS    
    mov r4, r24
    mov r5, r25

    ; --- READ ADXL335 (Y) ---
    ldi r16, (1<<REFS0) + 0x01
    sts ADMUX, r16
    rcall READ_ADC
    lds r16, BASE_Y_L
    lds r17, BASE_Y_H
    sub r24, r16
    sbc r25, r17
    rcall SCALE_AXIS    
    mov r6, r24
    mov r7, r25

    ; --- READ ADXL335 (Z) ---
    ldi r16, (1<<REFS0) + 0x02
    sts ADMUX, r16
    rcall READ_ADC
    lds r16, BASE_Z_L
    lds r17, BASE_Z_H
    sub r24, r16
    sbc r25, r17
    rcall SCALE_AXIS    
    mov r8, r24
    mov r9, r25

    ; --- 2. READ MUX: VOLTAGE (A3, Y0) ---
    cbi PORTB, 5
    cbi PORTB, 4
    cbi PORTB, 3
    rcall DELAY_MS_5
    ldi r16, (1<<REFS0) + 0x03
    sts ADMUX, r16
    rcall READ_AC_PEAK    
    rcall SCALE_VOLT      
    mov r12, r24
    mov r13, r25

    ; --- 3. READ MUX: CURRENT (A3, Y1) ---
    cbi PORTB, 5
    cbi PORTB, 4
    sbi PORTB, 3
    rcall DELAY_MS_5
    ldi r16, (1<<REFS0) + 0x03
    sts ADMUX, r16
    rcall READ_AC_PEAK    
    rcall SCALE_CURR      
    mov r14, r24
    mov r15, r25

    ; =====================================================================
    ; SAFETY LAYER 3: OVERCURRENT HARD TRIP ( > 3.50 A )
    ; =====================================================================
    mov r16, r14
    mov r17, r15
    subi r16, LOW(350)
    sbci r17, HIGH(350)
    brcs I_IS_SAFE       
    rjmp SYSTEM_TRIPPED  
I_IS_SAFE:

    ; --- 4. READ MUX: TEMP (A3, Y2) ---
    cbi PORTB, 5
    sbi PORTB, 4
    cbi PORTB, 3
    rcall DELAY_MS_5
    ldi r16, (1<<REFS0) + 0x03
    sts ADMUX, r16
    rcall READ_ADC
    rcall SCALE_TEMP      
    mov r10, r24
    mov r11, r25

    ; --- TRANSMIT 16-BYTE UART PACKET (RAW DATA UNTOUCHED!) ---
    ldi r16, 0xAA 
    rcall UART_SEND
    ldi r16, 0xBB 
    rcall UART_SEND
    ldi r16, 0xCC 
    rcall UART_SEND
    mov r16, r5   
    rcall UART_SEND
    mov r16, r4   
    rcall UART_SEND
    mov r16, r7   
    rcall UART_SEND
    mov r16, r6   
    rcall UART_SEND
    mov r16, r9   
    rcall UART_SEND
    mov r16, r8   
    rcall UART_SEND
    mov r16, r11  
    rcall UART_SEND
    mov r16, r10  
    rcall UART_SEND
    mov r16, r13  
    rcall UART_SEND
    mov r16, r12  
    rcall UART_SEND
    mov r16, r15  
    rcall UART_SEND
    mov r16, r14  
    rcall UART_SEND
    in r16, PORTB
    andi r16, 0x01
    rcall UART_SEND

    ; =====================================================================
    ; RETRIGGERABLE VIBRATION FAULT LOGIC (SINE WAVE SAFE!)
    ; =====================================================================
    ; Check X Absolute
    movw r24, r4
    sbrs r25, 7
    rjmp X_POS
    com r25
    com r24
    subi r24, 0xFF
    sbci r25, 0xFF
X_POS:
    cpi r24, LOW(250)
    ldi r16, HIGH(250)
    cpc r25, r16
    brcc VIB_FAULT_DETECTED

    ; Check Y Absolute
    movw r24, r6
    sbrs r25, 7
    rjmp Y_POS
    com r25
    com r24
    subi r24, 0xFF
    sbci r25, 0xFF
Y_POS:
    cpi r24, LOW(250)
    ldi r16, HIGH(250)
    cpc r25, r16
    brcc VIB_FAULT_DETECTED

    ; Check Z Absolute
    movw r24, r8
    sbrs r25, 7
    rjmp Z_POS
    com r25
    com r24
    subi r24, 0xFF
    sbci r25, 0xFF
Z_POS:
    cpi r24, LOW(250)
    ldi r16, HIGH(250)
    cpc r25, r16
    brcc VIB_FAULT_DETECTED

    ; NO PEAK THIS LOOP -> Decay the timer if > 0
    lds r16, VIB_FAULT_COUNT
    tst r16
    breq LCD_UPDATE_TICK    ; If timer is 0, do nothing
    dec r16                 ; Decay timer
    sts VIB_FAULT_COUNT, r16
    rjmp LCD_UPDATE_TICK

VIB_FAULT_DETECTED:
    ; PEAK HIT! Slam the timer back up to 50 loops (~1s hold time)
    ldi r16, 50
    sts VIB_FAULT_COUNT, r16

LCD_UPDATE_TICK:
    ; --- UPDATE LCD ---
    inc r23
    cpi r23, 10
    brne SKIP_LCD_UPDATE
    rcall UPDATE_MAIN_LCD
    clr r23             
SKIP_LCD_UPDATE:
    rcall DELAY_MS_10
    rcall DELAY_MS_10
    rjmp MAIN_LOOP


;==============================================================================
; SYSTEM TRIPPED DEAD-LOCK
;==============================================================================
SYSTEM_TRIPPED:
    in r16, PORTB
    andi r16, 0xFE
    out PORTB, r16
    cbi PORTD, 5
    sbi PORTD, 6
    
    ldi r16, 0x01
    rcall LCD_CMD
    rcall DELAY_MS_5
    ldi r16, 0x80
    rcall LCD_CMD
    ldi ZL, LOW(2*STR_TRIP)
    ldi ZH, HIGH(2*STR_TRIP)
    rcall PRINT_STRING
    ldi r16, 0xC0
    rcall LCD_CMD
    ldi ZL, LOW(2*STR_TRIP)
    ldi ZH, HIGH(2*STR_TRIP)
    rcall PRINT_STRING
TRIP_LOCK:
    rjmp TRIP_LOCK  

;==============================================================================
; SUBROUTINE: UPDATE MAIN LCD (INDEPENDENT ROWS FOR SIMULTANEOUS ALARMS)
;==============================================================================
UPDATE_MAIN_LCD:
    ; ======================= LINE 1 LOGIC =======================
    ldi r16, 0x80       
    rcall LCD_CMD  

    ; Check if Vib Timer is active (>0)
    lds r16, VIB_FAULT_COUNT
    tst r16
    breq DO_NORMAL_LINE1

    ; Print Vibration Warning on Line 1
    ldi ZL, LOW(2*STR_VWARN)
    ldi ZH, HIGH(2*STR_VWARN)
    rcall PRINT_STRING
    rjmp CHECK_LINE2_WARN

DO_NORMAL_LINE1:
    ; Normal Line 1 (X and Y)
    ldi ZL, LOW(2*STR_X) 
    ldi ZH, HIGH(2*STR_X) 
    rcall PRINT_STRING
    mov r24, r4 
    mov r25, r5 
    rcall PRINT_DECIMAL
    ldi r16, ' ' 
    rcall LCD_DATA
    ldi ZL, LOW(2*STR_Y) 
    ldi ZH, HIGH(2*STR_Y) 
    rcall PRINT_STRING
    mov r24, r6 
    mov r25, r7 
    rcall PRINT_DECIMAL
    ldi r16, ' ' 
    rcall LCD_DATA

    ; ======================= LINE 2 LOGIC =======================
CHECK_LINE2_WARN:
    ldi r16, 0xC0       
    rcall LCD_CMD  

    ; Check Overcurrent Warning (> 3.20A)
    mov r16, r14
    mov r17, r15
    subi r16, LOW(320)
    sbci r17, HIGH(320)
    brcs DO_SENSORS_LINE2

    ; Print Overcurrent Warning on Line 2
    ldi ZL, LOW(2*STR_WARN)
    ldi ZH, HIGH(2*STR_WARN)
    rcall PRINT_STRING
    ret                     ; End of LCD Update

DO_SENSORS_LINE2:
    ; Normal Line 2 (Z and Scrolling Variables)
    ldi ZL, LOW(2*STR_Z) 
    ldi ZH, HIGH(2*STR_Z) 
    rcall PRINT_STRING
    mov r24, r8 
    mov r25, r9 
    rcall PRINT_DECIMAL
    
    lds r16, RR_STATE
    cpi r16, 0
    breq SHOW_V
    cpi r16, 1
    breq SHOW_I
    rjmp SHOW_T

SHOW_V:
    ldi ZL, LOW(2*STR_V) 
    ldi ZH, HIGH(2*STR_V) 
    rcall PRINT_STRING
    mov r24, r12 
    mov r25, r13 
    rcall PRINT_NUM       
    rjmp PUSH_SPACES

SHOW_I:
    ldi ZL, LOW(2*STR_I) 
    ldi ZH, HIGH(2*STR_I) 
    rcall PRINT_STRING
    mov r24, r14 
    mov r25, r15 
    rcall PRINT_DECIMAL    
    rjmp PUSH_SPACES

SHOW_T:
    ldi ZL, LOW(2*STR_T) 
    ldi ZH, HIGH(2*STR_T) 
    rcall PRINT_STRING
    mov r24, r10 
    mov r25, r11 
    rcall PRINT_NUM

PUSH_SPACES:
    ldi r16, ' '
    rcall LCD_DATA
    ldi r16, ' '
    rcall LCD_DATA
    ldi r16, ' '
    rcall LCD_DATA

    lds r16, RR_TICKS
    inc r16
    cpi r16, 20         
    brne SAVE_TICKS
    
    clr r16             
    lds r17, RR_STATE
    inc r17             
    cpi r17, 3
    brne SAVE_STATE
    clr r17             
SAVE_STATE:
    sts RR_STATE, r17
SAVE_TICKS:
    sts RR_TICKS, r16
    ret

;==============================================================================
; SUBROUTINE: FAST 50Hz PEAK-TO-PEAK DETECTOR
;==============================================================================
READ_AC_PEAK:
    clr r26             
    clr r27             
    ldi r16, 0xFF       
    mov r18, r16        
    mov r19, r16        
    ldi r21, 250        
AC_LOOP:
    lds r17, ADCSRA 
    ori r17, (1<<ADSC) 
    sts ADCSRA, r17
AC_WAIT: 
    lds r17, ADCSRA 
    sbrc r17, ADSC 
    rjmp AC_WAIT
    lds r24, ADCL 
    lds r25, ADCH
    cp r26, r24
    cpc r27, r25
    brcc CHECK_MIN      
    mov r26, r24        
    mov r27, r25
CHECK_MIN:
    cp r24, r18
    cpc r25, r19
    brcc AC_NEXT        
    mov r18, r24        
    mov r19, r25
AC_NEXT:
    dec r21             
    brne AC_LOOP        
    sub r26, r18        
    sbc r27, r19
    lsr r27             
    ror r26
    mov r24, r26        
    mov r25, r27
    ret

;==============================================================================
; HARDWARE DSP MATH: SENSOR SCALING ROUTINES
;==============================================================================
SCALE_AXIS:
    mov r16, r24
    mov r17, r25
    lsl r24
    rol r25
    lsl r24
    rol r25
    lsl r24
    rol r25
    lsl r24
    rol r25
    sub r24, r16
    sbc r25, r17
    ret

SCALE_VOLT:
    ; --- 1. DIGITAL NOISE GATE ---
    cpi r25, 0       
    brne DO_VOLT
    cpi r24, 40      ; Safely blocks background static and phantom voltage
    brcc DO_VOLT
    
    ; Clamp to absolute 0
    clr r24
    clr r25
    ret

DO_VOLT:
    ; --- 2. BASELINE HARDWARE SCALING ---
    ; Math: Voltage = (Peak * 4 * 198) / 256
    
    ; Multiply Peak by 4 (Shift left TWICE)
    lsl r24
    rol r25
    lsl r24
    rol r25
    
    ; Stable baseline multiplier
    ldi r16, 198     
    mul r24, r16
    mov r18, r1
    mul r25, r16
    add r18, r0
    
    ; Output
    mov r24, r18
    clr r25          
    ret

SCALE_CURR:
    cpi r25, 0          
    brne DO_CURR
    cpi r24, 15         
    brcc DO_CURR
    clr r24
    clr r25
    ret
DO_CURR:
    ldi r16, 2          
    mul r24, r16        
    mov r18, r0         
    mov r19, r1         
    mul r25, r16        
    add r19, r0         
    mov r24, r18        
    mov r25, r19
    clr r1              
    ret

SCALE_TEMP:
    ldi r16, 23
    mul r24, r16
    mov r18, r1
    mul r25, r16
    add r18, r0
    mov r24, r18
    clr r25
    subi r24, 21
    brcc TEMP_DONE
    clr r24             
TEMP_DONE:
    ret

;==============================================================================
; SUBROUTINE: FACTORY RESET EEPROM
;==============================================================================
FACTORY_RESET_EEPROM:
    ldi r18, 0x00       
    ldi r16, 0x00       
    ldi r17, 0x00 
    rcall EEPROM_WRITE
    ldi r17, 0x01 
    rcall EEPROM_WRITE
    ldi r17, 0x02 
    rcall EEPROM_WRITE
    ldi r17, 0x03 
    rcall EEPROM_WRITE
    ldi r17, 0x04 
    rcall EEPROM_WRITE
    ldi r17, 0x05 
    rcall EEPROM_WRITE
    
    ldi r17, 0x06
    ldi r16, 0x00
    rcall EEPROM_WRITE
    
    rcall LOAD_EEPROM_TO_SRAM

    ldi r16, 0x01       
    rcall LCD_CMD
    rcall DELAY_MS_5
    ldi r16, 0x80       
    rcall LCD_CMD
    ldi ZL, LOW(2*STR_RESET1)
    ldi ZH, HIGH(2*STR_RESET1)
    rcall PRINT_STRING
    ldi r16, 0xC0       
    rcall LCD_CMD
    ldi ZL, LOW(2*STR_RESET2)
    ldi ZH, HIGH(2*STR_RESET2)
    rcall PRINT_STRING

    ldi r26, 10         
FLICKER_LOOP:
    in r16, PORTD
    ldi r17, (1<<4)
    eor r16, r17        
    out PORTD, r16
    rcall DELAY_MS_50
    dec r26             
    brne FLICKER_LOOP
    cbi PORTD, 4        
WAIT_RST_REL:
    sbis PIND, 3        
    rjmp WAIT_RST_REL
    rcall DELAY_MS_50
    rcall DELAY_MS_50
    ldi r16, 0x01       
    rcall LCD_CMD
    rcall DELAY_MS_5
    
    pop r16
    pop r16
    rjmp CHECK_CALIB_STATUS

;==============================================================================
; SUBROUTINE: TOGGLE RELAY (WITH TRAP)
;==============================================================================
TOGGLE_RELAY:
    in r16, PORTB
    ldi r17, 0x01
    eor r16, r17
    out PORTB, r16
    sbrc r16, 0
    rjmp RELAY_IS_ON
RELAY_IS_OFF:
    cbi PORTD, 5
    sbi PORTD, 6
    rjmp RELAY_DONE
RELAY_IS_ON:
    sbi PORTD, 5
    cbi PORTD, 6
RELAY_DONE:
    rcall DELAY_MS_50       
WAIT_RELAY_RELEASE:
    sbis PIND, 2            
    rjmp WAIT_RELAY_RELEASE 
    rcall DELAY_MS_50       
    ret

;==============================================================================
; SUBROUTINE: 10-SECOND CALIBRATION
;==============================================================================
RUN_CALIBRATION:
    sbi PORTD, 4        
    clr r2 
    clr r3 
    clr r4  
    clr r5 
    clr r6 
    clr r7  
    clr r8 
    clr r9 
    clr r10 
    ldi r16, 0x01 
    rcall LCD_CMD  
    rcall DELAY_MS_5
    ldi r26, 0          
    ldi r27, 10         
CALIB_LOOP:
    ldi r16, (1<<REFS0)
    sts ADMUX, r16
    rcall READ_ADC 
    clr r17
    add r2, r24 
    adc r3, r25 
    adc r4, r17          
    
    ldi r16, (1<<REFS0) + 0x01 
    sts ADMUX, r16
    rcall READ_ADC 
    clr r17
    add r5, r24 
    adc r6, r25 
    adc r7, r17
    
    ldi r16, (1<<REFS0) + 0x02 
    sts ADMUX, r16
    rcall READ_ADC 
    clr r17
    add r8, r24 
    adc r9, r25 
    adc r10, r17

    mov r16, r26
    cpi r16, 0
    brne CHECK_25
    rjmp DO_CALIB_LCD
CHECK_25:
    cpi r16, 25 
    breq DO_CALIB_LCD
    cpi r16, 50 
    breq DO_CALIB_LCD
    cpi r16, 75 
    breq DO_CALIB_LCD
    cpi r16, 100
    breq DO_CALIB_LCD
    cpi r16, 125
    breq DO_CALIB_LCD
    cpi r16, 150
    breq DO_CALIB_LCD
    cpi r16, 175
    breq DO_CALIB_LCD
    cpi r16, 200
    breq DO_CALIB_LCD
    cpi r16, 225
    breq DO_CALIB_LCD
    cpi r16, 250
    breq DO_CALIB_LCD
    rjmp SKIP_CALIB_LCD
DO_CALIB_LCD:
    ldi r16, 0x80 
    rcall LCD_CMD
    ldi ZL, LOW(2*STR_CALIB) 
    ldi ZH, HIGH(2*STR_CALIB) 
    rcall PRINT_STRING
    ldi r16, 0xC0 
    rcall LCD_CMD
    mov r24, r27 
    clr r25 
    rcall PRINT_NUM 
    ldi ZL, LOW(2*STR_REM) 
    ldi ZH, HIGH(2*STR_REM) 
    rcall PRINT_STRING
    dec r27
SKIP_CALIB_LCD:
    rcall DELAY_MS_10
    rcall DELAY_MS_10
    rcall DELAY_MS_10
    
    dec r26
    breq CALIB_DONE
    rjmp CALIB_LOOP

CALIB_DONE:
    ldi r18, 0x00       
    ldi r17, 0x00 
    mov r16, r3 
    rcall EEPROM_WRITE
    ldi r17, 0x01 
    mov r16, r4 
    rcall EEPROM_WRITE
    ldi r17, 0x02 
    mov r16, r6 
    rcall EEPROM_WRITE
    ldi r17, 0x03 
    mov r16, r7 
    rcall EEPROM_WRITE
    ldi r17, 0x04 
    mov r16, r9 
    rcall EEPROM_WRITE
    ldi r17, 0x05 
    mov r16, r10
    rcall EEPROM_WRITE
    
    ldi r17, 0x06
    ldi r16, 0x01
    rcall EEPROM_WRITE
    
    rcall LOAD_EEPROM_TO_SRAM
    cbi PORTD, 4        
    ldi r16, 0x01 
    rcall LCD_CMD  
    rcall DELAY_MS_5
WAIT_RELEASE_CAL:
    sbis PIND, 3        
    rjmp WAIT_RELEASE_CAL
    rcall DELAY_MS_50    
    ret

;==============================================================================
; PRINTING & HARDWARE DRIVERS
;==============================================================================
PRINT_STRING:
    lpm r16, Z+
    tst r16
    breq PRINT_STRING_END
    rcall LCD_DATA
    rjmp PRINT_STRING
PRINT_STRING_END:
    ret

PRINT_NUM:
    sbrs r25, 7         
    rjmp POSITIVE_NUM
    ldi r16, '-'        
    rcall LCD_DATA
    com r25             
    com r24
    subi r24, 0xFF
    sbci r25, 0xFF
POSITIVE_NUM:
    ldi r20, 0          
DIV_100:
    cpi r24, LOW(100) 
    ldi r16, HIGH(100) 
    cpc r25, r16 
    brcs PRINT_100
    subi r24, LOW(100) 
    sbci r25, HIGH(100) 
    inc r20 
    rjmp DIV_100
PRINT_100:
    cpi r20, 0
    breq SKIP_100
    mov r16, r20 
    subi r16, -48 
    rcall LCD_DATA
SKIP_100:
    ldi r20, 0          
DIV_10:
    cpi r24, 10 
    brcs PRINT_10
    subi r24, 10 
    inc r20 
    rjmp DIV_10
PRINT_10:
    mov r16, r20 
    subi r16, -48 
    rcall LCD_DATA
    mov r16, r24 
    subi r16, -48 
    rcall LCD_DATA 
    ret

PRINT_DECIMAL:
    sbrs r25, 7
    rjmp PD_POSITIVE
    ldi r16, '-'
    rcall LCD_DATA
    com r25
    com r24
    subi r24, 0xFF
    sbci r25, 0xFF
PD_POSITIVE:
    ldi r20, 0
DIV1000_D:
    cpi r24, LOW(1000)
    ldi r16, HIGH(1000)
    cpc r25, r16
    brcs PRT1000_D
    subi r24, LOW(1000)
    sbci r25, HIGH(1000)
    inc r20
    rjmp DIV1000_D
PRT1000_D:
    cpi r20, 0
    breq SKIP_T_D
    mov r16, r20
    subi r16, -48
    rcall LCD_DATA
SKIP_T_D:
    ldi r20, 0
DIV100_D:
    cpi r24, LOW(100)
    ldi r16, HIGH(100)
    cpc r25, r16
    brcs PRT100_D
    subi r24, LOW(100)
    sbci r25, HIGH(100)
    inc r20
    rjmp DIV100_D
PRT100_D:
    mov r16, r20
    subi r16, -48
    rcall LCD_DATA
    ldi r16, '.'
    rcall LCD_DATA
    ldi r20, 0
DIV10_D:
    cpi r24, 10
    brcs PRT10_D
    subi r24, 10
    inc r20
    rjmp DIV10_D
PRT10_D:
    mov r16, r20
    subi r16, -48
    rcall LCD_DATA
    mov r16, r24
    subi r16, -48
    rcall LCD_DATA
    ret

EEPROM_WRITE:
    sbic EECR, EEPE 
    rjmp EEPROM_WRITE
    out EEARH, r18 
    out EEARL, r17 
    out EEDR, r16
    sbi EECR, EEMPE 
    sbi EECR, EEPE
    ret

EEPROM_READ:
    sbic EECR, EEPE 
    rjmp EEPROM_READ
    out EEARH, r18 
    out EEARL, r17 
    sbi EECR, EERE 
    in r16, EEDR
    ret

LOAD_EEPROM_TO_SRAM:
    ldi r18, 0x00
    ldi r17, 0x00 
    rcall EEPROM_READ 
    sts BASE_X_L, r16
    ldi r17, 0x01 
    rcall EEPROM_READ 
    sts BASE_X_H, r16
    ldi r17, 0x02 
    rcall EEPROM_READ 
    sts BASE_Y_L, r16
    ldi r17, 0x03 
    rcall EEPROM_READ 
    sts BASE_Y_H, r16
    ldi r17, 0x04 
    rcall EEPROM_READ 
    sts BASE_Z_L, r16
    ldi r17, 0x05 
    rcall EEPROM_READ 
    sts BASE_Z_H, r16
    
    ldi r17, 0x06
    rcall EEPROM_READ
    sts CALIB_FLAG, r16
    ret

READ_ADC:
    lds r17, ADCSRA 
    ori r17, (1<<ADSC) 
    sts ADCSRA, r17
W_AD: 
    lds r17, ADCSRA 
    sbrc r17, ADSC 
    rjmp W_AD
    lds r24, ADCL 
    lds r25, ADCH
    ret

UART_SEND:
    lds r17, UCSR0A 
    sbrs r17, UDRE0 
    rjmp UART_SEND
    sts UDR0, r16
    ret

TWI_INIT:
    ldi r16, 0x00
    sts TWSR, r16
    ldi r16, 72
    sts TWBR, r16
    ldi r16, (1<<TWEN)
    sts TWCR, r16
    ret
TWI_START:
    ldi r16, (1<<TWINT) + (1<<TWSTA) + (1<<TWEN)
    sts TWCR, r16
TWI_START_WAIT:
    lds r16, TWCR
    sbrs r16, TWINT
    rjmp TWI_START_WAIT
    ret
TWI_STOP:
    ldi r16, (1<<TWINT) + (1<<TWEN) + (1<<TWSTO)
    sts TWCR, r16
    ret
TWI_WRITE:
    sts TWDR, r16
    ldi r16, (1<<TWINT) + (1<<TWEN)
    sts TWCR, r16
TWI_WRITE_WAIT:
    lds r16, TWCR
    sbrs r16, TWINT
    rjmp TWI_WRITE_WAIT
    ret
LCD_SEND:
    rcall TWI_START
    ldi r16, LCD_ADDR
    rcall TWI_WRITE
    mov r16, r17
    rcall TWI_WRITE
    rcall TWI_STOP
    ret
LCD_PULSE:
    mov r17, r18
    ori r17, (1<<EN)
    rcall LCD_SEND
    rcall DELAY_US
    mov r17, r18
    andi r17, 0xFB
    rcall LCD_SEND
    rcall DELAY_US
    ret
LCD_WRITE4:
    mov r18, r16
    andi r18, 0xF0
    ori r18, (1<<BL)
    tst r19
    breq LCD_NO_RS
    ori r18, (1<<RS)
LCD_NO_RS:
    rcall LCD_PULSE
    ret
LCD_SEND8:
    push r16
    rcall LCD_WRITE4
    pop r16
    swap r16
    rcall LCD_WRITE4
    rcall DELAY_MS_2
    ret
LCD_CMD:
    clr r19
    rcall LCD_SEND8
    ret
LCD_DATA:
    ldi r19, 1
    rcall LCD_SEND8
    ret
LCD_INIT:
    rcall DELAY_MS_50
    clr r19
    ldi r16, 0x30
    rcall LCD_WRITE4
    rcall DELAY_MS_5
    ldi r16, 0x30
    rcall LCD_WRITE4
    rcall DELAY_MS_5
    ldi r16, 0x30
    rcall LCD_WRITE4
    rcall DELAY_MS_5
    ldi r16, 0x20
    rcall LCD_WRITE4
    rcall DELAY_MS_5
    ldi r16, 0x28
    rcall LCD_CMD
    ldi r16, 0x0C
    rcall LCD_CMD
    ldi r16, 0x06
    rcall LCD_CMD
    ldi r16, 0x01
    rcall LCD_CMD
    rcall DELAY_MS_5
    ret
DELAY_US:
    nop
    nop
    nop
    nop
    ret
DELAY_MS_1:
    ldi r21, 250
DMS1_1:
    ldi r22, 16
DMS1_2:
    dec r22
    brne DMS1_2
    dec r21
    brne DMS1_1
    ret
DELAY_MS_2:
    ldi r20, 2
DMS2_LOOP:
    rcall DELAY_MS_1
    dec r20
    brne DMS2_LOOP
    ret
DELAY_MS_5:
    ldi r20, 5
DMS5_LOOP:
    rcall DELAY_MS_1
    dec r20
    brne DMS5_LOOP
    ret
DELAY_MS_10:
    ldi r20, 10
D10_LOOP:
    rcall DELAY_MS_1
    dec r20
    brne D10_LOOP
    ret
DELAY_MS_50:
    ldi r20, 50
DMS50_LOOP:
    rcall DELAY_MS_1
    dec r20
    brne DMS50_LOOP
    ret