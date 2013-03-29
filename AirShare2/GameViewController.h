#import "Game.h"
#import "MatchmakingClient.h"
#import "MatchmakingServer.h"
#import "PlaylistItem.h"
#import "PlaylistItemCell.h"

#import <MediaPlayer/MediaPlayer.h>

@class GameViewController;

@protocol GameViewControllerDelegate <NSObject>

- (void)gameViewController:(GameViewController *)controller didQuitWithReason:(QuitReason)reason;

@end

@interface GameViewController : UIViewController <UIAlertViewDelegate, UITableViewDataSource, UITableViewDelegate, MPMediaPickerControllerDelegate, GameDelegate, PlaylistItemDelegate> {
    PlaylistItem *_currentPlaylistItem;
    NSMutableDictionary *_voteAmount; // key is songID, value is vote amount
}
@property (nonatomic, weak) IBOutlet UILabel *songLabel;
@property (nonatomic, weak) IBOutlet UILabel *artistLabel;
@property (nonatomic, weak) IBOutlet UIButton *exitButton;
@property (nonatomic, weak) IBOutlet UITableView *userTable;
@property (nonatomic, weak) IBOutlet UITableView *playlistTable;
@property (nonatomic, weak) IBOutlet UIProgressView *playbackProgressBar;

@property (nonatomic, weak) id <GameViewControllerDelegate> delegate;
@property (nonatomic, strong) Game *game;

- (IBAction)exitAction:(id)sender;
- (IBAction)playMusic:(id)sender;

@end