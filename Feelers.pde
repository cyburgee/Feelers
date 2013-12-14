import org.apache.http.HttpEntity;
import org.apache.http.HttpResponse;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.impl.client.DefaultHttpClient;
import java.io.*;
import ddf.minim.spi.*;
import ddf.minim.signals.*;
import ddf.minim.*;
import ddf.minim.analysis.*;
import ddf.minim.ugens.*;
import ddf.minim.effects.*;

import processing.serial.*;
import cc.arduino.*;

int end = 10;

Arduino arduino;
int padPin = 0;
//int potPin = 1;

HueHub hub; // the hub
HueLight beginningLight; // light instances
HueLight middleLight;
HueLight endLight;

String targetLight = "targetNum";
String statusLight = "status";

// for smoothing
int numReadings = 60;

int readings[];      // the readings from the analog input
int potReadings[];
int index = 0;                  // the index of the current reading
int total = 0;                  // the running total
int potTotal = 0;
int average = 0;                // the average
int potAverage = 0;
int targetNum;
int statusNum = 0;
int statusColorHueNum = 0;
int targetColorHueNum = 0;
int nextTargetNum = 0;
int goalHeld = 0;
int minTouch = 300;
int maxTouch = 900;
int minTarget = 300;
int maxTarget = 900;
int maxColorVal = 41565; //white in cie space
int minColorVal = 0; //red in cie space
int maxFreq = 120;
int minFreq = 60;
int timeLimit = (int)(60*2.5);
int touchThresh;

Color statusColor = null;
Color targetColor  = null;

Minim minim;
AudioOutput out;
SineWave sineTarget;
SineWave sineStatus;
float targetFreq;
float statusFreq;

boolean bufferSetup = false;
//boolean changeColor = false;
boolean goalMet = false;

int frame;
int frameRate = 60;

String KEY = "newdeveloper"; // "secret" key/hash
String IP = "192.168.1.15";// ip address of the hub
boolean ONLINE = true;

DefaultHttpClient httpClient; // http client to send/receive data

void setup(){
  frameRate(frameRate);
  smooth();
  
  println(Arduino.list());
  arduino = new Arduino(this, Arduino.list()[4],115200);
  arduino.pinMode(padPin, Arduino.INPUT);
  //arduino.pinMode(potPin, Arduino.INPUT);
  
  readings = new int[numReadings];
  potReadings = new int[numReadings];
 
  
  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO);
  sineStatus = new SineWave(20, 0.4, out.sampleRate());
  sineTarget = new SineWave(targetFreq, 0.4, out.sampleRate());
  // set the portamento speed on the oscillator to 100 milliseconds
  sineStatus.portamento(100);
  sineTarget.portamento(500);
  // add the oscillator to the line out
  out.addSignal(sineStatus);
  out.addSignal(sineTarget);
  
  int t = millis();
  while (millis()-t < 40){
    println("reading: " + arduino.analogRead(padPin));
    //println("reading Pot: " + arduino.analogRead(potPin));
  }
    
  
  //init hub and lights
  httpClient = new DefaultHttpClient();
  
  hub = new HueHub();  
  beginningLight = new HueLight(1, hub);
  middleLight = new HueLight(2, hub);
  endLight = new HueLight(3, hub);
  
  targetNum = (int)random(minTarget,maxTarget);
  targetFreq = map(targetNum, minTouch, maxTouch, maxFreq, minFreq);
  
  //calibrate touch
  //the threshold is around the amount of touching that can cause a visible change in color
  touchThresh = (int)(0.7*(maxColorVal-minColorVal)/(maxTouch-minTouch));
  
  beginningLight.turnOn(); 
  middleLight.turnOn();
  endLight.turnOn();
  
  frame = 0; 
}

