// This code is fork off of Dave Brink's MPGuino v0.75 code
// written by Kyle Heide a.k.a. Sectorbob

// Purpose of fork: I wanted a version of MPGuino that could drive a smaller, higher pixel-density display. I identified the ST7735 1.8" TFT as my target.

// current development moved outside of arduino proper, reference
// Parent Repository: http://opengauge.googlecode.com/svn/trunk/mpguino/mpguino.cpp
// Fork Repository: TBD

// This build of MPGuino is meant for ATmega328 chips. personally, I have tested this on an Arduino Nano V3.0

//GPL Software    

#include <Adafruit_GFX.h>    // Core graphics library from Adafruit's github
#include <Adafruit_ST7735.h> // Hardware-specific library from Adafruit's github
#include <SPI.h>
#include <avr/pgmspace.h>  

//#define usedefaults true
unsigned long  parms[]={95ul,8208ul,500000000ul,3ul,420000000ul,10300ul,500ul,2400ul,0ul,2ul};//default values
char *  parmLabels[]={"Contrast","VSS Pulses    /Mile", "MicroSec/ Gallon","VSS Pulses   /2 revs","Timeout   (microSec)","Tank Gal     * 1000","Injector  Delay (uS)","Weight    (lbs)","Scratchpad(odo?)","VSS Delay (ms)"};

byte brightness[]={255,214,171,128}; //middle button cycles through these brightness settings      
#define brightnessLength (sizeof(brightness)/sizeof(byte)) //array size      
byte brightnessIdx=1;      


#define contrastIdx 0  //do contrast first to get display dialed in
#define vssPulsesPerMileIdx 1
#define microSecondsPerGallonIdx 2
#define injPulsesPer2Revolutions 3
#define currentTripResetTimeoutUSIdx 4
#define tankSizeIdx 5 
#define injectorSettleTimeIdx 6
#define weightIdx 7
#define scratchpadIdx 8
#define vsspause 9
#define parmsLength (sizeof(parms)/sizeof(unsigned long)) //array size      

#define nil 3999999999ul
#define intnil -32,768
 
#define guinosigold B10100101 
#define guinosig B11100111 
#include <EEPROM.h>
//Vehicle Interface Pins      
#define InjectorOpenPin 2      
#define InjectorClosedPin 3      
#define VSSPin 14 //analog 0           
 
#define lbuttonPin 17 // Left Button, on analog 3,        
#define mbuttonPin 18 // Middle Button, on analog 4       
#define rbuttonPin 19 // Right Button, on analog 5       
 
#define vssBit 1     //  pin14 is a bitmask 1 on port C        
#define lbuttonBit 8 //  pin17 is a bitmask 8 on port C        
#define mbuttonBit 16 // pin18 is a bitmask 16 on port C        
#define rbuttonBit 32 // pin19 is a bitmask 32 on port C        
#define loopsPerSecond 2 // how many times will we try and loop in a second     

typedef void (* pFunc)(void);//type for display function pointers      

volatile unsigned long timer2_overflow_count;

// NEW DIplay Glocal Variables
#define brightnessPin 6
#define cs   10
#define dc   9
#define rst  12
#define lcdpwr 8
Adafruit_ST7735 tft = Adafruit_ST7735(cs, dc, rst);
uint16_t textColor = ST7735_WHITE;
uint16_t backgroundColor = ST7735_BLACK;
// End Display variables

/*** Set up the Events ***
We have our own ISR for timer2 which gets called about once a millisecond.
So we define certain event functions that we can schedule by calling addEvent
with the event ID and the number of milliseconds to wait before calling the event. 
The milliseconds is approximate.

Keep the event functions SMALL!!!  This is an interrupt!

*/
//event functions

void enableLButton(){PCMSK1 |= (1 << PCINT11);}
void enableMButton(){PCMSK1 |= (1 << PCINT12);}
void enableRButton(){PCMSK1 |= (1 << PCINT13);}
//array of the event functions
pFunc eventFuncs[] ={enableVSS, enableLButton,enableMButton,enableRButton};
#define eventFuncSize (sizeof(eventFuncs)/sizeof(pFunc)) 
//define the event IDs
#define enableVSSID 0
#define enableLButtonID 1
#define enableMButtonID 2
#define enableRButtonID 3
//ms counters
unsigned int eventFuncCounts[eventFuncSize];

//schedule an event to occur ms milliseconds from now
void addEvent(byte eventID, unsigned int ms){
  if( ms == 0)
    eventFuncs[eventID]();
  else
    eventFuncCounts[eventID]=ms;
}

/* this ISR gets called every 1.024 milliseconds, we will call that a millisecond for our purposes
go through all the event counts, 
  if any are non zero subtract 1 and call the associated function if it just turned zero.  */
ISR(TIMER2_OVF_vect){
  timer2_overflow_count++;
  for(byte eventID = 0; eventID < eventFuncSize; eventID++){
    if(eventFuncCounts[eventID]!= 0){
      eventFuncCounts[eventID]--;
      if(eventFuncCounts[eventID] == 0)
          eventFuncs[eventID](); 
    }  
  }
}

 
 
unsigned long maxLoopLength = 0; //see if we are overutilizing the CPU      
 
 
#define buttonsUp   lbuttonBit + mbuttonBit + rbuttonBit  // start with the buttons in the right state      
byte buttonState = buttonsUp;      
 
 
//overflow counter used by millis2()      
unsigned long lastMicroSeconds=millis2() * 1000;   
unsigned long microSeconds (void){     
  unsigned long tmp_timer2_overflow_count;    
  unsigned long tmp;    
  byte tmp_tcnt2;    
  cli(); //disable interrupts    
  tmp_timer2_overflow_count = timer2_overflow_count;    
  tmp_tcnt2 = TCNT2;    
  sei(); // enable interrupts    
  tmp = ((tmp_timer2_overflow_count << 8) + tmp_tcnt2) * 4;     
  if((tmp<=lastMicroSeconds) && (lastMicroSeconds<4290560000ul))    
    return microSeconds();     
  lastMicroSeconds=tmp;   
  return tmp;     
}    
 
