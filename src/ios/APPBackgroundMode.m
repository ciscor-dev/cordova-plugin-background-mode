/*
  Copyright 2013-2017 appPlant GmbH

  Licensed to the Apache Software Foundation (ASF) under one
  or more contributor license agreements.  See the NOTICE file
  distributed with this work for additional information
  regarding copyright ownership.  The ASF licenses this file
  to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance
  with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing,
  software distributed under the License is distributed on an
  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
  KIND, either express or implied.  See the License for the
  specific language governing permissions and limitations
  under the License.
*/

#import "APPMethodMagic.h"
#import "APPBackgroundMode.h"
#import <Cordova/CDVAvailability.h>

@implementation APPBackgroundMode

#pragma mark -
#pragma mark Constants

NSString* const kAPPBackgroundJsNamespace = @"cordova.plugins.backgroundMode";
NSString* const kAPPBackgroundEventActivate = @"activate";
NSString* const kAPPBackgroundEventDeactivate = @"deactivate";

#pragma mark -
#pragma mark Life Cycle

/**
 * Called by runtime once the Class has been loaded.
 * Exchange method implementations to hook into their execution.
 */
+ (void) load
{
    [self swizzleWKWebViewEngine];
}

/**
 * Initialize the plugin.
 */
- (void) pluginInitialize
{
    enabled = NO;
    foreground = YES;
    audioInterrupted = NO;
    [self configureAudioPlayer];
    [self configureAudioSession];
    [self observeLifeCycle];
}

/**
 * Register the listener for pause and resume events.
 */
- (void) observeLifeCycle
{
    NSNotificationCenter* listener = [NSNotificationCenter
                                      defaultCenter];

        [listener addObserver:self
                     selector:@selector(handleApplicationDidEnterBackground)
                         name:UIApplicationDidEnterBackgroundNotification
                       object:nil];

        [listener addObserver:self
                     selector:@selector(handleApplicationWillEnterForeground)
                         name:UIApplicationWillEnterForegroundNotification
                       object:nil];

        [listener addObserver:self
                     selector:@selector(handleAudioSessionInterruption:)
                         name:AVAudioSessionInterruptionNotification
                       object:nil];

        [listener addObserver:self
                     selector:@selector(handleAudioSessionRouteChange:)
                         name:AVAudioSessionRouteChangeNotification
                       object:nil];

        [listener addObserver:self
                     selector:@selector(handleSilenceSecondaryAudioHint:)
                         name:AVAudioSessionSilenceSecondaryAudioHintNotification
                       object:nil];

        [listener addObserver:self
                     selector:@selector(handleMediaServicesWereLost)
                         name:AVAudioSessionMediaServicesWereLostNotification
                       object:nil];

        [listener addObserver:self
                     selector:@selector(handleMediaServicesWereReset)
                         name:AVAudioSessionMediaServicesWereResetNotification
                       object:nil];
}

#pragma mark -
#pragma mark Interface

/**
 * Enable the mode to stay awake
 * when switching to background for the next time.
 */
- (void) enable:(CDVInvokedUrlCommand*)command
{
	[self fireLog:@"enable() enter"];

	if (!enabled) {
    	enabled = YES;
    	if (!foreground) {
    		[self fireLog:@"enable() in background, so playing audio"];
    		[self playAudio];
			[self fireLog:@"enabled() firing activate event"];
			[self fireEvent:kAPPBackgroundEventActivate];
		}
    }

    [self fireLog:@"enable() invoking callback"];
    [self execCallback:command];
    [self fireLog:@"enable() exit"];
}

/**
 * Disable the background mode
 * and stop being active in background.
 */
- (void) disable:(CDVInvokedUrlCommand*)command
{
	[self fireLog:@"disable() enter"];

    if (enabled) {
    	enabled = NO;
    	if (!foreground) {
    		[self fireLog:@"disable() in background and audio not interrupted, so pausing audio"];
			[audioPlayer pause];
			[self fireLog:@"enabled() in background, so firing deactivate event"];
			[self fireEvent:kAPPBackgroundEventDeactivate];
        }
    }

    [self fireLog:@"disable() invoking callback"];
    [self execCallback:command];
    [self fireLog:@"disable() exit"];
}

#pragma mark -
#pragma mark Core

/**
 * Configure the audio player.
 */
- (void) configureAudioPlayer
{
    NSString* path = [[NSBundle mainBundle]
                      pathForResource:@"appbeep" ofType:@"wav"];

    NSURL* url = [NSURL fileURLWithPath:path];


    audioPlayer = [[AVAudioPlayer alloc]
                   initWithContentsOfURL:url error:NULL];

    audioPlayer.volume        = 0;
    audioPlayer.numberOfLoops = -1;
};

/**
 * Configure the audio session.
 */
