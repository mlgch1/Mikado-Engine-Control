;**********************************************************************
;                                                                     *
;    filename:        engine.asm                                      *
;    date:            Dec 2013                                        *
;    file version:                                                    *
;                                                                     *
;    author:          gjc                                             *
;    company:                                                         *
;                                                                     *
;                                                                     *
;**********************************************************************
;                                                                     *
;    files required:                                                  *
;       f:\pics\Mikado_Engine - pic16f916\program\p16f916.inc         *
;                                                                     *
;                                                                     *
;**********************************************************************
;                                                                     *
;    notes:                                                           *
;                                                                     *
;        ra0        input        Up Button        low - active        *
;        ra1        input        Down Button      low - active        *
;        ra2        input        Forward Button   low - active        *
;        ra3        input        Reverse Button   low - active        *
;        ra4        input	   Start Lock Inhibit                   *
;        ra5        input        Actuator Pulse                       *
;        ra6                                                          *
;        ra7                                                          *
;                                                                     *
;        rb0        output       Start Lock                           *
;        rb1        output	   Buzzer                               *
;        rb2        output       Forward Gear                         *
;        rb3        output       Reverse Gear                         *
;                                                                     *
;                                                                     *
;        rc0        output       Clutch         }                     *
;        rc1        output       Motor +        }  Throttle           *
;        rc2        output       Motor -        }                     *
;                                                                     *
;                   timer 0 used for contact de-bounce                *
;                   timer 1 not used                                  *
;                   timer 2 used as base counter for timers.          *
;                                                                     *
;**********************************************************************


          list                p=pic16f916 	; list directive to define processor

; processor specific variable definitions	

          #include       "f:\pics\Mikado_Engine-pic16f916\program\Mikado_Engine_Control.X\p16f916.inc"

          errorlevel          -302           ; suppress message 302s from list file
          errorlevel          -306           ; suppress message 306s from list file

; program configuration register

          __config            _cp_off & _debug_off & _cp_off & _cpd_off & _boren_off & _mclre_on & _pwrte_off & _wdt_off & _hs_osc & _ieso_off & _fcmen_off

#define   _c                  status,0                 
#define   _z                  status,2                 

#define   _dn_button_bit      0                        
#define   _up_button_bit      1                        
#define   _rev_button_bit     2                        
#define   _fwd_button_bit     3                        
#define   _start_inhibit_bit  4                        
#define   _act_bit            5                        

#define   _start_bit          0                        
#define   _buzz_bit           1                        
#define   _fwd_bit            2                        
#define   _rev_bit            3                        

#define   _clutch_bit         0                        
#define   _throttle_plus_bit  1                        
#define   _throttle_neg_bit   2                        

#define   _dn_button          porta,_dn_button_bit     
#define   _up_button          porta,_up_button_bit     
#define   _fwd_button         porta,_fwd_button_bit    
#define   _rev_button         porta,_rev_button_bit    
#define   _start_inhibit      porta,_start_inhibit_bit           
#define   _act                porta,_act_bit           

#define   _start              portb_sh,_start_bit         
#define   _buzz               portb_sh,_buzz_bit         
#define   _fwd                portb_sh,_fwd_bit           
#define   _rev                portb_sh,_rev_bit           

#define   _clutch             portc_sh,_clutch_bit        
#define   _throttle_plus      portc_sh,_throttle_plus_bit 
#define   _throttle_neg       portc_sh,_throttle_neg_bit  

#define   porta_bits          b'00111111'              
#define   portb_bits          b'00000000'              
#define   portc_bits          b'00000000'              

; Gear States

#define   neutral             0                        
#define   forward             1                        
#define   reverse             2                        
#define   n_to_f              3                        
#define   n_to_r              4                        
#define   f_to_n              5                        
#define   r_to_n              6                        

; Timer periods

#define   z_base_cntr_period  d'1'                     ; base of timer

#define   z_init_timer        d'200'                   

#define   z_up_high_period    d'5'                     
#define   z_up_low_period     d'10'                     
#define   z_up_delay_period   d'10'                     

#define   z_dn_high_period    d'5'                     
#define   z_dn_low_period     d'10'                     
#define   z_dn_delay_period   d'10'                     

; Miscellaneous

#define   z_neutral           d'25'                    

;===================================================================================

          cblock              0x20                     