unsigned long elapsedMicroseconds(unsigned long startMicroSeconds, unsigned long currentMicroseconds ){      
  if(currentMicroseconds >= startMicroSeconds)      
    return currentMicroseconds-startMicroSeconds;      
  return 4294967295 - (startMicroSeconds-currentMicroseconds);      
}      

unsigned long elapsedMicroseconds(unsigned long startMicroSeconds ){      
  return elapsedMicroseconds(startMicroSeconds, microSeconds());
}      
 
//Trip prototype      
class Trip{      
public:      
  unsigned long loopCount; //how long has this trip been running      
  unsigned long injPulses; //rpm      
  unsigned long injHiSec;// seconds the injector has been open      
  unsigned long injHius;// microseconds, fractional part of the injectors open       
  unsigned long injIdleHiSec;// seconds the injector has been open      
  unsigned long injIdleHius;// microseconds, fractional part of the injectors open       
  unsigned long vssPulses;//from the speedo      
  unsigned long vssEOCPulses;//from the speedo      
  unsigned long vssPulseLength; // only used by instant
  //these functions actually return in thousandths,       
  unsigned long miles();        
  unsigned long gallons();      
  unsigned long mpg();        
  unsigned long mph();        
  unsigned long time(); //mmm.ss        
  unsigned long eocMiles();  //how many "free" miles?        
  unsigned long idleGallons();  //how many gallons spent at 0 mph?        
  void update(Trip t);      
  void reset();      
  Trip();      
};
 
//main objects we will be working with:      
unsigned long injHiStart; //for timing injector pulses      
Trip tmpTrip;      
Trip instant;      
Trip current;      
Trip tank;      


unsigned volatile long instInjStart=nil; 
unsigned volatile long tmpInstInjStart=nil; 
unsigned volatile long instInjEnd; 
unsigned volatile long tmpInstInjEnd; 
unsigned volatile long instInjTot; 
unsigned volatile long tmpInstInjTot;     
unsigned volatile long instInjCount; 
unsigned volatile long tmpInstInjCount;     


void processInjOpen(void){      
  injHiStart = microSeconds();  
}      
 
void processInjClosed(void){      
  long t =  microSeconds();
  long x = elapsedMicroseconds(injHiStart, t)- parms[injectorSettleTimeIdx];       
  if(x >0)
    tmpTrip.injHius += x;       
  tmpTrip.injPulses++;      

  if (tmpInstInjStart != nil) {
    if(x >0)
      tmpInstInjTot += x;     
    tmpInstInjCount++;
  } else {
    tmpInstInjStart = t;
  }
  
  tmpInstInjEnd = t;
}


volatile boolean vssFlop = 0;

void enableVSS(){
//    tmpTrip.vssPulses++; 
    vssFlop = !vssFlop;
}

unsigned volatile long lastVSS1;
unsigned volatile long lastVSSTime;
unsigned volatile long lastVSS2;

volatile boolean lastVssFlop = vssFlop;

//attach the vss/buttons interrupt      
ISR( PCINT1_vect ){   
  static byte vsspinstate=0;      
  byte p = PINC;//bypassing digitalRead for interrupt performance      
  if ((p & vssBit) != (vsspinstate & vssBit)){      
    addEvent(enableVSSID,parms[vsspause] ); //check back in a couple milli
  }
  if(lastVssFlop != vssFlop){
    lastVSS1=lastVSS2;
    unsigned long t = microSeconds();
    lastVSS2=elapsedMicroseconds(lastVSSTime,t);
    lastVSSTime=t;
    tmpTrip.vssPulses++; 
    tmpTrip.vssPulseLength += lastVSS2;
    lastVssFlop = vssFlop;
  }
  vsspinstate = p;      
  buttonState &= p;      
}       

 
pFunc displayFuncs[] ={ 
  doDisplayCustom, 
  doDisplayInstantCurrent, 
  doDisplayInstantTank, 
  doDisplayBigInstant, 
  doDisplayBigCurrent, 
  doDisplayBigTank, 
  doDisplayCurrentTripData, 
  doDisplayTankTripData, 
  doDisplayEOCIdleData, 
  doDisplaySystemInfo,
};      
#define displayFuncSize (sizeof(displayFuncs)/sizeof(pFunc)) //array size      
prog_char  * displayFuncNames[displayFuncSize]; 
byte newRun = 0;
void setup (void){
  init2();
  newRun = load();//load the default parameters
  byte x = 0;
  displayFuncNames[x++]=  PSTR("Custom  "); 
  displayFuncNames[x++]=  PSTR("Instant/  Current "); 
  displayFuncNames[x++]=  PSTR("Instant/  Tank "); 
  displayFuncNames[x++]=  PSTR("BIG       Instant "); 
  displayFuncNames[x++]=  PSTR("BIG       Current "); 
  displayFuncNames[x++]=  PSTR("BIG Tank "); 
  displayFuncNames[x++]=  PSTR("Current "); 
  displayFuncNames[x++]=  PSTR("Tank "); 
  displayFuncNames[x++]=  PSTR("EOC mi/   Idle gal "); 
  displayFuncNames[x++]=  PSTR("CPU       Monitor ");      
 
  pinMode(brightnessPin,OUTPUT);      
  analogWrite(brightnessPin,brightness[brightnessIdx]);      
  delay2(500);
  
        // New Display Code
        pinMode(lcdpwr, OUTPUT); // pin for turning screen on/off
        initDisplay();
        // End new Diplay code   

  pinMode(InjectorOpenPin, INPUT);       
  pinMode(InjectorClosedPin, INPUT);       
  pinMode(VSSPin, INPUT);            
  attachInterrupt(0, processInjOpen, FALLING);      
  attachInterrupt(1, processInjClosed, RISING);      
 
  pinMode( lbuttonPin, INPUT );       
  pinMode( mbuttonPin, INPUT );       
  pinMode( rbuttonPin, INPUT );      
 
  //"turn on" the internal pullup resistors      
  digitalWrite( lbuttonPin, HIGH);       
  digitalWrite( mbuttonPin, HIGH);       
  digitalWrite( rbuttonPin, HIGH);       
//  digitalWrite( VSSPin, HIGH);       
 
  //low level interrupt enable stuff      
  PCMSK1 |= (1 << PCINT8);
  enableLButton();
  enableMButton();
  enableRButton();
  PCICR |= (1 << PCIE1);       
 
  delay2(1500);       
}       
 
