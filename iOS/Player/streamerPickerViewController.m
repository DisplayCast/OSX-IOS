// Copyright (c) 2012, Fuji Xerox Co., Ltd.
// All rights reserved.
// Author: Surendar Chandra, FX Palo Alto Laboratory, Inc.

#import "streamerPickerViewController.h"
#import "streamerSnapshotDownloader.h"

#include <sys/types.h>  /* for type definitions */
#include <sys/socket.h> /* for socket API calls */
#include <netinet/in.h> /* for address structs */
#include <arpa/inet.h>  /* for sockaddr_in */
#include <sys/time.h>
#include <fcntl.h>

// A category on NSNetService that's used to sort NSNetService objects by their name.
@interface NSNetService (streamerPickerViewControllerAdditions)
- (NSComparisonResult) localizedCaseInsensitiveCompareByName:(NSNetService *)aService;
@end

@implementation NSNetService (streamerPickerViewControllerAdditions)
- (NSComparisonResult) localizedCaseInsensitiveCompareByName:(NSNetService *)aService {
	return [[self name] localizedCaseInsensitiveCompare:[aService name]];
}
@end

@interface streamerPickerViewController()
@property (nonatomic, retain, readwrite) NSMutableArray *services;
@property (nonatomic, retain, readwrite) NSNetServiceBrowser *netServiceBrowser;
@property (nonatomic, retain, readwrite) NSTimer *timer;
@property (nonatomic, assign, readwrite) BOOL initialWaitOver;

- (void)initialWaitOver:(NSTimer *)timer;
@end

@implementation streamerPickerViewController

@synthesize snapshotDownloadsInProgress;
@synthesize streamers;
@synthesize delegate = _delegate;
@synthesize netServiceBrowser = _netServiceBrowser;
@synthesize services = _services;
@dynamic timer;
@synthesize initialWaitOver = _initialWaitOver;

- (id)initWithTitle:(NSString *)title {
	if ((self = [super initWithStyle:UITableViewStylePlain])) {
		self.title = title;
        self.tableView.rowHeight = PLAYERIOS_ICON_SIZE;
        self.tableView.separatorColor = [UIColor blackColor];
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLineEtched;
        
		_services = [[NSMutableArray alloc] init];

		// Make sure we have a chance to discover devices before showing the user that nothing was found (yet)
		[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(initialWaitOver:) userInfo:nil repeats:NO];
	}

	return self;
}

// Creates an NSNetServiceBrowser that searches for services of a particular type in a particular domain.
// If a service is currently being resolved, stop resolving it and stop the service browser from
// discovering other services.
- (BOOL)searchForServicesOfType:(NSString *)type inDomain:(NSString *)domain {
	[self.netServiceBrowser stop];
	[self.services removeAllObjects];

	NSNetServiceBrowser *aNetServiceBrowser = [[NSNetServiceBrowser alloc] init];
	if(! aNetServiceBrowser)
		return NO;

	aNetServiceBrowser.delegate = self;
	self.netServiceBrowser = aNetServiceBrowser;
	[aNetServiceBrowser release];
	[self.netServiceBrowser searchForServicesOfType:type inDomain:domain];

	[self.tableView reloadData];
	return YES;
}

- (NSTimer *)timer {
	return _timer;
}

// When this is called, invalidate the existing timer before releasing it.
- (void)setTimer:(NSTimer *)newTimer {
	[_timer invalidate];
	[newTimer retain];
	[_timer release];
	_timer = newTimer;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
#pragma unused(tableView)
    
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
#pragma unused(tableView, section)
    
	return [self.services count];
}