; Timers & Timer Flags

		f_init_timer                                 
		t_init_timer                            

		f_up_initial
		f_up_high
		t_up_high
		f_up_low
		t_up_low
		f_up_delay
		t_up_delay

		f_dn_initial
		f_dn_high
		t_dn_high
		f_dn_low
		t_dn_low
		f_dn_delay
		t_dn_delay
		
; States

          s_up_button                     ; State of Up Button - Pressed = set
          s_dn_button                     ; State of Dn Button - Pressed = set
          s_fwd_button                    ; State of Forward Button - Pressed = set
          s_rev_button                    ; State of Reverse Button - Pressed = set
          s_act                           ; State of Actuator input
          s_buzz                          ; Buzzer on or off

          s_gear_state                                 

          act_cntr                        ; Gear shift counter

; Flags		
		f_start
		
          endc                                         

;***********

; all banks ram (70 to 7f)

          cblock              0x70                     

          portb_sh
          portc_sh
          
          w_temp                          ; storage of w before interrupt
          status_temp                     ; status storage before interrupt
          pclath_temp                     ; pclath store

          t_base_timer_cntr                            
          clk_cnt                                      

          laststablestate           ; keep track of switch states (open-0; closed-1)
          input_change              ; high bit indicates which input has changed

          loopcount                                    

          endc                                         

;========================================================================================
;========================================================================================
;========================================================================================
          org                 0x000                    ; processor reset vector
          goto                init                     ; go to beginning of program
;========================================================================================
;========================================================================================
;========================================================================================

          org                 0x004                    ; interrupt vector location

interrupt:                                             
          movwf               w_temp                   ; save off current w register contents
          movf                status,w                 ; move status register into w register
          movwf               status_temp              ; save off contents of status register
          movf                pclath,w                 ; move pclath register into w register
          movwf               pclath_temp              ; save off contents of pclath register

          pagesel             interrupts               
          call                interrupts               
          pagesel             $                        

          movf                pclath_temp,w            ; retrieve copy of pclath register
          movwf               pclath                   ; restore pre-isr pclath register
          movf                status_temp,w            ; retrieve copy of status register
          movwf               status                   ; restore pre-isr status register
          swapf               w_temp,f                 
          swapf               w_temp,w                 ; restore pre-isr w register

          retfie                                       ; return from interrupt

;========================================================================================

          org                 0x20                     

;***********
;***********
init:                                                  
;***********
;***********
          banksel             osccon                   
          movlw               b'01100000'              ; internal clock 4 mhz
          movwf               osccon                   

          banksel             t1con                    
          clrf                t1con                    ; timer 1 is off
          clrf                ccp1con                  ; ccp module is off
          clrf                sspcon                   ; serial port disabled
          clrf                rcsta                    ; ausart disabled

; Timer 0
          banksel             option_reg               
          movlw               b'10000111'              ; prescalar for timer 0  
          									; 256 Port B pullups disabled
          movwf               option_reg               

; Port A
          banksel             porta                    
          clrf                porta                    ; clear all outputs

          banksel             cmcon0                   
          movlw               b'00000111'              
          movwf               cmcon0                   ; comparitors off

          banksel             ansel                    
          clrf                ansel                    ; all input pins digital (not analogue)

          banksel             trisa                    
          movlw               porta_bits               
          movwf               trisa                    ; porta inputs and outputs

; Port B
          banksel			iocb
          clrf				iocb
          
          banksel             trisb                    
          movlw               portb_bits               
          movwf               trisb                    ; portb inputs and outputs

          banksel             portb                    
          clrf                portb                    ; clear all outputs

; Port C
          banksel             portc                    
          clrf                portc                    ; clear all outputs

          banksel             trisc                    
          movlw               portc_bits               
          movwf               trisc                    ; portc inputs and outputs

          banksel             lcdcon                   
          clrf                lcdcon                   

; Clear RAM 0x20 to 0x50
          movlw               0x20                     
          movwf               fsr                      

          movlw               0x30                      
          movwf               loopcount                
loop:                                                  
          clrf                indf                     
          incf                fsr,f                    

          decfsz              loopcount,f              
          goto                loop                     

; Clear All Banks RAM
          clrf				portb_sh
          clrf				portc_sh
          
          clrf				laststablestate          ; keep track of switch states 
          									; (open-0; closed-1)
          clrf				input_change			; high bit indicates which input 
          									; has changed

; Read Start Inhibit
          banksel			porta
          movlw               porta_bits               ; read startup states - port a
          andwf               porta,w                  
          movwf               laststablestate          

		btfss			laststablestate,_start_inhibit_bit 
          goto				st_inh_on
          
          call                start_off                
          goto				cl_off