byte screen=0;      
byte holdDisplay = 0; 



#define looptime 1000000ul/loopsPerSecond //1/2 second      
void loop (void){       
  if(newRun !=1)
    initGuino();//go through the initialization screen
  unsigned long lastActivity =microSeconds();
  unsigned long tankHold;      //state at point of last activity
  while(true){      
    unsigned long loopStart=microSeconds();      
    instant.reset();           //clear instant      
    cli();
    instant.update(tmpTrip);   //"copy" of tmpTrip in instant now      
    tmpTrip.reset();           //reset tmpTrip first so we don't lose too many interrupts      
    instInjStart=tmpInstInjStart; 
    instInjEnd=tmpInstInjEnd; 
    instInjTot=tmpInstInjTot;     
    instInjCount=tmpInstInjCount;
    
    tmpInstInjStart=nil; 
    tmpInstInjEnd=nil; 
    tmpInstInjTot=0;     
    tmpInstInjCount=0;

    sei();
    
    //send out instantmpg * 1000, instantmph * 1000, the injector/vss raw data
    simpletx(format(instantmpg()));
    simpletx(",");
    simpletx(format(instantmph()));
    simpletx(",");
    simpletx(format(instant.injHius*1000));
    simpletx(",");
    simpletx(format(instant.injPulses*1000));
    simpletx(",");
    simpletx(format(instant.vssPulses*1000));
    simpletx("\n");
    
    
    current.update(instant);   //use instant to update current      
    tank.update(instant);      //use instant to update tank      

//currentTripResetTimeoutUS
    if(instant.vssPulses == 0 && instant.injPulses == 0 && holdDisplay==0){
      if(elapsedMicroseconds(lastActivity) > parms[currentTripResetTimeoutUSIdx] && lastActivity != nil){
        analogWrite(brightnessPin,brightness[0]);    //nitey night
        sleepDisplay();
        lastActivity = nil;
      }
    }else{
      if(lastActivity == nil){//wake up!!!
        analogWrite(brightnessPin,brightness[brightnessIdx]);
        initDisplay();
        
        lastActivity=loopStart;
        current.reset();
        tank.loopCount = tankHold;
        current.update(instant); 
        tank.update(instant);
        
        // Clean up display state
        tft.fillScreen(backgroundColor);
        tft.setTextSize(2);
        clearDisplayCache();
        
      }else{
        lastActivity=loopStart;
        tankHold = tank.loopCount;
      }
    }
       if(holdDisplay==0){
          displayFuncs[screen]();    //call the appropriate display routine      
          tft.setCursor(0,0);       
          
      //see if any buttons were pressed, display a brief message if so      
      if(!(buttonState&lbuttonBit) && !(buttonState&rbuttonBit)){// left and right = initialize      
          tft.print(getStr(PSTR("Setup ")));    
          initGuino();  
      //}else if(!(buttonState&lbuttonBit) && !(buttonState&rbuttonBit)){// left and right = run lcd init = tank reset      
      //    LCD::print(getStr(PSTR("Init LCD "))); 
      //    LCD::init();
      }else if (!(buttonState&lbuttonBit) && !(buttonState&mbuttonBit)){// left and middle = tank reset      
          tank.reset();      
          tft.print(getStr(PSTR("Tank Reset ")));      
      }else if(!(buttonState&mbuttonBit) && !(buttonState&rbuttonBit)){// right and middle = current reset      
          current.reset();      
          tft.print(getStr(PSTR("Current Reset ")));      
      }else if(!(buttonState&lbuttonBit)){ //left is rotate through screeens to the left      
        if(screen!=0)      
          screen=(screen-1);       
        else      
          screen=displayFuncSize-1;
        // Clean up display state
        tft.fillScreen(backgroundColor);
        tft.setTextSize(2);
        clearDisplayCache();
        tft.print(getStr(displayFuncNames[screen]));      
      }else if(!(buttonState&mbuttonBit)){ //middle is cycle through brightness settings      
        brightnessIdx = (brightnessIdx + 1) % brightnessLength;      
        analogWrite(brightnessPin,brightness[brightnessIdx]);      
        tft.print(getStr(PSTR("Brightness ")));      
        //LCD::LcdDataWrite('0' + brightnessIdx);
        // Clean up display state
        tft.fillScreen(backgroundColor);
        tft.setTextSize(2);
        clearDisplayCache();
      }else if(!(buttonState&rbuttonBit)){//right is rotate through screeens to the right      
        screen=(screen+1)%displayFuncSize;
        // Clean up display state
        tft.fillScreen(backgroundColor);
        tft.setTextSize(2);
        clearDisplayCache();
        tft.print(getStr(displayFuncNames[screen]));
      }      
      if(buttonState!=buttonsUp)
         holdDisplay=1;
     }else{
        holdDisplay=0;
    } 
    buttonState=buttonsUp;//reset the buttons      
 
      //keep track of how long the loops take before we go int waiting.      
      unsigned long loopX=elapsedMicroseconds(loopStart);      
      if(loopX>maxLoopLength) maxLoopLength = loopX;      
 
      while (elapsedMicroseconds(loopStart) < (looptime));//wait for the end of a second to arrive      
  }      
 
}       
 
 
char fBuff[7];//used by format    

