#import <GameKit/GameKit.h>

#import "Game.h"
#import "AFNetworking.h"
#import "MusicUpload.h"

#import "Packet.h"
#import "PacketSignInResponse.h"
#import "PacketPlayerList.h"
#import "PacketOtherClientQuit.h"
#import "PacketMusic.h"
#import "PacketMusicResponse.h"
#import "PacketPlayMusicNow.h"

const double DELAY_TIME = 2.000; // wait DELAY_TIME seconds until songs play


@implementation Game
{
	NSString *_serverPeerID;
	NSString *_localPlayerName;
    
    NSDateFormatter *_dateFormatter;
    
    ServerState _serverState;
}

@synthesize delegate = _delegate;
@synthesize isServer = _isServer;
@synthesize session = _session;
@synthesize players = _players;
@synthesize playlist = _playlist;

- (void)dealloc
{
    #ifdef DEBUG
	NSLog(@"dealloc %@", self);
    #endif
}

- (id)init
{
	if ((self = [super init]))
	{
		_players = [NSMutableDictionary dictionaryWithCapacity:4];
        _playlist = [[NSMutableArray alloc] initWithCapacity:8];
        _uploader = [[MusicUpload alloc] initWithGame:self];
        _downloader = [[MusicDownload alloc] initWithGame:self];
        
        _dateFormatter = [[NSDateFormatter alloc] init];
        [_dateFormatter setDateFormat:DATE_FORMAT];
	}
	return self;
}

#pragma mark - Game Logic

- (void)startClientGameWithSession:(GKSession *)session playerName:(NSString *)name server:(NSString *)peerID
{
	self.isServer = NO;
    
	_session = session;
	_session.available = NO;
	_session.delegate = self;
    
    self.maxClients = 4;
    
	[_session setDataReceiveHandler:self withContext:nil];
    
	_serverPeerID = peerID;
	_localPlayerName = name;
    NSLog(@"Name: %@", _localPlayerName);
    
	[self.delegate gameWaitingForServerReady:self];
    
    Packet *packet = [PacketSignInResponse packetWithPlayerName:_localPlayerName];
	[self sendPacketToServer:packet];
}

- (void)startServerGameWithSession:(GKSession *)session playerName:(NSString *)name clients:(NSArray *)clients
{
    NSLog(@"startServerGameWithSession:");
	self.isServer = YES;
    
	_session = session;
	_session.available = YES;
	_session.delegate = self;
    
    self.maxClients = 4;
    
	[_session setDataReceiveHandler:self withContext:nil];
    
    _serverState = ServerStateAcceptingConnections;
    
	[self.delegate gameWaitingForClientsReady:self];
    NSLog(@"Session displayname: %@", _session.displayName);
    _localPlayerName = name;
    
    
	Player *player = [[Player alloc] init];
	player.name = _localPlayerName;
	player.peerID = _session.peerID;
    
	[_players setObject:player forKey:player.peerID];
}

#pragma mark - GKSession Data Receive Handler

- (void)receiveData:(NSData *)data fromPeer:(NSString *)peerID inSession:(GKSession *)session context:(void *)context
{
    #ifdef DEBUG
	NSLog(@"Game: receive data from peer: %@, data: %@, length: %d", peerID, data, [data length]);
    #endif
    
	Packet *packet = [Packet packetWithData:data];
	if (packet == nil)
	{
		NSLog(@"Invalid packet: %@", data);
		return;
	}
    
	Player *player = [self playerWithPeerID:peerID];
    
	if (self.isServer)
		[self serverReceivedPacket:packet fromPlayer:player];
	else
		[self clientReceivedPacket:packet];
}

