
#import "RNSpeechToTextIos.h"
#import <UIKit/UIKit.h>
#import "RCTUtils.h"
#import "RCTBridge.h"
#import "RCTEventDispatcher.h"
#import <Speech/Speech.h>

@interface RNSpeechToTextIos () <SFSpeechRecognizerDelegate>

@property (nonatomic) SFSpeechRecognizer* speechRecognizer;
@property (nonatomic) SFSpeechAudioBufferRecognitionRequest* recognitionRequest;
@property (nonatomic) AVAudioEngine* audioEngine;
@property (nonatomic) SFSpeechRecognitionTask* recognitionTask;


@property (nonatomic, weak, readwrite) RCTBridge *bridge;

@end

@implementation RNSpeechToTextIos
{
}



- (void) setupAndStartRecognizing:(NSString*)localeStr {
    [self teardown];
    
    NSLocale* locale = nil;
    if ([localeStr length] > 0) {
        locale = [NSLocale localeWithLocaleIdentifier:localeStr];
    }
    
    if (locale) {
        self.speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
    } else {
        self.speechRecognizer = [[SFSpeechRecognizer alloc] init];
    }
    
    self.speechRecognizer.delegate = self;
    
    
    NSError* audioSessionError = nil;
    AVAudioSession* audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryRecord error:&audioSessionError];
    if (audioSessionError != nil) {
        [self sendResult:RCTMakeError([audioSessionError localizedDescription], nil, nil) :nil :nil :nil];
        return;
    }
    [audioSession setMode:AVAudioSessionModeMeasurement error:&audioSessionError];
    if (audioSessionError != nil) {
        [self sendResult:RCTMakeError([audioSessionError localizedDescription], nil, nil) :nil :nil :nil];
        return;
    }
    [audioSession setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&audioSessionError];
    if (audioSessionError != nil) {
        [self sendResult:RCTMakeError([audioSessionError localizedDescription], nil, nil) :nil :nil :nil];
        return;
    }
    
    
    self.recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    
    if (self.recognitionRequest == nil){
        [self sendResult:RCTMakeError(@"Unable to created a SFSpeechAudioBufferRecognitionRequest object", nil, nil) :nil :nil :nil];
        return;
    }
    
    if (self.audioEngine == nil) {
        self.audioEngine = [[AVAudioEngine alloc] init];
    }
    
    AVAudioInputNode* inputNode = self.audioEngine.inputNode;
    if (inputNode == nil) {
        [self sendResult:RCTMakeError(@"Audio engine has no input node", nil, nil) :nil :nil :nil];
        return;
    }
    
    // Configure request so that results are returned before audio recording is finished
    self.recognitionRequest.shouldReportPartialResults = YES;

    // A recognition task represents a speech recognition session.
    // We keep a reference to the task so that it can be cancelled.
    self.recognitionTask = [self.speechRecognizer recognitionTaskWithRequest:self.recognitionRequest resultHandler:^(SFSpeechRecognitionResult * _Nullable result, NSError * _Nullable error) {
        
        if (error != nil) {
            [self sendResult:RCTMakeError([error localizedDescription], nil, nil) :nil :nil :nil];
            [self teardown];
            return;
        }
        
        BOOL isFinal = result.isFinal;
        if (result != nil) {
            NSMutableArray* transcriptionDics = [NSMutableArray new];
            for (SFTranscription* transcription in result.transcriptions) {
                [transcriptionDics addObject:[self dicFromTranscription:transcription]];
            }
            
            [self sendResult:[NSNull null] :[self dicFromTranscription:result.bestTranscription] :transcriptionDics :@(isFinal)];
        }
        
        if (isFinal == YES) {
            [self teardown];
        }
        
        NSLog(@"CALLBACK : Final: %i, status:%i", isFinal, self.recognitionTask.state);
        
    }];
    
    AVAudioFormat* recordingFormat = [inputNode outputFormatForBus:0];
    
    [inputNode installTapOnBus:0 bufferSize:1024 format:recordingFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        if (self.recognitionRequest != nil) {
            [self.recognitionRequest appendAudioPCMBuffer:buffer];
        }
    }];
    
    [self.audioEngine prepare];
    [self.audioEngine startAndReturnError:&audioSessionError];
    if (audioSessionError != nil) {
        [self sendResult:RCTMakeError([audioSessionError localizedDescription], nil, nil) :nil :nil :nil];
        return;
    }
}