char* format(unsigned long num){
  if (num == nil) { // case where num == nil, return blank string[7]
    for(int i =0; i < 7; i++) {
      fBuff[i] = ' ';
    }
    return fBuff;
  }
    
  byte dp = 3;

  while(num > 99999){
    num /= 10;
    dp++;
    if( dp == 5 ) break; // We'll lose the top numbers like an odometer
  }
  if(dp == 5) dp = 99; // We don't need a decimal point here.

// Round off the non-printed value.
  if((num % 10) > 4)
    num += 10;
  num /= 10;
  byte x = 6;
  while(x > 0){
    x--;
    if(x==dp){ //time to poke in the decimal point?{
      fBuff[x]='.';
    }else{
      fBuff[x]= '0' + (num % 10);//poke the ascii character for the digit.
      num /= 10;
    } 
  }
  fBuff[6] = 0;
  return fBuff;
}

//format a number into NNN.NN  the number should already be representing thousandths      
/*char* format(unsigned long num){      
  unsigned long d = 10000;      
  long t;      
  byte dp=3;      
  byte l=6;      
 
  if(num>9999999){      
    d=100000;      
    dp=99;      
    num/=100;      
  }else if(num>999999){      
    dp=4;      
    num/=10;      
  }      
 
  unsigned long val = num/10;      
  if ((num - (val * 10)) >= 5)  //will the first unprinted digit be greater than 4?      
    val += 1;   //round up val      
 
  for(byte x = 0; x < l; x++){      
    if(x==dp)      //time to poke in the decimal point?      
      fBuff[x]='.';      
    else{      
      t = val/d;        
      fBuff[x]= '0' + t%10;//poke the ascii character for the digit.      
      val-= t*d;      
      d/=10;            
    }      
  }      
  fBuff[6]= 0;         //good old zero terminated strings       
  return fBuff;      
} */  
 
//get a string from flash 
char mBuff[17];//used by getStr 
char * getStr(prog_char * str){ 
  strcpy_P(mBuff, str); 
  return mBuff; 
} 

 

 /////////////////////////////////////////////////////////////////////////////////////////////////////
////////// New Display Code
//////////////////////////////////////////////////////////////////////////////////////////////////////

char * screenNames[] = {"CUST","INST/CURR","INST/Tank", "INST MPG", "Trip MPG", "Tank MPG","Curr -ent","Tank","EOC"," CPU Mntr"};
int lastScreen = -1;

int headerTextSize = 4;
int headerCursorX = 10;
int headerCursorY = 5;

int numberTextSize = 2;
int numberX[5] = {58, 71, 84, 97, 110};
int numberY[4] = {80, 100, 120, 140};

int bigNumberTextSize = 4;
int bigNumberX[5] = {4, 29, 54, 79, 104};
int bigNumberY = 100;

void doDisplayCustom() {
  unsigned long nums[4] = {instantmpg(), instantmph(), instantgph(), current.mpg()};
  char labels[16] = {'i','M','P','G',   'i','M','P','H',   'i','G','P','H',   'c','M','P','G'};
  displayTripCombo(0, labels, nums);
}

void doDisplayInstantCurrent() {
  unsigned long nums[4] = {instantmpg(), instantmph(), current.mpg(), current.miles()};
  char labels[16] = {'i','M','P','G',   'i','M','P','H',   'c','M','P','G',   'c','M','I','L'};
  displayTripCombo(1, labels, nums);
}

void doDisplayInstantTank() {
  unsigned long nums[4] = {instantmpg(), instantmph(), tank.mpg(), tank.miles()};
  char labels[16] = {'i','M','P','G',   'i','M','P','H',   't','M','P','G',   't','M','I','L'};
  displayTripCombo(2, labels, nums);
}

void doDisplayBigInstant() {
  bigNum(3, instantmpg());
}

void doDisplayBigCurrent() {
  bigNum(4, current.mpg());
}

void doDisplayBigTank() {
  bigNum(5, tank.mpg());
}

void doDisplayCurrentTripData(void) {
  unsigned long nums[4] = {current.mph(), current.mpg(), current.miles(), current.gallons()};
  char labels[16] = {'M','P','H',' ',   'M','P','G',' ',   'M','I','L','E',   'G','A','L','L'};
  displayTripCombo(6, labels, nums);
} //display current trip formatted data.

void doDisplayTankTripData(void) {
  unsigned long nums[4] = {tank.mph(), tank.mpg(), tank.miles(), tank.gallons()};
  char labels[16] = {'M','P','H',' ',   'M','P','G',' ',   'M','I','L','E',   'G','A','L','L'};
  displayTripCombo(7, labels, nums);
} //display tank trip formatted data.

void doDisplayEOCIdleData() {
  unsigned long nums[4] = {current.eocMiles(), current.idleGallons(), tank.eocMiles(), tank.idleGallons()};
  char labels[16] = {'c','E','O','C',   'c','I','D','G',   't','E','O','C',   't','I','D','G'};
  displayTripCombo(8, labels, nums);
}

void doDisplaySystemInfo(void) {
  unsigned long mem = memoryTest();
	mem *= 1000;
  unsigned long nums[4] = {maxLoopLength * 1000 / (looptime / 100), tank.time(), mem, nil};
  char labels[16] = {'C','P','U','%',   'T','I','M','E',   'f','M','E','M',   ' ',' ',' ',' '};
  displayTripCombo(9, labels, nums);
} //display max cpu utilization and ram.