- (void) configureAudioSession
{
	[self fireLog:@"configureAudioSession() enter"];
	AVAudioSession* session = [AVAudioSession
                               sharedInstance];

	NSError* __autoreleasing err = nil;

    // deactivate the audio session
	[self fireLog:@"configureAudioSession() deactivating audio session"];
    if (![session setActive:NO error:&err]) {
    	[self fireLog:[NSString stringWithFormat:@"configureAudioSession() failed to deactivate audio session: %@", [err localizedFailureReason]]];
    }

    // set category and options
	[self fireLog:@"configureAudioSession() setting category and options"];
    if (![session setCategory:AVAudioSessionCategoryPlayback
    		withOptions:AVAudioSessionCategoryOptionMixWithOthers
            error:&err])
	{
   		[self fireLog:[NSString stringWithFormat:@"configureAudioSession() failed to set category and options: %@", [err localizedFailureReason]]];
	}

    // activate the audio session
	[self fireLog:@"configureAudioSession() activating audio session"];
    if (![session setActive:YES error:&err]) {
    	[self fireLog:[NSString stringWithFormat:@"configureAudioSession() failed to activate audio session: %@", [err localizedFailureReason]]];
    }

	[self fireLog:@"configureAudioSession() exit"];
};

/**
 * Play audio.
 */
- (void) playAudio
{
	[self fireLog:@"playAudio() enter"];

	[self fireLog:@"playAudio() configuring audio session"];
	[self configureAudioSession];

	[self fireLog:@"playAudio() playing audio"];
	if (![audioPlayer play]) {
		[self fireLog:@"handleApplicationDidEnterBackground() audioPlayer.play failed"];
	}

	[self fireLog:@"playAudio() exit"];
};

/**
 * Handle when app is brought to foreground.
 */
- (void) handleApplicationWillEnterForeground
{
	[self fireLog:@"handleApplicationWillEnterForeground() enter"];

	if (enabled) {
		[self fireLog:@"handleApplicationWillEnterForeground() enabled, so pausing audio"];
		[audioPlayer pause];
	}

	foreground = YES;
	audioInterrupted = NO;

	if (enabled) {
		[self fireLog:@"handleApplicationWillEnterForeground() enabled, so firing deactivate event"];
		[self fireEvent:kAPPBackgroundEventDeactivate];
	}

    [self fireLog:@"handleApplicationWillEnterForeground() exit"];
}

/**
 * Handle when app enters background.
 */
- (void) handleApplicationDidEnterBackground
{
    [self fireLog:@"handleApplicationDidEnterBackground() enter"];

    if (enabled) {
		[self fireLog:@"handleApplicationDidEnterBackground() enabled, so playing audio"];
		[self playAudio];
    }

    foreground = NO;

	if (enabled) {
		[self fireLog:@"handleApplicationDidEnterBackground() enabled, so firing activate event"];
		[self fireEvent:kAPPBackgroundEventActivate];
    }

    [self fireLog:@"handleApplicationDidEnterBackground() exit"];
}

/**
 * Restart playing sound when interrupted by phone calls.
 */
- (void) handleAudioSessionInterruption:(NSNotification*)notification
{
	[self fireLog:@"handleAudioSessionInterruption() enter"];

	NSDictionary *dict = notification.userInfo;
	NSInteger interruptionType = [[dict valueForKey:AVAudioSessionInterruptionTypeKey] integerValue];
	switch (interruptionType) {
		case AVAudioSessionInterruptionTypeBegan:
			[self fireLog:@"handleAudioSessionInterruption() type=began"];

			if (enabled && !foreground) {
				[self fireLog:@"handleAudioSessionInterruption() enabled and in background, so playing audio"];
				[self playAudio];
			}

			audioInterrupted = YES;
			break;
		case AVAudioSessionInterruptionTypeEnded:
			[self fireLog:@"handleAudioSessionInterruption() type=ended"];

			if (enabled && !foreground) {
				[self fireLog:@"handleAudioSessionInterruption() enabled and in background, so playing audio"];
				[self playAudio];
			}

			audioInterrupted = NO;
			break;
		default:
			[self fireLog:@"handleAudioSessionInterruption() type=default"];
			break;
	}

   	[self fireLog:@"handleAudioSessionInterruption() exit"];
}

/**
 * Observe route changes.
 */
