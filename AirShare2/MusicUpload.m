//
//  MusicUpload.m
//  AirShare2
//
//  Created by mata on 3/24/13.
//  Copyright (c) 2013 Matthew Arbesfeld. All rights reserved.
//

#import "MusicUpload.h"
#import <AudioToolbox/AudioToolbox.h> // for the core audio constants
#import "AFNetworking.h"
#import "PacketMusicDownload.h"
#import "MusicItem.h"
#import "Game.h"

@implementation MusicUpload

- (void)dealloc {
    [super dealloc];
}

- (void)convertAndUpload:(MusicItem *)musicItem withAssetURL:(NSURL *)assetURL andSessionID:(NSString *)sessionID progress:(void (^)())progress completion:(void (^)())completionBlock{
	// set up an AVAssetReader to read from the iPod Library
	AVURLAsset *songAsset = [AVURLAsset URLAssetWithURL:assetURL options:nil];
    
	NSError *assetError = nil;
	AVAssetReader *assetReader = [[AVAssetReader assetReaderWithAsset:songAsset
															   error:&assetError] retain];
	if (assetError) {
		NSLog (@"error: %@", assetError);
		return;
	}
	AVAssetReaderOutput *assetReaderOutput = [[AVAssetReaderAudioMixOutput
											  assetReaderAudioMixOutputWithAudioTracks:songAsset.tracks
                                              audioSettings: nil] retain];
	if (! [assetReader canAddOutput: assetReaderOutput]) {
		NSLog (@"can't add reader output... die!");
		return;
	}
	[assetReader addOutput: assetReaderOutput];
    
    // export path is where it is saved locally
	NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectoryPath = [dirs objectAtIndex:0];
    NSString *fileName = [NSString stringWithFormat:@"%@.m4a", musicItem.ID];
	NSString *exportPath = [[documentsDirectoryPath stringByAppendingPathComponent:fileName] retain];
    
	if ([[NSFileManager defaultManager] fileExistsAtPath:exportPath]) {
		[[NSFileManager defaultManager] removeItemAtPath:exportPath error:nil];
	}
	NSURL *exportURL = [NSURL fileURLWithPath:exportPath];
	AVAssetWriter *assetWriter = [[AVAssetWriter assetWriterWithURL:exportURL
														  fileType:AVFileTypeAppleM4A
															 error:&assetError] retain];
	if (assetError) {
		NSLog (@"error: %@", assetError);
		return;
	}
	AudioChannelLayout channelLayout;
	memset(&channelLayout, 0, sizeof(AudioChannelLayout));
	channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
    NSDictionary *outputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithInt: kAudioFormatMPEG4AAC], AVFormatIDKey,
                                    [NSNumber numberWithFloat:44100.0], AVSampleRateKey,
                                    [NSNumber numberWithInt:2], AVNumberOfChannelsKey,
                                    [NSNumber numberWithInt:128000], AVEncoderBitRateKey,
                                    [NSData dataWithBytes:&channelLayout    length:sizeof(AudioChannelLayout)], AVChannelLayoutKey,
                                    
                                    nil];
	AVAssetWriterInput *assetWriterInput = [[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
																			  outputSettings:outputSettings] retain];
	if ([assetWriter canAddInput:assetWriterInput]) {
		[assetWriter addInput:assetWriterInput];
	} else {
		NSLog (@"can't add asset writer input... die!");
		return;
	}
    
	assetWriterInput.expectsMediaDataInRealTime = NO;
    
	[assetWriter startWriting];
	[assetReader startReading];
    
	AVAssetTrack *soundTrack = [songAsset.tracks objectAtIndex:0];
	CMTime startTime = CMTimeMake (0, soundTrack.naturalTimeScale);
	[assetWriter startSessionAtSourceTime: startTime];
    
	__block UInt64 convertedByteCount = 0;
    
	dispatch_queue_t mediaInputQueue = dispatch_queue_create("mediaInputQueue", NULL);
	[assetWriterInput requestMediaDataWhenReadyOnQueue:mediaInputQueue
											usingBlock: ^
	 {
         //NSLog (@"top of block");
		 while (assetWriterInput.readyForMoreMediaData) {
             if ([musicItem isCancelled]) {
                 // early cancellation---should quit now
                 return;
             }
             
             CMSampleBufferRef nextBuffer = [assetReaderOutput copyNextSampleBuffer];
             if (nextBuffer) {
                 // append buffer
                 [assetWriterInput appendSampleBuffer: nextBuffer];
                 //				NSLog (@"appended a buffer (%d bytes)",
                 //					   CMSampleBufferGetTotalSampleSize (nextBuffer));
                 convertedByteCount += CMSampleBufferGetTotalSampleSize (nextBuffer);
                 // oops, no
                 // sizeLabel.text = [NSString stringWithFormat: @"%ld bytes converted", convertedByteCount];
                 
                 //NSNumber *convertedByteCountNumber = [NSNumber numberWithLong:convertedByteCount];
//                 [self performSelectorOnMainThread:@selector(updateSizeLabel:)
//                                        withObject:convertedByteCountNumber
//                                     waitUntilDone:NO];
             } else {
                 // done!
                 __block int it = 0;
                 [assetWriterInput markAsFinished];
                 [assetWriter finishWritingWithCompletionHandler:^{
                     [assetReader cancelReading];
                     
                     NSDictionary *outputFileAttributes = [[NSFileManager defaultManager]
                                                           attributesOfItemAtPath:exportPath
                                                           error:nil];
                     NSLog (@"Converting done. File size is %lld", [outputFileAttributes fileSize]);
                     
                     //loadProgressTimerBlock();
                     // now upload to server
                     NSData *songData = [NSData dataWithContentsOfFile:exportPath];
                     
                     NSLog(@"Uploading to server: %@", musicItem.ID);
                     
                     NSURL *url = [NSURL URLWithString:BASE_URL];
                     NSLog(@"Posting with id = %@ and sessionid = %@", musicItem.ID, sessionID);
                     AFHTTPClient *httpClient = [[AFHTTPClient alloc] initWithBaseURL:url];
                     NSMutableURLRequest *request = [httpClient multipartFormRequestWithMethod:@"POST" path:@"/airshare-upload.php" parameters:nil constructingBodyWithBlock: ^(id <AFMultipartFormData>formData) {
                         [formData appendPartWithFileData:songData name:@"musicfile" fileName:musicItem.ID mimeType:@"audio/x-m4a"];
                         [formData appendPartWithFormData:[musicItem.ID dataUsingEncoding:NSUTF8StringEncoding]
                                                     name:@"id"];
                         [formData appendPartWithFormData:[sessionID dataUsingEncoding:NSUTF8StringEncoding]
                                                     name:@"sessionid"];
                     }];
                     AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
                     __block int ntimes = 5;
                     [operation setUploadProgressBlock:^(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite) {
                         //NSLog(@"Sent %lld of %lld bytes", totalBytesWritten, totalBytesExpectedToWrite);
                         if(it % 300 == 0) {
                             progress();
                         }
                         it++;
                         musicItem.loadProgress = (double)totalBytesWritten / totalBytesExpectedToWrite;
                     }];
                     [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
                         NSLog(@"Upload Success: %@", operation.responseString);
                         musicItem.loadProgress = 1.0;
                         // now tell others that you have uploaded
                         completionBlock();
                     }
                      failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                          NSLog(@"Upload Error: %@",  operation.responseString);
                          if(ntimes > 0) {
                              // retry upload
                              [httpClient enqueueHTTPRequestOperation:operation];
                          }
                          ntimes--;
                      }];
                     if ([musicItem isCancelled]) {
                         // check again for early cancellation
                         return;
                     }
                     [httpClient enqueueHTTPRequestOperation:operation];
                     musicItem.uploadOperation = operation;
                 }];
                 [assetReader release];
                 [assetReaderOutput release];
                 [assetWriter release];
                 [assetWriterInput release];
                 [exportPath release];
                 break;
             }
             
             CMSampleBufferInvalidate(nextBuffer);
             CFRelease(nextBuffer);
             nextBuffer = nil; // NULL?
         }
	 }];
}
@end