// Display 4 number driver method //
unsigned long lastNums[4];
char lastChars[20];
void displayTripCombo(int screenIndex, char * labels, unsigned long * nums) {
  
  // If we are changing the screen, we need to wipe the screen and write the title and labels
  if(screenIndex != lastScreen) {
    tft.fillScreen(backgroundColor);
      // Write Screen Label
      tft.setTextSize(headerTextSize);
      tft.setCursor(headerCursorX, headerCursorY);
      tft.setTextColor(textColor);
      tft.print(screenNames[screenIndex]);
      tft.setTextSize(numberTextSize);
      for(int i = 0; i < 4; i++) {
        tft.setCursor(7, numberY[i]);
        tft.print(labels[i*4 + 0]);
        tft.print(labels[i*4 + 1]);
        tft.print(labels[i*4 + 2]);
        tft.print(labels[i*4 + 3]);
        tft.setCursor(numberX[2], numberY[i]);
      }
      lastScreen = screenIndex;
  }
  
  tft.setTextSize(numberTextSize);
  for(int j = 0; j < 4; j++){
    int y = numberY[j];
    char * chars;
    char * tmpAry;
    
    if(lastNums[j] != nums[j]) { // check to see if the numerical value is different, if so, attempt to format and print
      
      chars = format(nums[j]); // get the current number to write
      
      boolean printedNonZero = false;
      unsigned int shiftCount = 0; // marked the number of spaces to the right we shifted - for now it will be either 0 or 1
      for(int i = 0; i < 5; i++) {
        
        // for the first character.. if it is '0' shift to the right
        if(chars[i] == '0' && i == 1) {
          shiftCount++;
        }
        
        int lastCharIndex = 5*j + i;// used to keep track of the previous number chars on the screen
        int currCharIndex = i + shiftCount; // used to keep track of the current char index
        
        if(lastChars[lastCharIndex] != chars[currCharIndex]) {
          // Erase old char
          tft.setCursor(numberX[i], numberY[j]);
          tft.setTextColor(backgroundColor);
          tft.print(lastChars[lastCharIndex]);
          
          // if there was a non zero character before or if this non is non-zero print it
          // Print new char
          if(chars[currCharIndex] != '0' || printedNonZero) {
            tft.setCursor(numberX[i], numberY[j]);
            tft.setTextColor(textColor);
            tft.print(chars[currCharIndex]);
            printedNonZero = true;
          } 
          
          // since the new char is different save it in the cache
          lastChars[lastCharIndex] = chars[currCharIndex];
          
        } else if(chars[currCharIndex] != '0') {
          // case where lastchar = char && char != '0'
          // set the printed non zero to true
          printedNonZero = true;
        }
        
      } // end column loop
      
    }
    // copy the current value to the cache
    for(int i = 0; i < 4; i++) {
        lastNums[j] = nums[j];
    }
  } // end row loop
}

char * currentNumText;
char lastNumText[5];
unsigned long lastNumDisplayed;
void bigNum(int screenIndex, unsigned long num) {
  
  // If we are changing the screen, we need to wipe the screen and write the title
  if(screenIndex != lastScreen) {
    tft.fillScreen(backgroundColor);
    // Write Screen Label
    tft.setTextSize(headerTextSize);
    tft.setCursor(headerCursorX, headerCursorY);
    tft.setTextColor(textColor);
    tft.print(screenNames[screenIndex]);
    lastScreen = screenIndex;
  }
  
  // in the case where the lastr number display was the same, don't do anything, just exit the function
  if(lastNumDisplayed == num) {
    return;
  }
  
  tft.setTextSize(bigNumberTextSize);
  
  // Format the Big text
  currentNumText = format(num);
  ///////////////////////
  
  boolean printedNonZero = false;
  unsigned int shiftCount = 0; // marked the number of spaces to the right we shifted - for now it will be either 0 or 1
  for(int i = 0; i < 5; i++) {
    // for the first character.. if it is '0' shift to the right
    if(currentNumText[i] == '0' && i == 0) {
      shiftCount++;
    }
    
    //indexes
    int lastCharIndex = i; // used to keep track of the previous number chars on the screen
    int currCharIndex = i + shiftCount; // used to keep track of the current char index
    
    if(lastNumText[lastCharIndex] != currentNumText[currCharIndex]) {
      // Erase old char
      tft.setCursor(bigNumberX[i], bigNumberY);
      tft.setTextColor(backgroundColor);
      tft.print(lastNumText[lastCharIndex]);
      
      // if there was a non zero character before or if this non is non-zero print it
      // Print new char
      if(currentNumText[currCharIndex] != '0' || printedNonZero) {
        tft.setCursor(bigNumberX[i], bigNumberY);
        tft.setTextColor(textColor);
        tft.print(currentNumText[currCharIndex]);
        printedNonZero = true;
      } 
      
      // since the new char is different save it in the cache
      lastNumText[lastCharIndex] = currentNumText[currCharIndex];
      
    } else if(currentNumText[currCharIndex] != '0') {
      // case where lastchar = char && char != '0'
      // set the printed non zero to true
      printedNonZero = true;
    }
    
  } // end column loop
}

////////////////  Display maintenance Routines

// turns on the display, configures it
 void initDisplay() {
   digitalWrite(lcdpwr, HIGH);// power on display
   tft.initR(INITR_REDTAB);
   tft.setRotation(2);
   tft.fillScreen(backgroundColor);
   tft.setTextSize(2);
   tft.setTextColor(textColor);
   tft.print("OpenGauge ");
   tft.print("MPGuino   ");
   tft.print("v0.75 with");
   tft.print("TFT mod   ");
   tft.print("          ");
   tft.print("by        ");
   tft.print("Kyle Heide");
 }
 
 // turns off the display
 void sleepDisplay() {
   digitalWrite(lcdpwr, LOW); // power off diplay
 }
 
 // clears all of the text display cache, to give new screens a more accurate state
 void clearDisplayCache() {
   // Clear out the Previous Big screen last number text
   for(int i = 0; i < 5; i ++) { // the big num previous char array
     lastNumText[i] = 0;
   }
   
   // Clear out the previous lastNums for the four display
   for(int i = 0; i < 4; i ++) {
     lastNums[i] = nil;
   }
   
   // Clear out the previous text numbers for the four display (20 = 4 rows * 5 columns)
   for(int i = 0; i < 20; i++) {
     lastChars[i] = 0;
   }
   
   // since this routine will  be called in screen changes or waking, set the current screen index to -1
   lastScreen = -1;
 }

///////////////////////////////////////////////////////////////////////////////////////////
// END New Code
/////////////////
 