st_inh_on:          
          call				start_on
          
cl_off:          
          call                clutch_off               
          call                throttle_off             
          call                gear_off                 
          call				buzz_off

; Check Buttons - high = set = off        low = reset = on

test_fwd:                                              
          banksel             porta                    
          btfsc               _fwd_button              ; check Forward button is off
          goto                test_rev                 ; off
test_fwd1:                                             
          call                buzz_on                  
          btfss               _fwd_button              ; on - loop till off
          goto                test_fwd1                
test_rev:                                              
          banksel             porta                    
          btfsc               _rev_button              ; check Reverse button is off
          goto                test_ok                  ; off
test_rev1:                                             
          call                buzz_on                  
          btfss               _rev_button              ; on - loop till off
          goto                test_rev1                

test_ok:                                               
          call                buzz_off                 

; Read Ports
          movlw               porta_bits               ; read startup states - port a
          andwf               porta,w                  
          movwf               laststablestate          

; Initiate Gear Actuator
          call                gear_fwd                 

          banksel             f_init_timer             
          bsf                 f_init_timer,0           

          movlw               z_init_timer             
          movwf               t_init_timer        

; Set up Timer
          movlw               z_base_cntr_period       
          movwf               t_base_timer_cntr        
          call                base_timer_setup         ; timer 2 - interrupt timer. 
          									; enable interrupts
          
          bsf				intcon,gie			; global interrupt enable

          goto                mainloop                 

;========================================================================================
;========================================================================================

;***********
;***********
mainloop:                                              
;***********
;***********
          banksel             porta                    
          movlw               porta_bits               
          andwf               porta,w                  
          subwf               laststablestate,w        

          btfsc               _z                       
          goto                mainloop                 

          banksel             porta                    
          clrf                tmr0                     ; bounce delay

timeloop_a:                                              
          movlw               0x0f                     
          subwf               tmr0,w                   
          btfss               _z                       
          goto                timeloop_a               

          banksel             porta                    
          movlw               porta_bits               ; check change is still there
          andwf               porta,w                  
          subwf               laststablestate,w        
          btfsc               _z                       
          goto                mainloop                 

          movfw               laststablestate          ; store which input has changed
          banksel             porta                    
          xorwf               porta,w                  
          movwf               input_change             

          movlw               porta_bits               ; store change
          andwf               porta,w                  
          movwf               laststablestate          

; set or clear flags
          btfsc               laststablestate,_up_button_bit ; Up Button
          goto                p1_a                     
          bsf                 s_up_button,0            
          goto                p2_a                     
p1_a:     bcf                 s_up_button,0            
p2_a:                                                  
          btfsc               laststablestate,_dn_button_bit ; Down Button
          goto                p3_a                     
          bsf                 s_dn_button,0            
          goto                p4_a                     
p3_a:     bcf                 s_dn_button,0            
p4_a:                                                  
          btfsc               laststablestate,_fwd_button_bit ; Forward Button
          goto                p5_a                     
          bsf                 s_fwd_button,0           
          goto                p6_a                     
p5_a:     bcf                 s_fwd_button,0           
p6_a:                                                  
          btfsc               laststablestate,_rev_button_bit ; Reverse Button
          goto                p7_a                     
          bsf                 s_rev_button,0           
          goto                p8_a                     
p7_a:     bcf                 s_rev_button,0           
p8_a:                                                  
          btfsc               laststablestate,_act_bit ; Actuator
          goto                p9_a                    
          bsf                 s_act,0                  
          goto                analyse                  
p9_a:    bcf                 s_act,0                  

; analyse flags
analyse:                                               
          btfsc               input_change,_up_button_bit ; Up Button change
          call                up_op                    

          btfsc               input_change,_dn_button_bit ; Down Button change
          call                dn_op                    

          btfsc               input_change,_fwd_button_bit ; Forward Button change
          call                fwd_op                   

          btfsc               input_change,_rev_button_bit ; Reverse Button change
          call                rev_op                   

          btfsc               input_change,_act_bit    ; Actuator change
          call                act_op                   

          goto                mainloop                 

;========================================================================================
;========================================================================================

;***********
;***********
up_op:                                                 
;***********
;***********
; Up Button
          banksel             porta                    
          call                clutch_on                

          btfss               s_up_button,0            ; up button
          goto                up1                      

		bsf				f_up_initial,0
		
          call                up_pulse              

          return                                       
