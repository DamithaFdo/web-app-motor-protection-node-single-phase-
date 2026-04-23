#include <SoftwareSerial.h>

// RX on Digital Pin 2 (Connects to MCU 1 TX)
SoftwareSerial mcu1Serial(2, 3); 

const byte HEADER[3] = {0xAA, 0xBB, 0xCC};
int headerIndex = 0;

void setup() {
  Serial.begin(115200); 
  while (!Serial) { ; } 
  mcu1Serial.begin(9600);
}

void loop() {
  while (mcu1Serial.available() > 0) {
    byte b = mcu1Serial.read();

    if (b == HEADER[headerIndex]) {
      headerIndex++;
      
      if (headerIndex == 3) {
        // Wait safely for the 13 payload bytes
        unsigned long startTime = millis();
        while (mcu1Serial.available() < 13) {
           if (millis() - startTime > 50) {
              headerIndex = 0; 
              return; 
           }
        }

        // Read perfectly aligned bytes
        byte payload[13];
        for(int i=0; i<13; i++){
          payload[i] = mcu1Serial.read();
        }

        // Reconstruct Data (Pure Assembly Math Integers)
        int16_t rawX = (payload[0] << 8) | payload[1];
        int16_t rawY = (payload[2] << 8) | payload[3];
        int16_t rawZ = (payload[4] << 8) | payload[5];
        int16_t tempC = (payload[6] << 8) | payload[7];
        int16_t voltRMS = (payload[8] << 8) | payload[9];
        int16_t currRMS = (payload[10] << 8) | payload[11];
        int relay = payload[12];

        // Only scale X, Y, Z for the decimal point (Assembly multiplied by 100)
        float calcX = rawX / 100.0;
        float calcY = rawY / 100.0;
        float calcZ = rawZ / 100.0;

        // The Assembly Current was multiplied by 100 so "150" = 1.50A
        float calcCurr = currRMS / 100.0;

        // Print directly to Web App (No extra math!)
        Serial.print("{\"x\":");        Serial.print(calcX, 2);
        Serial.print(", \"y\":");       Serial.print(calcY, 2);
        Serial.print(", \"z\":");       Serial.print(calcZ, 2);
        Serial.print(", \"tempC\":");   Serial.print(tempC);
        Serial.print(", \"voltage\":"); Serial.print(voltRMS);
        Serial.print(", \"current\":"); Serial.print(calcCurr, 2);
        Serial.print(", \"relay\":");   Serial.print(relay);
        Serial.println("}");

        headerIndex = 0; 
      }
    } else {
      headerIndex = 0; 
      if (b == HEADER[0]) headerIndex = 1; 
    }
  }
}