- (void)clientReceivedPacket:(Packet *)packet
{
	switch (packet.packetType)
	{
        case PacketTypePlayerList:
            self.players = ((PacketPlayerList *)packet).players;
            
            NSLog(@"the players are: %@", self.players);
            
            [self.delegate reloadTable];
            break;
        
        case PacketTypeMusic:
        {
            NSString *songName  = ((PacketMusic *)packet).songName;
            NSString *artistName  = ((PacketMusic *)packet).artistName;
            
            NSLog(@"Client recieved music packet with songName %@ and artistName %@", songName, artistName);
            
            [_downloader downloadFileWithName:songName andArtistName:artistName];
            break;
        }
            
        case PacketTypePlayMusicNow:
        {
            NSString *songName = ((PacketPlayMusicNow *)packet).songName;
            NSDate *playDate = ((PacketPlayMusicNow *)packet).time;
            
            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
            [dateFormatter setDateFormat:DATE_FORMAT];
            NSString *playDateString = [dateFormatter stringFromDate:playDate];
            
            NSLog(@"Client received packet PlayTypeMusicNow, songName = %@, playString = %@", songName, playDateString);
            
            AFHTTPClient *httpClient = [[AFHTTPClient alloc] initWithBaseURL:[NSURL URLWithString:@"http://protected-harbor-4741.herokuapp.com/"]];
            NSString *urlString = @"http://protected-harbor-4741.herokuapp.com/airshare-time.php";
            NSMutableURLRequest *request = [httpClient requestWithMethod:@"GET"
                                                                    path:urlString
                                                              parameters:nil];
            AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
            [httpClient registerHTTPOperationClass:[AFHTTPRequestOperation class]];
            
            [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
                NSLog(@"Success, data length: %d", [responseObject length]);
                
                NSDate *currentDate = [_dateFormatter dateFromString:[[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding]];
    
                // have to multiply by 1000 then devide to get double precision
                double delay = [self secondBetweenDate:currentDate andDate:playDate] * 1000.0;
                delay /= 1000.0;
                
                NSLog(@"Client to play music item, song = %@, delay: %f", songName, delay);
                [self performSelector:@selector(playMusicItemWithName:) withObject:songName afterDelay:delay];
                
            } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                NSLog(@"Error: %@", error);
            }];
            [operation start];
            
            break;
        }
            
        case PacketTypeServerQuit:
			[self quitGameWithReason:QuitReasonServerQuit];
			break;
        
        case PacketTypeOtherClientQuit:
        {
            PacketOtherClientQuit *quitPacket = ((PacketOtherClientQuit *)packet);
            [self clientDidDisconnect:quitPacket.peerID];
			
			break;
		}
        default:
			NSLog(@"Client received unexpected packet: %@", packet);
			break;
	}
}

- (void)serverReceivedPacket:(Packet *)packet fromPlayer:(Player *)player
{
	switch (packet.packetType)
	{
		case PacketTypeSignInResponse:
        {
            player.name = ((PacketSignInResponse *)packet).playerName;
            
            NSLog(@"Server received sign in from client '%@'", player.name);
            
            // received a sign in from player, now return with a PacketPlayerList
            Packet *packet = [PacketPlayerList packetWithPlayers:_players];
            [self sendPacketToAllClients:packet];
			break;
        }
            
        case PacketTypeMusic:
        {
            NSString *songName  = ((PacketMusic *)packet).songName;
            NSString *artistName  = ((PacketMusic *)packet).artistName;
            NSLog(@"Server recieved music packet with song = %@ and artist = %@", songName, artistName);
            
            [_downloader downloadFileWithName:songName andArtistName:artistName];
            break;
        }
        case PacketTypeMusicResponse:
        {
            NSString *songName  = ((PacketMusicResponse *)packet).songName;
            NSLog(@"Server recieved music response packet from player = %@ and song = %@", player.name, songName);
            
            [player.hasMusicList setObject:@YES forKey:songName];
            
            MusicItem *musicItem = (MusicItem *)[self playlistItemWithName:songName];
            if([self allPlayersHaveMusic:musicItem]) {
                [self serverStartPlayingMusic:musicItem];
            }
            break;
        }
        case PacketTypeClientQuit:
			[self clientDidDisconnect:player.peerID];
			break;
            
		default:
			NSLog(@"Server received unexpected packet: %@", packet);
			break;
	}
}
- (void)uploadMusicWithMediaItem:(MPMediaItem *)song
{
    NSLog(@"Game: playMusicWithURL: %@", [song valueForProperty:MPMediaItemPropertyAssetURL]);
    [_uploader convertAndUpload:song];
}

- (void)playMusicItemWithName:(NSString *)name
{
    MusicItem *musicItem = (MusicItem *)[self playlistItemWithName:name];
    NSLog(@"Playing music item, song = %@, artist = %@", musicItem.name, musicItem.subtitle);
    
    NSError *error;
    _audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:musicItem.songURL error:&error];
    _audioPlayer.delegate = self;
    if (_audioPlayer == nil) {
        NSLog(@"AudioPlayer did not load properly: %@", [error description]);
    } else {
        [_audioPlayer prepareToPlay];
        [_audioPlayer play];
    }
}

