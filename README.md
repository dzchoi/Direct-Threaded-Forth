# Direct-Threaded-Forth
Direct-Thread Forth in x86 assembly

- Focused on the optimization of the running speed  
  - source code written in an x86 assembly language from scratch  
  - built-in words (called procedures or functions in other languages) were coded “directly threaded” (that is, access to the execution code for every word is given directly, not through a pointer) in the definition area

- It is not fully supportive of the official standard FORTH, but is self-contained enough to be able to define any words with the built-in words I have made

- For example, the following code will print "Hello, World" to the screen 10 times
```
: IMMEDIATE LAST @ DUP C@ $40 OR SWAP C! ;  
: DO COMPILE do [COMPILE] BEGIN ; IMMEDIATE  
: LOOP COMPILE loop , ; IMMEDIATE  
: TEST 10 0 DO CR ." Hello" LOOP CR ;  
TEST  
```
