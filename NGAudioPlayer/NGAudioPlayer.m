//
//  NGAudioPlayer.m
//  NGAudioPlayer
//
//  Created by Matthias Tretter on 21.06.12.
//  Copyright (c) 2012 NOUS Wissensmanagement GmbH. All rights reserved.
//

#import "NGAudioPlayer.h"
#import "NGAudioPlayerDelegate.h"


#define kNGAudioPlayerKeypathRate           NSStringFromSelector(@selector(rate))
#define kNGAudioPlayerKeypathStatus         NSStringFromSelector(@selector(status))
#define kNGAudioPlayerKeypathCurrentItem    NSStringFromSelector(@selector(currentItem))


static char rateContext;
static char statusContext;
static char currentItemContext;


@interface NGAudioPlayer () {
    // flags for methods implemented in the delegate
    struct {
        unsigned int didStartPlaybackOfURL:1;
        unsigned int didChangePlaybackState:1;
	} _delegateFlags;
}

@property (nonatomic, strong) AVQueuePlayer *player;
@property (nonatomic, readonly) CMTime CMDurationOfCurrentItem;

- (NSURL *)URLOfItem:(AVPlayerItem *)item;
- (CMTime)CMDurationOfItem:(AVPlayerItem *)item;
- (NSTimeInterval)durationOfItem:(AVPlayerItem *)item;

- (void)handleRateChange:(NSDictionary *)change;
- (void)handleStatusChange:(NSDictionary *)change;
- (void)handleCurrentItemChange:(NSDictionary *)change;

@end


@implementation NGAudioPlayer

@synthesize delegate = _delegate;
@synthesize player = _player;

////////////////////////////////////////////////////////////////////////
#pragma mark - Lifecycle
////////////////////////////////////////////////////////////////////////

+ (void)initialize {
    if (self == [NGAudioPlayer class]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            (void)[self initBackgroundAudio];
        });
    }
}

- (id)initWithURLs:(NSArray *)urls {
    if ((self = [super init])) {
        if (urls.count > 0) {
            NSMutableArray *items = [NSMutableArray arrayWithCapacity:urls.count];
            
            for (NSURL *url in urls) {
                if ([url isKindOfClass:[NSURL class]]) {
                    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
                    [items addObject:item];
                }
            }
            
            _player = [AVQueuePlayer queuePlayerWithItems:items];
        } else {
            _player = [AVQueuePlayer queuePlayerWithItems:nil];
        }
        
        [self addObserver:self forKeyPath:kNGAudioPlayerKeypathRate options:NSKeyValueObservingOptionNew context:&rateContext];
        [self addObserver:self forKeyPath:kNGAudioPlayerKeypathStatus options:NSKeyValueObservingOptionNew context:&statusContext];
        [self addObserver:self forKeyPath:kNGAudioPlayerKeypathCurrentItem options:NSKeyValueObservingOptionNew context:&currentItemContext];
    }
    
    return self;
}

- (id)initWithURL:(NSURL *)url {
    return [self initWithURLs:[NSArray arrayWithObject:url]];
}

- (id)init {
    return [self initWithURLs:nil];
}

- (void)dealloc {
    [self removeObserver:self forKeyPath:kNGAudioPlayerKeypathRate];
    [self removeObserver:self forKeyPath:kNGAudioPlayerKeypathStatus];
    [self removeObserver:self forKeyPath:kNGAudioPlayerKeypathCurrentItem];
}

////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject KVO
////////////////////////////////////////////////////////////////////////

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &rateContext && [keyPath isEqualToString:kNGAudioPlayerKeypathRate]) {
        [self handleRateChange:change];
    } else if (context == &statusContext && [keyPath isEqualToString:kNGAudioPlayerKeypathStatus]) {
        [self handleStatusChange:change];
    } else if (context == &currentItemContext && [keyPath isEqualToString:kNGAudioPlayerKeypathCurrentItem]) {
        [self handleCurrentItemChange:change];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

////////////////////////////////////////////////////////////////////////
#pragma mark - NGAudioPlayer Properties
////////////////////////////////////////////////////////////////////////

- (BOOL)isPlaying {
    return self.playbackState == NGAudioPlayerPlaybackStatePlaying;
}

- (NGAudioPlayerPlaybackState)playbackState {
    if (self.player && self.player.rate != 0.f) {
        return NGAudioPlayerPlaybackStatePlaying;
    }
    
    return NGAudioPlayerPlaybackStatePaused;
}

- (NSURL *)currentPlayingURL {
    return [self URLOfItem:self.player.currentItem];
}

- (NSTimeInterval)durationOfCurrentPlayingURL {
    return [self durationOfItem:self.player.currentItem];
}

- (NSArray *)enqueuedURLs {
    NSArray *items = self.player.items;
    NSArray *itemsWithURLAssets = [items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [self URLOfItem:evaluatedObject] != nil;
    }]];
    
    NSAssert(items.count == itemsWithURLAssets.count, @"All Assets should be AVURLAssets");
    
    return [itemsWithURLAssets valueForKey:@"URL"];
}