void draw(){
  frame++;
  if (frame == 60)
    frame = 0;
 
  //want to draw the goal reached response then change to the next target Color
  if (goalMet == true) {
    //get a new target
    targetNum = (int)random(minTarget,maxTarget);
    int t = millis();
    while (millis()-t < 1000) {
      //if(frame%20 == 0)
        middleLight.dim();
    }
    endLight.setTransitionTime((byte)0xf);
    beginningLight.setTransitionTime((byte)0xf);
    setTargetColor(targetNum);
    targetFreq = map(targetNum, minTarget, maxTarget, maxFreq, minFreq);
    sineTarget.setFreq(targetFreq);
    
    //changeColor = true;
    goalMet = false;
    return;
  }
  
  // subtract the last reading:
  total = total - readings[index];
  // read from the sensor:  
  readings[index] = arduino.analogRead(padPin); 
  // add the reading to the total:
  total= total + readings[index];
  // advance to the next position in the array:  
  index = index + 1;                    

  // if we're at the end of the array...
  if (index >= numReadings) {      
    // ...wrap around to the beginning: 
    index = 0;
    bufferSetup = true;
  }
  
  // calculate the average:
  average = total / numReadings;
 
  if (bufferSetup == false)
    return;
    
  //normalize voltage reading average to color number  
  float touchVal = (float)average;
  println("touchVal: " + touchVal);
  //constain touch values
  touchVal = constrain(touchVal, minTouch, maxTouch);
  
  
  statusNum = (int)map(touchVal, minTouch, maxTouch, minTarget, maxTarget);
  println("touchThresh: " + touchThresh);
  println("statusNum: "  + statusNum);
  println("targetNum: " + targetNum);
  
  setStatusColor(statusNum);
  setTargetColor(targetNum);
  
  
  //map the touching sound frequencies
  statusFreq = map(statusNum, minTouch, maxTouch, maxFreq, minFreq);
  targetFreq = map(targetNum, minTarget, maxTarget, maxFreq, minFreq);
  println("statusFreq: " + statusFreq);
  println("targetFreq: " + targetFreq);
  sineStatus.setFreq(statusFreq);
  sineTarget.setFreq(targetFreq);
  
  //see if the touching amount is within range enough
  compareTouch(targetNum,statusNum);
  
  //need to hold for 1.5 seconds
  println("goalHeld: " + goalHeld);
  if (goalHeld > timeLimit) {
    goalMet = true;
    resetVals();
  }
}


void compareTouch(int targetNum, int statusNum) {
  if (abs(targetNum - statusNum) < touchThresh) 
    goalHeld++;
  else
    goalHeld = 0;
}


//set the color of the target lights
void setTargetColor(int targetNum){
  if (frame%20 != 0)
    return;
  if(!beginningLight.isOn())
    beginningLight.turnOn();
  if(!endLight.isOn())
    endLight.turnOn();
  targetColorHueNum = (int)map(targetNum,minTarget, maxTarget, minColorVal, maxColorVal);
  beginningLight.setHue(targetColorHueNum);
  beginningLight.update();
  endLight.setHue(targetColorHueNum);
  endLight.update();
}

//set the color of the status light
void setStatusColor(int statusNum){
  if (frame%20 != 0)
    return;
  if(!middleLight.isOn())
    middleLight.turnOn();
  middleLight.setBrightness(255);
  statusColorHueNum = (int)map(statusNum, minTouch, maxTouch, minColorVal, maxColorVal);
  middleLight.setHue(statusColorHueNum);
  middleLight.update();
}


void stop()
{
  out.close();
  minim.stop();
  hub.disconnect();
  super.stop();
}


//modified code from https://github.com/jvandewiel/hue
// Hub class, contains the http stuff as well
// Handles url as url = http://<IP>/api/<KEY>/lights/<id>/state";
class HueHub {
  // constructor, init http
  public HueHub() {
  }

  // Query the hub for the name of a light
  public String getLightName(HueLight light) {
    // build string to get the name,   
    return "noname";
  }
 
