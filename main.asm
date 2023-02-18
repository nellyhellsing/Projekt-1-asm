.EQU LED1 = PORTB0    ; led1 ansluten till pin 8.
.EQU LED2 = PORTB1    ; led2 ansluten till pin 9.
.EQU BUTTON1 = PORTB4 ; button1 ansluten till 12.
.EQU BUTTON2 = PORTB5 ; button2 ansluten till 13.
.EQU BUTTON3 = PORTB3 ; button3 ansluten till 11.

.EQU TIMER0_MAX_COUNT = 18   ; Motsvarar ca 300 ms f�rdr�jning.
.EQU TIMER1_MAX_COUNT = 6    ; Motsvarar ca 100 ms f�rdr�jning.
.EQU TIMER2_MAX_COUNT = 12   ; Motsvarar ca 200 ms f�rdr�jning.

.EQU RESET_vect        = 0x00 ; Reset-vektor, programmets startpunkt.
.EQU PCINT0_vect       = 0x06 ; Avbrottsvektor f�r PCI-avbrott p� I/O-port B.
.EQU TIMER2_OVF_vect   = 0x12 ; Avbrottsvektor f�r Timer 2 i Normal Mode.
.EQU TIMER1_COMPA_vect = 0x16 ; Avbrottsvektor f�r Timer 1 i CTC Mode.
.EQU TIMER0_OVF_vect   = 0x20 ; Avbrottsvektor f�r Timer 0 i Normal Mode.



;********************************************************************************
; I R16 ligger (1 << LED1) = 0000 0001, samma som (1 << TOIE0) och (1 << PCIE0).
; I R17 ligger (1 << LED2) = 0000 0010, samma som (1 << OCIE1A). TIMER 2
;********************************************************************************

;********************************************************************************
; .DSEG: Dataminnet, h�r lagras statiska variabler. F�r att allokera minne f�r
;        en variabel anv�nds f�ljande syntax:
;
;        variabelnamn: .datatyp antal_byte
;********************************************************************************
.DSEG
.ORG SRAM_START
counter0: .byte 1 ; static uint8_t counter0 = 0;
counter1: .byte 1 ; static uint8_t counter1 = 0;
counter2: .byte 1 ; static uint8_t counter2 = 0;

;********************************************************************************
; .CSEG: Programminnet - H�r lagrar programkoden.
;********************************************************************************
.CSEG

;********************************************************************************
;* RESET_vect: Hoppar till subrutinen main f�r att starta programmet.
;********************************************************************************
.ORG RESET_vect
   RJMP main

;/********************************************************************************
;* PCINT0_vect: Avbrottsvektor f�r PCI-avbrott p� I/O-port B, som �ger rum vid
;*              nedtryckning eller uppsl�ppning av n�gon av tryckknapparna.
;*              Hopp sker till motsvarande avbrottsrutin ISR_PCINT0 f�r att
;*              hantera avbrottet.
;********************************************************************************/
.ORG PCINT0_vect
   RJMP ISR_PCINT0

;********************************************************************************
; TIMER2_OVF_vect: Avbrottsvektor f�r overflow-avbrott p� Timer 2.
;********************************************************************************
.ORG TIMER2_OVF_vect
   RJMP ISR_TIMER2_OVF

;********************************************************************************
; TIMER1_COMPA_vect: Avbrottsvektor f�r CTC-avbrott p� Timer 1.
;********************************************************************************
.ORG TIMER1_COMPA_vect
   RJMP ISR_TIMER1_COMPA

;********************************************************************************
; TIMER0_OVF_vect: Avbrottsvektor f�r overflow-avbrott p� Timer 0.
;********************************************************************************
.ORG TIMER0_OVF_vect
   RJMP ISR_TIMER0_OVF


;********************************************************************************
; ISR_PCINT0: Avbrottsrutin f�r PCI-avbrott p� I/O-port, som anropas vid
;             nedtryckning och uppsl�ppning av tryckknappar. Vid nedtryckning
;             togglas Timer 1 alt timer 2. Om Timer 1 eller 2 st�ngs av sl�cks 
;             den tilldelade lysdioden.
;********************************************************************************
ISR_PCINT0:
   CLR R24
   STS PCICR, R24
   STS TIMSK0, R16
ISR_PCINT0_1:
   IN R24, PINB            
   ANDI R24, (1 << BUTTON1) 
   BREQ ISR_PCINT0_2     
   CALL timer1_toggle
   RETI       
ISR_PCINT0_2:
   IN R24, PINB            
   ANDI R24, (1 << BUTTON2) 
   BREQ ISR_PCINT0_3     
   CALL timer2_toggle
   RETI        
