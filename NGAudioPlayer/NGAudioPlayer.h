//
//  NGAudioPlayer.h
//  NGAudioPlayer
//
//  Created by Matthias Tretter on 21.06.12.
//  Copyright (c) 2012 NOUS Wissensmanagement GmbH. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NGWeak.h"
#import "NGAudioPlayerPlaybackState.h"
#import "NGAudioPlayerDelegate.h"


@interface NGAudioPlayer : NSObject

@property (nonatomic, ng_weak) id<NGAudioPlayerDelegate> delegate;
@property (nonatomic, readonly, getter = isPlaying) BOOL playing;
@property (nonatomic, readonly) NGAudioPlayerPlaybackState playbackState;

@property (nonatomic, readonly) NSURL *currentPlayingURL;
@property (nonatomic, readonly) NSTimeInterval durationOfCurrentPlayingURL;
@property (nonatomic, readonly) NSArray *enqueuedURLs;


/******************************************
 @name Class Methods
 ******************************************/

+ (BOOL)setAudioSessionCategory:(NSString *)audioSessionCategory;
+ (BOOL)initBackgroundAudio;

/******************************************
 @name Lifecycle
 ******************************************/

- (id)initWithURL:(NSURL *)url;
- (id)initWithURLs:(NSArray *)urls;

/******************************************
 @name Playback
 ******************************************/

/**
 This method removes all items from the queue and starts playing the given URL.
 
 @param url the URL to play
 */
- (void)playURL:(NSURL *)url;
- (void)play;
- (void)pause;
- (void)togglePlayback;

/******************************************
 @name Queuing
 ******************************************/

/**
 This method adds the given URL to the end of the queue.
 
 @param url the URL to add to the queue
 @return YES if the URL was added successfully, NO otherwise
 */
- (BOOL)enqueueURL:(NSURL *)url;

/**
 This method adds the given URLs to the end of the queue.
 
 @param urls the URLs to add to the queue
 @return YES if all URLs were added successfully, NO otherwise
 */
- (BOOL)enqueueURLs:(NSArray *)urls;

/******************************************
 @name Removing
 ******************************************/

/**
 Removes the item with the given URL from the player-queue.
 
 @param url the URL of the item to remove
 @return YES if an item was removed, NO otherwise
 */
- (BOOL)removeURL:(NSURL *)url;
- (void)removeAllURLs;

- (void)advanceToNextURL;

@end
