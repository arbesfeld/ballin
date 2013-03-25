#import <GameKit/GameKit.h>
#import <MediaPlayer/MediaPlayer.h>

#import "MatchmakingServer.h"
#import "Player.h"
#import "MusicUpload.h"
#import "MusicDownload.h"
#import "Packet.h"

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
- (void)gameWaitingForServerReady:(Game *)game;
- (void)gameWaitingForClientsReady:(Game *)game;

- (void)reloadTable;

- (void)gameServer:(Game *)server clientDidConnect:(Player *)player;
- (void)gameServer:(Game *)server clientDidDisconnect:(Player *)player;
- (void)gameServerSessionDidEnd:(Game *)server;
- (void)gameServerNoNetwork:(Game *)server;

@end

@interface Game : NSObject <GKSessionDelegate> {
    MusicUpload *_uploader;
    MusicDownload *_downloader;
}

@property (nonatomic, weak) id <GameDelegate> delegate;
@property (nonatomic, assign) BOOL isServer;
@property (nonatomic, assign) int maxClients;
@property (nonatomic, strong) NSMutableDictionary *players;
@property (nonatomic, strong) NSMutableArray *playlist;
@property (nonatomic, strong) GKSession *session;

- (void)startClientGameWithSession:(GKSession *)session playerName:(NSString *)name server:(NSString *)peerID;
- (void)quitGameWithReason:(QuitReason)reason;
- (void)startServerGameWithSession:(GKSession *)session playerName:(NSString *)name clients:(NSArray *)clients;

- (void)endSession;
- (NSString *)displayNameForPeerID:(NSString *)peerID;
- (void)stopAcceptingConnections;

- (void)uploadMusicWithMediaItem:(MPMediaItem *)song;
@end