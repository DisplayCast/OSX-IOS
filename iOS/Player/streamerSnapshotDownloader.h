#import "Globals.h"
#import "streamerInfo.h"

@class streamerViewController;

@protocol StreamerSnapshotDownloaderDelegate;

@interface streamerSnapshotDownloader : NSObject {
    NSIndexPath *_indexPathInTableView;
    id <StreamerSnapshotDownloaderDelegate> _delegate;
		// NSString *_imageURLString;
		// UIImage *_streamerIcon;
    NSMutableData *_activeDownload;
    NSURLConnection *_imageConnection;
	streamerInfo *_streamer;
}
@property (nonatomic, retain) NSIndexPath *indexPathInTableView;
@property (nonatomic, assign) id <StreamerSnapshotDownloaderDelegate> delegate;
@property (nonatomic, retain) NSString *imageURLString;
@property (nonatomic, retain) UIImage *streamerIcon;
@property (nonatomic, retain) NSMutableData *activeDownload;
@property (nonatomic, retain) NSURLConnection *imageConnection;
@property (nonatomic, retain) streamerInfo *streamer;

- (void)startDownload;
- (void)cancelDownload;

@end

@protocol StreamerSnapshotDownloaderDelegate

- (void)appImageDidLoad:(NSIndexPath *)indexPath;

@end