// this function will return the number of bytes currently free in RAM      
extern int  __bss_end; 
extern int  *__brkval; 
int memoryTest(){ 
  int free_memory; 
  if((int)__brkval == 0) 
    free_memory = ((int)&free_memory) - ((int)&__bss_end); 
  else 
    free_memory = ((int)&free_memory) - ((int)__brkval); 
  return free_memory; 
} 
 
 
Trip::Trip(){      
}      
 
//for display computing
unsigned long tmp1[2];
unsigned long tmp2[2];
unsigned long tmp3[2];

unsigned long instantmph(){      
  //unsigned long vssPulseTimeuS = (lastVSS1 + lastVSS2) / 2;
  unsigned long vssPulseTimeuS = instant.vssPulseLength/instant.vssPulses;
  
  init64(tmp1,0,1000000000ul);
  init64(tmp2,0,parms[vssPulsesPerMileIdx]);
  div64(tmp1,tmp2);
  init64(tmp2,0,3600);
  mul64(tmp1,tmp2);
  init64(tmp2,0,vssPulseTimeuS);
  div64(tmp1,tmp2);
  return tmp1[1];
}

unsigned long instantmpg(){     
  unsigned long imph=instantmph();
  unsigned long igph=instantgph();
  if(imph == 0) return 0;
  if(igph == 0) return 999999000;
  init64(tmp1,0,1000ul);
  init64(tmp2,0,imph);
  mul64(tmp1,tmp2);
  init64(tmp2,0,igph);
  div64(tmp1,tmp2);
  return tmp1[1];
}


unsigned long instantgph(){      
//  unsigned long vssPulseTimeuS = instant.vssPulseLength/instant.vssPulses;
  
//  unsigned long instInjStart=nil; 
//unsigned long instInjEnd; 
//unsigned long instInjTot; 
  init64(tmp1,0,instInjTot);
  init64(tmp2,0,3600000000ul);
  mul64(tmp1,tmp2);
  init64(tmp2,0,1000ul);
  mul64(tmp1,tmp2);
  init64(tmp2,0,parms[microSecondsPerGallonIdx]);
  div64(tmp1,tmp2);
  init64(tmp2,0,instInjEnd-instInjStart);
  div64(tmp1,tmp2);
  return tmp1[1];      
}
/*
unsigned long instantrpm(){      
  init64(tmp1,0,instInjCount);
  init64(tmp2,0,120000000ul);
  mul64(tmp1,tmp2);
  init64(tmp2,0,1000ul);
  mul64(tmp1,tmp2);
  init64(tmp2,0,parms[injPulsesPer2Revolutions]);
  div64(tmp1,tmp2);
  init64(tmp2,0,instInjEnd-instInjStart);
  div64(tmp1,tmp2);
  return tmp1[1];      
} */





unsigned long Trip::miles(){      
  init64(tmp1,0,vssPulses);
  init64(tmp2,0,1000);
  mul64(tmp1,tmp2);
  init64(tmp2,0,parms[vssPulsesPerMileIdx]);
  div64(tmp1,tmp2);
  return tmp1[1];      
}      
 
unsigned long Trip::eocMiles(){      
  init64(tmp1,0,vssEOCPulses);
  init64(tmp2,0,1000);
  mul64(tmp1,tmp2);
  init64(tmp2,0,parms[vssPulsesPerMileIdx]);
  div64(tmp1,tmp2);
  return tmp1[1];      
}       
 
unsigned long Trip::mph(){      
  if(loopCount == 0)     
     return 0;     
  init64(tmp1,0,loopsPerSecond);
  init64(tmp2,0,vssPulses);
  mul64(tmp1,tmp2);
  init64(tmp2,0,3600000);
  mul64(tmp1,tmp2);
  init64(tmp2,0,parms[vssPulsesPerMileIdx]);
  div64(tmp1,tmp2);
  init64(tmp2,0,loopCount);
  div64(tmp1,tmp2);
  return tmp1[1];      
}      
 
unsigned long  Trip::gallons(){      
  init64(tmp1,0,injHiSec);
  init64(tmp2,0,1000000);
  mul64(tmp1,tmp2);
  init64(tmp2,0,injHius);
  add64(tmp1,tmp2);
  init64(tmp2,0,1000);
  mul64(tmp1,tmp2);
  init64(tmp2,0,parms[microSecondsPerGallonIdx]);
  div64(tmp1,tmp2);
  return tmp1[1];      
}      

unsigned long  Trip::idleGallons(){      
  init64(tmp1,0,injIdleHiSec);
  init64(tmp2,0,1000000);
  mul64(tmp1,tmp2);
  init64(tmp2,0,injIdleHius);
  add64(tmp1,tmp2);
  init64(tmp2,0,1000);
  mul64(tmp1,tmp2);
  init64(tmp2,0,parms[microSecondsPerGallonIdx]);
  div64(tmp1,tmp2);
  return tmp1[1];      
}      

//eocMiles
//idleGallons
 
unsigned long  Trip::mpg(){      
  if(vssPulses==0) return 0;      
  if(injPulses==0) return 999999000; //who doesn't like to see 999999?  :)      
 
  init64(tmp1,0,injHiSec);
  init64(tmp3,0,1000000);
  mul64(tmp3,tmp1);
  init64(tmp1,0,injHius);
  add64(tmp3,tmp1);
  init64(tmp1,0,parms[vssPulsesPerMileIdx]);
  mul64(tmp3,tmp1);
 
  init64(tmp1,0,parms[microSecondsPerGallonIdx]);
  init64(tmp2,0,1000);
  mul64(tmp1,tmp2);
  init64(tmp2,0,vssPulses);
  mul64(tmp1,tmp2);
 
  div64(tmp1,tmp3);
  return tmp1[1];      
}      
 
