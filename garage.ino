/****************************************************************************
// Adafruit IO Digital Input Example
// Tutorial Link: https://learn.adafruit.com/adafruit-io-basics-digital-input
//
// Adafruit invests time and resources providing this open source code.
// Please support Adafruit and open source hardware by purchasing
// products from Adafruit!
//
// Written by Todd Treece for Adafruit Industries
// Copyright (c) 2016 Adafruit Industries
// Licensed under the MIT license.
//
// All text above must be included in any redistribution.

 * modified in June 2017 to implement a garage door monitor/opener/closer
 * Jim Calvin
 ****************************************************************************/

/************************** Configuration ***********************************
 * edit the config.h tab and enter your Adafruit IO credentials
 * and any additional configuration needed for WiFi, cellular,
 * or ethernet clients.
 ****************************************************************************/

#include "config.h"

#define loggingOn 1                     // set to 0 to disable logging to serial monitor

// these first two are the reed switches on the garage door to detect open/close
AdafruitIO_Feed *leftreed = io.feed("left-reed");
AdafruitIO_Feed *rightreed = io.feed("right-reed");

// and these two are button presses to open/close the garage door (if feature implemented)
AdafruitIO_Feed *leftopenclose = io.feed("left-open-close");
AdafruitIO_Feed *rightopenclose = io.feed("right-open-close");

// GPIO pins used for the reed switches (INPUTS)
#define leftReedPin 14
#define rightReedPin 12
// GPIO pins used for triggering the relay to open/close doors
// had previously used 13 & 15, but board wouldn't boot with relay attached
#define leftRelayPin 5
#define rightRelayPin 4

// definitions to use to make sure ESP.restart() works properly
#define GPIO0 0
#define GPIO2 2
#define GPIO15 15

// definitions used to blink LEDs to show activity
#define connectingLEDPin 2
#define activeLEDPin 0

// time period definitions
#define updatePeriod (10)               // # of seconds between sending updates for stuff to keep things active
#define kReconnectNetworkPeriod (60*7)  // # seconds between restarting the system

#define blinkPeriod 250                 // 1/4 of a second between transitions (red LED active indicator)

#define doorLogicOpen HIGH
#define doorLogicClosed LOW

// remembered states of switches and relay outputs
int leftReedState = 1;                  // open
int rightReedState = 1;
int leftOpenCloseButtonState = 0;
int rightOpenCloseButtonState = 0;

// when we last did certain things
unsigned long lastForcedUpdate = 0;     // this time + updatePeriod is time to resend our data
unsigned long lastNetworkConnect = 0;   // when we last connected
int forcedLastSent = 0;                 // index to cycle through the various things we update

unsigned long blinkTimer = millis();    // time since we toggled the state of the RED LED
int blinkState = LOW;                   // state of RED LED
int connectingState = LOW;              // state of BLUE LED (connecting active/squawk received)

unsigned long leftRelayOnMillis = 0;
unsigned long rightRelayOnMillis = 0;

#if loggingOn == 1
// print a number that's at least 2 digits, leading zero if need be
void printLeadingZero(unsigned long thing, unsigned long forSize) {
  if (thing < forSize) {
    Serial.print("0");
    if ((forSize > 10) && (thing == 0)) {
      Serial.print("0");
    }
  }
  Serial.print(thing);
}

// for debugging, print a time stamp of the form h:mm:ss.mil<space>
void doTimeStamp() {
    unsigned long tm = millis();
    unsigned long mill = tm % 1000;
    unsigned long secs = tm / 1000;
    unsigned long mins = secs / 60;
    unsigned long hrs = mins / 60;
    mins = mins % 60;
    secs = secs % 60;
    printLeadingZero(hrs, 10);
    Serial.print(":");
    printLeadingZero(mins, 10);
    Serial.print(":");
    printLeadingZero(secs, 10);
    Serial.print(".");
    printLeadingZero(mill, 100);
    Serial.print(" ");
}

#else

// versions to use to suppress actual logging
void log(String s, int addTimeStamp, int newLine) {
}

void log(int value, int addTimeStamp, int newLine) {
}

void log(unsigned long value, int addTimeStamp, int newLine) {
}

#endif

#if loggingOn == 1
// version to log information on serial monitor, including a time stamp
// log info - for debugging; string version
void log(String s, int addTimeStamp, int newLine) {
  if (addTimeStamp > 0) {
    doTimeStamp();
  }
  if (newLine > 0) {
    Serial.println(s);
  } else {
    Serial.print(s);
  }
}

// log info - for debugging; int version
void log(int value, int addTimeStamp, int newLine) {
  if (addTimeStamp > 0) {
    doTimeStamp();
  }
  if (newLine > 0) {
    Serial.println(value);
  } else {
    Serial.print(value);
  }
}