ISR_PCINT0_3:
   IN R24, PINB
   ANDI R24, (1 << BUTTON3)
   BREQ ISR_PCINT0_end
   CALL system_reset
ISR_PCINT0_end:
   RETI  


;********************************************************************************
; ISR_TIMER2_OVF: Avbrottsrutin f�r overflow-avbrott p� Timer 0-2.
;********************************************************************************
;Timer2
ISR_TIMER2_OVF:
   LDS R24, counter2         
   INC R24                   
   CPI R24, TIMER2_MAX_COUNT 
   BRLO ISR_TIMER2_OVF_end   
   OUT PINB, R17             
   CLR R24                  
ISR_TIMER2_OVF_end:
   STS counter2, R24         
   RETI  
; Timer 1
ISR_TIMER1_COMPA:
   LDS R24, counter1
   INC R24
   CPI R24, TIMER1_MAX_COUNT
   BRLO ISR_TIMER1_COMPA_end
   OUT PINB, R16
   CLR R24
ISR_TIMER1_COMPA_end:
   STS counter1, R24
   RETI

; Timer 0
ISR_TIMER0_OVF:
   LDS R24, counter0
   INC R24
   CPI R24, TIMER0_MAX_COUNT
   BRLO ISR_TIMER0_OVF_end
   LDI R24, (1 << PCIE0)
   STS PCICR, R24
   CLR R24
   STS TIMSK0, R24
ISR_TIMER0_OVF_end:
   STS counter0, R24
   RETI
 
;********************************************************************************
; main: Initierar systemet vid start. Programmet h�lls sedan ig�ng s� l�nge
;       matningssp�nning tillf�rs.
;********************************************************************************
main:
   RCALL setup
   main_loop:
   RJMP main_loop

;********************************************************************************
; setup: Initierar I/O-portar samt aktiverar timerkretsar Timer 0 - Timer 2 s�
;        att timeravbrott sker.
;        F�rst s�tts lysdiodernas pinnar till utportar. 
;        D�refter sparas v�rden i CPU-register R16 och R17 f�r att enkelt toggla
;        de enskilda lysdioderna. Knapparna sparas i R18.
;        Sedan aktiveras avbrott globalt.
;********************************************************************************
setup:
   LDI R16, (1 << LED1) | (1 << LED2)
   OUT DDRB, R16 

   LDI R16, (1 << LED1) 
   LDI R17, (1 << LED2) 

   LDI R18, (1 << BUTTON1) | (1 << BUTTON2) | (1 << BUTTON3)
   OUT PORTB, R18

   SEI
   STS PCICR, R16
   STS PCMSK0, R18

   ; Avbrott timer 0
   LDI R25, (1 << CS02) | (1 << CS00)
   OUT TCCR0B, R25
   
   ; Avbrott timer 1
   LDI R25, (1 << WGM12) | (1 << CS12) | (1 << CS10)
   STS TCCR1B, R25
   LDI R25, high (256)
   STS OCR1AH, R25
   LDI R25, low (256)
   STS OCR1AL, R25

   ;Avbrott timer 2
   LDI R27, (1 << CS22) | (1 << CS21) | (1 << CS20)
   STS TCCR2B, R27
   RET
 
 
 
;*******************************************************************
; �vriga subrutiner:
;*******************************************************************     

system_reset: ; st�nger av timer 1 och tv�.
    CALL timer1_off
	CALL timer2_off
	RET 

timer1_toggle: ; Togglar timer1
   LDS R24, TIMSK1       
   ANDI R24, (1 << OCIE1A)  
   BRNE timer1_off  
          
timer1_on:    ; S�tter p� timer1        
   STS TIMSK1, R17  ; TIMSK1 = (1 << OCIE1A);        
   RET 
                   
timer1_off:   ; st�nger av timer1
   CLR R24                  
   STS TIMSK1, R24         
   IN R24, PORTB            
   ANDI R24, ~(1 << LED1) 
   OUT PORTB, R24   
   RET

timer2_toggle:  ; Togglar timer2
   LDS R24, TIMSK2        
   ANDI R24, (1 << TOIE2)  
   BRNE timer2_off    
        
timer2_on:      ; s�tter p� timer2       
   STS TIMSK2, R16  ; TIMSK2 = (1 << TOIE2);        
   RET               
     
timer2_off:     ; st�nger av timer2
   CLR R24                  
   STS TIMSK2, R24         
   IN R24, PORTB            
   ANDI R24, ~(1 << LED2) 
   OUT PORTB, R24
   RET  
                