//return the seconds as a time mmm.ss, eventually hhh:mm too      
unsigned long Trip::time(){      
//  return seconds*1000;      
  byte d = 60;      
  unsigned long seconds = loopCount/loopsPerSecond;     
//  if(seconds/60 > 999) d = 3600; //scale up to hours.minutes if we get past 999 minutes      
  return ((seconds/d)*1000) + ((seconds%d) * 10);       
}      
 
 
void Trip::reset(){      
  loopCount=0;      
  injPulses=0;      
  injHius=0;      
  injHiSec=0;      
  vssPulses=0;  
  vssPulseLength=0;
  injIdleHiSec=0;
  injIdleHius=0;
  vssEOCPulses=0;
}      
 
void Trip::update(Trip t){     
  loopCount++;  //we call update once per loop     
  vssPulses+=t.vssPulses;      
  vssPulseLength+=t.vssPulseLength;
  if(t.injPulses ==0 )  //track distance traveled with engine off
    vssEOCPulses+=t.vssPulses;
  
  if(t.injPulses > 2 && t.injHius<500000){//chasing ghosts      
    injPulses+=t.injPulses;      
    injHius+=t.injHius;      
    if (injHius>=1000000){  //rollover into the injHiSec counter      
      injHiSec++;      
      injHius-=1000000;      
    }
    if(t.vssPulses == 0){    //track gallons spent sitting still
      
      injIdleHius+=t.injHius;      
      if (injIdleHius>=1000000){  //r
        injIdleHiSec++;
        injIdleHius-=1000000;      
      }      
    }
  }      
}   
//the standard 64 bit math brings in  5000+ bytes
//these bring in 1214 bytes, and everything is pass by reference
unsigned long zero64[]={0,0};
 
void init64(unsigned long  an[], unsigned long bigPart, unsigned long littlePart ){
  an[0]=bigPart;
  an[1]=littlePart;
}
 
//left shift 64 bit "number"
void shl64(unsigned long  an[]){
 an[0] <<= 1; 
 if(an[1] & 0x80000000)
   an[0]++; 
 an[1] <<= 1; 
}
 
//right shift 64 bit "number"
void shr64(unsigned long  an[]){
 an[1] >>= 1; 
 if(an[0] & 0x1)
   an[1]+=0x80000000; 
 an[0] >>= 1; 
}
 
//add ann to an
void add64(unsigned long  an[], unsigned long  ann[]){
  an[0]+=ann[0];
  if(an[1] + ann[1] < ann[1])
    an[0]++;
  an[1]+=ann[1];
}
 
//subtract ann from an
void sub64(unsigned long  an[], unsigned long  ann[]){
  an[0]-=ann[0];
  if(an[1] < ann[1]){
    an[0]--;
  }
  an[1]-= ann[1];
}
 
//true if an == ann
boolean eq64(unsigned long  an[], unsigned long  ann[]){
  return (an[0]==ann[0]) && (an[1]==ann[1]);
}
 
//true if an < ann
boolean lt64(unsigned long  an[], unsigned long  ann[]){
  if(an[0]>ann[0]) return false;
  return (an[0]<ann[0]) || (an[1]<ann[1]);
}
 
//divide num by den
void div64(unsigned long num[], unsigned long den[]){
  unsigned long quot[2];
  unsigned long qbit[2];
  unsigned long tmp[2];
  init64(quot,0,0);
  init64(qbit,0,1);
 
  if (eq64(num, zero64)) {  //numerator 0, call it 0
    init64(num,0,0);
    return;        
  }
 
  if (eq64(den, zero64)) { //numerator not zero, denominator 0, infinity in my book.
    init64(num,0xffffffff,0xffffffff);
    return;        
  }
 
  init64(tmp,0x80000000,0);
  while(lt64(den,tmp)){
    shl64(den);
    shl64(qbit);
  } 
 
  while(!eq64(qbit,zero64)){
    if(lt64(den,num) || eq64(den,num)){
      sub64(num,den);
      add64(quot,qbit);
    }
    shr64(den);
    shr64(qbit);
  }
 
  //remainder now in num, but using it to return quotient for now  
  init64(num,quot[0],quot[1]); 
}
 
 
//multiply num by den
void mul64(unsigned long an[], unsigned long ann[]){
  unsigned long p[2] = {0,0};
  unsigned long y[2] = {ann[0], ann[1]};
  while(!eq64(y,zero64)) {
    if(y[1] & 1) 
      add64(p,an);
    shl64(an);
    shr64(y);
  }
  init64(an,p[0],p[1]);
} 
  
void save(){
  EEPROM.write(0,guinosig);
  EEPROM.write(1,parmsLength);
  byte p = 0;
  for(int x=4; p < parmsLength; x+= 4){
    unsigned long v = parms[p];
    EEPROM.write(x ,(v>>24)&255);
    EEPROM.write(x + 1,(v>>16)&255);
    EEPROM.write(x + 2,(v>>8)&255);
    EEPROM.write(x + 3,(v)&255);
    p++;
  }
}

byte load(){ //return 1 if loaded ok
  #ifdef usedefaults
    return 1;
  #endif
  byte b = EEPROM.read(0);
  byte c = EEPROM.read(1);
  if(b == guinosigold)
    c=9; //before fancy parameter counter

  if(b == guinosig || b == guinosigold){
    byte p = 0;

    for(int x=4; p < c; x+= 4){
      unsigned long v = EEPROM.read(x);
      v = (v << 8) + EEPROM.read(x+1);
      v = (v << 8) + EEPROM.read(x+2);
      v = (v << 8) + EEPROM.read(x+3);
      parms[p]=v;
      p++;
    }
    return 1;
  }
  return 0;
}


char * uformat(unsigned long val){ 
  unsigned long d = 1000000000ul;
  for(byte p = 0; p < 10 ; p++){
    mBuff[p]='0' + (val/d);
    val=val-(val/d*d);
    d/=10;
  }
  mBuff[10]=0;
  return mBuff;
} 

unsigned long rformat(char * val){ 
  unsigned long d = 1000000000ul;
  unsigned long v = 0ul;
  for(byte p = 0; p < 10 ; p++){
    v=v+(d*(val[p]-'0'));
    d/=10;
  }
  return v;
} 

int setupY[4] = {0, 40, 70, 100};

