#import <GameKit/GameKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

#import "MatchmakingServer.h"
#import "MediaItem.h"
#import "Player.h"
#import "MusicUpload.h"
#import "MusicDownload.h"
#import "Packet.h"
#import "CustomMovieController.h"

typedef enum
{
	ServerStateIdle,
	ServerStateAcceptingConnections,
	ServerStateIgnoringNewConnections,
}
ServerState;

@class Game;

@protocol GameDelegate <NSObject>

- (void)game:(Game *)game didQuitWithReason:(QuitReason)reason;

- (void)reloadTable;
- (void)reloadPlaylistItem:(PlaylistItem *)playlistItem;
- (void)addPlaylistItem:(PlaylistItem *)playlistItem;
- (void)removePlaylistItem:(PlaylistItem *)playlistItem animation:(UITableViewRowAnimation)animation;
- (void)cancelMusicAndUpdateAll:(PlaylistItem *)playlistItem;

- (void)mediaFinishedPlaying;

- (void)game:(Game *)game setCurrentItem:(PlaylistItem *)playlistItem;
- (void)game:(Game *)game setSkipItemCount:(int)skipItemCount;

- (void)game:(Game *)game clientDidConnect:(Player *)player;
- (void)game:(Game *)game clientDidDisconnect:(Player *)player;

- (void)gameSessionDidEnd:(Game *)server;
- (void)gameNoNetwork:(Game *)server;

- (void)setPlaybackProgress:(double)f;

- (void)showViewController:(UIViewController *)viewController;

@end

@interface Game : NSObject <GKSessionDelegate, AVAudioPlayerDelegate, CustomMovieControllerDelegate> {
}

@property (nonatomic, weak) id <GameDelegate> delegate;
@property (nonatomic, assign) BOOL isServer;
@property (nonatomic, assign) int maxClients;
@property (nonatomic, strong) NSMutableDictionary *players;
@property (nonatomic, strong) GKSession *session;

@property (nonatomic, strong) PlaylistItem *currentItem;
@property (nonatomic, strong) NSMutableArray *playlist;

@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (nonatomic, strong) CustomMovieController *moviePlayerController;

- (void)startClientGameWithSession:(GKSession *)session playerName:(NSString *)name server:(NSString *)peerID;
- (void)startServerGameWithSession:(GKSession *)session playerName:(NSString *)name clients:(NSArray *)clients;

- (void)quitGameWithReason:(QuitReason)reason;
- (void)endSession;
- (void)stopAcceptingConnections;

- (NSString *)displayNameForPeerID:(NSString *)peerID;

- (void)uploadMusicWithMediaItem:(MPMediaItem *)song video:(BOOL)isVideo;
- (void)skipButtonPressed;
- (void)cancelMusic:(PlaylistItem *)selectedItem;
- (int)indexForPlaylistItem:(PlaylistItem *)playlistItem;

- (void)sendVotePacketForItem:(PlaylistItem *)selectedItem andAmount:(int)amount upvote:(BOOL)upvote;
- (void)sendCancelMusicPacket:(PlaylistItem *)selectedItem;
- (void)sendSyncPacketsForItem:(MediaItem *)mediaItem;
@end