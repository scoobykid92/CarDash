//
//  FAOBD2Communicator.m
//  CarDash
//
//  Created by Jeff McFadden on 7/12/14.
//  Copyright (c) 2015 Jeff McFadden. All rights reserved.
//

//https://en.wikipedia.org/wiki/OBD-II_PIDs
//http://www.windmill.co.uk/obdii.pdf :
//MPG = VSS * 7.718 / MAF

#import "FAOBD2Communicator.h"

// Notifications
NSString *const kFAOBD2PIDDataUpdatedNotification = @"kFAOBD2PIDDataUpdatedNotification";
// Speed
NSString *const kFAOBD2PIDVehicleSpeed             = @"0D";
NSString *const kFAOBD2PIDEngineRPM                = @"0C";
NSString *const kFAOBD2PIDThrottlePosition         = @"11";
NSString *const kFAOBD2PIDTurboChargerRPM          = @"6F";
// Temperature
NSString *const kFAOBD2PIDAmbientAirTemperature    = @"46";
NSString *const kFAOBD2PIDEngineCoolantTemperature = @"05";
NSString *const kFAOBD2PIDAirIntakeTemperature     = @"0F";
// Flow
NSString *const kFAOBD2PIDMassAirFlow              = @"10";
NSString *const kFAOBD2PIDFuelFlow = @"kFAOBD2PIDFuelFlow"; //Calculated
NSString *const kFAOBD2PIDControlModuleVoltage     = @"42";
// Levels
NSString *const kFAOBD2PIDVehicleFuelLevel         = @"2F";
NSString *const kFAOBD2PIDBoostPressure            = @"70";
NSString *const kFAOBD2PIDExhaustPressure          = @"73";

@interface FAOBD2Communicator () <NSStreamDelegate>

@property (nonatomic) NSInputStream *inputStream;
@property (nonatomic) NSOutputStream *outputStream;

@property (atomic, assign) BOOL readyToSend;

@property (nonatomic) NSArray *sensorPIDsToScan;

@property (assign) NSInteger currentPIDIndex;

@property (nonatomic) NSTimer *pidsTimer;

@property (nonatomic) NSTimer *demoTimer;

@end

@implementation FAOBD2Communicator

+ (id)sharedInstance
{
  static FAOBD2Communicator *sharedInstance;
  static dispatch_once_t onceToken;
  
  dispatch_once(&onceToken, ^
                {
                  sharedInstance = [[FAOBD2Communicator alloc] init];
                });
  
  return sharedInstance;
}

- (id)init
{
  self = [super init];
  if (self) {
    self.readyToSend = YES;
    
    self.sensorPIDsToScan = @[kFAOBD2PIDVehicleSpeed,
                              kFAOBD2PIDEngineRPM,
                              kFAOBD2PIDThrottlePosition,
                              kFAOBD2PIDTurboChargerRPM,
                              
                              kFAOBD2PIDAmbientAirTemperature,
                              kFAOBD2PIDEngineCoolantTemperature,
                              kFAOBD2PIDAirIntakeTemperature,
                              
                              kFAOBD2PIDMassAirFlow,
                              kFAOBD2PIDFuelFlow,
                              kFAOBD2PIDControlModuleVoltage,
                              
                              kFAOBD2PIDVehicleFuelLevel,
                              kFAOBD2PIDBoostPressure,
                              kFAOBD2PIDExhaustPressure];
    self.currentPIDIndex =  0;
    
  }
  return self;
}

- (CGFloat)ctof:(CGFloat)c
{
  return (c * 1.8000 + 32.00 );
}