// log info - for debugging; unsigned long version
void log(unsigned long value, int addTimeStamp, int newLine) {
  if (addTimeStamp > 0) {
    doTimeStamp();
  }
  if (newLine > 0) {
    Serial.println(value);
  } else {
    Serial.print(value);
  }
}
#endif

// separate method to set up network so we can restart it if connection dies for some reason
// but probably never gets used for an actual network (only) restart
void setupNetwork() {
// subscribe for messages
  leftopenclose->onMessage(handleLeftButton);   // client pressed and open/close button
  rightopenclose->onMessage(handleRightButton); // client pressed and open/close button

// connect to io.adafruit.com
  log("Connecting to io.adafruit.com", 1, 0);
  io.connect();
  pinMode(connectingLEDPin, OUTPUT);            // blink blue LED that we're doing this
  digitalWrite(connectingLEDPin, connectingState);
  int counter = 0;
  while(io.status() < AIO_CONNECTED) {
    log(".", 0, 0);
    delay(500);
    blinkBlueLED();
    counter = counter + 1;
    if (counter > 15) {                         // if the connection doesn't happen for a long time, restart
      log("waiting too long for connection; restarting...", 1, 1);
      delay(500);      
      maybeRestartNetwork(1);
    }
  }
  digitalWrite(connectingLEDPin, HIGH);
  lastNetworkConnect = millis();

// we are connected

  log("", 0, 1);
  log(io.statusText(), 1, 1);
  pinMode(activeLEDPin, OUTPUT);
}

void setupSerial() {
#if loggingOn == 1
// start the serial connection
  Serial.begin(115200);
// wait for serial monitor to open
  while(! Serial) {
    delay(50);
  }
#endif
}

// setup GPIO pins we use
void setupGPIOPins() {
// pins for the reed switches detecting if door is open/closed
  pinMode(leftReedPin, INPUT);
  pinMode(rightReedPin, INPUT);

// setup the pins for dealing with the open/close relay
  pinMode(leftRelayPin, OUTPUT);
  pinMode(rightRelayPin, OUTPUT);
// default relays (LOW would activate the relay)
  digitalWrite(leftRelayPin, HIGH);
  digitalWrite(rightRelayPin, HIGH);
}

// we blink the BLUE LED to indicate we've sent (or received) data
void blinkBlueLED () {
  connectingState = !connectingState;
  digitalWrite(connectingLEDPin, connectingState);
}

// send (publish) either "Closed" or "Open" based on the state of the a switch
void saveState(AdafruitIO_Feed *theFeed, int state) {
  String strState = "Open";
  if (state == doorLogicClosed) {
    strState = "Closed";
  }
  theFeed->save(strState);
}

/****************************************************************** 
 * handleLeftButton
 * this function is called when the MQTT broker sends us a publish
 * in this case the client has asked to open/close the left door
 *****************************************************************/
void handleLeftButton(AdafruitIO_Data *data) {
  int value = data->toInt();
  log("left button: ", 1, 0);
  log(value, 0, 1);
  unsigned long now = millis();
  if (value == 0) {                     // returning to OFF?
    if ((digitalRead(leftRelayPin) == HIGH) && 
       ((leftRelayOnMillis+6000) < now)) {  // received OFF, but never saw ON?
      digitalWrite(leftRelayPin, LOW);  // yes, do the ON now, & let time-out handle off
      leftRelayOnMillis = now;          // remember when we turned it ON
    } else {
      digitalWrite(leftRelayPin, HIGH); // back to OFF state; (HIGH == OFF) for relay
    }
  } else {
    digitalWrite(leftRelayPin, LOW);
    leftRelayOnMillis = now;           // remember when we turned it ON
  }
  blinkBlueLED();
}

/****************************************************************** 
 * handleRightButton
 * this function is called when the MQTT broker sends us a publish
 * in this case the client has asked to open/close the right door
 *****************************************************************/
void handleRightButton(AdafruitIO_Data *data) {
  int value = data->toInt();
  log("right button: ", 1, 0);
  log(value, 0 , 1);
  unsigned long now = millis();
  if (value == 0) {                       // returning to OFF?
    if ((digitalRead(rightRelayPin) == HIGH) &&
       ((rightRelayOnMillis+6000) < now)) {  // received OFF, but never saw ON?
      digitalWrite(rightRelayPin, LOW);   // yes, do the ON now, & let time-out handle off
      rightRelayOnMillis = now;           // remember when we turned it ON
    } else {
      digitalWrite(rightRelayPin, HIGH);  // back to OFF state; (HIGH == OFF) for relay
    }
  } else {
    digitalWrite(rightRelayPin, LOW);
    rightRelayOnMillis = now;             // remember when we turned it ON
  }
  blinkBlueLED();
}

