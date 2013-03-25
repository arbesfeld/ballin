//
//  PacketMusic.h
//  AirShare2
//
//  Created by mata on 3/24/13.
//  Copyright (c) 2013 Matthew Arbesfeld. All rights reserved.
//

#import "Packet.h"
#import <MediaPlayer/MediaPlayer.h>

@interface PacketMusic : Packet

@property (nonatomic, strong) NSString *songName;
@property (nonatomic, strong) NSString *artistName;

+ (id)packetWithSongName:(NSString *)songName andArtistName:(NSString *)artistName;

@end