- (void) sendResult:(NSDictionary*)error :(NSDictionary*)bestTranscription :(NSArray*)transcriptions :(NSNumber*)isFinal {
//    NSString *eventName = notification.userInfo[@"name"];
    NSMutableDictionary* result = [[NSMutableDictionary alloc] init];
    if (error != nil && error != [NSNull null]) {
        result[@"error"] = error;
    }
    if (bestTranscription != nil) {
        result[@"bestTranscription"] = bestTranscription;
    }
    if (transcriptions != nil) {
        result[@"transcriptions"] = transcriptions;
    }
    if (isFinal != nil) {
        result[@"isFinal"] = isFinal;
    }
    
    [self.bridge.eventDispatcher sendAppEventWithName:@"SpeechToText"
                                                 body:result];
}

- (void) teardown {
    [self.recognitionTask cancel];
    self.recognitionTask = nil;
    
    if (self.audioEngine.isRunning) {
        [self.audioEngine stop];
        [self.recognitionRequest endAudio];
        [self.audioEngine.inputNode removeTapOnBus:0];
    }
    
    self.recognitionRequest = nil;
}

- (NSDictionary*) dicFromTranscription:(SFTranscription*) transcription {
    NSMutableArray* secgmentsDics = [NSMutableArray new];
    for (SFTranscriptionSegment* segment in transcription.segments) {
        id dic = @{@"substring":segment.substring,
                   @"substringRange":@{@"location":@(segment.substringRange.location),
                                       @"length":@(segment.substringRange.length)},
                   @"timestamp":@(segment.timestamp),
                   @"duration":@(segment.duration),

                   @"confidence":@(segment.confidence),
                   @"alternativeSubstrings":segment.alternativeSubstrings,
                   };
        [secgmentsDics addObject:dic];
    }
    
    return @{@"formattedString":transcription.formattedString,
             @"segments":secgmentsDics};
}


// Called when the availability of the given recognizer changes
- (void)speechRecognizer:(SFSpeechRecognizer *)speechRecognizer availabilityDidChange:(BOOL)available {
    if (available == false) {
        [self sendResult:RCTMakeError(@"Speech recognition is not available now", nil, nil) :nil :nil :nil];
    }
}

RCT_EXPORT_METHOD(finishRecognition)
{
    // lets finish it
    [self.recognitionTask finish];
}


RCT_EXPORT_METHOD(stopRecognition)
{
    [self teardown];
}

RCT_EXPORT_METHOD(startRecognition:(NSString*)localeStr)
{
    if (self.recognitionTask != nil) {
        [self sendResult:RCTMakeError(@"Speech recognition already started!", nil, nil) :nil :nil :nil];
        return;
    }
    
    
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        switch (status) {
            case SFSpeechRecognizerAuthorizationStatusNotDetermined:
                [self sendResult:RCTMakeError(@"Speech recognition not yet authorized", nil, nil) :nil :nil :nil];
                break;
            case SFSpeechRecognizerAuthorizationStatusDenied:
                [self sendResult:RCTMakeError(@"User denied access to speech recognition", nil, nil) :nil :nil :nil];
                break;
            case SFSpeechRecognizerAuthorizationStatusRestricted:
                [self sendResult:RCTMakeError(@"Speech recognition restricted on this device", nil, nil) :nil :nil :nil];
                break;
            case SFSpeechRecognizerAuthorizationStatusAuthorized:
                [self setupAndStartRecognizing:localeStr];
                break;
        }
    }];
    
}




- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()

//- (NSDictionary *)constantsToExport {
//    return @{@"greeting": @"Welcome to the DevDactic\n React Native Tutorial!"};
//}


@end
  