- (void)appImageDidLoad:(NSIndexPath *)indexPath {
	streamerSnapshotDownloader *snapshotDownloader = [snapshotDownloadsInProgress objectForKey:indexPath];
	if (snapshotDownloader != nil) {
			// NSLog(@"Trying to redraw: %@", snapshotDownloader.streamer.icon);
		[self sortAndUpdateUI];

			// UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:snapshotDownloader.indexPathInTableView];
			// cell.imageView.image = snapshotDownloader.streamerIcon;
			// NSLog(@"WTF: %@ vs %@", cell.textLabel.text, [snapshotDownloader label]);
	}
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *tableCellIdentifier = @"UITableViewCell";
    
	UITableViewCell *cell = (UITableViewCell *)[tableView dequeueReusableCellWithIdentifier:tableCellIdentifier];
	if (cell == nil)
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:tableCellIdentifier] autorelease];
	
    if ([self.services count] == 0)
        return cell;

	// Set up the text for the cell
	NSNetService *service = [self.services objectAtIndex:indexPath.row];
    NSDictionary *keys = [NSNetService dictionaryFromTXTRecordData:[service TXTRecordData]];
    
#ifdef PLAYERIOS_USE_STREAMERICON
	streamerInfo *streamer = [streamers objectForKey:[service name]];
	
	if (streamer == NULL) {			// We don't know anything about this streamer
		int imagePort = [[[[NSString alloc] initWithData:[keys objectForKey:@"imagePort" ] encoding:NSUTF8StringEncoding] autorelease] intValue];
		
		if (imagePort > 0) {
			boolean_t connected = false;
			NSArray *addresses = [service addresses];
			NSData *address;
			struct sockaddr_in address_sin;
			int receiveSocket;
			
			for (address in addresses) {
				memcpy(&address_sin, (struct sockaddr_in *)[address bytes], sizeof(struct sockaddr_in));
				address_sin.sin_port = (short) htons(imagePort);
				
					// char buffer[1024];
					// NSLog(@"DEBUG: Trying... %s:%d", inet_ntop(AF_INET, &(address_sin.sin_addr), buffer, sizeof(buffer)), ntohs(address_sin.sin_port));
				
				if (address_sin.sin_family == AF_INET) {
					fd_set fdset;
					struct timeval tv;
					
					receiveSocket = socket(AF_INET, SOCK_STREAM, 0);
					fcntl(receiveSocket, F_SETFL, O_NONBLOCK);
					
					connect(receiveSocket, (struct sockaddr *)&address_sin, (socklen_t)sizeof(struct sockaddr_in));
					
					FD_ZERO(&fdset);
					FD_SET(receiveSocket, &fdset);
					tv.tv_sec = 1;             /* 1 second timeout */
					tv.tv_usec = 0;
					
					if (select(receiveSocket + 1, NULL, &fdset, NULL, &tv) == 1) {
						int so_error;
						socklen_t len = sizeof so_error;
						
						getsockopt(receiveSocket, SOL_SOCKET, SO_ERROR, &so_error, &len);
						close(receiveSocket);
						
						if (so_error == 0) {
							connected = true;
							break;
						}
					}
				}
			}
				// NSLog(@"Done trying");
			
			if (connected) {
					// NSLog(@"Connected with %d pending", [snapshotDownloadsInProgress count]);
				char buffer[1024];
				NSString *imageURL = [NSString stringWithFormat:@"http://%s:%d/snapshot?width=%d", inet_ntop(AF_INET, &(address_sin.sin_addr), buffer, sizeof(buffer)), imagePort, (PLAYERIOS_ICON_SIZE * 2)];
				
				streamer = [[[streamerInfo alloc] init] autorelease];
				streamer.name = [service name];
				streamer.imageURLString = imageURL;
				streamer.icon = nil;
					// NSLog(@"Storing streamer: %@", streamer.name);
				[streamers setObject:streamer forKey:[service name]];

					// This code doesn't work, when the delegate returns, I need to repaint only the visible entry and not the cell
				streamerSnapshotDownloader *snapshotDownloader = [snapshotDownloadsInProgress objectForKey:indexPath];
				if (snapshotDownloader == nil) {
					snapshotDownloader = [[streamerSnapshotDownloader alloc] init];
					snapshotDownloader.streamer = streamer;

					[indexPath retain];
					snapshotDownloader.indexPathInTableView = indexPath;
					
					snapshotDownloader.delegate = self;
					[snapshotDownloadsInProgress setObject:snapshotDownloader forKey:indexPath];
					[snapshotDownloader startDownload];
					[snapshotDownloader release];
				}

				// This requires SDWebImage
				// [cell.imageView setImageWithURL:[NSURL URLWithString:imageURL] placeHolderImage:[UIImage imageNamed:@"Icon.png"]];

					// The following code would download images synchrnously without any caching
					// UIImage *icon = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:imageURL]]];
					// [cell.imageView setImage:icon];
			} else {
					// NSLog(@"Did not connect to streamer %@", [service name]);
				
				[cell.imageView setImage:nil];
			}
		} else {
				// NSLog(@"No image port: %@", [service name]);
			[cell.imageView setImage:nil];
		}
    } else {
		if (streamer.icon != nil) {
				// NSLog(@"We also have its icon: %@", [service name]);
			[cell.imageView setImage:streamer.icon];
		}
			// Otherise, it is still pending and so we don't do anything
	}