up1:                                                   
          call                up_pulse_cancel             

          return                                       

;========================================================================================

;***********
;***********
dn_op:                                                 
;***********
;***********
; Down Button
          banksel             porta                    
          call                clutch_on                

          btfss               s_dn_button,0            ; down button
          goto                dn1                      

		bsf				f_dn_initial,0
		
          call                dn_pulse              

          return                                       
dn1:                                                   
          call                dn_pulse_cancel             

          return                                       

;========================================================================================

;***********
;***********
fwd_op:                                                
;***********
;***********
; Forward Button
          banksel             porta                    
          btfsc               s_fwd_button,0           ; Forward button
          goto                fwd1                     

          call                fwd_to_neut              

          return                                       
fwd1:                                                  
          call                neut_to_fwd              

          return                                       

;========================================================================================

;***********
;***********
neut_to_fwd:                                              
;***********
;***********
          call                clutch_off               

          btfss               s_gear_state,neutral     
          goto                n_f_5                    

          clrf                s_gear_state             
          bsf                 s_gear_state,n_to_f      

          call                gear_fwd                 

          movlw               z_neutral                
          movwf               act_cntr                 

          return                                       

n_f_5:                                                 
          btfss               s_gear_state,f_to_n      
          return                                       

          call                gear_fwd                 

          clrf                s_gear_state             
          bsf                 s_gear_state,n_to_f      

          return                                       

;========================================================================================

;***********
;***********
fwd_to_neut:                                              
;***********
;***********
          call                clutch_off               

          btfss               s_gear_state,forward     
          goto                f_n_3                    

          clrf                s_gear_state             
          bsf                 s_gear_state,f_to_n      

          clrf                act_cntr                 

          call                gear_rev                 

          return                                       

f_n_3:                                                 
          btfss               s_gear_state,n_to_f      
          return                                       

          call                gear_rev                 

          clrf                s_gear_state             
          bsf                 s_gear_state,f_to_n      

          return                                       

;========================================================================================

;***********
;***********
rev_op:                                                
;***********
;***********
; Reverse Button
          banksel             porta                    
          btfsc               s_rev_button,0           ; Reverse button
          goto                rev1                     

          call                rev_to_neut              

          return                                       
rev1:                                                  
          call                neut_to_rev              

          return                                       

;========================================================================================

;***********
;***********
neut_to_rev:                                              
;***********
;***********
          call                clutch_off               

          btfss               s_gear_state,neutral     
          goto                n_r_6                    

          clrf                s_gear_state             
          bsf                 s_gear_state,n_to_r      

          movlw               z_neutral                
          movwf               act_cntr                 

          call                gear_rev                 

          return                                       

n_r_6:                                                 
          btfss               s_gear_state,r_to_n      
          return                                       

          call                gear_rev                 

          clrf                s_gear_state             
          bsf                 s_gear_state,n_to_r      

          return                                       

;========================================================================================

;***********
;***********
rev_to_neut:                                              
;***********
;***********
          call                clutch_off               

          btfss               s_gear_state,reverse     
          goto                r_n_4                    

          clrf                s_gear_state             
          bsf                 s_gear_state,r_to_n      

          clrf                act_cntr                 

          call                gear_fwd                 

          return                                       

r_n_4:                                                 
          btfss               s_gear_state,n_to_r      
          return                                       

          call                gear_fwd                 

          clrf                s_gear_state             
          bsf                 s_gear_state,r_to_n      

          return                                       

;========================================================================================

;***********
;***********
act_op:                                                
;***********
;***********
; Gear Actuator
          banksel             f_init_timer                    
          btfsc               f_init_timer,0           
          return                                       

          btfss               s_act,0                  
          return                                       

; Neutral to Forward
          btfss               s_gear_state,n_to_f      
          goto                gear_4                   

          decfsz              act_cntr,f               
          return                                       

          call                gear_off                 

          clrf                s_gear_state             
          bsf                 s_gear_state,forward     

          return                                       

gear_4:                                                
; Neutral to Reverse
          btfss               s_gear_state,n_to_r      
          goto                gear_5                   

          decfsz              act_cntr,f               
          return                                       

          call                gear_off                 

          clrf                s_gear_state             
          bsf                 s_gear_state,reverse     

          return                                       