- (void) handleAudioSessionRouteChange:(NSNotification*)notification
{
	[self fireLog:@"handleAudioSessionRouteChange() enter"];

	NSDictionary *dict = notification.userInfo;
	NSInteger routeChangeReason = [[dict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
	switch (routeChangeReason) {
		case AVAudioSessionRouteChangeReasonUnknown:
			[self fireLog:@"handleAudioSessionRouteChange() reason=unknown"];
			break;
		case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
			[self fireLog:@"handleAudioSessionRouteChange() reason=new device available"];
			break;
		case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
			[self fireLog:@"handleAudioSessionRouteChange() reason=old device unavailable"];
			break;
		case AVAudioSessionRouteChangeReasonCategoryChange:
			[self fireLog:@"handleAudioSessionRouteChange() reason=category change"];
			break;
		case AVAudioSessionRouteChangeReasonOverride:
			[self fireLog:@"handleAudioSessionRouteChange() reason=override"];
			break;
		case AVAudioSessionRouteChangeReasonWakeFromSleep:
			[self fireLog:@"handleAudioSessionRouteChange() reason=wake from sleep"];
			break;
		case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
			[self fireLog:@"handleAudioSessionRouteChange() reason=no suitable route for category"];
			break;
		case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
			[self fireLog:@"handleAudioSessionRouteChange() reason=route configuration change"];
			break;
		default:
			[self fireLog:@"handleAudioSessionRouteChange() reason=default"];
			break;
	}

	if (enabled && !foreground) {
		[self fireLog:@"handleAudioSessionRouteChange() enabled and in background, so playing audio"];
		[self playAudio];
	}

   	[self fireLog:@"handleAudioSessionRouteChange() exit"];
}

/**
 * Observe silence secondary audio hints.
 */
- (void) handleSilenceSecondaryAudioHint:(NSNotification*)notification
{
	[self fireLog:@"handleSilenceSecondaryAudioHint() enter"];

	NSDictionary *dict = notification.userInfo;
	NSInteger hintType = [[dict valueForKey:AVAudioSessionSilenceSecondaryAudioHintTypeKey] integerValue];
	switch (hintType) {
		case AVAudioSessionSilenceSecondaryAudioHintTypeBegin:
			[self fireLog:@"handleSilenceSecondaryAudioHint() type=begin"];
			break;
		case AVAudioSessionSilenceSecondaryAudioHintTypeEnd:
			[self fireLog:@"handleSilenceSecondaryAudioHint() type=end"];
			break;
		default:
			[self fireLog:@"handleSilenceSecondaryAudioHint() type=default"];
			break;
	}

   	[self fireLog:@"handleSilenceSecondaryAudioHint() exit"];
}

/**
 * Observe media services lost.
 */
- (void) handleMediaServicesWereLost
{
    [self fireLog:@"handleMediaServicesWereLost()"];
}

/**
 * Observe media services reset.
 */
- (void) handleMediaServicesWereReset
{
    [self fireLog:@"handleMediaServicesWereReset()"];
}

#pragma mark -
#pragma mark Helper

/**
 * Simply invokes the callback without any parameter.
 */
- (void) execCallback:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult *result = [CDVPluginResult
                               resultWithStatus:CDVCommandStatus_OK];

    [self.commandDelegate sendPluginResult:result
                                callbackId:command.callbackId];
}

/**
 * Find out if the app runs inside the webkit powered webview.
 */
+ (BOOL) isRunningWebKit
{
    return IsAtLeastiOSVersion(@"8.0") && NSClassFromString(@"CDVWKWebViewEngine");
}

/**
 * Method to fire an event with some parameters in the browser.
 */
- (void) fireEvent:(NSString*)event
{
    NSString* active =
    [event isEqualToString:kAPPBackgroundEventActivate] ? @"true" : @"false";

    NSString* flag = [NSString stringWithFormat:@"%@._isActive=%@;",
                      kAPPBackgroundJsNamespace, active];

    NSString* depFn = [NSString stringWithFormat:@"%@.on%@();",
                       kAPPBackgroundJsNamespace, event];

    NSString* fn = [NSString stringWithFormat:@"%@.fireEvent('%@');",
                    kAPPBackgroundJsNamespace, event];

    NSString* js = [NSString stringWithFormat:@"%@%@%@", flag, depFn, fn];

    [self.commandDelegate evalJs:js];
}

/**
 * Method to fire a log message event.
 */
- (void) fireLog:(NSString*)message
{
    NSString* js = [NSString stringWithFormat:@"%@.onlog('%@');",
                      kAPPBackgroundJsNamespace, message];

    [self.commandDelegate evalJs:js];
}

#pragma mark -
#pragma mark Swizzling

/**
 * Method to swizzle.
 */
+ (NSString*) wkProperty
{
    NSString* str = @"X2Fsd2F5c1J1bnNBdEZvcmVncm91bmRQcmlvcml0eQ==";
    NSData* data  = [[NSData alloc] initWithBase64EncodedString:str options:0];

    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

/**
 * Swizzle some implementations of CDVWKWebViewEngine.
 */
+ (void) swizzleWKWebViewEngine
{
    if (![self isRunningWebKit])
        return;

    Class wkWebViewEngineCls = NSClassFromString(@"CDVWKWebViewEngine");
    SEL selector = NSSelectorFromString(@"createConfigurationFromSettings:");

    SwizzleSelectorWithBlock_Begin(wkWebViewEngineCls, selector)
    ^(CDVPlugin *self, NSDictionary *settings) {
        id obj = ((id (*)(id, SEL, NSDictionary*))_imp)(self, _cmd, settings);

        [obj setValue:[NSNumber numberWithBool:YES]
               forKey:[APPBackgroundMode wkProperty]];

        [obj setValue:[NSNumber numberWithBool:NO]
               forKey:@"requiresUserActionForMediaPlayback"];

        return obj;
    }
    SwizzleSelectorWithBlock_End;
}

@end