- (void)hasDownloadedMusic:(MusicItem *)musicItem
{
    if(!self.isServer) {
        // alert the server that you have musicItem
        PacketMusicResponse *packet = [PacketMusicResponse packetWithSongName:musicItem.name];
        [self sendPacketToServer:packet];
    }
    else {
        // mark that you have item
        [((Player *)[_players objectForKey:_session.peerID]).hasMusicList setObject:@YES forKey:musicItem.name];
        
        // see if you should start playing
        if([self allPlayersHaveMusic:musicItem]) {
            [self serverStartPlayingMusic:musicItem];
        }
    }
}

- (BOOL)allPlayersHaveMusic:(MusicItem *)musicItem
{
    for (NSString *peerID in _players)
	{
		Player *player = [self playerWithPeerID:peerID];
		if (![player.hasMusicList objectForKey:musicItem.name]) {
            NSLog(@"Player %@ does not have music %@", player.name, musicItem.name);
			return NO;
        }
	}
    return YES;
}
- (void)serverStartPlayingMusic:(MusicItem *)musicItem {
    AFHTTPClient *httpClient = [[AFHTTPClient alloc] initWithBaseURL:[NSURL URLWithString:@"http://protected-harbor-4741.herokuapp.com/"]];
    NSString *urlString = @"http://protected-harbor-4741.herokuapp.com/airshare-time.php";
    NSMutableURLRequest *request = [httpClient requestWithMethod:@"GET"
                                                            path:urlString
                                                      parameters:nil];
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    [httpClient registerHTTPOperationClass:[AFHTTPRequestOperation class]];
    
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"Success, data length: %d", [responseObject length]);
        
        NSDate *currentDate = [_dateFormatter dateFromString:[[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding]];
        NSDate *playDate = [currentDate dateByAddingTimeInterval:DELAY_TIME];
        
        PacketPlayMusicNow *packet = [PacketPlayMusicNow packetWithSongName:musicItem.name andTime:playDate];
        [self sendPacketToAllClients:packet];
        
        [self performSelector:@selector(playMusicItemWithName:) withObject:musicItem.name afterDelay:DELAY_TIME];
        NSLog(@"Server preparing to play music item with name = %@ and delay = %f", musicItem.name, DELAY_TIME);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error: %@", error);
    }];
    [operation start];
}

#pragma mark - Networking

- (void)sendPacketToAllClients:(Packet *)packet
{
	GKSendDataMode dataMode = GKSendDataReliable;
	NSData *data = [packet data];
	NSError *error;
	if (![_session sendDataToAllPeers:data withDataMode:dataMode error:&error])
	{
		NSLog(@"Error sending data to clients: %@", error);
	}
}

- (void)sendPacketToServer:(Packet *)packet
{
    NSLog(@"Sending packet to server");
	GKSendDataMode dataMode = GKSendDataReliable;
	NSData *data = [packet data];
	NSError *error;
	if (![_session sendData:data toPeers:[NSArray arrayWithObject:_serverPeerID] withDataMode:dataMode error:&error])
	{
		NSLog(@"Error sending data to server: %@", error);
	}
}

#pragma mark - GKSessionDelegate

- (void)session:(GKSession *)session peer:(NSString *)peerID didChangeState:(GKPeerConnectionState)state
{
    #ifdef DEBUG
	NSLog(@"Game: peer %@ changed state %d", peerID, state);
    #endif
    
    switch (state)
    {
        case GKPeerStateAvailable:
            break;
            
        case GKPeerStateUnavailable:
            break;
            
            // A new client has connected to the server.
        case GKPeerStateConnected:
            if (self.isServer)
            {
                [self clientDidConnect:peerID];
            }
            break;
            
            // A client has disconnected from the server.
        case GKPeerStateDisconnected:
            if (self.isServer)
            {
                [self clientDidDisconnect:peerID];
            }
            else if ([peerID isEqualToString:_serverPeerID])
            {
                [self quitGameWithReason:QuitReasonConnectionDropped];
            }
            break;
            
        case GKPeerStateConnecting:
            break;
    }
    
}


- (void)session:(GKSession *)session didReceiveConnectionRequestFromPeer:(NSString *)peerID
{
    #ifdef DEBUG
	NSLog(@"Game: connection request from peer %@", peerID);
    #endif
    
	if (_isServer && _serverState == ServerStateAcceptingConnections && [_players count] < self.maxClients)
	{
		NSError *error;
		if ([session acceptConnectionFromPeer:peerID error:&error])
			NSLog(@"Game: Connection accepted from peer %@", peerID);
		else
			NSLog(@"Game: Error accepting connection from peer %@, %@", peerID, error);
	}
	else  // not accepting connections or too many clients
	{
		[session denyConnectionFromPeer:peerID];
	}
}