void editParm(byte parmIdx){
  unsigned long v = parms[parmIdx];
  byte p=9;  //right end of 10 digit number
  //display label on top line
  //set cursor visible
  //set pos = 0
  //display v
  tft.setTextSize(2);
  tft.fillScreen(backgroundColor);
  tft.setCursor(0,setupY[0]);    
  tft.print(parmLabels[parmIdx]);
  tft.setCursor(0,setupY[1]);
  char * fmtv=    uformat(v);
  tft.print(fmtv);
  tft.setCursor(0,setupY[2]);
  tft.print(" OK   XX ");
  //LCD::LcdCommandWrite(B00001110);

  for(int x=9 ; x>=0 ;x--){ //do a nice thing and put the cursor at the first non zero number
    if(fmtv[x] != '0')
       p=x; 
  }
  byte keyLock=1;
 
 int cursorX[12] = {0, 12, 24, 36, 48, 60, 72, 84, 96, 108, 12, 72};
 int cursorY1 = setupY[1] + 3;
 int cursorY2 = setupY[2] + 3;
 int currCursor[2] = {cursorX[p], cursorY1};
 int lastCursor[2];
 
  
  while(true){
    //save current sursor as lastCursor
    lastCursor[0] = currCursor[0]; lastCursor[1] = currCursor[1];
    
    // delet old cursor
    tft.setCursor(lastCursor[0], lastCursor[1]);
    tft.setTextColor(backgroundColor);
    tft.print("_");
    
    // move cursor
    currCursor[0] = cursorX[p];  // x is indexed
    if(p < 10) currCursor[1] = cursorY1;
    if(p == 10 || p== 11) currCursor[1] = cursorY2;
    tft.setCursor(currCursor[0], currCursor[1]);
    
    // print new cursor
    tft.setTextColor(textColor);
    tft.print("_");
    
     if(keyLock == 0){ 
        if(!(buttonState&lbuttonBit) && !(buttonState&rbuttonBit)){// left & right
            if(p<10)p=10;
            else if(p==10) p=11;
            else{
              for(int x=9 ; x>=0 ;x--){ //do a nice thing and put the cursor at the first non zero number
                if(fmtv[x] != '0')
               p=x; 
              }
            }
        }else  if(!(buttonState&lbuttonBit)){// left
            p=p-1;
            if(p==255)p=11;
        }else if(!(buttonState&rbuttonBit)){// right
             p=p+1;
            if(p==12)p=0;
        }else if(!(buttonState&mbuttonBit)){// middle
             if(p==11){  //cancel selected
                //LCD::LcdCommandWrite(B00001100);
                tft.fillScreen(backgroundColor);
                return;
             }
             if(p==10){  //ok selected
                //LCD::LcdCommandWrite(B00001100);
                parms[parmIdx]=rformat(fmtv);
                tft.fillScreen(backgroundColor);
                return;
             }
             
             tft.setTextColor(backgroundColor);
             tft.setCursor(0,setupY[1]);
             tft.print(fmtv);
             tft.setTextColor(textColor);
             byte n = fmtv[p]-'0';
             n++;
             if (n > 9) n=0;
             if(p==0 && n > 3) n=0;
             fmtv[p]='0'+ n;
             tft.setCursor(0,setupY[1]);
             tft.print(fmtv);
             tft.setCursor(p,setupY[1]);        
             //if(parmIdx==contrastIdx)//adjust contrast dynamically
             //    analogWrite(ContrastPin,rformat(fmtv));
        }

      if(buttonState!=buttonsUp)
         keyLock=1;
     }else{
        keyLock=0;
     }
      buttonState=buttonsUp;
      delay2(125);
  }      
  
}

void initGuino(){ //edit all the parameters
  for(int x = 0;x<parmsLength;x++)
    editParm(x);
  save();
  holdDisplay=1;
}  

unsigned long millis2(){
	return timer2_overflow_count * 64UL * 2 / (16000000UL / 128000UL);
}

void delay2(unsigned long ms){
	unsigned long start = millis2();
	while (millis2() - start < ms);
}

/* Delay for the given number of microseconds.  Assumes a 16 MHz clock. 
 * Disables interrupts, which will disrupt the millis2() function if used
 * too frequently. */
void delayMicroseconds2(unsigned int us){
	uint8_t oldSREG;
	if (--us == 0)	return;
	us <<= 2;
	us -= 2;
	oldSREG = SREG;
	cli();
	// busy wait
	__asm__ __volatile__ (
		"1: sbiw %0,1" "\n\t" // 2 cycles
		"brne 1b" : "=w" (us) : "0" (us) // 2 cycles
	);
	// reenable interrupts.
	SREG = oldSREG;
}

void init2(){
	// this needs to be called before setup() or some functions won't
	// work there
	sei();
	
	// timer 0 is used for millis2() and delay2()
	timer2_overflow_count = 0;
	// on the ATmega168, timer 0 is also used for fast hardware pwm
	// (using phase-correct PWM would mean that timer 0 overflowed half as often
	// resulting in different millis2() behavior on the ATmega8 and ATmega168)
        TCCR2A=1<<WGM20|1<<WGM21;
	// set timer 2 prescale factor to 64
        TCCR2B=1<<CS22;


//      TCCR2A=TCCR0A;
//      TCCR2B=TCCR0B;
	// enable timer 2 overflow interrupt
	TIMSK2|=1<<TOIE2;
	// disable timer 0 overflow interrupt
	TIMSK0&=!(1<<TOIE0);
}
#define myubbr (16000000/16/9600-1)
void simpletx( char * string ){
 if (UCSR0B != (1<<TXEN0)){ //do we need to init the uart?
    UBRR0H = (unsigned char)(myubbr>>8);
    UBRR0L = (unsigned char)myubbr;
    UCSR0B = (1<<TXEN0);//Enable transmitter
    UCSR0C = (3<<UCSZ00);//N81
 }
 while (*string)
 {
   while ( !( UCSR0A & (1<<UDRE0)) );
   UDR0 = *string++; //send the data
 }
}