// force out an update of the door states if a certain time has passed
void maybeForceUpdate(unsigned long now) {
  if ((lastForcedUpdate+(updatePeriod*1000)) <= now) {
    saveState(leftreed, leftReedState);
    saveState(rightreed, rightReedState);
    blinkBlueLED();
    lastForcedUpdate = now;
  }
}

// time to blink the RED LED to show we're active
void maybeBlinkActiveLED(unsigned long now) {
  if (now == 0) {
    now = millis();
  }
  if ((now-blinkTimer) >= blinkPeriod) {
    blinkState = !blinkState;
    digitalWrite(activeLEDPin, blinkState);
    blinkTimer = now;
  }
}

/****************************************************************** 
 * maybeRestartNetwork
 * during testing, it seemed like the connect to the MQTT broker
 * would occasionally go dead. Restarting the ESP seems to avoid
 * this problem
 * check to see if connection has failed (or time has elapsed) & try to restart
 *****************************************************************/
void maybeRestartNetwork(int forceRestart) {
  if (((io.status() != AIO_CONNECTED) || (forceRestart != 0)) ||
      ((lastNetworkConnect + kReconnectNetworkPeriod*1000) < millis())) {
    log("", 0, 1);
    log("re-intializing network connection", 1, 0);
    if (forceRestart != 0) {
      log(" - forced restart", 0, 1);
    } else {
      log(" - no longer connected", 0, 1);
    }
    delay(500);
    pinMode(GPIO0, INPUT_PULLUP);     // put things in a known state so the restart
    pinMode(GPIO2, INPUT_PULLUP);     //   will work reliably
    digitalWrite(GPIO0, HIGH);
    digitalWrite(GPIO2, HIGH);
    digitalWrite(GPIO15, LOW);
    delay(500);
    ESP.restart();
  }
}

/****************************************************************** 
 * maybeResetRelays 
 * we only want the relay to temporarily be engaged - about 1/2 second 
 * we may recieve an ON/OFF pair from the broker, but it's possible
 * one (or both) may get lost
 * So, we keep track of when we engaged the relay so we can
 * release it after it's been engaged for 1/2 sec
 ******************************************************************/
void maybeResetRelays(unsigned long now) {
  int state = digitalRead(leftRelayPin);
  if ((state == LOW) && ((leftRelayOnMillis + 500) < now)) {
    digitalWrite(leftRelayPin, HIGH);   // yes, we flip the logic sense
  }
  state = digitalRead(rightRelayPin);
  if ((state == LOW) && ((rightRelayOnMillis + 500) < now)) {
    digitalWrite(rightRelayPin, HIGH);   // yes, we flip the logic sense
  }
}

// just for logging door state
void logDoorState(int doorState) {
   if (doorState == 0) {
      log("Closed", 0, 1);
    } else {
      log("Open", 0, 1);
    }
}

// standard setup function
void setup() {
  setupSerial();
  setupGPIOPins();
  setupNetwork();
}

/******************************************************** 
 io.run(); is required for all sketches.
 it should always be present at the top of your loop
 function. it keeps the client connected to
 io.adafruit.com, and processes any incoming data.
********************************************************/
void loop() {
  io.run();
  unsigned long now = millis();
// check to see if the left door state has changed
  int newState = digitalRead(leftReedPin);
  if (newState != leftReedState) {
    log("Left door => ", 1, 0);
    logDoorState(newState);
    leftReedState = newState;
    saveState(leftreed, leftReedState);
    lastForcedUpdate = now;
  }
// check to see if the right door state has changed
  newState = digitalRead(rightReedPin);
  if (newState != rightReedState) {
    log("Right door => ", 1, 0);
    logDoorState(newState);
    rightReedState = newState;
    saveState(rightreed, rightReedState);
    lastForcedUpdate = now;
  }
  maybeForceUpdate(now);            // send door state updates after some timeout period
  maybeBlinkActiveLED(now);         // blink the LED to say we're active
  maybeResetRelays(now);            // release the relay if time for that
  maybeRestartNetwork(0);           // restart if need be (or seems like a good idea)
}   // end of loop()

/* Edit notes
[ 4 Jun 17] Toggle BLUE led when we receive a door open/close button push
[ 5 Jun 17] Added code to set alarm when door open for some period
[ 6 Jun 17] Adjustments to maybeForceUpdate & restart only if connection dead, relay on updates to keep alive
[16 Jun 17] Dumb it down - ditch squawk; force updates every few seconds; no door open alarm
[17 Jun 17] More tweaks - if we see "relay off" and it's been awhile since "relay on", pretend it's relay ON,
              turned off logging
[ 5 Jul 17] Additional comments; deleted some unused defintions & code; conditionally compile logging

*/