- (void)setDelegate:(id<NGAudioPlayerDelegate>)delegate {
    if (delegate != _delegate) {
        _delegate = delegate;
        
        _delegateFlags.didStartPlaybackOfURL = [delegate respondsToSelector:@selector(audioPlayer:didStartPlaybackOfURL:)];
        _delegateFlags.didChangePlaybackState = [delegate respondsToSelector:@selector(audioPlayerDidChangePlaybackState:)];
    }
}

////////////////////////////////////////////////////////////////////////
#pragma mark - NGAudioPlayer Class Methods
////////////////////////////////////////////////////////////////////////

+ (BOOL)setAudioSessionCategory:(NSString *)audioSessionCategory {
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setCategory:audioSessionCategory
                                           error:&error];
    
    if (error != nil) {
        NSLog(@"There was an error setting the AudioCategory to %@", audioSessionCategory);
        return NO;
    }
    
    return YES;
}

+ (BOOL)initBackgroundAudio {
    if (![self setAudioSessionCategory:AVAudioSessionCategoryPlayback]) {
        return NO;
    }
    
    NSError *error = nil;
	if (![[AVAudioSession sharedInstance] setActive:YES error:&error]) {
		NSLog(@"Unable to set AudioSession active: %@", error);
        
        return NO;
	}
    
    return YES;
}

////////////////////////////////////////////////////////////////////////
#pragma mark - NGAudioPlayer Playback
////////////////////////////////////////////////////////////////////////

- (void)playURL:(NSURL *)url {
    [self removeAllURLs];
    [self enqueueURL:url];
    [self play];
}

- (void)play {
    [self.player play];
}

- (void)pause {
    [self.player pause];
}

- (void)togglePlayback {
    if (self.playing) {
        [self pause];
    } else {
        [self play];
    }
}

////////////////////////////////////////////////////////////////////////
#pragma mark - NGAudioPlayer Queuing
////////////////////////////////////////////////////////////////////////

- (BOOL)enqueueURL:(NSURL *)url {
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    
    if ([self.player canInsertItem:item afterItem:nil]) {
        [self.player insertItem:item afterItem:nil];
        
        return YES;
    }
    
    return NO;
}

- (BOOL)enqueueURLs:(NSArray *)urls {
    BOOL successfullyAdded = YES;
    
    for (NSURL *url in urls) {
        if ([url isKindOfClass:[NSURL class]]) {
            successfullyAdded = successfullyAdded && [self enqueueURL:url];
        }
    }
    
    return successfullyAdded;
}

////////////////////////////////////////////////////////////////////////
#pragma mark - NGAudioPlayer Removing
////////////////////////////////////////////////////////////////////////

- (BOOL)removeURL:(NSURL *)url {
    NSArray *items = self.player.items;
    NSArray *itemsWithURL = [items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [[self URLOfItem:evaluatedObject] isEqual:url];
    }]];
    
    // We only remove the first item with this URL (there should be a maximum of one)
    if (itemsWithURL.count > 0) {
        [self.player removeItem:[itemsWithURL objectAtIndex:0]];
        
        return YES;
    }
    
    return NO;
}

- (void)removeAllURLs {
    [self.player removeAllItems];
}

////////////////////////////////////////////////////////////////////////
#pragma mark - NGAudioPlayer Advancing
////////////////////////////////////////////////////////////////////////

- (void)advanceToNextURL {
    [self.player advanceToNextItem];
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Private
////////////////////////////////////////////////////////////////////////

- (NSURL *)URLOfItem:(AVPlayerItem *)item {
    AVAsset *asset = item.asset;
    
    if ([asset isKindOfClass:[AVURLAsset class]]) {
        AVURLAsset *urlAsset = (AVURLAsset *)asset;
        
        return urlAsset.URL;
    }
    
    return nil;
}

- (CMTime)CMDurationOfCurrentItem {
    return [self CMDurationOfItem:self.player.currentItem];
}

- (CMTime)CMDurationOfItem:(AVPlayerItem *)item {
    // Peferred in HTTP Live Streaming
    if ([item respondsToSelector:@selector(duration)] && // 4.3
        item.status == AVPlayerItemStatusReadyToPlay) {
        
        if (CMTIME_IS_VALID(item.duration)) {
            return item.duration;
        }
    }
    
    else if (CMTIME_IS_VALID(item.asset.duration)) {
        return item.asset.duration;
    }
    
    return kCMTimeInvalid;
}

- (NSTimeInterval)durationOfItem:(AVPlayerItem *)item {
    return CMTimeGetSeconds([self CMDurationOfItem:item]);
}

- (void)handleRateChange:(NSDictionary *)change {
    [self.delegate audioPlayerDidChangePlaybackState:self.playbackState];
}

- (void)handleStatusChange:(NSDictionary *)change {
    AVPlayerStatus newStatus = (AVPlayerStatus)[[change valueForKey:NSKeyValueChangeNewKey] intValue];
    
    // TODO: tell delegate that something happened
}

- (void)handleCurrentItemChange:(NSDictionary *)change {
    AVPlayerItem *newItem = (AVPlayerItem *)[change valueForKey:NSKeyValueChangeNewKey];
    NSURL *url = [self URLOfItem:newItem];
    
    if (self.playing && _delegateFlags.didStartPlaybackOfURL) {
        [self.delegate audioPlayer:self didStartPlaybackOfURL:url];
    }
}

@end