gear_5:                                                
; Forward to Neutral
          btfss               s_gear_state,f_to_n      
          goto                gear_6                   

          incf                act_cntr,f               

          movf                act_cntr,w               
          addlw               d'256' - z_neutral         
          skpc                                         
          return                                       

          call                gear_off                 

          clrf                s_gear_state             
          bsf                 s_gear_state,neutral     

          btfss               f_start,0           
          goto                gear_5_cont              

          clrf                f_start             
          call                start_on                 

gear_5_cont:                                              
          btfss               s_rev_button,0           
          return                                       

          call                neut_to_rev              

          return                                       

gear_6:                                                
; Reverse to Neutral
          btfss               s_gear_state,r_to_n      
          return                                       

          incf                act_cntr,f               

          movf                act_cntr,w               
          addlw               d'256' - z_neutral         
          skpc                                         
          return                                       

          call                gear_off                 

          clrf                s_gear_state             
          bsf                 s_gear_state,neutral     

          btfss               s_fwd_button,0           
          return                                       

          call                neut_to_fwd              

          return                                       

;========================================================================================
;***********
;***********
buzz_on:                                               
;***********
;***********
          banksel             portb                   
          bsf                 _buzz                

		call				shadow_to_port
		
          return                                       

;========================================================================================
;***********
;***********
buzz_off:                                              
;***********
;***********
          banksel             portb                   
          bcf                 _buzz                 
          
		call				shadow_to_port
		
          return                                       

;========================================================================================
;***********
;***********
start_on:                                              
;***********
;***********
		banksel			porta
          bsf                 _start                   

		call				shadow_to_port
		
          return                                       

;========================================================================================
;***********
;***********
start_off:                                             
;***********
;***********
		banksel			porta
          bcf                 _start                   

		call				shadow_to_port
		
          return                                       

;========================================================================================
;***********
;***********
clutch_on:                                             
;***********
;***********
		banksel			porta
          bsf                 _clutch                  

		call				shadow_to_port
		
          return                                       

;========================================================================================
;***********
;***********
clutch_off:                                              
;***********
;***********
		banksel			porta
          bcf                 _clutch                  

		call				shadow_to_port
		
          return                                       

;========================================================================================
;***********
;***********
up_pulse:                                              
;***********
;***********
		call				throttle_up
		
          movlw               z_up_high_period             
          movwf               t_up_high
          
          bsf				f_up_high,0       
		
          return                                       

;========================================================================================
;***********
;***********
dn_pulse:                                              
;***********
;***********
		call				throttle_dn
		
          movlw               z_dn_high_period             
          movwf               t_dn_high
          
          bsf				f_dn_high,0       
		
          return                                       

;========================================================================================
;***********
;***********
up_pulse_cancel:                                              
;***********
;***********
          clrf				f_up_initial
          clrf				t_up_high
          clrf				t_up_low
          clrf				t_up_delay
          
          call				throttle_off
          
          return                                       

;========================================================================================
;***********
;***********
dn_pulse_cancel:                                              
;***********
;***********
          clrf				f_dn_initial
          clrf				t_dn_high
          clrf				t_dn_low
          clrf				t_dn_delay
          
          call				throttle_off
          
          return                                       

;========================================================================================
;***********
;***********
throttle_up:                                              
;***********
;***********
		banksel			porta
          bsf                 _throttle_plus           
          bcf                 _throttle_neg            

		call				shadow_to_port
		
          return                                       

;========================================================================================
;***********
;***********
throttle_dn:                                              
;***********
;***********
		banksel			porta
          bcf                 _throttle_plus           
          bsf                 _throttle_neg            

		call				shadow_to_port
		
          return                                       

;========================================================================================
;***********
;***********
throttle_off:                                              
;***********
;***********
		banksel			porta
          bcf                 _throttle_plus           
          bcf                 _throttle_neg            

		call				shadow_to_port
		
          return                                       

;========================================================================================
;***********
;***********
gear_fwd:                                              
;***********
;***********
		banksel			porta
          bsf                 _fwd                     
          bcf                 _rev                     

		call				shadow_to_port
		
          return                                       

;========================================================================================
;***********
;***********+
gear_rev:                                              
;***********
;***********
		banksel			porta
          bsf                 _rev                     
          bcf                 _fwd                     

		call				shadow_to_port
		
          return                                       

;========================================================================================
;***********
;***********
gear_off:                                              
;***********
;***********
		banksel			porta
          bcf                 _fwd                     
          bcf                 _rev                     

		call				shadow_to_port
		
          return                                       