- (void)session:(GKSession *)session connectionWithPeerFailed:(NSString *)peerID withError:(NSError *)error
{
    #ifdef DEBUG
	NSLog(@"Game: connection with peer %@ failed %@", peerID, error);
    #endif
    
	// Not used.
}

- (void)session:(GKSession *)session didFailWithError:(NSError *)error
{
#ifdef DEBUG
	NSLog(@"Game: session failed %@", error);
#endif
    
	if ([[error domain] isEqualToString:GKSessionErrorDomain])
	{
        [self quitGameWithReason:QuitReasonConnectionDropped];
	}
}

- (NSString *)displayNameForPeerID:(NSString *)peerID
{
	return [_session displayNameForPeer:peerID];
}

- (void)clientDidConnect:(NSString *)peerID
{
    if([_players objectForKey:peerID] == nil) {
        Player *player = [[Player alloc] init];
        player.peerID = peerID;
        [_players setObject:player forKey:player.peerID];
        [self.delegate gameServer:self clientDidConnect:player];
    }
}

- (void)clientDidDisconnect:(NSString *)peerID
{
    Player *player = [self playerWithPeerID:peerID];
    if (player != nil)
    {
        [_players removeObjectForKey:peerID];
        
        // Tell the other clients that this one is now disconnected.
        if (self.isServer)
        {
            PacketOtherClientQuit *packet = [PacketOtherClientQuit packetWithPeerID:peerID];
            [self sendPacketToAllClients:packet];
        }
        [self.delegate gameServer:self clientDidDisconnect:player];
    }
}


- (Player *)playerWithPeerID:(NSString *)peerID
{
	return [_players objectForKey:peerID];
}

- (PlaylistItem *)playlistItemWithName:(NSString *)name
{
    for(int i = 0; i < _playlist.count; i++) {
        if([((PlaylistItem *)_playlist[i]).name isEqualToString:name]) {
            return _playlist[i];
        }
    }
    NSLog(@"Playlist item %@ not found!", name);
    return nil;
}

# pragma mark - Time Functions

- (NSTimeInterval) secondBetweenDate:(NSDate *)firstDate andDate:(NSDate *)secondDate
{
    NSTimeInterval firstDiff = [firstDate timeIntervalSinceNow];
    NSTimeInterval secondDiff = [secondDate timeIntervalSinceNow];
    NSTimeInterval dateDiff = secondDiff - firstDiff;
    return dateDiff;
}

- (NSDate *)getTimeFromServer
{
    NSURL *url = [NSURL URLWithString:@"http://protected-harbor-4741.herokuapp.com/airshare-time.php"];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    NSError *error;
    NSData *receivedData = [NSURLConnection sendSynchronousRequest:request
                                                 returningResponse:nil
                                                             error:&error];
    
    NSString *dateString = [[NSString alloc] initWithData:receivedData
                                                 encoding:NSUTF8StringEncoding];
    NSLog(@"Time from server = %@", dateString);
    if(error) {
      NSLog(@"Error: %@", error);
        return [NSDate date];
    } else {
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:DATE_FORMAT];
        NSDate *time = [dateFormatter dateFromString:dateString];
        
        return time;
    }
}

# pragma mark - End Session Handling

- (void)endSession
{
	_serverState = ServerStateIdle;
    
	[_session disconnectFromAllPeers];
	_session.available = NO;
	_session.delegate = nil;
	_session = nil;
    
    _players = nil;
    
	[self.delegate gameServerSessionDidEnd:self];
}

- (void)stopAcceptingConnections
{
	_serverState = ServerStateIgnoringNewConnections;
	_session.available = NO;
}

- (void)quitGameWithReason:(QuitReason)reason
{
	if (reason == QuitReasonUserQuit)
	{
		if (self.isServer)
		{
			Packet *packet = [Packet packetWithType:PacketTypeServerQuit];
			[self sendPacketToAllClients:packet];
		}
		else
		{
			Packet *packet = [Packet packetWithType:PacketTypeClientQuit];
			[self sendPacketToServer:packet];
		}
	}
    
	[_session disconnectFromAllPeers];
	_session.delegate = nil;
	_session = nil;
    
	[self.delegate game:self didQuitWithReason:reason];
}
@end