#endif /* PLAYERIOS_USE_STREAMERICON */
    
    [cell.textLabel setFont:[UIFont boldSystemFontOfSize:10.0]];
    cell.textLabel.text = [[[NSString alloc] initWithData:[keys objectForKey:@"name"] encoding:NSUTF8StringEncoding] autorelease];
    cell.textLabel.textColor = [UIColor blackColor];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; // UITableViewCellAccessoryNone;
	
	// Note that the underlying array could have changed, and we want to show the activity indicator on the correct cell
    if (cell.accessoryView)
		cell.accessoryView = nil;
	
	return cell;
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
#pragma unused(tableView)
    
	// Ignore the selection if there are no services as the searchingForServicesString cell
	// may be visible and tapping it would do nothing
	if ([self.services count] == 0)
		return nil;

	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
	return indexPath;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
#pragma unused(tableView)
    [self.delegate streamerPickerViewController:self didResolveInstance:[self.services objectAtIndex:indexPath.row]];
}

- (void)initialWaitOver:(NSTimer *)timer {
#pragma unused(timer)
	self.initialWaitOver= YES;
	if (![self.services count])
		[self.tableView reloadData];
}

- (void)sortAndUpdateUI {
	// Sort the services by name.
	[self.services sortUsingSelector:@selector(localizedCaseInsensitiveCompareByName:)];
	[self.tableView reloadData];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didRemoveService:(NSNetService *)service moreComing:(BOOL)moreComing {
#pragma unused(netServiceBrowser)
	// If a service went away, stop resolving it if it's currently being resolved,
	// remove it from the list and update the table view if no more events are queued.
    [self.services removeObject:service];
	
	// If moreComing is NO, it means that there are no more messages in the queue from the Bonjour daemon, so we should update the UI.
	// When moreComing is set, we don't update the UI so that it doesn't 'flash'.
	if (!moreComing) {
		[self sortAndUpdateUI];
	}
}	

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing {
#pragma unused(netServiceBrowser,moreComing)
    [service retain];
    [service setDelegate:self];
    [service resolveWithTimeout:0.0];
}	

// This should never be called, since we resolve with a timeout of 0.0, which means indefinite
- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict {
#pragma unused(sender, errorDict)
	[self.tableView reloadData];
}

- (void)netServiceDidResolveAddress:(NSNetService *)service {
    [service startMonitoring];
}

- (void)netService:(NSNetService *)service didUpdateTXTRecordData:(NSData *)data {
#pragma unused(data)
    [self.services addObject:service];
    [self sortAndUpdateUI];
}

- (void)cancelAction {
	[self.delegate streamerPickerViewController:self didResolveInstance:nil];
}

- (void)dealloc {
	// Cleanup any running resolve and free memory
	self.services = nil;
	[self.netServiceBrowser stop];
	self.netServiceBrowser = nil;
	
	[super dealloc];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    
    return interfaceOrientation == UIInterfaceOrientationPortrait || interfaceOrientation == UIInterfaceOrientationLandscapeLeft || interfaceOrientation == UIInterfaceOrientationLandscapeRight || interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown;
}

@end
