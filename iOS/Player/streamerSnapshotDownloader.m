#import "streamerSnapshotDownloader.h"

@implementation streamerSnapshotDownloader

@synthesize indexPathInTableView = _indexPathInTableView;
@synthesize delegate = _delegate;
@synthesize activeDownload = _activeDownload;
@synthesize imageConnection = _imageConnection;
@synthesize streamerIcon = _streamerIcon;
@synthesize imageURLString = _imageURLString;
@synthesize streamer = _streamer;

#pragma mark

- (void)dealloc {
		// [self.indexPathInTableView release];
		// [self.activeDownload release];
    [self.imageConnection cancel];
		// [self.imageConnection release];
		// [self.streamerIcon release];
		// [self.streamer release];
	
    [super dealloc];
}

- (void)startDownload {
    self.activeDownload = [NSMutableData data];
    // alloc+init and start an NSURLConnection; release on completion/failure
	// NSLog(@"Starting URL Request for: %@", imageURLString);
    NSURLConnection *conn = [[NSURLConnection alloc] initWithRequest:
                             [NSURLRequest requestWithURL:[NSURL URLWithString:self.streamer.imageURLString]] delegate:self];
    self.imageConnection = conn;
    [conn release];
}

- (void)cancelDownload {
    [self.imageConnection cancel];
    self.imageConnection = nil;
    self.activeDownload = nil;
}


#pragma mark -
#pragma mark Download support (NSURLConnectionDelegate)

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
#pragma unused(connection)
		// NSLog(@"Received %d bytes for %@", [data length], connection);
    [self.activeDownload appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
#pragma unused(connection, error)

	NSLog(@"Failed with error %@ for connection %@", error, [connection debugDescription]);
	// Clear the activeDownload property to allow later attempts
    self.activeDownload = nil;

    // Release the connection now that it's finished
    self.imageConnection = nil;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
#pragma unused(connection)
    // Set appIcon and clear temporary data/image
    UIImage *image = [[UIImage alloc] initWithData:self.activeDownload];
    
    if ((int) image.size.width != PLAYERIOS_ICON_SIZE && (int) image.size.height != PLAYERIOS_ICON_SIZE) {
        CGSize itemSize = CGSizeMake(PLAYERIOS_ICON_SIZE, PLAYERIOS_ICON_SIZE);

		UIGraphicsBeginImageContext(itemSize);
		CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
		[image drawInRect:imageRect];
		self.streamer.icon = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
    } else
        self.streamer.icon = image;
    self.activeDownload = nil;
    [image release];
    
    // Release the connection now that it's finished
    self.imageConnection = nil;
        
    // call our delegate and tell it that our icon is ready for display
    [self.delegate appImageDidLoad:self.indexPathInTableView];
}

@end