;========================================================================================
;***********
;***********
shadow_to_port:                                               
;***********
;***********
		banksel			portb
          movfw               portb_sh              
          movwf			portb                  

		banksel			portc
          movfw               portc_sh              
          movwf			portc                  

          return                                       

;========================================================================================
;========================================================================================
; set up base timer
;========================================================================================

;***********
;***********
base_timer_setup:                                              
;***********
;***********
          banksel             tmr2                     
          clrf                tmr2                     

          movlw               0x7e                     
          movwf               t2con                    
          bsf                 intcon,peie                

          movlw               z_base_cntr_period       
          movwf               t_base_timer_cntr        

          banksel             pr2                      
          movlw               0xff                     
          movwf               pr2                      

          banksel			pie1
          bsf                 pie1,1                   

          banksel             tmr2                     

          return                                       

;========================================================================================
;========================================================================================

; handle interrupts

          org                 0x800                    
;***********
;***********
interrupts:                                              
;***********
;***********

;========================
; base timer
;========================
          banksel             t_base_timer_cntr        
          decfsz              t_base_timer_cntr,f      
          goto                ret                      

          movlw               z_base_cntr_period       
          movwf               t_base_timer_cntr        

;========================
; Initiate Gear actuator Delay
;========================
gear_delay:                                              
          banksel             f_init_timer             
          btfss               f_init_timer,0           
          goto                up_initial              

          decfsz              t_init_timer,f      
          goto                up_initial              

          clrf            	f_init_timer
		bsf				f_start,0
		
          clrf                s_gear_state             
          bsf                 s_gear_state,forward     

          pagesel             fwd_to_neut              
          call                fwd_to_neut              
          pagesel             $                        

;;========================
; Up pulse
;========================
up_initial:                                              
		banksel			s_up_button
		btfss			s_up_button,0
		goto				dn_initial
		
		btfss			f_up_high,0
		goto				up_low
		
		decfsz			t_up_high,f
		goto				ret
		
		clrf				f_up_high
		bsf				f_up_low,0

          movlw               z_up_low_period         
          movwf               t_up_low
          
          pagesel			throttle_off
          call				throttle_off
		pagesel			$
		
		goto				ret

up_low:
		banksel			f_up_low
		btfss			f_up_low,0
		goto				up_delay
		
		decfsz			t_up_low,f
		goto				ret
		
		clrf				f_up_low
		
		btfss			f_up_initial,0
		goto				up_pulse1
		
          clrf				f_up_initial
          bsf				f_up_delay,0
          
          movlw               z_up_delay_period         
          movwf               t_up_delay
          
          goto				ret

up_delay:
		banksel			f_up_delay
		btfss			f_up_delay,0
		goto				ret
		
		decfsz			t_up_delay,f
		goto				ret
		
		clrf				f_up_delay
		
up_pulse1:
          pagesel			up_pulse
		call				up_pulse
		pagesel			$

		goto				ret
		
;========================
; Down pulse
;========================
dn_initial:                                              
		banksel			s_dn_button
		btfss			s_dn_button,0
		goto				ret
		
		btfss			f_dn_high,0
		goto				dn_low
		
		decfsz			t_dn_high,f
		goto				ret
		
		clrf				f_dn_high
		bsf				f_dn_low,0

          movlw               z_dn_low_period         
          movwf               t_dn_low
          
          pagesel			throttle_off
          call				throttle_off
		pagesel			$

		goto				ret

dn_low:
		banksel			f_dn_low
		btfss			f_dn_low,0
		goto				dn_delay
		
		decfsz			t_dn_low,f
		goto				ret
		
		clrf				f_dn_low
		
		btfss			f_dn_initial,0
		goto				dn_pulse1
		
          clrf				f_dn_initial
          bsf				f_dn_delay,0
          
          
          movlw               z_dn_delay_period         
          movwf               t_dn_delay
          
          goto				ret

dn_delay:
		banksel			f_dn_delay
		btfss			f_dn_delay,0
		goto				ret
		
		decfsz			t_dn_delay,f
		goto				ret
		
		clrf				f_dn_delay
		
dn_pulse1:
          pagesel			dn_pulse
		call				dn_pulse
		pagesel			$

		goto				ret
		
;========================
; Return
;========================
ret:                                                   
          banksel             pir1                     
          bcf                 pir1,1                   

          return                                       

;===================================================================================

     end                                               
