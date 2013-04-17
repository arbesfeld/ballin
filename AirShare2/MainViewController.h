#import "MainViewController.h"
#import "GameViewController.h"
#import "MatchmakingClient.h"
#import "MatchmakingServer.h"
#import "UIImage+animatedGIF.h"

@interface MainViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIAlertViewDelegate, GameViewControllerDelegate, MatchmakingClientDelegate, MatchmakingServerDelegate>

@property (weak, nonatomic) IBOutlet UIButton *hostGameButton;

@property (nonatomic, weak) IBOutlet UITextField *nameTextField;
@property (nonatomic, weak) IBOutlet UILabel *statusLabel;
@property (nonatomic, weak) IBOutlet UITableView *tableView;
@property (nonatomic, strong) IBOutlet UIImageView *waitingView;
@property (strong, nonatomic) IBOutlet UILabel *sessionsLabel;

- (IBAction)hostGameAction:(id)sender;

@end