- (void)connect
{
  CFReadStreamRef readStream;
  CFWriteStreamRef writeStream;
  CFStreamCreatePairWithSocketToHost(NULL, (CFStringRef)@"192.168.0.10", 35000, &readStream, &writeStream);
  self.inputStream = (__bridge NSInputStream *)readStream;
  self.outputStream = (__bridge NSOutputStream *)writeStream;
  
  self.inputStream.delegate = self;
  self.outputStream.delegate = self;
  
  [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
  [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
  
  [self.inputStream open];
  [self.outputStream open];
}

- (void)restart
{
  DEBUG_NSLOG_FUNCTION_CALL
  
  [self stop];
  [self performSelector:@selector(startStreaming) withObject:nil afterDelay:2.0];
}

- (void)stop
{
  DEBUG_NSLOG_FUNCTION_CALL
  
  [self.pidsTimer invalidate];
  [self.inputStream close];
  [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
  [self.outputStream close];
  [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
}

- (void)startStreaming
{
  DEBUG_NSLOG_FUNCTION_CALL
  
  [self performSelector:@selector(connect) withObject:nil afterDelay:1.0];
  [self performSelector:@selector(sendInitialATCommands1) withObject:nil afterDelay:2.0];
  [self performSelector:@selector(sendInitialATCommands2) withObject:nil afterDelay:3.0];
  [self performSelector:@selector(streamPIDs) withObject:nil afterDelay:4.0];
}

- (void)sendInitialATCommands1
{
  DEBUG_NSLOG_FUNCTION_CALL
  
  NSString *message  = [NSString stringWithFormat:@"ATZ\r"];
  [self sendToOutputStream:message];
  DLog(@"sendInitialATCommands1: %@",message);
}

- (void)sendInitialATCommands2
{
  DEBUG_NSLOG_FUNCTION_CALL
  
  NSString *message  = [NSString stringWithFormat:@"ATP0\r"];
  [self sendToOutputStream:message];
  
  DLog(@"sendInitialATCommands2: %@",message);
  
}

- (void)streamPIDs
{
  DEBUG_NSLOG_FUNCTION_CALL
  
  self.pidsTimer = [NSTimer timerWithTimeInterval:0.1 target:self selector:@selector(askForPIDs) userInfo:nil repeats:YES];
  
  [[NSRunLoop currentRunLoop] addTimer:self.pidsTimer forMode:NSDefaultRunLoopMode];
}

- (void)askForPIDs
{
  if (self.readyToSend) {
    self.readyToSend = NO;
    NSString *sensorPID = self.sensorPIDsToScan[self.currentPIDIndex];
    
    NSString *message  = [NSString stringWithFormat:@"01%@1\r", sensorPID];
    [self sendToOutputStream:message];
    DLog(@"askForPIDs: %@",message);
    
    
    self.currentPIDIndex += 1;
    
    if (self.currentPIDIndex >= self.sensorPIDsToScan.count) {
      self.currentPIDIndex = 0;
    }
  }
}

- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent {
  switch (streamEvent) {
      
    case NSStreamEventOpenCompleted:
      DLog(@"Stream opened");
      break;
      
    case NSStreamEventHasBytesAvailable:
      DLog(@"NSStreamEventHasBytesAvailable");
      
      if (theStream == self.inputStream) {
        
        uint8_t buffer[1024];
        long len;
        
        while ([self.inputStream hasBytesAvailable]) {
          len = [self.inputStream read:buffer maxLength:sizeof(buffer)];
          if (len > 0) {
            
            NSString *output = [[NSString alloc] initWithBytes:buffer length:len encoding:NSASCIIStringEncoding];
            
            if (nil != output) {
              DLog(@"server said: %@", output);
              
              [output enumerateLinesUsingBlock:^(NSString *line, BOOL *stop){
                
                [self parseResponse:line];
                
              }];
            }else{
              DLog(@"Output Stream is nil");
              //self.readyToSend = YES;
            }
          }
        }
      }
      
      break;
      
    case NSStreamEventErrorOccurred:
      DLog(@"Can not connect to the host!");
      break;
      
    case NSStreamEventEndEncountered:
      DLog(@"NSStreamEventEndEncountered");
      
      [theStream close];
      [theStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
      
      break;
      
    case NSStreamEventNone:
      DLog(@"NSStreamEventNone");
      break;
      
    default: ;
      //DLog(@"Unknown event %lu", (unsigned long)streamEvent);
  }
}

- (void)parseResponse:(NSString *)response
{
  DLog(@"Response: %@",response);
  
  if ([response isEqualToString:@">"]) {
    self.readyToSend = YES;
    DLog(@"ReadToSend = YES");
    return;
  }
  
  if (response.length < 5) {
    DLog( @"Too short of a response line to care." );
    return;
  }
  // WTF IS THIS
  if ([[response substringToIndex:2] isEqualToString:@"41"]) {
    DLog( @"We have a response we can parse: %@", response );
    
    NSString *responseSensorID = [response substringWithRange:NSMakeRange(3, 2)];
    NSString *responseData     = [response substringFromIndex:6];
    
    NSMutableArray *byteValues = [NSMutableArray new];
    
    
    NSArray *responseBytes = [responseData componentsSeparatedByString:@" "];
    
    for (NSString *byte in responseBytes){
      NSScanner *scanner = [NSScanner scannerWithString:byte];
      unsigned int dataValue;
      [scanner scanHexInt:&dataValue];
      
      DLog(@"Converted data (%@) to int is: %d", byte, dataValue );
      
      [byteValues addObject:[NSNumber numberWithInt:dataValue]];
    }
    
    if ([responseSensorID isEqualToString:kFAOBD2PIDMassAirFlow]) {
      CGFloat maf = (([byteValues[0] intValue] * 256.0 ) + [byteValues[1] intValue]) / 100.0;
      CGFloat gph = maf * 0.0805;
      DLog(@"MAF: %0.1f grams/sec", maf );
      DLog(@"GPH: %0.1f", gph );
      [self postNotificationWithSensor:kFAOBD2PIDMassAirFlow WithValue:maf];
      [self postNotificationWithSensor:kFAOBD2PIDFuelFlow WithValue:gph];
      
    }else if ([responseSensorID isEqualToString:kFAOBD2PIDVehicleSpeed] ) {
      CGFloat mph = ([byteValues[0] intValue] * 0.621371 );
      DLog(@"MPH: %0.1f ", mph );
      [self postNotificationWithSensor:kFAOBD2PIDVehicleSpeed WithValue:mph];
      
    }else if ([responseSensorID isEqualToString:kFAOBD2PIDEngineCoolantTemperature] ) {
      CGFloat c = ([byteValues[0] intValue] - 40 );
      CGFloat f = [self ctof:c];
      DLog(@"Coolant Temp (F): %0.1f ", f );
      [self postNotificationWithSensor:kFAOBD2PIDEngineCoolantTemperature WithValue:f];
      
    }else if ([responseSensorID isEqualToString:kFAOBD2PIDAmbientAirTemperature] ) {
      CGFloat c = ([byteValues[0] intValue] - 40 );
      CGFloat f = [self ctof:c];
      DLog(@"Ambient Temp (F): %0.1f ", f );
      [self postNotificationWithSensor:kFAOBD2PIDAmbientAirTemperature WithValue:f];
      
    }else if ([responseSensorID isEqualToString:kFAOBD2PIDAirIntakeTemperature] ) {
      CGFloat c = ([byteValues[0] intValue] - 40 );
      CGFloat f = [self ctof:c];
      DLog(@"Intake Temp (F): %0.1f ", f );
      [self postNotificationWithSensor:kFAOBD2PIDAirIntakeTemperature WithValue:f];
      
    }else if ([responseSensorID isEqualToString:kFAOBD2PIDControlModuleVoltage] ) {
      CGFloat v = (([byteValues[0] intValue] * 256.0 ) + [byteValues[1] intValue]) / 1000.0;
      DLog(@"Control Module Voltage: %0.1f ", v );
      [self postNotificationWithSensor:kFAOBD2PIDControlModuleVoltage WithValue:v];
      
    }else if ([responseSensorID isEqualToString:kFAOBD2PIDVehicleFuelLevel] ) {
      CGFloat fl = (([byteValues[0] intValue] * 100.0)/255.0);
      DLog(@"Fuel Level: %0.1f", fl );
      [self postNotificationWithSensor:kFAOBD2PIDVehicleFuelLevel WithValue:fl];
      
    }
    DLog(@"Response Sensor ID: %@", responseSensorID );
    DLog(@"Response Sensor Data: %@", responseData );
    
  }else{
    DLog( @"This looks like something I don't know how to parse right now: %@", response );
  }
}

- (void)sendToOutputStream:(NSString *)message{
  NSData *data = [[NSData alloc] initWithData:[message dataUsingEncoding:NSASCIIStringEncoding]];
  [self.outputStream write:[data bytes] maxLength:[data length]];
}
- (void)postNotificationWithSensor:(NSString *)sensor
                         WithValue:(CGFloat)value{
  [[NSNotificationCenter defaultCenter]
   postNotificationName:kFAOBD2PIDDataUpdatedNotification
   object:@{@"sensor":sensor, @"value":[NSNumber numberWithDouble:value]}];
}
@end