  // apply the state for the passed hue light based on the values
  public void applyState(HueLight light) { 
    ByteArrayOutputStream baos = new ByteArrayOutputStream();
    try {
      // format url for specific light
      StringBuilder url = new StringBuilder("http://");
      url.append(IP);
      url.append("/api/");
      url.append(KEY);
      url.append("/lights/");
      url.append(light.getID());
      url.append("/state");
      // get the data from the light instance
      String data = light.getData();
      StringEntity se = new StringEntity(data);
      HttpPut httpPut = new HttpPut(url.toString());
      // debugging
       //println(url);
      //println(light.getID() + "->" + data);

      //with post requests you can use setParameters, however this is
      //the only way the put request works with the JSON parameters
      httpPut.setEntity(se);
      // println( "executing request: " + httpPut.getRequestLine() );

      // sending data to url is only executed when ONLINE = true
      if (ONLINE) { 
        HttpResponse response = httpClient.execute(httpPut);
        HttpEntity entity = response.getEntity();
        
        if (entity != null) {
          // only check for failures, eg [{"success":
          entity.writeTo(baos);
          //success = baos.toString();
          //if (!baos.toString().startsWith("[{\"success\":")) println("error updating"); 
          //println(baos.toString());
        }
        
        // needs to be done to ensure next put can be executed and connection is released
        if (entity != null) entity.consumeContent();
      }
    } 
    catch( Exception e ) { 
      e.printStackTrace();
    }
  }

  // close connections and cleanup
  public void disconnect() {
    // when HttpClient instance is no longer needed, 
    // shut down the connection manager to ensure
    // deallocation of all system resources
    httpClient.getConnectionManager().shutdown();
  }
}

  
//modified code from https://github.com/jvandewiel/hue
// Hue class; one instance represents a lamp which is addressed using number
class HueLight {
  private int id; // lamp number/ID as known by the hub, e.g. 1,2,3
  // light variables
  private int hue = 0;//30000; // hue value for the lamp
  private int saturation = 255; // saturation value
  private int brightness = 255;
  private boolean lightOn = false; // is the lamp on or off, true if on?
  private byte transitiontime = (byte)0xa; // transition time, how fast  state change is executed -> 1 corresponds to 0.1s
  private float[] xy = {0,0};
  // hub variables
  private HueHub hub; // hub to register at
  private String name = "noname"; // set when registering the lamp with the hub
  // graphic settings
  private byte radius = 80; // size of the ellipse drawn on screen
  private int x; // x position on screen
  private int y; // y position on screen
  // control variables
  private float damping = 0.9; // control how fast dim() impacts brightness and lights turn off
  private float flashDuration = 0.2; // in approx. seconds
  private float frameCounter; // keeps track of number of frames drawn and turns light off when ==0

  // constructor, requires light ID and hub
  public HueLight(int lightID, HueHub aHub) {
    id = lightID;
    hub = aHub;
    // check if registered, get name [not implemented]
    name = hub.getLightName(this);
    if (name == "middleLight")
      brightness = 0;
  }

  // cycle thrue the colors
  public void incHue() {
    hue += 1000;
    setHue(hue);
  }

  // set the hue value; if outside bounds set to min/max allowed
  public void setHue(int hueValue) {
    hue = hueValue;
    if (hue < 0 || hue > 65535) {
      hue = 0;
    }
  }
  
  public void setxy(float x, float y) {
    xy[0] = x;
    xy[1] = y;
  }

  // set the brightness value, max 255
  public void setBrightness(int bri) {
    brightness = bri;
  }

  // set the saturation value, max 255
  public void setSaturation(byte sat) {
    saturation = sat;
  }

  // set the tranistion time; 1 = 0.1sec (not sure if there is a max)
  public void setTransitionTime(byte transTime) {
    transitiontime = transTime;
  }

  // returns true if the light is on (based on last state change, not a query of the light) 
  public boolean isOn() {
    return this.lightOn;
  }

