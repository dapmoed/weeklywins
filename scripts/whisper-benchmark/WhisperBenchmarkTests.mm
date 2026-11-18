#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#include <memory>
#include "whisper.h"

static NSDictionary *batterySnapshot(void) {
    return @{@"level": @(UIDevice.currentDevice.batteryLevel),
             @"charging_state": @(UIDevice.currentDevice.batteryState),
             @"thermal_state": @(NSProcessInfo.processInfo.thermalState)};
}

static NSDictionary *measure(NSBundle *bundle, NSString *name, NSURL *model) {
    NSURL *audioURL = [bundle URLForResource:name withExtension:@"m4a"];
    double start = NSProcessInfo.processInfo.systemUptime;
    NSError *error = nil;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:audioURL error:&error];
    if (!file || file.processingFormat.sampleRate != 16000 || file.processingFormat.channelCount != 1
        || file.length <= 0 || file.length > 16000 * 301) {
        return @{@"error": error.localizedDescription ?: @"Expected mono 16 kHz fixture"};
    }
    AVAudioPCMBuffer *pcm = [[AVAudioPCMBuffer alloc] initWithPCMFormat:file.processingFormat
                                                       frameCapacity:(AVAudioFrameCount)file.length];
    if (![file readIntoBuffer:pcm error:&error] || !pcm.floatChannelData || pcm.frameLength != file.length) {
        return @{@"error": error.localizedDescription ?: @"Incomplete PCM decode"};
    }

    auto options = whisper_context_default_params();
    options.use_gpu = false;
    double loadStart = NSProcessInfo.processInfo.systemUptime;
    std::unique_ptr<whisper_context, decltype(&whisper_free)> context(
        whisper_init_from_file_with_params(model.fileSystemRepresentation, options), whisper_free);
    if (!context) return @{@"error": @"Model initialization failed"};

    auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.language = "ru";
    params.n_threads = 4;
    params.print_progress = params.print_realtime = params.print_timestamps = false;
    double inferenceStart = NSProcessInfo.processInfo.systemUptime;
    int code = whisper_full(context.get(), params, pcm.floatChannelData[0], pcm.frameLength);
    double inferenceEnd = NSProcessInfo.processInfo.systemUptime;
    if (code) return @{@"error": [NSString stringWithFormat:@"whisper_full returned %d", code]};

    NSMutableString *transcript = [NSMutableString string];
    for (int index = 0; index < whisper_full_n_segments(context.get()); index++) {
        NSString *segment = @(whisper_full_get_segment_text(context.get(), index));
        [transcript appendString:segment];
    }
    double elapsed = NSProcessInfo.processInfo.systemUptime - start;
    NSData *audio = [NSData dataWithContentsOfURL:audioURL];
    if (!audio) return @{@"error": @"Could not read fixture identity"};
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(audio.bytes, (CC_LONG)audio.length, bytes);
    NSMutableString *hash = [NSMutableString string];
    for (unsigned char byte : bytes) [hash appendFormat:@"%02x", byte];

    return @{@"fixture": [name stringByAppendingPathExtension:@"m4a"],
             @"sha256": hash, @"audio_seconds": @(pcm.frameLength / 16000.0),
             @"provider": @"whisper.cpp v1.9.5 Base Q5_1, CPU, 4 threads",
             @"transcript": transcript, @"processing_seconds": @(elapsed),
             @"model_load_seconds": @(inferenceStart - loadStart),
             @"inference_seconds": @(inferenceEnd - inferenceStart),
             @"ios_version": NSProcessInfo.processInfo.operatingSystemVersionString};
}

@interface WhisperBenchmarkTests : XCTestCase
@end

@implementation WhisperBenchmarkTests
- (void)testRussianCorpus {
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSURL *model = [bundle URLForResource:@"ggml-base-q5_1" withExtension:@"bin"];
    NSURL *manifestURL = [bundle URLForResource:@"whisper-build" withExtension:@"json"];
    NSData *manifestData = [NSData dataWithContentsOfURL:manifestURL];
    NSDictionary *manifest = manifestData ? [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:NULL] : nil;
    XCTAssertNotNil(manifest);
    XCTAssertNotNil(model);
    if (!model || !manifest) return;
    UIDevice *device = UIDevice.currentDevice;
    BOOL original = device.batteryMonitoringEnabled;
    device.batteryMonitoringEnabled = YES;
    NSURL *folder = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                        inDomains:NSUserDomainMask].firstObject
        URLByAppendingPathComponent:@"ASRAcceptance" isDirectory:YES];
    NSError *error = nil;
    XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtURL:folder
                         withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);
    for (NSString *name in @[@"ru-one-minute", @"ru-five-minute"]) {
        @autoreleasepool {
            NSDictionary *before = batterySnapshot();
            NSMutableDictionary *report = [measure(bundle, name, model) mutableCopy];
            report[@"model"] = manifest;
            report[@"battery_before"] = before;
            report[@"battery_after"] = batterySnapshot();
            NSData *json = [NSJSONSerialization dataWithJSONObject:report
                                       options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
            NSURL *url = [folder URLByAppendingPathComponent:[name stringByAppendingString:@".whisper-report.json"]];
            XCTAssertTrue([json writeToURL:url options:NSDataWritingAtomic error:&error], @"%@", error);
            XCTAssertNil(report[@"error"]);
            XCTAssertGreaterThan([report[@"transcript"] length], 0U);
        }
    }
    device.batteryMonitoringEnabled = original;
}
@end