  /*
   have the changes to the settings applied to the lamp & visualize; this
   calls the hub which handles the actual updates of the lights
   */
  public void update() {
    hub.applyState(this);
    // debugging
    // println("send update " + id);
  }

  // convenience method to turn the light off
  public void turnOff() {
    this.lightOn = false;
    update();
  }

  /* 
   turn on the light for <duration> ms; compensates for transition time 
   if duration = 2000 ms and fps = 20 -> #frames = (2000 / 1000) / (1/20) = 40 frames
   transition is subtracted before framecount is calculated
   */
  public void flashLight(float duration) {
    float durationOn = duration - (transitiontime * 100); // transition time of 1 = 0.1s = 100ms
    // translate the duration in ms to number of frames
    frameCounter = (duration/1000) / (1/frameRate);
    lightOn = true;
    // println("on for " + duration + "[ms], translates to " + frameCounter + "[frames] with fps " + frameRate);
    update();
  }

  // convenience method to turn the light on
  public void turnOn() {
    this.lightOn = true;
    update(); // apply new state
  }

  // convenience method to turn the light on with some passed settings
  public void turnOn(int hue, int brightness) {
    this.lightOn = true;
    this.hue = hue;
    this.brightness = brightness;
    update(); // apply new state
  }

  /* 
   return data with lamp settings, JSON formatted string, to be send to hub
   sometimes after a while you get an error message that the light is off
   and it won’t change, even when it’s actually on. You can work around 
   this by always turning the light on first. 
   */
  public String getData() {
    StringBuilder data = new StringBuilder("{");
    data.append("\"on\" :"); 
    data.append(lightOn);
    // only if the light is on we need the rest
    if (lightOn) {
      data.append(", \"hue\":");
      data.append(hue);
      //data.append(",\"xy\":");
      //data.append ("[" + xy[0] + "," + xy[1] + "]"); 
      data.append(", \"bri\":");
      data.append(brightness);
      data.append(", \"sat\":");
      data.append(saturation);
    }
    // always send transition time, to control how fast the state is changed
    data.append(", \"transitiontime\":");
    data.append(transitiontime);
    data.append("}");
    return data.toString();
  }

  // get current values
  public int getBrightness() {
    return brightness;
  }

  public int getSaturation() {
    return saturation;
  }

  public int getHue() {
    return hue;
  }

  public int getID() {
    return id;
  }

  /*
   dim the light using damping factor; if brightness < x and lighton then turn if
   this could allow for smoother on/off changes but also risk for hub errors (to any changes) 
   */
  public void dim() {
    brightness *= 0.8;
    if (brightness < 1 && lightOn) { // 20 is arbitrary threshold, could be higher/lower
      brightness = 0;
      lightOn=false;
      update();
    }
  }
}

void keyPressed() {
  if (key == 'b' || key == 'B') {
    if (maxTouch > minTouch*2) {
      minTouch += 15;
      setTargetColor(targetNum);
      touchThresh = (int)((0.7)*(maxColorVal - minColorVal) / (maxTouch - minTouch));
    }
    else
      println("maxTouch too low");
  }
  if (key == 'u' || key == 'U') {
    if (touchThresh < (maxTouch - minTouch))
      touchThresh += 5;
    else
      println("touchThresh too high");
  }
  if (key == 't' || key == 'T') {
    if (timeLimit > 60)
      timeLimit -= 15;
    else
      println("timeLimit too low");
  }
  if (key == 'r' || key == 'R'){
    resetVals();
  } 
}

//resets the game values
void resetVals() { 
  minTarget = 300;
  maxTarget = 900;
  minTouch = 300;
  maxTouch = 900;
  maxColorVal = 41565; //white in cie space
  minColorVal = 0; //red in cie space
  maxFreq = 120;
  minFreq = 60;
  timeLimit = (int)(60);
  touchThresh = (int)(1*(maxColorVal - minColorVal) / (maxTouch - minTouch));
}

